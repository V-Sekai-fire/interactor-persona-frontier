# SPDX-License-Identifier: MIT
# party_saga.exs  check | solve FILE.dzn [SOLVER] | practice | learn | frontier [--steps N] [--limit S] [--max-held H]
# The quest-beater (Saga.Gen) builds a level; the quest-solver (MiniZinc oracles) tries it; the loop is the frontier loop.
defmodule Saga do
  @root Path.expand("../entities/fixtures/minizinc/party-saga", __DIR__)
  @home System.get_env("MINIZINC_HOME", "/mnt/fire/6-datasource/minizinc-bundle/x/MiniZincIDE-2.11.0-x86_64-linux-gnu")
  @modes ~w(STICK SPRINT CLIMB TELEPORT)
  @elements ~w(EMBER TIDE STONE GALE)
  @tracks ~w(scout arms controller party loadout board saga)
  @steps [2, 4, 6, 8, 12, 16, 24, 32, 48, 64]
  def root, do: @root
  def tracks, do: @tracks
  def steps, do: @steps

  def terrain(t), do: t |> to_string() |> String.upcase()
  def flat(rows), do: List.flatten(rows)
  def list(xs), do: "[" <> Enum.map_join(xs, ", ", &val/1) <> "]"
  def val(v) when is_boolean(v), do: to_string(v)
  def val(v) when is_integer(v), do: Integer.to_string(v)
  def val(v) when is_atom(v), do: v |> to_string() |> String.upcase()
  def val(v) when is_binary(v), do: v
  def table(rows, enum, xs), do: "array2d(1..#{rows}, #{enum}, #{list(xs)})"
  def bools(xs, all), do: Enum.map(all, &(&1 in xs))

  def render(w) do
    cs = w.chars
    ts = w.tasks
    rows = fn f -> Enum.map(ts, f) end
    [
      "nn = #{w.nodes}; ne = #{length(w.edges)};",
      "from = #{list(Enum.map(w.edges, &elem(&1, 0)))}; to = #{list(Enum.map(w.edges, &elem(&1, 1)))};",
      "length = #{list(Enum.map(w.edges, &elem(&1, 2)))}; terrain = #{list(Enum.map(w.edges, &elem(&1, 3)))};",
      "nc = #{length(cs)}; home = #{list(Enum.map(cs, & &1.home))};",
      "has_mode = #{table(length(cs), "MODE", flat(Enum.map(cs, &bools(&1.modes, @modes))))};",
      "arm_reach = #{list(Enum.map(cs, & &1.reach))}; stride = #{list(Enum.map(cs, & &1.stride))};",
      "can_perform = #{list(Enum.map(cs, & &1.perform))}; role = #{list(Enum.map(cs, & &1.role))};",
      "slots = #{list(Enum.map(cs, & &1.slots))}; cooldown = #{list(Enum.map(cs, & &1.cooldown))};",
      "nk = #{length(w.crystals)}; crystal_element = #{list(w.crystals)};",
      "nt = #{length(ts)}; kind = #{list(rows.(& &1.kind))}; at = #{list(rows.(& &1.at))}; zone = #{list(rows.(& &1.zone))};",
      "required = #{list(rows.(& &1.required))};",
      "duration = #{table(length(ts), "RECIPE", flat(rows.(&[&1.quick, &1.perf])))};",
      "reach_needed = #{list(rows.(& &1.reach))};",
      "need_role = #{table(length(ts), "ROLE", flat(rows.(&Tuple.to_list(&1.roles))))};",
      "need_art = #{table(length(ts), "ELEMENT", flat(rows.(&bools(&1.arts, @elements))))};",
      "points = #{list(rows.(& &1.points))}; min_points = #{list(rows.(& &1.minp))}; bonus = #{list(rows.(& &1.bonus))};",
      "release = #{list(rows.(& &1.release))}; deadline = #{list(rows.(& &1.deadline))};",
      "nz = #{length(w.zones)}; zone_capacity = #{list(w.zones)};",
      "np = #{length(w.pairs)}; before = #{list(Enum.map(w.pairs, &elem(&1, 0)))}; after = #{list(Enum.map(w.pairs, &elem(&1, 1)))};",
      "climb_min_reach = #{w.climb}; blink_range = #{w.blink}; time_weight = #{w.tw}; point_weight = #{w.pw};"
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def char(o \\ []), do: Map.merge(%{home: 1, modes: ~w(STICK), reach: 5, stride: 100, perform: false, role: :damage, slots: 0, cooldown: 0}, Map.new(o))
  def task(o \\ []) do
    Map.merge(%{kind: :scout, at: 2, zone: 1, required: true, quick: 2, perf: 4, reach: 1, roles: {0, 0, 0, 0}, arts: [],
                points: 0, minp: 0, bonus: 0, release: 0, deadline: 100_000}, Map.new(o))
  end
  def world(o \\ []) do
    Map.merge(%{nodes: 2, edges: [{1, 2, 3, :land}], chars: [char()], crystals: [], tasks: [task()], zones: [2], pairs: [],
                climb: 3, blink: 2, tw: 1, pw: 0}, Map.new(o))
  end

  def mzn, do: Path.join(@root, "party-saga.mzn")
  # Turbo (GPU) takes its soft limit as -timeout (the hard -t can hang) and needs its solver file; its fixed cost is seconds.
  def limit_args("turbo" <> _, limit_s), do: ["-timeout", Integer.to_string(max(limit_s, 30) * 1000)]
  def limit_args(_, limit_s), do: ["-t", Integer.to_string(limit_s * 1000)]
  def solver_env("turbo" <> _), do: [{"MZN_SOLVER_PATH", Path.join(System.get_env("TURBO_HOME", "/mnt/fire/6-datasource/turbo-build"), "msc")}]
  def solver_env(_), do: []
  def agree_solvers, do: ~w(chuffed gecode) ++ if(System.get_env("TURBO_HOME"), do: ["turbo.gpu.release"], else: []) ++ if(System.get_env("TURBO_SLANG"), do: ["turbo-slang"], else: [])
  # The Slang port of Turbo: compile to FlatZinc with MiniZinc's own library (the fzn is identical to the one Turbo's `mzn-lib` gives: its `redefinitions.mzn` is empty), dump the preprocessing with the Lean front end (`frontier_frontend --dump`), search through the planner player on the GPU, print with the Lean front end (`--solution`), map back with the .ozn.
  def run("turbo-slang", model, dzn, limit_s) do
    frontend = Path.expand("../.lake/build/bin/frontier_frontend", __DIR__)
    work = Path.join(System.tmp_dir!(), "slang-#{System.unique_integer([:positive])}")
    File.mkdir_p!(work)
    [fzn, ozn, cp] = for ext <- ~w(fzn ozn cp), do: Path.join(work, "party." <> ext)
    env = [{"LD_LIBRARY_PATH", Path.join(@home, "lib")}]
    {us, status_out} = :timer.tc(fn ->
      {_, 0} = System.cmd(Path.join(@home, "bin/minizinc"), ["--solver", "org.minizinc.mzn-fzn", "-c", "--fzn", fzn, "--ozn", ozn, model, dzn], env: env, stderr_to_stdout: true)
      {dump, 0} = System.cmd(frontend, ["--dump", fzn], stderr_to_stdout: false)
      File.write!(cp, dump)
      slang_search(cp, fzn, work, limit_s)
    end)
    out = slang_output(status_out, ozn, work, env)
    obj = case Regex.scan(~r/objective = (-?\d+);/, out) do [] -> nil; ms -> ms |> List.last() |> List.last() |> String.to_integer() end
    status = cond do
      String.contains?(out, "==========") -> :optimal
      String.contains?(out, "----------") -> :incumbent
      true -> :none
    end
    %{status: status, objective: obj, seconds: Float.round(us / 1.0e6, 2), out: out}
  end
  def run(solver, model, dzn, limit_s) do
    args = ["--solver", solver] ++ limit_args(solver, limit_s) ++ [model, dzn]
    env = [{"LD_LIBRARY_PATH", Path.join(@home, "lib")}] ++ solver_env(solver)
    {us, {out, _}} = :timer.tc(fn -> System.cmd(Path.join(@home, "bin/minizinc"), args, env: env, stderr_to_stdout: true) end)
    status = cond do
      String.contains?(out, "=====UNSATISFIABLE=====") -> :unsat
      String.contains?(out, "==========") -> :optimal
      String.contains?(out, "----------") -> :incumbent
      true -> :none
    end
    obj = case Regex.scan(~r/objective = (-?\d+);/, out) do [] -> nil; ms -> ms |> List.last() |> List.last() |> String.to_integer() end
    %{status: status, objective: obj, seconds: Float.round(us / 1.0e6, 2), out: out}
  end

  defp slang_search(cp, fzn, work, limit_s) do
    args = ["#{limit_s}", "elixir", "tools/turbo_player.exs", cp, "--engine", "gpu", "--slice", "500", "--duty", "50", "--fzn", fzn, "--checkpoint", Path.join(work, "ck.bin")]
    {_, code} = System.cmd("timeout", args, env: [{"TMPDIR", work}, {"ELIXIR_ERL_OPTIONS", "+fnu"}], stderr_to_stdout: true)
    if code == 0, do: :finished, else: :stopped
  end
  defp slang_output(:stopped, _, _, _), do: ""
  defp slang_output(:finished, _ozn, work, _env) do
    scratch = Path.join([work, "turbo_solve", "party"])
    [_, bound] = Regex.run(~r/approx (-?\d+)/, File.read!(Path.join(scratch, "result.txt")))
    File.read!(Path.join(scratch, "solution.mzn")) <> "objective = #{bound};\n==========\n"
  end
  def tmp(text) do
    p = Path.join(System.tmp_dir!(), "saga-#{System.unique_integer([:positive])}.dzn")
    File.write!(p, text)
    p
  end
  def solve_world(w, solver \\ "cp-sat", limit \\ 30, model \\ mzn()), do: run(solver, model, tmp(render(w)), limit)
end

defmodule Saga.Tests do
  import Saga
  def at1(o \\ []), do: task([at: 1] ++ o)
  def all do
    [
      {"t01 one scout at distance 3, ramp 1", world(), {:obj, 6}},
      {"t02 the only mode cannot cross", world(edges: [{1, 2, 3, :water}], chars: [char(modes: ~w(SPRINT))]), :unsat},
      {"t03 prerequisite forces order", world(nodes: 1, edges: [], tasks: [at1(quick: 2), at1(quick: 3)], pairs: [{2, 1}]), {:obj, 5}},
      {"t04a optional performance with the skill", world(nodes: 1, edges: [], chars: [char(perform: true)], tasks: [at1(required: false, quick: 2, perf: 10, bonus: 100)]), {:obj, -90}},
      {"t04b optional performance without the skill", world(nodes: 1, edges: [], tasks: [at1(required: false, quick: 2, perf: 10, bonus: 100)]), {:obj, 0}},
      {"t05 two scouts at one node use two arms", world(nodes: 1, edges: [], tasks: [at1(quick: 4), at1(quick: 4)]), {:obj, 4}},
      {"t06 reach too short", world(tasks: [task(reach: 9)]), :unsat},
      {"t07a cliff beyond blink range, no climb", world(edges: [{1, 2, 5, :cliff}], chars: [char(modes: ~w(STICK TELEPORT))]), :unsat},
      {"t07b cliff within blink range by teleport", world(edges: [{1, 2, 2, :cliff}], chars: [char(modes: ~w(STICK TELEPORT))]), {:obj, 3}},
      {"t08a zone capacity 1 serialises", world(nodes: 1, edges: [], chars: [char(), char()], tasks: [at1(), at1()], zones: [1]), {:obj, 4}},
      {"t08b zone capacity 2 overlaps", world(nodes: 1, edges: [], chars: [char(), char()], tasks: [at1(), at1()], zones: [2]), {:obj, 2}},
      {"t09 duty in a capacity-1 zone", world(nodes: 1, edges: [], chars: [char(role: :tank)], tasks: [at1(kind: :duty, roles: {1, 0, 0, 0}, quick: 5)], zones: [1]), :unsat},
      {"t10 duty with a tank and a healer", world(nodes: 1, edges: [], chars: [char(role: :tank), char(role: :healer)], tasks: [at1(kind: :duty, roles: {1, 1, 0, 0}, quick: 5)], zones: [4]), {:obj, 5}},
      {"t11 duty with only a damage character", world(nodes: 1, edges: [], chars: [char(role: :damage)], tasks: [at1(kind: :duty, roles: {1, 0, 0, 0}, quick: 5)], zones: [4]), :unsat},
      {"t12a duty with an art, slot and crystal", world(nodes: 1, edges: [], chars: [char(role: :tank, slots: 1)], crystals: [:ember], tasks: [at1(kind: :duty, roles: {1, 0, 0, 0}, arts: ~w(EMBER), quick: 5)], zones: [4]), {:obj, 5}},
      {"t12b duty with an art, no slot", world(nodes: 1, edges: [], chars: [char(role: :tank, slots: 0)], crystals: [:ember], tasks: [at1(kind: :duty, roles: {1, 0, 0, 0}, arts: ~w(EMBER), quick: 5)], zones: [4]), :unsat},
      {"t13 duty cooldown forces a gap", world(nodes: 1, edges: [], chars: [char(role: :tank, cooldown: 4)], tasks: [at1(kind: :duty, roles: {1, 0, 0, 0}, quick: 3), at1(kind: :duty, roles: {1, 0, 0, 0}, quick: 3)], zones: [2]), {:obj, 10}},
      {"t14 rank gate forces order", world(nodes: 1, edges: [], tasks: [at1(points: 10), at1(minp: 10)], zones: [4]), {:obj, 4}}
    ]
  end
  def verdict(%{status: :unsat}, :unsat), do: :ok
  def verdict(%{status: :optimal, objective: o}, {:obj, o}), do: :ok
  def verdict(r, want), do: {:fail, r.status, r.objective, want}
  def run_all(solver \\ "cp-sat") do
    for {name, w, want} <- all() do
      {name, verdict(solve_world(w, solver), want)}
    end
  end
end

defmodule Saga.Gen do
  import Saga
  @roles ~w(tank healer damage support)a
  @elements ~w(EMBER TIDE STONE GALE)
  def level(track, g, h, seed \\ 1) do
    :rand.seed(:exsss, {seed, g, h + 17})
    n = Enum.at(Saga.steps(), g - 1)
    ti = Enum.find_index(Saga.tracks(), &(&1 == track))
    nodes = n + 3
    chars_n = 2 + div(g, 2)
    ring = for i <- 1..nodes, {a, b, fwd?} <- [{i, rem(i, nodes) + 1, true}, {rem(i, nodes) + 1, i, false}], do: {a, b, 2 + :rand.uniform(6), if(fwd?, do: :land, else: terr(ti))}
    ring = Enum.uniq_by(ring, fn {a, b, _, _} -> {a, b} end)
    chars = Enum.map(1..chars_n, fn i -> char_for(i, ti, nodes) end)
    chars = ensure_party(chars, ti)
    duty_n = if ti >= 3, do: div(n, 3), else: 0
    tasks = Enum.map(1..n, fn i -> task_for(i, nodes, ti, i <= duty_n, chars) end)
    {tasks, crystals, chars} = if ti >= 4, do: loadout(tasks, chars), else: {tasks, [], chars}
    tasks = if ti >= 5, do: gate(tasks), else: tasks
    pairs = if ti >= 5, do: for(i <- 2..n//3, do: {i - 1, i}), else: []
    {tasks, pairs} = drop_held(tasks, pairs, h)
    zones = zone_caps(tasks)
    tasks = Enum.map(tasks, &Map.put(&1, :zone, rem(&1.at, length(zones)) + 1))
    zones = zone_caps(tasks, length(zones))
    world(nodes: nodes, edges: ring, chars: chars, crystals: crystals, tasks: tasks, zones: zones, pairs: pairs, tw: 10, pw: if(ti >= 5, do: 1, else: 0))
  end

  def terr(ti) when ti >= 2, do: Enum.random([:land, :water, :cliff])
  def terr(_), do: :land
  def char_for(i, ti, nodes) do
    modes = if ti >= 2, do: Enum.take_random(~w(SPRINT CLIMB TELEPORT), :rand.uniform(3) - 1), else: []
    char(home: rem(i * 2, nodes) + 1, modes: ["STICK" | modes], reach: 4 + :rand.uniform(4), stride: 70 + :rand.uniform(60),
         perform: ti >= 1 and rem(i, 2) == 0, role: Enum.at(@roles, rem(i - 1, 4)), slots: if(ti >= 4, do: 1 + rem(i, 2), else: 0), cooldown: if(ti >= 3, do: 2 + rem(i, 3), else: 0))
  end
  def ensure_party(chars, ti) do
    chars |> Enum.with_index() |> Enum.map(fn {c, i} -> if ti >= 1 and i == 0, do: %{c | perform: true, reach: 8}, else: c end)
  end
  def task_for(i, nodes, ti, duty?, chars) do
    roles = if duty?, do: duty_roles(chars), else: {0, 0, 0, 0}
    task(kind: if(duty?, do: :duty, else: :scout), at: rem(i * 3, nodes) + 1, required: ti < 1 or rem(i, 3) != 0, quick: 2 + :rand.uniform(3), perf: 5 + :rand.uniform(4),
         reach: 1 + :rand.uniform(4), roles: roles, bonus: if(ti >= 1, do: 5 * :rand.uniform(6), else: 0), points: if(ti >= 5, do: :rand.uniform(5), else: 0),
         release: if(ti >= 5, do: rem(i, 4) * 3, else: 0))
  end
  def duty_roles(chars) do
    counts = for r <- @roles, do: Enum.count(chars, &(&1.role == r))
    pick = Enum.map(counts, fn c -> min(c, 1) end)
    List.to_tuple(pick)
  end
  def loadout(tasks, chars) do
    elems = Enum.take_random(@elements, 2)
    tasks = Enum.map(tasks, fn t -> if t.kind == :duty, do: %{t | arts: [Enum.random(elems)]}, else: t end)
    need = tasks |> Enum.flat_map(& &1.arts) |> Enum.uniq()
    crystals = Enum.map(need, &(&1 |> String.downcase() |> String.to_atom()))
    chars = Enum.map(chars, fn c -> %{c | slots: max(c.slots, 1)} end)
    {tasks, crystals, chars}
  end
  def gate(tasks) do
    {done, _} =
      Enum.map_reduce(tasks, 0, fn t, acc -> {if(rem(t.at, 4) == 0 and acc >= 3, do: %{t | minp: min(acc, 5)}, else: t), acc + (t.points || 0)} end)
    done
  end
  def drop_held(tasks, pairs, 0), do: {tasks, pairs}
  def drop_held(tasks, pairs, h) do
    kept = Enum.drop(tasks, h)
    credit = tasks |> Enum.take(h) |> Enum.map(& &1.points) |> Enum.sum()
    kept = Enum.map(kept, &%{&1 | minp: max(&1.minp - credit, 0)})
    pairs = for {a, b} <- pairs, a > h, do: {a - h, b - h}
    {kept, pairs}
  end
  def zone_caps(tasks), do: List.duplicate(2, max(1, div(length(tasks), 4) + 1))
  def zone_caps(tasks, nz) do
    for z <- 1..nz do
      need = tasks |> Enum.filter(&(&1.zone == z)) |> Enum.map(fn t -> if t.kind == :duty, do: 2 * 4, else: 2 end)
      max(2, Enum.max([0 | need]))
    end
  end
end

defmodule Saga.Frontier do
  import Saga
  def state_path, do: Path.join(root(), "frontier.json")
  def trace_path, do: Path.join(root(), "traces.jsonl")
  def traces do
    case File.read(trace_path()) do
      {:ok, t} -> t |> String.split("\n", trim: true) |> Enum.map(&:json.decode/1)
      _ -> []
    end
  end
  def levels(max_held) do
    for t <- Saga.tracks(), g <- 1..length(Saga.steps()), h <- 0..min(g - 1, max_held), do: {t, g, h}
  end
  def stat(ts, {t, g, h}) do
    mine = Enum.filter(ts, &(&1["kind"] == "practice" and &1["track"] == t and &1["g"] == g and &1["h"] == h))
    %{attempts: length(mine), solved: Enum.count(mine, & &1["solved"])}
  end
  def open?(ts, track) do
    case Enum.find_index(Saga.tracks(), &(&1 == track)) do
      0 -> true
      i -> prev = Enum.at(Saga.tracks(), i - 1); Enum.any?(ts, &(&1["track"] == prev and &1["solved"] == true))
    end
  end
  def next_level(max_held) do
    ts = traces()
    st = Map.new(levels(max_held), &{&1, stat(ts, &1)})
    hit = fn {t, g, h} -> (st[{t, g, h}] || %{solved: 0}).solved > 0 end
    edge =
      Enum.filter(levels(max_held), fn {t, g, h} = l ->
        s = st[l]
        open?(ts, t) and ((s.attempts > 0 and s.solved < s.attempts) or (s.attempts == 0 and (g == 1 or hit.({t, g - 1, h}) or (h > 0 and hit.({t, g, h - 1})))))
      end)
    Enum.min_by(edge, fn {t, g, h} = l -> {st[l].attempts, g, -h, t} end, fn -> nil end)
  end
  def practice({track, g, h}, limit) do
    seed = stat(traces(), {track, g, h}).attempts + 1
    w = Saga.Gen.level(track, g, h, seed)
    r = solve_world(w, "cp-sat", limit)
    if r.status == :unsat do
      File.write!(trace_path(), IO.iodata_to_binary(:json.encode(%{"kind" => "invalid", "track" => track, "g" => g, "h" => h, "seed" => seed})) <> "\n", [:append])
      raise "generator fault: #{track} g=#{g} h=#{h} seed=#{seed} is unsatisfiable"
    end
    t = %{"kind" => "practice", "track" => track, "g" => g, "h" => h, "seed" => seed, "solved" => r.status == :optimal, "status" => to_string(r.status), "objective" => r.objective, "seconds" => r.seconds, "limit" => limit}
    File.write!(trace_path(), IO.iodata_to_binary(:json.encode(t)) <> "\n", [:append])
    t
  end
  def table(ts) do
    for track <- Saga.tracks() do
      mine = Enum.filter(ts, &(&1["kind"] == "practice" and &1["track"] == track))
      solved = mine |> Enum.filter(& &1["solved"]) |> Enum.map(& &1["g"])
      top = Enum.max([0 | solved])
      "#{String.pad_trailing(track, 11)} tried #{String.pad_leading(Integer.to_string(length(mine)), 3)}  frontier g=#{top}  next unsolved g=#{if top < length(Saga.steps()), do: top + 1, else: "-"}"
    end
  end
end

defmodule Saga.Path do
  @inf 1_000_000
  def inf, do: @inf
  def ramp("STICK"), do: 1
  def ramp("SPRINT"), do: 2
  def ramp("CLIMB"), do: 1
  def ramp(_), do: 0

  def speed(c, "STICK", t, _w), do: (case t do :land -> c.stride; :water -> div(c.stride, 2); _ -> 0 end)
  def speed(c, "SPRINT", t, _w), do: if(t == :land, do: div(c.stride * 3, 2), else: 0)
  def speed(c, "CLIMB", t, w), do: if(t == :cliff and c.reach >= w.climb, do: div(c.stride, 3), else: 0)
  def speed(_, _, _, _), do: 0

  def mode_time(c, m, {_, _, len, terr}, w) do
    cond do
      m == "TELEPORT" -> if len <= w.blink, do: 1, else: @inf
      speed(c, m, terr, w) <= 0 -> @inf
      true -> div(len * 100 + speed(c, m, terr, w) - 1, speed(c, m, terr, w)) + ramp(m)
    end
  end

  def best(c, e, w) do
    c.modes |> Enum.map(&{mode_time(c, &1, e, w), &1}) |> Enum.min_by(&elem(&1, 0))
  end

  def tables(w, c) do
    nodes = 1..w.nodes
    direct =
      for {u, v, len, _} = e <- w.edges, reduce: %{} do
        acc ->
          {t, m} = best(c, e, w)
          if t >= @inf or Map.get(acc, {u, v}, {@inf, nil, nil})|> elem(0) <= t, do: acc, else: Map.put(acc, {u, v}, {t, m, len})
      end
    dist0 = for u <- nodes, v <- nodes, into: %{}, do: {{u, v}, if(u == v, do: 0, else: (case direct[{u, v}] do {t, _, _} -> t; nil -> @inf end))}
    nxt0 = for {{u, v}, _} <- direct, into: %{}, do: {{u, v}, v}
    {dist, nxt} =
      for k <- nodes, u <- nodes, v <- nodes, reduce: {dist0, nxt0} do
        {d, n} ->
          via = min(d[{u, k}] + d[{k, v}], @inf * 2)
          if via < d[{u, v}], do: {Map.put(d, {u, v}, via), Map.put(n, {u, v}, n[{u, k}])}, else: {d, n}
      end
    {dist, nxt, direct}
  end

  def route(nxt, u, v), do: if(u == v, do: [], else: [{u, nxt[{u, v}]} | route(nxt, nxt[{u, v}], v)])
end

defmodule Saga.Packets do
  import Saga
  def field(out, name) do
    case Regex.run(~r/^#{name} = \[(.*?)\];$/m, out) do
      [_, body] -> body |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      _ -> []
    end
  end
  def ints(out, name), do: out |> field(name) |> Enum.map(&String.to_integer/1)
  @arm %{"LEFT" => 0, "RIGHT" => 1, "BOTH" => 2}
  @elements ~w(EMBER TIDE STONE GALE)

  def steps(w, out) do
    done = field(out, "done")
    how = field(out, "how")
    arm = field(out, "arm")
    start = ints(out, "start")
    party = ints(out, "party")
    dur = ints(out, "dur")
    held = ints(out, "held")
    tasks = Enum.with_index(w.tasks, 1)
    chars = Enum.with_index(w.chars, 1)
    moves_and_tasks =
      for {c, ci} <- chars do
        {dist, nxt, direct} = Saga.Path.tables(w, c)
        mine = for {t, ti} <- tasks, Enum.at(done, ti - 1) == "true", Bitwise.band(Enum.at(party, ti - 1), Bitwise.bsl(1, ci - 1)) != 0, do: {t, ti}
        mine = Enum.sort_by(mine, fn {_, ti} -> Enum.at(start, ti - 1) end)
        {steps, _, _} =
          Enum.reduce(mine, {[], c.home, 0}, fn {t, ti}, {acc, node, arc} ->
            begin = Enum.at(start, ti - 1)
            depart = begin - dist[{node, t.at}]
            {hops, _, arc2} =
              Enum.reduce(Saga.Path.route(nxt, node, t.at), {[], depart, arc}, fn {a, b}, {hs, clock, arc} ->
                {time, mode, len} = direct[{a, b}]
                hop = %{"kind" => "move", "actor" => ci, "depart_ms" => clock * 1000, "ticks" => 64 * time, "ramp_ticks" => 64 * Saga.Path.ramp(mode),
                        "length_um" => len * 1_000_000, "arc_um" => arc, "from" => a, "to" => b}
                {hs ++ [hop], clock + time, arc + len * 1_000_000}
              end)
            cmd =
              if t.kind == :duty,
                do: %{"kind" => "duty", "actor" => ci, "ms" => begin * 1000, "args" => [ti, Enum.at(party, ti - 1), 64 * Enum.at(dur, ti - 1)]},
                else: %{"kind" => "scout", "actor" => ci, "ms" => begin * 1000, "args" => [ti, if(Enum.at(how, ti - 1) == "PERFORMANCE", do: 1, else: 0), Map.fetch!(@arm, Enum.at(arm, ti - 1)), 64 * Enum.at(dur, ti - 1)]}
            {acc ++ hops ++ [cmd], t.at, arc2}
          end)
        steps
      end
    equips = for {h, k} <- Enum.with_index(held, 1), h > 0, do: %{"kind" => "equip", "actor" => h, "ms" => 0, "args" => [k, Enum.find_index(@elements, &(&1 == val(Enum.at(w.crystals, k - 1)))) || 0]}
    all = equips ++ List.flatten(moves_and_tasks)
    Enum.sort_by(all, fn st -> st["depart_ms"] || st["ms"] end)
  end

  def distances_agree?(w, out) do
    flat = ints(out, "dist")
    n = w.nodes
    mine = for {c, _} <- Enum.with_index(w.chars, 1), {dist, _, _} = Saga.Path.tables(w, c), u <- 1..n, v <- 1..n, do: min(dist[{u, v}], Saga.Path.inf())
    theirs = Enum.map(flat, &min(&1, Saga.Path.inf()))
    mine == theirs
  end

  def exe, do: Path.expand("../.lake/build/bin/frontier_packets", __DIR__)
  def encode_steps(steps) do
    json = IO.iodata_to_binary(:json.encode(%{"steps" => steps}))
    jp = tmp(json)
    bin = Path.join(System.tmp_dir!(), "saga-#{System.unique_integer([:positive])}.bin")
    {out, rc} = System.cmd(exe(), [jp, bin], stderr_to_stdout: true)
    lines = String.split(out, "\n", trim: true)
    summary = Enum.find(lines, &String.starts_with?(&1, "OK ")) || Enum.find(lines, &String.starts_with?(&1, "FAILED")) || "no result"
    %{ok: rc == 0, summary: summary, bytes: (case File.stat(bin) do {:ok, %{size: n}} -> n; _ -> 0 end), bin: bin, lines: lines}
  end
end

defmodule Saga.Cli do
  import Saga
  def main(["check" | _]) do
    results = Saga.Tests.run_all() ++ packet_checks()
    for {name, v} <- results, do: IO.puts("  #{if v == :ok, do: "ok  ", else: "FAIL"} #{name} #{if v == :ok, do: "", else: inspect(v)}")
    if Enum.all?(results, &(elem(&1, 1) == :ok)), do: IO.puts("OK: #{length(results)} tests"), else: (IO.puts("FAILED"); System.halt(1))
  end
  def main(["packets" | rest]) do
    {track, g} = {List.first(rest) || "party", String.to_integer(Enum.at(rest, 1) || "1")}
    w = Saga.Gen.level(track, g, 0, 1)
    r = solve_world(w, "cp-sat", 30)
    if r.status != :optimal, do: (IO.puts("not solved: #{r.status}"); System.halt(1))
    res = Saga.Packets.encode_steps(Saga.Packets.steps(w, r.out))
    IO.puts("#{track} g=#{g}: #{res.summary}, #{res.bytes} bytes, distances agree with MiniZinc: #{Saga.Packets.distances_agree?(w, r.out)}")
    if not res.ok, do: System.halt(1)
  end
  def main(["solve", file | rest]) do
    solver = List.first(rest) || "cp-sat"
    r = run(solver, mzn(), file, 60)
    IO.puts("#{solver}: #{r.status} objective=#{inspect(r.objective)} #{r.seconds}s")
  end
  def main(["dump", track, g, seed, out]) do
    w = Saga.Gen.level(String.to_atom(track), String.to_integer(g), 0, String.to_integer(seed))
    File.write!(out, Saga.render(w))
    IO.puts("wrote #{out}")
  end
  def main(["agree" | rest]) do
    limit = opt(rest, "--limit", 30)
    rows = Enum.filter(Saga.Frontier.traces(), &(&1["kind"] == "practice" and &1["solved"]))
    out =
      for r <- rows do
        w = Saga.Gen.level(r["track"], r["g"], r["h"], r["seed"] || 1)
        others = for sv <- Saga.agree_solvers(), do: {sv, solve_world(w, sv, limit)}
        verdicts = for {sv, o} <- others, do: {sv, o.status, o.objective}
        ok = Enum.all?(verdicts, fn {_, st, ob} -> st != :optimal or ob == r["objective"] end)
        proved = Enum.count(verdicts, fn {_, st, _} -> st == :optimal end)
        IO.puts("  #{if ok, do: "agree   ", else: "DISAGREE"} #{r["track"]} g=#{r["g"]} cp-sat=#{r["objective"]} #{inspect(verdicts)}")
        %{"track" => r["track"], "g" => r["g"], "ok" => ok, "others_proved" => proved}
      end
    File.write!(Path.join(root(), "agree.json"), IO.iodata_to_binary(:json.encode(out)) <> "\n")
    bad = Enum.count(out, &(not &1["ok"]))
    IO.puts("agreement: #{length(out) - bad} of #{length(out)} proved levels, #{Enum.count(out, &(&1["others_proved"] == 2))} proved by all three")
    if bad > 0, do: System.halt(1)
  end
  def main(["report" | _]) do
    ts = Enum.filter(Saga.Frontier.traces(), &(&1["kind"] == "practice"))
    tasks = fn g -> Enum.at(Saga.steps(), g - 1) end
    IO.puts("| Track | Solved up to (tasks) | Slowest proved | Levels tried | Unsolved levels (tasks, attempts) |")
    IO.puts("|-------|----------------------|----------------|--------------|-----------------------------------|")
    for track <- Saga.tracks() do
      mine = Enum.filter(ts, &(&1["track"] == track))
      solved = mine |> Enum.filter(& &1["solved"])
      top = solved |> Enum.map(& &1["g"]) |> Enum.max(fn -> 0 end)
      slow = solved |> Enum.map(& &1["seconds"]) |> Enum.max(fn -> 0 end)
      unsolved = for g <- Enum.uniq(Enum.map(mine, & &1["g"])) |> Enum.sort(), not Enum.any?(solved, &(&1["g"] == g)), do: "#{tasks.(g)} (#{Enum.count(mine, &(&1["g"] == g))})"
      IO.puts("| `#{track}` | #{if top == 0, do: "none", else: tasks.(top)} | #{slow} s | #{length(mine)} | #{if unsolved == [], do: "none", else: Enum.join(unsolved, ", ")} |")
    end
    case File.read(Path.join(root(), "agree.json")) do
      {:ok, t} ->
        a = :json.decode(t)
        IO.puts("\nSolver agreement: #{Enum.count(a, & &1["ok"])} of #{length(a)} proved levels agree; #{Enum.count(a, &(&1["others_proved"] == 2))} proved by CP-SAT, Chuffed and Gecode.")
      _ -> IO.puts("\nSolver agreement: not run yet.")
    end
  end
  def main(["validate" | rest]) do
    gmax = opt(rest, "--g", 4)
    bad =
      for t <- Saga.tracks(), g <- 1..gmax, seed <- 1..3, r = solve_world(Saga.Gen.level(t, g, 0, seed), "cp-sat", 10), r.status == :unsat do
        IO.puts("  UNSAT #{t} g=#{g} seed=#{seed}")
        {t, g, seed}
      end
    IO.puts(if bad == [], do: "OK: every generated level up to g=#{gmax} is satisfiable", else: "FAILED: #{length(bad)} unsatisfiable levels")
    if bad != [], do: System.halt(1)
  end
  def main(["learn" | _]) do
    {ok?, report} = learn()
    IO.puts(report)
    if not ok?, do: System.halt(1)
  end
  def main(["practice" | rest]) do
    limit = opt(rest, "--limit", 20)
    case Saga.Frontier.next_level(opt(rest, "--max-held", 0)) do
      nil -> IO.puts("no open level")
      l -> IO.inspect(Saga.Frontier.practice(l, limit))
    end
  end
  def main(["frontier" | rest]) do
    {limit, n, mh} = {opt(rest, "--limit", 20), opt(rest, "--steps", 30), opt(rest, "--max-held", 0)}
    for _ <- 1..n do
      case Saga.Frontier.next_level(mh) do
        nil -> :done
        l -> t = Saga.Frontier.practice(l, limit); IO.puts("  #{elem(l, 0)} g=#{elem(l, 1)} h=#{elem(l, 2)} #{t["status"]} #{t["seconds"]}s")
      end
    end
    {ok?, _} = learn()
    IO.puts(Enum.join(Saga.Frontier.table(Saga.Frontier.traces()), "\n"))
    if not ok?, do: IO.puts("gate failed: frontier.json not updated")
  end
  # The edge of a solver, read only: each track climbs its ladder from the smallest level (seed 1, no cleared tasks) until the solver does not prove the
  # optimum inside the limit. Nothing is written to the repository (no traces, no learn), so it can be run for any solver at any time.
  def main(["edge", solver | rest]) do
    limit = opt(rest, "--limit", 15)
    ladder = Saga.steps()
    rows =
      for track <- Saga.tracks() do
        {solved, stopped} =
          Enum.reduce_while(1..length(ladder), {0, "top of the ladder"}, fn g, {top, _} ->
            r = Saga.solve_world(Saga.Gen.level(track, g, 0, 1), solver, limit)
            IO.puts("#{String.pad_trailing(track, 11)} g=#{String.pad_leading(Integer.to_string(g), 2)} tasks #{String.pad_leading(inspect(Enum.at(ladder, g - 1)), 2)}  #{r.status}  #{Float.round(r.seconds * 1.0, 1)} s  objective #{inspect(r.objective)}")
            if r.status == :optimal, do: {:cont, {g, "top of the ladder"}}, else: {:halt, {top, "g=#{g}: #{r.status}"}}
          end)
        {track, solved, stopped}
      end
    IO.puts("edge of #{solver}, limit #{limit} s per level (seed 1, wall time including the compile)")
    for {track, g, stopped} <- rows, do: IO.puts("#{String.pad_trailing(track, 11)} solved up to g=#{g} (#{if g == 0, do: 0, else: Enum.at(ladder, g - 1)} tasks), stopped at #{stopped}")
  end
  def main(_), do: IO.puts("usage: party_saga.exs check | solve FILE [SOLVER] | learn | practice | frontier [--steps N] [--limit S] [--max-held H] | edge SOLVER [--limit S]")

  def packet_checks do
    find = fn prefix -> Enum.find(Saga.Tests.all(), fn {n, _, _} -> String.starts_with?(n, prefix) end) |> elem(1) end
    cases = [
      {"p01 ramped move and a scout", "t01", "OK packets=6 commands=2 states=4"},
      {"p02 teleport is a jump", "t07b", "OK packets=4 commands=2 states=2"},
      {"p03 duty gives one command per member", "t10", "OK packets=2 commands=2 states=0"}
    ]
    for {name, prefix, want} <- cases do
      w = find.(prefix)
      r = solve_world(w)
      res = Saga.Packets.encode_steps(Saga.Packets.steps(w, r.out))
      agree = Saga.Packets.distances_agree?(w, r.out)
      {name, if(res.ok and res.summary == want and res.bytes == 100 * String.to_integer(hd(Regex.run(~r/packets=(\d+)/, want, capture: :all_but_first))) and agree, do: :ok, else: {:fail, res.summary, res.bytes, agree})}
    end
  end

  def opt(args, flag, default) do
    case Enum.drop_while(args, &(&1 != flag)) do [_, v | _] -> String.to_integer(v); _ -> default end
  end

  def mutant(name) do
    src = File.read!(mzn())
    {from, to} =
      case name do
        :zone -> {"constraint forall(z in ZONE)(cumulative(", "constraint forall(z in ZONE)(true \\/ cumulative("}
        :role -> {"sum(c in CHAR where role[c] = r)(bool2int(part[c, t])) = if done[t] then need_role[t, r] else 0 endif", "sum(c in CHAR where role[c] = r)(bool2int(part[c, t])) >= 0"}
        :reach -> {" /\\ reach_needed[t] <= arm_reach[c]", ""}
      end
    if not String.contains?(src, from), do: raise("mutation target missing: #{name}")
    p = Path.join(System.tmp_dir!(), "saga-mutant-#{name}.mzn")
    File.write!(p, String.replace(src, from, to, global: false))
    p
  end

  def learn do
    tests = Saga.Tests.all()
    pick = fn prefix -> Enum.find(tests, fn {n, _, _} -> String.starts_with?(n, prefix) end) end
    {_, w1, e1} = pick.("t01")
    positive = Saga.Tests.verdict(solve_world(w1), e1) == :ok
    negative =
      for {m, prefix} <- [zone: "t08a", role: "t11", reach: "t06"] do
        {_, w, want} = pick.(prefix)
        {m, Saga.Tests.verdict(solve_world(w, "cp-sat", 30, mutant(m)), want) != :ok}
      end
    pass = positive and Enum.all?(negative, &elem(&1, 1))
    rev = case File.read(Saga.Frontier.state_path()) do {:ok, t} -> :json.decode(t)["revision"] + 1; _ -> 1 end
    st = %{"revision" => rev, "levels" => length(Saga.Frontier.traces())}
    if pass, do: File.write!(Saga.Frontier.state_path(), IO.iodata_to_binary(:json.encode(st)) <> "\n")
    {pass, "gate: positive=#{positive} negative=#{inspect(negative)} #{if pass, do: "revision #{rev}", else: "not landed"}"}
  end
end

Saga.Cli.main(System.argv())
