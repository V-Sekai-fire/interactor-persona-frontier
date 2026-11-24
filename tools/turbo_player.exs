# Solve a dumped problem in time slices, planning each slice with the planner (domain turbo_solve, stored in SQLite) and only when the machine is free.
# The game on this machine is real time: a slice is a bounded number of nodes at the lowest priority, the planner is asked again after every slice
# (reentrant, like the replan loop of an HTN planner), and the whole search state is in a checkpoint file, so this tool can be stopped and started at any time.
# Usage: elixir tools/turbo_player.exs <level.cp> [--slice NODES] [--max-load L] [--max-gpu PERCENT] [--poll-ms MS] [--max-slices N] [--checkpoint FILE]
#   the level is the file's base name: scout, party or saga (the enumeration `level` of the domain).
# Free means the one-minute load average is under --max-load (default 4, the host has 8 threads) and the GPU is under --max-gpu percent busy (default 30).
{opts, [cp_path], _} = OptionParser.parse(System.argv(), strict: [slice: :integer, max_load: :float, max_gpu: :integer, poll_ms: :integer, max_slices: :integer, checkpoint: :string])
slice = Keyword.get(opts, :slice, 100)
max_load = Keyword.get(opts, :max_load, 4.0)
max_gpu = Keyword.get(opts, :max_gpu, 30)
poll_ms = Keyword.get(opts, :poll_ms, 2000)
max_slices = Keyword.get(opts, :max_slices, :infinity)
root = File.cwd!()
level = Path.basename(cp_path, ".cp")
level_value = %{"scout" => 1, "party" => 2, "saga" => 3} |> Map.fetch!(level)
store_bin = Path.join(root, ".lake/build/bin/frontier_store")
[scratch] = case System.cmd("elixir", [Path.join(root, "tools/turbo_solve.exs"), cp_path, "--prepare"], env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}]) do
  {out, 0} -> out |> String.split("\n", trim: true) |> Enum.take(-1)
  {out, code} -> raise("prepare failed (#{code}): #{String.slice(out, 0, 400)}")
end
checkpoint = Keyword.get(opts, :checkpoint, Path.join(scratch, "checkpoint.bin"))
status_file = checkpoint <> ".status"
domain = Path.join(root, "entities/domains/turbo-solve.jsonld")

load1 = fn -> "/proc/loadavg" |> File.read!() |> String.split() |> hd() |> String.to_float() end
gpu_percent = fn ->
  case System.cmd("nvidia-smi", ["--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"], stderr_to_stdout: true) do
    {out, 0} -> out |> String.split("\n", trim: true) |> Enum.map(&String.to_integer(String.trim(&1))) |> Enum.max()
    _ -> 0
  end
end
free? = fn -> load1.() < max_load and gpu_percent.() < max_gpu end
done? = fn -> File.read(status_file) == {:ok, "done"} end

# One planner call: a problem with the observed state in a fresh database, planned from the tables.
plan = fn free, done ->
  db = Path.join(scratch, "plan.sqlite")
  File.rm(db)
  File.rm(db <> "-journal")
  env = [{"FRONTIER_DB", db}]
  name = "turbo_solve_#{level}_tick"
  problem = %{
    "@context" => %{"VSEKAI" => "https://v-sekai.org/", "domain" => "VSEKAI:planning/domain/"}, "@type" => "domain:Problem",
    "capabilities" => %{"entities" => %{}, "graph" => %{"edges" => []}}, "domain" => "turbo_solve", "name" => name,
    "source" => "interactor-persona-frontier", "todo_list" => [["solve-level", "machine.host", "level.#{level}"]],
    "variables" => [%{"init" => %{"1" => if(free, do: 1, else: 0)}, "name" => "free", "type" => "int"},
                    %{"init" => %{"#{level_value}" => if(done, do: 1, else: 0)}, "name" => "done", "type" => "int"}],
    "version" => "0.1.0"}
  problem_file = Path.join(scratch, "problem.jsonld")
  File.write!(problem_file, JSON.encode!(problem))
  {_, 0} = System.cmd(store_bin, ["migrate"], env: env, stderr_to_stdout: true)
  {_, 0} = System.cmd(store_bin, ["import", domain, problem_file], env: env, stderr_to_stdout: true)
  {out, 0} = System.cmd(store_bin, ["plan", name], env: env, stderr_to_stdout: true)
  doc = JSON.decode!(out)
  if doc["reached"] != true, do: raise("the planner refused the goal: #{String.slice(out, 0, 300)}")
  Enum.map(doc["steps"], fn s -> s["action"] end)
end

run_slice = fn ->
  {out, code} = System.cmd("nice", ["-n", "19", Path.join(scratch, "solve"), Path.join(scratch, "input.txt"), checkpoint, Integer.to_string(slice)])
  if code != 0, do: raise("slice failed (#{code})")
  [status | rest] = String.split(out, "\n", trim: true)
  if String.starts_with?(status, "status done") do
    File.write!(status_file, "done")
    File.write!(Path.join(scratch, "result.txt"), Enum.join(rest, "\n") <> "\n")
  end
  status
end

loop = fn loop, slices ->
  steps = plan.(free?.(), done?.())
  cond do
    steps == [] ->
      IO.puts("done after #{slices} slice(s); result in #{Path.join(scratch, "result.txt")}")
      IO.puts(File.read!(Path.join(scratch, "result.txt")) |> String.split("\n") |> Enum.take(4) |> Enum.join("\n"))
    max_slices != :infinity and slices >= max_slices -> IO.puts("paused after #{slices} slice(s); checkpoint #{checkpoint}")
    hd(steps) == "wait-free" ->
      IO.puts("waiting: load #{load1.()} (limit #{max_load}), gpu #{gpu_percent.()}% (limit #{max_gpu}%)")
      Process.sleep(poll_ms)
      loop.(loop, slices)
    hd(steps) == "solve-slice" ->
      status = run_slice.()
      IO.puts("slice #{slices + 1}: #{status}")
      loop.(loop, slices + 1)
  end
end
loop.(loop, 0)
