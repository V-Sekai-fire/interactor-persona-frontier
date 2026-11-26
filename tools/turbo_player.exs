# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-FileCopyrightText: 2025 Pierre Talbot
# SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
# SPDX-License-Identifier: Apache-2.0 AND MIT
# Solve a dumped problem in time slices, planning each slice with the planner (domain turbo_solve, stored in SQLite) and only when the machine is free.
# The game on this machine is real time: a slice is a bounded number of nodes at the lowest priority, the planner is asked again after every slice
# (reentrant, like the replan loop of an HTN planner), and the whole search state is in a checkpoint file, so this tool can be stopped and started at any time.
# --engine gpu runs the cooperative CUDA kernel instead (tools/turbo_gpu.exs builds it): the resident host takes "run N" launches per slice (--slice, default 10), each launch
# a launch of about a millisecond (the kernel stops it by its own clock), under a duty cap (--duty, default 25 percent); its state is saved to the checkpoint every --save-every slices.
# For that engine the gate is the GPU only, minus this process's own recent share.
# Usage: elixir tools/turbo_player.exs <level.cp> [--slice NODES] [--max-load L] [--max-gpu PERCENT] [--poll-ms MS] [--max-slices N] [--checkpoint FILE]
#   the level is the file's base name: scout, party or saga (the enumeration `level` of the domain).
# --fzn FILE (the level's FlatZinc) with --printer (the frontier_frontend binary, default .lake/build/bin/frontier_frontend: Lean port of Turbo's preprocessing and solver output) writes the solution in MiniZinc format to solution.mzn in the scratch folder at the end.
# Time is the entity packet's hybrid logical clock (48 bits of milliseconds, 16 of counter): commands to the GPU host carry the player's stamp, replies carry the host's, and with TURBO_EVENTS=FILE
# each slice appends "slice HLC PLAN_MS RUN_MS" to the host's launch lines, so tools/turbo_profile.exs can order them and split planner time from GPU time.
# Free means the one-minute load average is under --max-load (default 4, the host has 8 threads) and the GPU is under --max-gpu percent busy (default 30).
{opts, [cp_path], _} = OptionParser.parse(System.argv(), strict: [slice: :integer, max_load: :float, max_gpu: :integer, poll_ms: :integer, max_slices: :integer, checkpoint: :string, engine: :string, blocks: :integer, power: :integer, gpu_slice: :integer, duty: :float, save_every: :integer, fzn: :string, printer: :string])
engine = Keyword.get(opts, :engine, "cpu")
gpu? = engine == "gpu"
# The frame is 64 Hz, as for the CPU host. One launch and its pause fill one frame, so a launch is the duty's share of a frame (25 percent of 15.6 ms is 3.9 ms) and a slice of 64
# launches is one second: long against the planner call (about 120 ms), and a fifth of the 5 s a FoundationDB transaction may live. No node count, no other constant.
frame_hz = 64
launch_us = round(Keyword.get(opts, :duty, 25.0) / 100 * 1_000_000 / frame_hz)
slice = Keyword.get(opts, :slice, if(gpu?, do: 64, else: 100))
max_load = Keyword.get(opts, :max_load, 4.0)
max_gpu = Keyword.get(opts, :max_gpu, 30)
poll_ms = Keyword.get(opts, :poll_ms, 2000)
max_slices = Keyword.get(opts, :max_slices, :infinity)
root = File.cwd!()
level = Path.basename(cp_path, ".cp")
level_value = %{"scout" => 1, "party" => 2, "saga" => 3} |> Map.fetch!(level)
store_bin = Path.join(root, ".lake/build/bin/frontier_store")
{scratch, gpu_files} =
  if gpu? do
    {out, 0} = System.cmd("elixir", [Path.join(root, "tools/turbo_gpu.exs"), cp_path, "--prepare", "--blocks", Integer.to_string(Keyword.get(opts, :blocks, 64)), "--power", Integer.to_string(Keyword.get(opts, :power, 0))], env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}])
    [cubin, host, dir] = out |> String.split("\n", trim: true) |> Enum.take(-3)
    {dir, {cubin, host, Path.join(dir, "input.txt")}}
  else
    case System.cmd("elixir", [Path.join(root, "tools/turbo_solve.exs"), cp_path, "--prepare"], env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}]) do
      {out, 0} -> {out |> String.split("\n", trim: true) |> List.last(), nil}
      {out, code} -> raise("prepare failed (#{code}): #{String.slice(out, 0, 400)}")
    end
  end
checkpoint = Keyword.get(opts, :checkpoint, Path.join(scratch, "checkpoint.bin"))
status_file = checkpoint <> ".status"
domain = Path.join(root, "entities/domains/turbo-solve.yamlld")

load1 = fn -> "/proc/loadavg" |> File.read!() |> String.split() |> hd() |> String.to_float() end
nvidia_smi = System.find_executable("nvidia-smi") || (if File.exists?("/usr/lib/wsl/lib/nvidia-smi"), do: "/usr/lib/wsl/lib/nvidia-smi")
# No nvidia-smi at all means no GPU to protect; a GPU that cannot be read counts as busy.
gpu_percent = fn ->
  if nvidia_smi == nil do
    0
  else
    case System.cmd(nvidia_smi, ["--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"], stderr_to_stdout: true) do
      {out, 0} -> out |> String.split("\n", trim: true) |> Enum.map(&String.to_integer(String.trim(&1))) |> Enum.max()
      _ -> 100
    end
  end
end
{:ok, own} = Agent.start_link(fn -> %{burst_ms: 0, checked_at: System.monotonic_time(:millisecond)} end)
{:ok, clock} = Agent.start_link(fn -> {0, 0} end)
now_ms = fn -> System.os_time(:millisecond) end
hlc_send = fn ->
  Agent.get_and_update(clock, fn {l0, c0} ->
    l = max(l0, now_ms.())
    c = if l == l0, do: c0 + 1, else: 0
    {Bitwise.bor(Bitwise.bsl(l, 16), Bitwise.band(c, 0xFFFF)), {l, c}}
  end)
end
hlc_recv = fn word ->
  Agent.update(clock, fn {l0, c0} ->
    ml = Bitwise.bsr(word, 16)
    mc = Bitwise.band(word, 0xFFFF)
    l = Enum.max([l0, ml, now_ms.()])
    c = cond do
      l == l0 and l == ml -> max(c0, mc) + 1
      l == l0 -> c0 + 1
      l == ml -> mc + 1
      true -> 0
    end
    {l, c}
  end)
end
trace = fn line -> if (path = System.get_env("TURBO_EVENTS")), do: File.write!(path, line <> "\n", [:append]) end

# The GPU reading includes this process's own launches: subtract its share of the time since the last reading.
others_gpu = fn ->
  reading = gpu_percent.()
  now = System.monotonic_time(:millisecond)
  Agent.get_and_update(own, fn %{burst_ms: burst, checked_at: at} = st ->
    share = min(100, round(burst * 100 / max(now - at, 1000)))
    {max(reading - share, 0), %{st | burst_ms: 0, checked_at: now}}
  end)
end
free? = fn -> if gpu?, do: others_gpu.() < max_gpu, else: load1.() < max_load and gpu_percent.() < max_gpu end
done? = fn -> File.read(status_file) == {:ok, "done"} end

# One planner call: the observed state as a problem in the run's database (the schema and the domain are loaded once, before the first call), planned from the tables.
# Every call does the same two things, import its problem and plan it, so a call costs about 120 ms; a database made afresh and migrated on every call cost about 370 ms.
db = Path.join(scratch, "plan.sqlite")
File.rm(db)
File.rm(db <> "-journal")
planner_env = [{"FRONTIER_DB", db}]
{_, 0} = System.cmd(store_bin, ["migrate"], env: planner_env, stderr_to_stdout: true)
{_, 0} = System.cmd(store_bin, ["import", domain], env: planner_env, stderr_to_stdout: true)
{:ok, ticks} = Agent.start_link(fn -> 0 end)
plan = fn free, done ->
  tick = Agent.get_and_update(ticks, fn n -> {n, n + 1} end)
  name = "turbo_solve_#{level}_tick_#{tick}"
  problem = %{
    "@context" => %{"@vocab" => "https://v-sekai.org/planning/", "VSEKAI" => "https://v-sekai.org/", "domain" => "VSEKAI:planning/domain/"}, "@type" => "domain:Problem",
    "capabilities" => %{"entities" => %{}, "graph" => %{"edges" => []}}, "domain" => "turbo_solve", "name" => name,
    "source" => "interactor-persona-frontier", "todo_list" => [["solve-level", "machine.host", "level.#{level}"]],
    "variables" => [%{"init" => %{"1" => if(free, do: 1, else: 0)}, "name" => "free", "type" => "int"},
                    %{"init" => %{"#{level_value}" => if(done, do: 1, else: 0)}, "name" => "done", "type" => "int"}],
    "version" => "0.1.0"}
  problem_file = Path.join(scratch, "problem.jsonld")
  File.write!(problem_file, JSON.encode!(problem))
  {_, 0} = System.cmd(store_bin, ["import", problem_file], env: planner_env, stderr_to_stdout: true)
  {out, 0} = System.cmd(store_bin, ["plan", name], env: planner_env, stderr_to_stdout: true)
  doc = JSON.decode!(out)
  if doc["reached"] != true, do: raise("the planner refused the goal: #{String.slice(out, 0, 300)}")
  Enum.map(doc["steps"], fn s -> s["action"] end)
end

run_cpu_slice = fn ->
  {out, code} = System.cmd("nice", ["-n", "19", Path.join(scratch, "solve"), Path.join(scratch, "input.txt"), checkpoint, Integer.to_string(slice)])
  if code != 0, do: raise("slice failed (#{code})")
  [status | rest] = String.split(out, "\n", trim: true)
  if String.starts_with?(status, "status done") do
    File.write!(status_file, "done")
    File.write!(Path.join(scratch, "result.txt"), Enum.join(rest, "\n") <> "\n")
  end
  status
end

# The resident GPU host: one process for the whole run, spoken to in lines.
{:ok, gpu_state} = Agent.start_link(fn -> %{port: nil, slices: 0} end)
gpu_line = fn port ->
  receive do
    {^port, {:data, {:eol, line}}} -> line
    {^port, {:exit_status, code}} -> raise("the GPU host exited with #{code}")
  after 120_000 -> raise("the GPU host did not answer in 120 s")
  end
end
gpu_reply = fn port, command ->
  Port.command(port, command <> "\n")
  # the reply that ends a command: status for run and status, saved for save, loaded for load
  terminal = fn line ->
    cond do
      String.starts_with?(command, "save") -> line in ["saved", "save failed"]
      String.starts_with?(command, "load") -> line in ["loaded", "load failed"]
      true -> String.starts_with?(line, "status")
    end
  end
  Stream.repeatedly(fn -> gpu_line.(port) end)
  |> Enum.reduce_while([], fn line, seen ->
    cond do
      String.starts_with?(line, "best bound") -> IO.puts("  " <> line); {:cont, seen}
      match?([_, _], Regex.run(~r/hlc (\d+)/, line)) and String.starts_with?(line, "status") ->
        [_, w] = Regex.run(~r/hlc (\d+)/, line)
        hlc_recv.(String.to_integer(w))
        {:halt, Enum.reverse([line | seen])}
      terminal.(line) -> {:halt, Enum.reverse([line | seen])}
      true -> {:cont, [line | seen]}
    end
  end)
end
gpu_port = fn ->
  case Agent.get(gpu_state, & &1.port) do
    nil ->
      {cubin, host, input} = gpu_files
      env = [{~c"TURBO_SERVE", ~c"1"}, {~c"TURBO_GPU_DUTY", ~c"#{Keyword.get(opts, :duty, 25.0)}"}]
      port = Port.open({:spawn_executable, host}, [:binary, :exit_status, :stderr_to_stdout, {:line, 4096}, {:env, env},
        {:args, [cubin, input, Integer.to_string(Keyword.get(opts, :blocks, 64)), Integer.to_string(launch_us)]}])
      if File.exists?(checkpoint) and not done?.(), do: IO.puts("  " <> Enum.join(gpu_reply.(port, "load " <> checkpoint), " / "))
      Agent.update(gpu_state, &%{&1 | port: port})
      port
    port -> port
  end
end
run_gpu_slice = fn ->
  port = gpu_port.()
  t0 = System.monotonic_time(:millisecond)
  [status] = Enum.filter(gpu_reply.(port, "run #{slice} #{hlc_send.()}"), &String.starts_with?(&1, "status"))
  Agent.update(own, fn st -> %{st | burst_ms: st.burst_ms + System.monotonic_time(:millisecond) - t0} end)
  n = Agent.get_and_update(gpu_state, fn st -> {st.slices + 1, %{st | slices: st.slices + 1}} end)
  if rem(n, Keyword.get(opts, :save_every, 50)) == 0, do: gpu_reply.(port, "save " <> checkpoint)
  if String.starts_with?(status, "status done") do
    Port.command(port, "result\n")
    File.write!(status_file, "done")
    rest = Stream.repeatedly(fn -> receive do {^port, {:data, {:eol, l}}} -> l; {^port, {:exit_status, _}} -> :eof after 60_000 -> :eof end end) |> Enum.take_while(&(&1 != :eof))
    File.write!(Path.join(scratch, "result.txt"), Enum.join(rest, "\n") <> "\n")
  end
  status
end
run_slice = if gpu?, do: run_gpu_slice, else: run_cpu_slice

print_solution = fn ->
  fzn = Keyword.get(opts, :fzn)
  printer = Keyword.get(opts, :printer, Path.join(root, ".lake/build/bin/frontier_frontend"))
  if fzn != nil do
    {out, 0} = System.cmd("nice", ["-n", "19", printer, "--solution", fzn, Path.join(scratch, "result.txt")])
    File.write!(Path.join(scratch, "solution.mzn"), out)
    IO.puts("solution in #{Path.join(scratch, "solution.mzn")}")
  end
end

loop = fn loop, slices ->
  plan_started = System.monotonic_time(:microsecond)
  steps = plan.(free?.(), done?.())
  plan_ms = (System.monotonic_time(:microsecond) - plan_started) / 1000
  cond do
    steps == [] ->
      IO.puts("done after #{slices} slice(s); result in #{Path.join(scratch, "result.txt")}")
      print_solution.()
      IO.puts(File.read!(Path.join(scratch, "result.txt")) |> String.split("\n") |> Enum.take(4) |> Enum.join("\n"))
    max_slices != :infinity and slices >= max_slices ->
      if gpu? and Agent.get(gpu_state, & &1.port) != nil, do: IO.puts("  " <> Enum.join(gpu_reply.(Agent.get(gpu_state, & &1.port), "save " <> checkpoint), " / "))
      IO.puts("paused after #{slices} slice(s); checkpoint #{checkpoint}")
    hd(steps) == "wait-free" ->
      IO.puts("waiting: load #{load1.()} (limit #{max_load}), gpu #{gpu_percent.()}% (limit #{max_gpu}%)")
      Process.sleep(poll_ms)
      loop.(loop, slices)
    hd(steps) == "solve-slice" ->
      run_started = System.monotonic_time(:microsecond)
      status = run_slice.()
      trace.("slice #{hlc_send.()} #{Float.round(plan_ms, 2)} #{Float.round((System.monotonic_time(:microsecond) - run_started) / 1000, 2)}")
      IO.puts("slice #{slices + 1}: #{status}")
      loop.(loop, slices + 1)
  end
end
loop.(loop, 0)
