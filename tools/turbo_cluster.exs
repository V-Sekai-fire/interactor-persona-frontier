# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-FileCopyrightText: 2025 Pierre Talbot
# SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
# SPDX-License-Identifier: Apache-2.0 AND MIT
# Distributed solving over Erlang distribution: a coordinator node hands out subproblems and shares the best bound; worker nodes (one per core, GPU or machine) each run
# the solver guest ELF under libriscv. Nodes are cookie-authenticated Erlang nodes, so a worker can be on another machine: start it there with the same cookie.
#   coordinator:  elixir --name coord@HOST --cookie C tools/turbo_cluster.exs coordinator LEVEL.cp [--power P] [--workers N] [--no-steal] [--problem INPUT.txt]
#   worker:       elixir --name wK@HOST    --cookie C tools/turbo_cluster.exs worker coord@HOST GUEST.elf HOST_BINARY [--kind cpu|gpu] [--budget INSTRUCTIONS]
#   local test:   elixir tools/turbo_cluster.exs local LEVEL.cp [--power P] [--nodes gpu:1,cpu:2] [--slow-us US] [--no-steal] [--kill-one] [--frame-ms 2.0]
# --frame-ms runs every guest in 64 Hz frames of that much compute time (the host sleeps to the frame edge), for a machine that also runs a real-time game.
# A node says what it is (cpu or gpu). The coordinator is a queue machine: a node that asks gets the head of the queue of pending subproblems; with the queue empty and jobs in flight it takes the oldest in-flight job of a node that has finished fewer jobs than it has by
# presuming that node dead: the subproblem is redone, whichever copy finishes first wins, and the other is cancelled. The same path recovers a node that really dies.
# Message formats are in service/turbo-cluster.asyncapi.yaml.
{opts, [role | args], _} =
  OptionParser.parse(System.argv(),
    strict: [power: :integer, workers: :integer, budget: :integer, cookie: :string, guest: :string, host: :string, kind: :string, nodes: :string,
             slow_us: :integer, problem: :string, frame_ms: :float, no_steal: :boolean, kill_one: :boolean, hold_first_job: :boolean, die_at_first_job: :boolean])
root = File.cwd!()
runs = "/mnt/fire/6-datasource/turbo-runs"
cookie = Keyword.get(opts, :cookie, "turbo_cluster")

# Every message carries the sender's hybrid logical clock (EntityPacket/Hlc.lean: 48 bits of milliseconds, 16 of counter, one integer), kept per process:
# a send stamps, a receive merges. First-finish is decided by the stamp, not by arrival, and TURBO_EVENTS=FILE appends "cluster HLC NODE EVENT DETAIL" lines
# that tools/turbo_profile.exs merges across nodes.
hlc_send = fn ->
  {l0, c0} = Process.get(:hlc, {0, 0})
  l = max(l0, System.os_time(:millisecond))
  c = if l == l0, do: c0 + 1, else: 0
  Process.put(:hlc, {l, c})
  Bitwise.bor(Bitwise.bsl(l, 16), Bitwise.band(c, 0xFFFF))
end
hlc_recv = fn word ->
  {l0, c0} = Process.get(:hlc, {0, 0})
  ml = Bitwise.bsr(word, 16)
  mc = Bitwise.band(word, 0xFFFF)
  l = Enum.max([l0, ml, System.os_time(:millisecond)])
  c = cond do
    l == l0 and l == ml -> max(c0, mc) + 1
    l == l0 -> c0 + 1
    l == ml -> mc + 1
    true -> 0
  end
  Process.put(:hlc, {l, c})
  Bitwise.bor(Bitwise.bsl(l, 16), Bitwise.band(c, 0xFFFF))
end
trace = fn event, detail ->
  if path = System.get_env("TURBO_EVENTS"), do: File.write!(path, "cluster #{hlc_send.()} #{node()} #{event} #{detail}\n", [:append])
end

problem_text = fn cp_path, power ->
  {out, 0} = System.cmd("elixir", [Path.join(root, "tools/turbo_solve.exs"), cp_path, "--prepare", "--power", Integer.to_string(power)], env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}])
  dir = out |> String.split("\n", trim: true) |> List.last()
  File.read!(Path.join(dir, "input.txt"))
end

coordinate = fn cp_path, power, wanted ->
  Process.register(self(), :turbo_coordinator)
  if System.get_env("TURBO_DEBUG") do
    tracer = spawn(fn -> Stream.repeatedly(fn -> receive do {:trace, _, :receive, m} -> if is_tuple(m) and elem(m, 0) in [:from_worker, :hello, :DOWN], do: IO.puts("  <- " <> String.slice(inspect(m, limit: 6, printable_limit: 40), 0, 130)) end end) |> Stream.run() end)
    :erlang.trace(self(), true, [:receive, {:tracer, tracer}])
  end
  # --problem FILE hands over the solver's input text as it is (a fixture), so the coordinator needs no solver build
  text = case Keyword.get(opts, :problem) do
    nil -> problem_text.(cp_path, power)
    file -> File.read!(file)
  end
  [_, _, _, objective] = text |> String.split() |> Enum.take(4) |> Enum.map(&String.to_integer/1)
  total = Bitwise.bsl(1, power)
  steal? = not Keyword.get(opts, :no_steal, false)
  started = System.monotonic_time(:millisecond)
  now = fn -> System.monotonic_time(:millisecond) end
  IO.puts("coordinator #{node()} waiting for #{wanted} worker node(s); #{total} subproblems; stealing #{if steal?, do: "on", else: "off"}")

  share = fn st, from, bound ->
    if bound < st.bound do
      for {pid, _} <- st.workers, pid != from, do: send(pid, {:to_host, "B #{bound}", hlc_send.()})
      %{st | bound: bound}
    else
      st
    end
  end
  runners = fn st, job -> st.workers |> Enum.filter(fn {_, w} -> w.job == job end) |> Enum.map(&elem(&1, 0)) end
  live_jobs = fn st, except -> st.workers |> Enum.filter(fn {pid, w} -> pid != except and w.job != nil and not MapSet.member?(st.done, w.job) end) end
  take = fn st ->
    case st.retry do
      [index | rest] -> {index, %{st | retry: rest}}
      [] -> if st.next < total, do: {st.next, %{st | next: st.next + 1}}, else: {nil, st}
    end
  end
  # A node with nothing to do waits while some subproblem is in flight, because that one may have to be done again.
  wake = fn st ->
    for message <- Enum.reverse(st.parked), do: send(self(), message)
    %{st | parked: []}
  end
  finished? = fn st -> st.started and st.results != [] and MapSet.size(st.alive) == 0 end

  # Work stealing: a victim is a node whose subproblem has run longer than the threshold and which is clearly slower than the thief.
  # Its subproblem is treated as lost (the node is presumed dead for that job) and given to the thief; the victim keeps running until it is cancelled.
  victim = fn st, thief ->
    if steal? do
      thief_done = Map.fetch!(st.workers, thief).done_jobs
      st
      |> live_jobs.(thief)
      |> Enum.filter(fn {_pid, w} -> length(runners.(st, w.job)) == 1 and w.done_jobs < thief_done end)
      |> Enum.min_by(fn {_, w} -> w.seq end, fn -> nil end)
    end
  end

  assign = fn st, pid, job ->
    if System.get_env("TURBO_DEBUG"), do: IO.puts("  -> S #{job} to #{inspect(pid)}")
    send(pid, {:to_host, "S #{job} #{st.bound}", hlc_send.()})
    trace.("assign", "job=#{job} to=#{inspect(pid)}")
    w = Map.fetch!(st.workers, pid)
    %{st | workers: Map.put(st.workers, pid, %{w | job: job, seq: st.seq}), seq: st.seq + 1}
  end

  loop = fn loop, st ->
    receive do
      {:hello, pid, kind, w} ->
        hlc_recv.(w)
        trace.("hello", "from=#{inspect(pid)} kind=#{kind}")
        Process.monitor(pid)
        send(pid, {:problem, text, hlc_send.()})
        st = %{st | alive: MapSet.put(st.alive, pid)}
        st = put_in(st.workers[pid], %{kind: kind, job: nil, seq: 0, done_jobs: 0})
        st = if map_size(st.workers) >= wanted and not st.started, do: wake.(%{st | started: true, parked: st.parked ++ st.pending, pending: []}), else: st
        loop.(loop, st)
      {:from_worker, pid, <<"U ", rest::binary>>, w} ->
        hlc_recv.(w)
        loop.(loop, share.(st, pid, String.to_integer(rest)))
      {:from_worker, _pid, <<"A ", _::binary>>, _w} = message when not st.started ->
        loop.(loop, %{st | pending: [message | st.pending]})
      {:from_worker, pid, <<"A ", rest::binary>>, w_hlc} = message ->
        hlc_recv.(w_hlc)
        [skip, bound, solutions, nodes] = rest |> String.split() |> Enum.map(&String.to_integer/1)
        st = share.(st, pid, bound)
        w = Map.fetch!(st.workers, pid)
        # the node reports a finished or cancelled subproblem
        st =
          if w.job != nil and not MapSet.member?(st.done, w.job) do
            others = runners.(st, w.job) -- [pid]
            for other <- others, do: send(other, {:to_host, "C", hlc_send.()})
            if others != [], do: IO.puts("subproblem #{w.job} finished by #{inspect(pid)} first; #{length(others)} copy cancelled")
            trace.("finish", "job=#{w.job} by=#{inspect(pid)} stamp=#{w_hlc}")
            %{st | done: MapSet.put(st.done, w.job), finished_by: Map.update(st.finished_by, pid, 1, &(&1 + 1)),
                   won: Map.put(st.won, w.job, {w_hlc, pid}), next: max(st.next, skip)}
          else
            if w.job != nil do
              # a copy that arrived later may have finished earlier: the smaller stamp wins
              case Map.get(st.won, w.job) do
                {first, loser} when w_hlc < first ->
                  trace.("reorder", "job=#{w.job} first=#{inspect(pid)} arrived after #{inspect(loser)}")
                  fb = st.finished_by |> Map.update(loser, 0, &max(&1 - 1, 0)) |> Map.update(pid, 1, &(&1 + 1))
                  %{st | wasted: st.wasted + 1, finished_by: fb, won: Map.put(st.won, w.job, {w_hlc, pid}), reordered: st.reordered + 1}
                _ -> %{st | wasted: st.wasted + 1}
              end
            else
              %{st | next: max(st.next, skip)}
            end
          end
        st = %{st | nodes: Map.put(st.nodes, pid, nodes), solutions: Map.put(st.solutions, pid, solutions),
                    workers: Map.put(st.workers, pid, %{w | job: nil, done_jobs: w.done_jobs + (if w.job != nil, do: 1, else: 0)})}
        st = if st.parked != [] and live_jobs.(st, nil) == [], do: wake.(st), else: st
        {job, st} = take.(st)
        cond do
          job != nil ->
            loop.(loop, assign.(st, pid, job))
          (stolen = victim.(st, pid)) != nil ->
            {slow, slow_w} = stolen
            trace.("steal", "thief=#{inspect(pid)} victim=#{inspect(slow)} job=#{slow_w.job}")
            IO.puts("#{inspect(pid)} (#{Map.fetch!(st.workers, pid).kind}) presumes #{inspect(slow)} (#{slow_w.kind}) dead for subproblem #{slow_w.job} and redoes it")
            loop.(loop, assign.(%{st | steals: st.steals + 1}, pid, slow_w.job))
          live_jobs.(st, pid) != [] ->
            loop.(loop, %{st | parked: [message | st.parked]})
          true ->
            if System.get_env("TURBO_DEBUG"), do: IO.puts("  -> D to #{inspect(pid)}")
            send(pid, {:to_host, "D", hlc_send.()})
            loop.(loop, wake.(st))
        end
      {:from_worker, pid, <<"R ", rest::binary>>, w} ->
        hlc_recv.(w)
        [head | rows] = String.split(rest, "\n", trim: true)
        [nodes, fails, solutions, bound, depth, exhaustive] = head |> String.split() |> Enum.map(&String.to_integer/1)
        result = %{pid: pid, kind: Map.fetch!(st.workers, pid).kind, nodes: nodes, fails: fails, solutions: solutions, bound: bound, depth: depth, exhaustive: exhaustive, store: rows}
        st = %{st | results: [result | st.results], alive: MapSet.delete(st.alive, pid)}
        if finished?.(st), do: {:ok, st}, else: loop.(loop, st)
      {:DOWN, _, :process, pid, _reason} ->
        st =
          case Map.get(st.workers, pid) do
            %{job: index} when index != nil ->
              if MapSet.member?(st.done, index) or runners.(st, index) -- [pid] != [] do
                st
              else
                IO.puts("worker #{inspect(pid)} lost; subproblem #{index} goes back in the queue")
                %{st | retry: [index | st.retry]}
              end
            _ -> st
          end
        st = wake.(%{st | workers: Map.delete(st.workers, pid), alive: MapSet.delete(st.alive, pid)})
        if finished?.(st), do: {:ok, st}, else: loop.(loop, st)
    end
  end
  state = %{workers: %{}, next: 0, bound: 2_147_483_647, retry: [], solutions: %{}, nodes: %{}, results: [], pending: [], parked: [], started: false, alive: MapSet.new(),
            done: MapSet.new(), finished_by: %{}, seq: 0, steals: 0, wasted: 0, won: %{}, reordered: 0}
  {:ok, final} = loop.(loop, state)
  if System.get_env("TURBO_DEBUG"), do: IO.puts("  registered #{inspect(Map.keys(final.workers))} results #{inspect(Enum.map(final.results, & &1.pid))}")
  best = final.results |> Enum.filter(&(&1.solutions > 0)) |> Enum.min_by(& &1.bound, fn -> nil end)
  IO.puts("done in #{now.() - started} ms on #{length(final.results)} node(s) of #{wanted} started (#{map_size(final.workers)} registered); #{final.steals} steal(s), #{MapSet.size(final.done)} of #{total} subproblems done, #{final.wasted} redone copies discarded, #{final.reordered} finish(es) reordered by their stamps")
  for r <- Enum.sort_by(final.results, &{&1.kind, -&1.nodes}),
      do: IO.puts("  #{r.kind} node: #{Map.get(final.finished_by, r.pid, 0)} subproblems, nodes #{r.nodes} fails #{r.fails} solutions #{r.solutions} bound #{r.bound} exhaustive #{r.exhaustive}")
  IO.puts("total nodes #{Enum.sum(Enum.map(final.results, & &1.nodes))} solutions #{Enum.sum(Enum.map(final.results, & &1.solutions))}")
  if best && objective >= 0 do
    [lower, upper] = best.store |> Enum.at(objective) |> String.split()
    IO.puts("objective [#{lower}, #{upper}]")
  else
    IO.puts("no solution")
  end
end

work = fn coord, guest, host_bin, budget, kind ->
  true = Node.connect(coord)
  Node.monitor(coord, true)
  frame_env = case Keyword.get(opts, :frame_ms) do
    nil -> []
    ms -> [{~c"TURBO_FRAME_MS", ~c"#{ms}"}]
  end
  port = Port.open({:spawn_executable, host_bin}, [:binary, :exit_status, {:packet, 4}, {:env, frame_env}, {:args, [guest, Integer.to_string(budget)]}])
  # The worker is a small state machine. `held` is a job it was given and has not started: with --hold-first-job the first assignment is kept, standing for a node that
  # is busy elsewhere, and a cancel while holding is answered for the host (the finished frame), after which the node is ready again.
  loop = fn loop, st ->
    receive do
      {^port, {:data, "H"}} ->
        send({:turbo_coordinator, coord}, {:hello, self(), kind, hlc_send.()})
        loop.(loop, st)
      {:problem, text, w} ->
        hlc_recv.(w)
        Port.command(port, "P " <> text)
        loop.(loop, st)
      {:to_host, frame, w} ->
        hlc_recv.(w)
        assignment? = String.starts_with?(frame, "S ")
        cond do
          assignment? and Keyword.get(opts, :die_at_first_job, false) ->
            IO.puts("worker #{node()} dies on its first assignment")
            System.halt(1)
          assignment? and Keyword.get(opts, :hold_first_job, false) and not st.spent ->
            trace.("hold", String.slice(frame, 0, 12))
            loop.(loop, %{st | held: frame, spent: true})
          frame == "C" and st.held != nil ->
            [_, _, bound] = String.split(st.held)
            trace.("release", "cancelled while held")
            send({:turbo_coordinator, coord}, {:from_worker, self(), "A 0 #{bound} 0 0", hlc_send.()})
            loop.(loop, %{st | held: nil})
          true ->
            Port.command(port, frame)
            loop.(loop, st)
        end
      {^port, {:data, frame}} ->
        trace.("send", String.slice(frame, 0, 12))
        send({:turbo_coordinator, coord}, {:from_worker, self(), frame, hlc_send.()})
        if String.starts_with?(frame, "R "), do: :ok, else: loop.(loop, st)
      {:nodedown, ^coord} ->
        System.halt(0)
      {^port, {:exit_status, code}} ->
        if code != 0, do: IO.puts("host exited with #{code}")
    end
  end
  loop.(loop, %{held: nil, spent: false})
end

case role do
  "coordinator" ->
    [cp_path] = args
    Node.start(String.to_atom(System.get_env("NODE_NAME", "coord@127.0.0.1")), :longnames)
    Node.set_cookie(String.to_atom(cookie))
    coordinate.(cp_path, Keyword.get(opts, :power, 0), Keyword.get(opts, :workers, 1))
  "worker" ->
    [coord, guest, host_bin] = args
    name = System.get_env("NODE_NAME", "w#{System.unique_integer([:positive])}@127.0.0.1")
    Node.start(String.to_atom(name), :longnames)
    Node.set_cookie(String.to_atom(cookie))
    work.(String.to_atom(coord), guest, host_bin, Keyword.get(opts, :budget, 50_000_000), Keyword.get(opts, :kind, "cpu"))
  "local" ->
    [cp_path] = args
    spec = Keyword.get(opts, :nodes, "cpu:#{Keyword.get(opts, :workers, 2)}")
    kinds = spec |> String.split(",") |> Enum.flat_map(fn part -> [kind, count] = String.split(part, ":"); List.duplicate(kind, String.to_integer(count)) end)
    guest = Keyword.get(opts, :guest, Path.join(runs, "guest/turbo_guest.elf"))
    host_bin = Keyword.get(opts, :host, Path.join(runs, "host-build/turbo_host"))
    slow_us = Keyword.get(opts, :slow_us, 0)
    Node.start(:"coord@127.0.0.1", :longnames)
    Node.set_cookie(String.to_atom(cookie))
    ports =
      for {kind, k} <- Enum.with_index(kinds, 1) do
        throttled = kind == "cpu" and slow_us > 0
        budget = if throttled, do: 1_000_000, else: Keyword.get(opts, :budget, 50_000_000)
        env = [{~c"NODE_NAME", ~c"w#{k}@127.0.0.1"}, {~c"ELIXIR_ERL_OPTIONS", ~c"+fnu"}] ++
              (if throttled, do: [{~c"TURBO_SLEEP_US", ~c"#{slow_us}"}], else: []) ++
              []
        Port.open({:spawn_executable, System.find_executable("nice")},
          [:binary, :exit_status,
           {:args, ["-n", "19", System.find_executable("elixir"), Path.join(root, "tools/turbo_cluster.exs"), "worker", "coord@127.0.0.1", guest, host_bin,
                    "--budget", Integer.to_string(budget), "--kind", kind, "--cookie", cookie] ++ (if k == 2 and Keyword.get(opts, :kill_one, false), do: ["--die-at-first-job"], else: []) ++ (case Keyword.get(opts, :frame_ms) do nil -> []; ms -> ["--frame-ms", to_string(ms)] end)}, {:env, env}])
      end
    coordinate.(cp_path, Keyword.get(opts, :power, 0), length(kinds))
    for p <- ports, Port.info(p) != nil, do: Port.close(p)
end
