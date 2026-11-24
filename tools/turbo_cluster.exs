# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-FileCopyrightText: 2025 Pierre Talbot
# SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
# SPDX-License-Identifier: Apache-2.0 AND MIT
# Distributed solving over Erlang distribution: a coordinator node hands out subproblems; worker nodes (one per core, GPU or machine) each run the solver guest ELF
# under libriscv. Nodes are cookie-authenticated Erlang nodes, so a worker can be on another machine: start it there with the same cookie.
#   coordinator:  NODE_NAME=coord@HOST elixir tools/turbo_cluster.exs coordinator LEVEL.cp [--power P] [--workers N] [--replicas R] [--strikes S] [--forgive-after M]
#                 [--lifetime-strikes L] [--no-steal] [--problem INPUT.txt] [--cookie C]
#   worker:       NODE_NAME=wK@HOST elixir tools/turbo_cluster.exs worker coord@HOST GUEST.elf HOST_BINARY [--kind cpu|gpu] [--budget INSTRUCTIONS] [--frame-ms MS]
#                 [--hold-first-job] [--die-at-first-job] [--lie] [--lie-times N] [--cookie C]
#   local:        elixir tools/turbo_cluster.exs local LEVEL.cp [--power P] [--nodes gpu:1,cpu:2] [--kill-one] [--frame-ms 2.0] and the coordinator's options
# --frame-ms runs every guest in 64 Hz frames of that much compute time, for a machine that also runs a real-time game.
# The coordinator trusts no node. A subproblem's answer depends only on the problem, its index and the bound it is assigned with (tools/cluster_replay.exs checks this),
# so an answer is accepted when --replicas nodes (f + 1, default 2) give the same one; a node whose answer differs from the accepted one gets a strike.
# Both sides are gen_statem machines and no decision reads a clock. Message formats are in service/turbo-cluster.asyncapi.yaml.
{opts, [role | args], _} =
  OptionParser.parse(System.argv(),
    strict: [power: :integer, workers: :integer, budget: :integer, cookie: :string, guest: :string, host: :string, kind: :string, nodes: :string, problem: :string,
             frame_ms: :float, no_steal: :boolean, kill_one: :boolean, hold_first_job: :boolean, die_at_first_job: :boolean, lie: :boolean, lie_times: :integer,
             replicas: :integer, strikes: :integer, forgive_after: :integer, lifetime_strikes: :integer])
root = File.cwd!()
runs = "/mnt/fire/6-datasource/turbo-runs"
cookie = Keyword.get(opts, :cookie, "turbo_cluster")

# Every message carries the sender's hybrid logical clock (EntityPacket/Hlc.lean: 48 bits of milliseconds, 16 of counter, one integer), kept per process: a send
# stamps, a receive merges. A stamp more than a minute ahead of this node's own clock is not merged (one node must not be able to push every clock forward).
# TURBO_EVENTS=FILE appends "cluster HLC NODE EVENT DETAIL" lines that tools/turbo_profile.exs merges across nodes.
defmodule Turbo.Hlc do
  @moduledoc false
  @ahead_ms 60_000

  def send do
    {logical, counter} = Process.get(:hlc, {0, 0})
    now = max(logical, System.os_time(:millisecond))
    put(now, if(now == logical, do: counter + 1, else: 0))
  end

  def recv(word) do
    {logical, counter} = Process.get(:hlc, {0, 0})
    physical = System.os_time(:millisecond)
    theirs = Bitwise.bsr(word, 16)
    their_counter = Bitwise.band(word, 0xFFFF)
    if theirs > physical + @ahead_ms do
      trace("refused", "a stamp #{theirs - physical} ms ahead")
      send()
    else
      now = Enum.max([logical, theirs, physical])
      put(now, merged_counter(now, {logical, counter}, {theirs, their_counter}))
    end
  end

  defp merged_counter(now, {now, counter}, {now, their_counter}), do: max(counter, their_counter) + 1
  defp merged_counter(now, {now, counter}, _theirs), do: counter + 1
  defp merged_counter(now, _mine, {now, their_counter}), do: their_counter + 1
  defp merged_counter(_now, _mine, _theirs), do: 0

  defp put(logical, counter) do
    Process.put(:hlc, {logical, counter})
    Bitwise.bor(Bitwise.bsl(logical, 16), Bitwise.band(counter, 0xFFFF))
  end

  def trace(event, detail) do
    if path = System.get_env("TURBO_EVENTS"), do: File.write!(path, "cluster #{__MODULE__.send()} #{node()} #{event} #{detail}\n", [:append])
  end
end

# The coordinator: a gen_statem with the states `registering` (until all wanted nodes have joined; answers are postponed) and `running`.
# Data: nodes (the job in hand, counters, strikes), jobs (the bound given, who tried it, live runners, answers, the accepted answer, replicas wanted), the set of nodes
# waiting for work. A waiting node is looked at again only after an event that changed a job or a node. When every live node waits and a job is still open the run
# stops with "no quorum" instead of waiting for ever.
defmodule Turbo.Coordinator do
  @moduledoc false
  @behaviour :gen_statem
  @infinity 2_147_483_647
  alias Turbo.Hlc

  def start(config), do: :gen_statem.start_link({:local, :turbo_coordinator}, __MODULE__, config, [])

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(config) do
    counters = %{next: 0, bound: @infinity, sequence: 0, extra: 0, frauds: 0, accepted: 0, started: System.monotonic_time(:millisecond)}
    sets = %{nodes: %{}, jobs: %{}, waiting: MapSet.new(), banned: MapSet.new(), alive: MapSet.new(), results: []}
    IO.puts("coordinator #{node()} waiting for #{config.wanted} worker node(s); #{config.total} subproblems; #{config.faults + 1} equal answers accept one")
    {:ok, :registering, config |> Map.merge(counters) |> Map.merge(sets)}
  end

  def registering(:info, {:hello, pid, kind, stamp}, data) do
    data = register(data, pid, kind, stamp)
    if map_size(data.nodes) >= data.wanted, do: {:next_state, :running, data}, else: {:keep_state, data}
  end
  def registering(:info, {:from_worker, _pid, _frame, _stamp}, _data), do: {:keep_state_and_data, :postpone}
  def registering(:info, {:DOWN, _, :process, pid, _}, data), do: {:keep_state, lose(data, pid)}

  def running(:info, {:hello, pid, kind, stamp}, data), do: {:keep_state, register(data, pid, kind, stamp)}
  def running(:info, {:from_worker, pid, <<"A ", rest::binary>>, stamp}, data) do
    Hlc.recv(stamp)
    fields = rest |> String.split() |> Enum.map(&String.to_integer/1)
    data |> answer(pid, fields) |> serve(pid) |> settle()
  end
  def running(:info, {:from_worker, pid, <<"R ", rest::binary>>, stamp}, data) do
    Hlc.recv(stamp)
    settle(%{data | results: [result(data, pid, rest) | data.results], alive: MapSet.delete(data.alive, pid), waiting: MapSet.delete(data.waiting, pid)})
  end
  def running(:info, {:from_worker, _pid, _bound_report, stamp}, _data) do
    Hlc.recv(stamp)
    :keep_state_and_data
  end
  def running(:info, {:DOWN, _, :process, pid, _}, data), do: data |> lose(pid) |> settle()

  # ---- nodes

  defp register(data, pid, kind, stamp) do
    Hlc.recv(stamp)
    Hlc.trace("hello", "from=#{inspect(pid)} kind=#{kind}")
    Process.monitor(pid)
    send(pid, {:problem, data.text, Hlc.send()})
    node = %{kind: kind, job: nil, cancelled: false, done_jobs: 0, strikes: 0, streak: 0, lifetime: 0}
    %{data | nodes: Map.put(data.nodes, pid, node), alive: MapSet.put(data.alive, pid)}
  end

  defp lose(data, pid) do
    data = release(data, pid, "worker #{inspect(pid)} lost")
    %{data | nodes: Map.delete(data.nodes, pid), alive: MapSet.delete(data.alive, pid), waiting: MapSet.delete(data.waiting, pid)}
  end

  # The job in a node's hand goes back to the queue (the node died or was banned).
  defp release(data, pid, why) do
    case data.nodes[pid] do
      %{job: index} when index != nil ->
        job = data.jobs[index]
        if job.accepted == nil, do: IO.puts("#{why}; subproblem #{index} goes back in the queue")
        put_in(data.jobs[index], %{job | runners: MapSet.delete(job.runners, pid)})
      _ -> data
    end
  end

  defp result(data, pid, text) do
    [head | rows] = String.split(text, "\n", trim: true)
    [nodes, fails, solutions, bound, depth, exhaustive] = head |> String.split() |> Enum.map(&String.to_integer/1)
    kind = get_in(data.nodes, [pid, :kind]) || "gone"
    %{pid: pid, kind: kind, nodes: nodes, fails: fails, solutions: solutions, bound: bound, depth: depth, exhaustive: exhaustive, store: rows}
  end

  # ---- answers

  # A waiting frame: the node finished (or was cancelled on) the job in its hand, or it has none yet.
  # The four numbers are the answer of the subproblem itself: the first subproblem it did not make unreachable, its best bound, its solutions and its nodes.
  defp answer(data, pid, [skip, bound, solutions, nodes]) do
    node = data.nodes[pid]
    data = put_in(data.nodes[pid], %{node | job: nil, done_jobs: node.done_jobs + if(node.job == nil, do: 0, else: 1)})
    cond do
      node.job == nil or MapSet.member?(data.banned, pid) -> data
      node.cancelled -> finish_run(data, node.job, pid)
      true -> data |> finish_run(node.job, pid) |> record(node.job, pid, {skip, bound, solutions, nodes})
    end
  end

  defp finish_run(data, index, pid), do: update_in(data.jobs[index].runners, &MapSet.delete(&1, pid))

  defp record(data, index, pid, value) do
    Hlc.trace("answer", "job=#{index} by=#{inspect(pid)}")
    data = put_in(data.jobs[index].answers[pid], value)
    case data.jobs[index].accepted do
      nil -> judge(data, index)
      accepted -> compare(data, pid, index, value, accepted)
    end
  end

  # Accept at f + 1 equal answers of nodes with no strike; ask for one more replica when the answers in hand cannot reach that.
  defp judge(data, index) do
    job = data.jobs[index]
    counted = for {pid, value} <- job.answers, trusted?(data, pid), do: value
    winner = counted |> Enum.frequencies() |> Enum.find(fn {_value, count} -> count >= data.faults + 1 end)
    cond do
      winner != nil -> accept(data, index, elem(winner, 0))
      length(counted) >= job.demand and job.demand < 2 * data.faults + 1 ->
        IO.puts("subproblem #{index}: answers disagree, one more replica")
        put_in(data.jobs[index].demand, job.demand + 1)
      true -> data
    end
  end

  defp accept(data, index, {skip, bound, _solutions, _nodes} = value) do
    job = data.jobs[index]
    Hlc.trace("accept", "job=#{index} bound=#{bound}")
    for pid <- job.runners, do: send(pid, {:to_host, "C", Hlc.send()})
    nodes = Enum.reduce(job.runners, data.nodes, fn pid, nodes -> Map.update!(nodes, pid, &%{&1 | cancelled: true}) end)
    data = %{data | nodes: nodes, bound: min(data.bound, bound), next: max(data.next, skip), accepted: data.accepted + 1,
                    jobs: Map.put(data.jobs, index, %{job | accepted: value, runners: MapSet.new()})}
    Enum.reduce(job.answers, data, fn {pid, theirs}, data -> compare(data, pid, index, theirs, value) end)
  end

  defp compare(data, pid, index, value, accepted) do
    cond do
      MapSet.member?(data.banned, pid) or data.nodes[pid] == nil -> data
      value == accepted -> agree(data, pid)
      true -> strike(data, pid, index, value, accepted)
    end
  end

  # ---- strikes: trusted -> probation -> banned, by counts only

  defp trusted?(data, pid), do: not MapSet.member?(data.banned, pid) and data.nodes[pid] != nil and data.nodes[pid].strikes == 0

  defp agree(data, pid) do
    node = data.nodes[pid]
    streak = node.streak + 1
    if node.strikes > 0 and streak >= data.forgive_after do
      IO.puts("forgiven: #{inspect(pid)} gave #{streak} accepted answers in a row, strikes #{node.strikes} -> #{node.strikes - 1}")
      Hlc.trace("forgive", "node=#{inspect(pid)}")
      put_in(data.nodes[pid], %{node | strikes: node.strikes - 1, streak: 0})
    else
      put_in(data.nodes[pid], %{node | streak: streak})
    end
  end

  defp strike(data, pid, index, value, accepted) do
    node = data.nodes[pid]
    node = %{node | strikes: node.strikes + 1, lifetime: node.lifetime + 1, streak: 0}
    IO.puts("fraud: #{inspect(pid)} answered #{inspect(value)} for subproblem #{index}, accepted #{inspect(accepted)} (strike #{node.strikes} of #{data.strike_limit}, #{node.lifetime} in all)")
    Hlc.trace("fraud", "job=#{index} node=#{inspect(pid)} strike=#{node.strikes}")
    data = %{put_in(data.nodes[pid], node) | frauds: data.frauds + 1}
    if node.strikes >= data.strike_limit or node.lifetime >= data.lifetime_limit, do: ban(data, pid), else: data
  end

  # A banned node is told to stop; its live job goes back to the queue and its answers to jobs still open are void.
  defp ban(data, pid) do
    IO.puts("banned: #{inspect(pid)}")
    send(pid, {:to_host, "D", Hlc.send()})
    data = release(data, pid, "node #{inspect(pid)} banned")
    jobs = Map.new(data.jobs, fn {index, job} -> {index, if(job.accepted == nil, do: %{job | answers: Map.delete(job.answers, pid)}, else: job)} end)
    %{data | jobs: jobs, banned: MapSet.put(data.banned, pid), waiting: MapSet.delete(data.waiting, pid)}
  end

  # ---- the queue

  # Replicas a job still wants: answers and live runs of nodes on probation do not count.
  defp need(data, job) do
    counted = Enum.count(Map.keys(job.answers), &trusted?(data, &1)) + Enum.count(job.runners, &trusted?(data, &1))
    job.demand - counted
  end

  # What a node asking for work gets: the lowest job that wants a replica and that it has not tried; else the next new index; else an extra replica of the oldest
  # job all of whose runners have answered fewer jobs than this node; else it waits while any job is open; else there is nothing left.
  defp pick(data, pid) do
    open = for {index, job} <- data.jobs, job.accepted == nil, not MapSet.member?(job.tried, pid), do: {index, job}
    wanting = for {index, job} <- open, need(data, job) > 0, do: index
    cond do
      wanting != [] -> {:job, Enum.min(wanting), :replica}
      data.next < data.total -> {:job, data.next, :new}
      (index = extra_replica(data, pid, open)) != nil -> {:job, index, :extra}
      Enum.any?(data.jobs, fn {_index, job} -> job.accepted == nil end) -> :wait
      true -> :done
    end
  end

  defp extra_replica(%{steal?: false}, _pid, _open), do: nil
  defp extra_replica(data, pid, open) do
    done = data.nodes[pid].done_jobs
    slower? = fn job -> MapSet.size(job.runners) > 0 and Enum.all?(job.runners, &(data.nodes[&1].done_jobs < done)) end
    case open |> Enum.filter(fn {_index, job} -> slower?.(job) end) |> Enum.min_by(fn {_index, job} -> job.sequence end, fn -> nil end) do
      {index, _job} -> index
      nil -> nil
    end
  end

  defp serve(data, pid) do
    cond do
      MapSet.member?(data.banned, pid) or data.nodes[pid] == nil or data.nodes[pid].job != nil -> data
      true -> hand(data, pid, pick(data, pid))
    end
  end

  defp hand(data, pid, {:job, index, kind}), do: assign(%{data | waiting: MapSet.delete(data.waiting, pid)}, pid, index, kind)
  defp hand(data, pid, :wait), do: %{data | waiting: MapSet.put(data.waiting, pid)}
  defp hand(data, pid, :done) do
    send(pid, {:to_host, "D", Hlc.send()})
    %{data | waiting: MapSet.delete(data.waiting, pid)}
  end

  defp assign(data, pid, index, kind) do
    data = if kind == :new, do: open_job(data, index), else: data
    job = data.jobs[index]
    send(pid, {:to_host, "S #{index} #{job.bound}", Hlc.send()})
    Hlc.trace("assign", "job=#{index} to=#{inspect(pid)} kind=#{kind}")
    node = data.nodes[pid]
    job = %{job | tried: MapSet.put(job.tried, pid), runners: MapSet.put(job.runners, pid)}
    %{data | jobs: Map.put(data.jobs, index, job), nodes: Map.put(data.nodes, pid, %{node | job: index, cancelled: false}),
             extra: data.extra + if(kind == :extra, do: 1, else: 0)}
  end

  # The bound a job is given is fixed here, from accepted answers only, so every replica of it gets the same one.
  defp open_job(data, index) do
    job = %{bound: data.bound, tried: MapSet.new(), runners: MapSet.new(), answers: %{}, accepted: nil, demand: data.faults + 1, sequence: data.sequence}
    %{data | jobs: Map.put(data.jobs, index, job), next: index + 1, sequence: data.sequence + 1}
  end

  # ---- after every event

  defp settle(data) do
    data = Enum.reduce(Enum.sort(data.waiting), data, &serve(&2, &1))
    cond do
      MapSet.size(data.alive) == 0 and data.results != [] and stuck_job(data) == nil -> finish(data)
      stuck_job(data) != nil and idle?(data) -> no_quorum(data, stuck_job(data))
      true -> {:keep_state, data}
    end
  end

  defp stuck_job(data), do: Enum.find(Enum.sort(data.jobs), fn {_index, job} -> job.accepted == nil end)

  # Nothing is running and every node that could still work is waiting (or none is left).
  defp idle?(data) do
    working = for {pid, node} <- data.nodes, not MapSet.member?(data.banned, pid), MapSet.member?(data.alive, pid), node.job != nil, do: pid
    able = for {pid, _node} <- data.nodes, not MapSet.member?(data.banned, pid), MapSet.member?(data.alive, pid), do: pid
    working == [] and Enum.all?(able, &MapSet.member?(data.waiting, &1))
  end

  defp no_quorum(data, {index, job}) do
    IO.puts("no quorum for subproblem #{index}: #{data.faults + 1} equal answers needed, answers #{inspect(Map.values(job.answers))}, #{MapSet.size(job.tried)} node(s) tried it, #{MapSet.size(data.waiting)} waiting")
    for pid <- data.alive, do: send(pid, {:to_host, "D", Hlc.send()})
    summary(data)
    {:stop, {:shutdown, :no_quorum}}
  end

  defp finish(data) do
    summary(data)
    if data.bound < @infinity, do: IO.puts("objective [#{data.bound}, #{data.bound}]"), else: IO.puts("no solution")
    {:stop, :normal}
  end

  # The objective is the smallest accepted bound: it rests on f + 1 equal answers, never on one node's final report.
  defp summary(data) do
    honest = Enum.reject(data.results, &MapSet.member?(data.banned, &1.pid))
    elapsed = System.monotonic_time(:millisecond) - data.started
    IO.puts("done in #{elapsed} ms on #{length(honest)} node(s) of #{data.wanted} started; #{data.accepted} of #{data.total} subproblems accepted with #{data.faults + 1} equal answers (the rest skipped), #{data.extra} extra replica(s), #{data.frauds} fraud(s), #{MapSet.size(data.banned)} node(s) banned")
    for report <- Enum.sort_by(honest, &{&1.kind, -&1.nodes}),
        do: IO.puts("  #{report.kind} node: nodes #{report.nodes} fails #{report.fails} solutions #{report.solutions} exhaustive #{report.exhaustive}")
    IO.puts("total nodes #{Enum.sum(Enum.map(honest, & &1.nodes))} solutions #{Enum.sum(Enum.map(honest, & &1.solutions))}")
  end
end

# The worker: a gen_statem with two states. In `ready` frames go through to the guest host. With --hold-first-job the first assignment is kept instead (the node is
# busy elsewhere) and the worker is `held`: it answers a cancel for the host with the waiting frame and is ready again; every other frame still goes through.
defmodule Turbo.Worker do
  @moduledoc false
  @behaviour :gen_statem
  alias Turbo.Hlc

  def start(args), do: :gen_statem.start_link(__MODULE__, args, [])

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(%{coordinator: coordinator, guest: guest, host: host, budget: budget, frame_env: frame_env} = args) do
    true = Node.connect(coordinator)
    Node.monitor(coordinator, true)
    port = Port.open({:spawn_executable, host}, [:binary, :exit_status, {:packet, 4}, {:env, frame_env}, {:args, [guest, Integer.to_string(budget)]}])
    {:ok, :ready, Map.merge(args, %{port: port, held: nil, spent: false, assigned: 0})}
  end

  def ready(:info, {:to_host, <<"S ", _::binary>> = frame, stamp}, data) do
    Hlc.recv(stamp)
    cond do
      data.die_first ->
        IO.puts("worker #{node()} dies on its first assignment")
        System.halt(1)
      data.hold_first and not data.spent ->
        Hlc.trace("hold", String.slice(frame, 0, 12))
        {:next_state, :held, %{data | held: frame, spent: true}}
      true ->
        Port.command(data.port, frame)
        {:keep_state, %{data | assigned: data.assigned + 1}}
    end
  end
  def ready(:info, {:to_host, frame, stamp}, data), do: forward(frame, stamp, data)
  def ready(:info, event, data), do: common(event, data)

  def held(:info, {:to_host, "C", stamp}, data) do
    Hlc.recv(stamp)
    [_, _, bound] = String.split(data.held)
    Hlc.trace("release", "cancelled while held")
    report(data, "A 0 #{bound} 0 0")
    {:next_state, :ready, %{data | held: nil}}
  end
  def held(:info, {:to_host, frame, stamp}, data), do: forward(frame, stamp, data)
  def held(:info, event, data), do: common(event, data)

  defp forward(frame, stamp, data) do
    Hlc.recv(stamp)
    Port.command(data.port, frame)
    :keep_state_and_data
  end

  defp report(data, frame), do: send({:turbo_coordinator, data.coordinator}, {:from_worker, self(), frame, Hlc.send()})

  defp common({port, {:data, "H"}}, %{port: port} = data) do
    send({:turbo_coordinator, data.coordinator}, {:hello, self(), data.kind, Hlc.send()})
    :keep_state_and_data
  end
  defp common({:problem, text, stamp}, data), do: forward("P " <> text, stamp, data)
  # a node that lies: --lie answers every subproblem wrongly, --lie-times N only its first N answers (a flaky node)
  defp common({port, {:data, <<"A ", rest::binary>>}}, %{port: port, lies: lies, assigned: assigned} = data) when lies > 0 and assigned > 0 do
    [skip, bound, solutions, nodes] = rest |> String.split() |> Enum.map(&String.to_integer/1)
    report(data, "A #{skip} #{bound - 1} #{solutions} #{nodes + 1}")
    {:keep_state, %{data | lies: lies - 1, assigned: assigned - 1}}
  end
  defp common({port, {:data, frame}}, %{port: port} = data) do
    Hlc.trace("send", String.slice(frame, 0, 12))
    report(data, frame)
    if String.starts_with?(frame, "R "), do: {:stop, :normal}, else: :keep_state_and_data
  end
  defp common({:nodedown, coordinator}, %{coordinator: coordinator}), do: System.halt(0)
  defp common({port, {:exit_status, code}}, %{port: port}) do
    if code != 0, do: IO.puts("host exited with #{code}")
    {:stop, :normal}
  end
  defp common(_other, _data), do: :keep_state_and_data
end

problem_text = fn cp_path, power ->
  {out, 0} = System.cmd("elixir", [Path.join(root, "tools/turbo_solve.exs"), cp_path, "--prepare", "--power", Integer.to_string(power)], env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}])
  File.read!(Path.join(out |> String.split("\n", trim: true) |> List.last(), "input.txt"))
end

# Run a machine to its end and give its stop reason.
await = fn {:ok, pid} ->
  reference = Process.monitor(pid)
  receive do
    {:DOWN, ^reference, :process, ^pid, reason} -> reason
  end
end

coordinate = fn cp_path, power, wanted ->
  # --problem FILE hands over the solver's input text as it is (a fixture), so the coordinator needs no solver build
  text = case Keyword.get(opts, :problem) do
    nil -> problem_text.(cp_path, power)
    file -> File.read!(file)
  end
  strikes = Keyword.get(opts, :strikes, 3)
  Process.flag(:trap_exit, true)
  reason = await.(Turbo.Coordinator.start(%{text: text, total: Bitwise.bsl(1, power), wanted: wanted, faults: Keyword.get(opts, :replicas, 2) - 1,
    steal?: not Keyword.get(opts, :no_steal, false), strike_limit: strikes, forgive_after: Keyword.get(opts, :forgive_after, 3),
    lifetime_limit: Keyword.get(opts, :lifetime_strikes, 2 * strikes)}))
  if reason != :normal, do: System.halt(1)
end

work = fn coordinator, guest, host, budget, kind ->
  frame_env = case Keyword.get(opts, :frame_ms) do
    nil -> []
    ms -> [{~c"TURBO_FRAME_MS", ~c"#{ms}"}]
  end
  lies = if Keyword.get(opts, :lie, false), do: 1_000_000_000, else: Keyword.get(opts, :lie_times, 0)
  Process.flag(:trap_exit, true)
  await.(Turbo.Worker.start(%{coordinator: coordinator, guest: guest, host: host, budget: budget, frame_env: frame_env, kind: kind, lies: lies,
    hold_first: Keyword.get(opts, :hold_first_job, false), die_first: Keyword.get(opts, :die_at_first_job, false)}))
end

case role do
  "coordinator" ->
    [cp_path] = args
    Node.start(String.to_atom(System.get_env("NODE_NAME", "coord@127.0.0.1")), :longnames)
    Node.set_cookie(String.to_atom(cookie))
    coordinate.(cp_path, Keyword.get(opts, :power, 0), Keyword.get(opts, :workers, 1))
  "worker" ->
    [coordinator, guest, host] = args
    name = System.get_env("NODE_NAME", "w#{System.unique_integer([:positive])}@127.0.0.1")
    Node.start(String.to_atom(name), :longnames)
    Node.set_cookie(String.to_atom(cookie))
    work.(String.to_atom(coordinator), guest, host, Keyword.get(opts, :budget, 50_000_000), Keyword.get(opts, :kind, "cpu"))
  "local" ->
    [cp_path] = args
    spec = Keyword.get(opts, :nodes, "cpu:#{Keyword.get(opts, :workers, 2)}")
    kinds = spec |> String.split(",") |> Enum.flat_map(fn part -> [kind, count] = String.split(part, ":"); List.duplicate(kind, String.to_integer(count)) end)
    guest = Keyword.get(opts, :guest, Path.join(runs, "guest/turbo_guest.elf"))
    host = Keyword.get(opts, :host, Path.join(runs, "host-build/turbo_host"))
    frame = case Keyword.get(opts, :frame_ms) do nil -> []; ms -> ["--frame-ms", to_string(ms)] end
    Node.start(:"coord@127.0.0.1", :longnames)
    Node.set_cookie(String.to_atom(cookie))
    ports =
      for {kind, number} <- Enum.with_index(kinds, 1) do
        dies = if number == 2 and Keyword.get(opts, :kill_one, false), do: ["--die-at-first-job"], else: []
        worker = ["worker", "coord@127.0.0.1", guest, host, "--budget", Integer.to_string(Keyword.get(opts, :budget, 50_000_000)), "--kind", kind, "--cookie", cookie]
        Port.open({:spawn_executable, System.find_executable("nice")},
          [:binary, :exit_status, {:env, [{~c"NODE_NAME", ~c"w#{number}@127.0.0.1"}, {~c"ELIXIR_ERL_OPTIONS", ~c"+fnu"}]},
           {:args, ["-n", "19", System.find_executable("elixir"), Path.join(root, "tools/turbo_cluster.exs")] ++ worker ++ dies ++ frame}])
      end
    coordinate.(cp_path, Keyword.get(opts, :power, 0), length(kinds))
    for port <- ports, Port.info(port) != nil, do: Port.close(port)
end
