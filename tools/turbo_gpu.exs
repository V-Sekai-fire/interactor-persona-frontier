# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-FileCopyrightText: 2025 Pierre Talbot
# SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
# SPDX-License-Identifier: Apache-2.0 AND MIT
# Solve a dumped problem on the GPU with the cooperative Slang kernel (turbo/Turbo/Coop.lean): build the cubin and the CUDA host when they are stale, make the input, run
# in bounded launches under a duty-cycle cap. The game on this machine uses the same GPU, so the run waits until the GPU is under --max-gpu percent busy.
# `--prepare` builds and prints three lines (cubin, host binary, input folder) without running; tools/turbo_player.exs --engine gpu uses it.
# Usage: elixir tools/turbo_gpu.exs <problem.cp> [--blocks N] [--power P] [--duty PERCENT] [--max-gpu PERCENT] [--stop-nodes N] [--max-launches N]
{opts, [cp_path], _} = OptionParser.parse(System.argv(), strict: [blocks: :integer, power: :integer, duty: :float, max_gpu: :integer, stop_nodes: :integer, max_launches: :integer, wait: :boolean, prepare: :boolean])
root = File.cwd!()
sdk = Path.join(root, ".slang/2026.20")
runs = "/mnt/fire/6-datasource/turbo-runs"
nvcc_env = System.get_env("CUDA_ENV", "/mnt/fire/6-datasource/turbo-build/cuda/.pixi/envs/default")
# 64 blocks and no up-front split: measured on party (3.5 s, against 1.5 s on 256) and saga (13.2 s, against 16.4 s on 256 and 30 s on one block); see docs/turbo-slang.md
blocks = Keyword.get(opts, :blocks, 64)
power = Keyword.get(opts, :power, 0)
# a launch is a time budget in microseconds (a sixteenth of a 64 Hz frame), not a node count: the kernel stops it by its own clock
launch_us = 1000
duty = Keyword.get(opts, :duty, 100.0)
max_gpu = Keyword.get(opts, :max_gpu, 30)
work = Path.join(runs, "gpu-build")
File.mkdir_p!(work)
env = [{"LD_LIBRARY_PATH", Path.join(sdk, "lib")}]

run = fn cmd, args, extra_env ->
  {out, status} = System.cmd(cmd, args, env: env ++ extra_env, stderr_to_stdout: true)
  if status != 0, do: raise("#{Path.basename(cmd)} failed: #{String.slice(out, 0, 600)}")
  out
end

nvidia_smi = System.find_executable("nvidia-smi") || "/usr/lib/wsl/lib/nvidia-smi"
gpu_percent = fn ->
  case System.cmd(nvidia_smi, ["--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"], stderr_to_stdout: true) do
    {out, 0} -> out |> String.trim() |> String.split("\n") |> Enum.map(&String.to_integer(String.trim(&1))) |> Enum.max()
    _ -> 100
  end
end
wait_until_free = fn wait_until_free ->
  busy = gpu_percent.()
  if busy >= max_gpu do
    if Keyword.get(opts, :wait, false) do
      IO.puts("waiting: GPU #{busy}% busy (limit #{max_gpu}%)")
      Process.sleep(2000)
      wait_until_free.(wait_until_free)
    else
      IO.puts("the GPU is #{busy}% busy (limit #{max_gpu}%); pass --wait to wait, or --max-gpu to raise the limit")
      System.halt(3)
    end
  end
end
if not Keyword.get(opts, :prepare, false), do: wait_until_free.(wait_until_free)

text = run.(Path.join(root, ".lake/build/bin/turbo_emit"), ["solve-coop"], [])
hash = :crypto.hash(:sha256, text <> File.read!(Path.join(root, "guest/gpu/turbo_gpu.cpp"))) |> Base.encode16()
cubin = Path.join(work, "solve_coop.cubin")
host = Path.join(work, "turbo_gpu")
if File.read(Path.join(work, "hash")) != {:ok, hash} or not File.exists?(cubin) or not File.exists?(host) do
  File.write!(Path.join(work, "solve_coop.slang"), text)
  run.(Path.join(sdk, "bin/slangc"), [Path.join(work, "solve_coop.slang"), "-target", "cuda", "-entry", "solve", "-stage", "compute", "-o", Path.join(work, "solve_coop.cu")], [])
  run.(Path.join(nvcc_env, "bin/nvcc"), ["-arch=sm_89", "-cubin", "-O2", "-std=c++17", "-I", Path.join(sdk, "include"), "-I", Path.join(nvcc_env, "include"), "-o", cubin, Path.join(work, "solve_coop.cu")], [])
  run.("g++", ["-O2", "-std=c++17", "-I", Path.join(nvcc_env, "targets/x86_64-linux/include"), Path.join(root, "guest/gpu/turbo_gpu.cpp"), "-o", host, "-L", "/usr/lib/wsl/lib", "-lcuda"], [])
  File.write!(Path.join(work, "hash"), hash)
end

prepare_args = [Path.join(root, "tools/turbo_solve.exs"), cp_path, "--prepare", "--power", Integer.to_string(power)] ++
  (case Keyword.get(opts, :stop_nodes) do nil -> []; n -> ["--stop-nodes", Integer.to_string(n)] end)
dir = System.cmd("elixir", prepare_args, env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}]) |> elem(0) |> String.split("\n", trim: true) |> List.last()
if Keyword.get(opts, :prepare, false) do
  IO.puts(cubin)
  IO.puts(host)
  IO.puts(dir)
  System.halt(0)
end
launch_env = [{"TURBO_GPU_DUTY", to_string(duty)}] ++ (case Keyword.get(opts, :max_launches) do nil -> []; n -> [{"TURBO_MAX_LAUNCHES", Integer.to_string(n)}] end)
{out, status} = System.cmd(host, [cubin, Path.join(dir, "input.txt"), Integer.to_string(blocks), Integer.to_string(launch_us)], env: launch_env, stderr_to_stdout: true)
IO.write(out)
System.halt(status)
