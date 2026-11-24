# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-FileCopyrightText: 2025 Pierre Talbot
# SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
# SPDX-License-Identifier: Apache-2.0 AND MIT
# Is the search on many GPU blocks, with work moving between blocks, still the same search? Small generated Party Saga worlds are solved on one block, on 8 and
# on 64; every run must end, every block must say its search was exhaustive, and the best objective must be the one block's. Local only (it needs the GPU).
# Usage: elixir tools/turbo_blocks_check.exs [--worlds 25] [--sizes 1,2]   (worlds per size; seeds 1..worlds)
{opts, [], _} = OptionParser.parse(System.argv(), strict: [worlds: :integer, sizes: :string])
root = File.cwd!()
minizinc_home = System.get_env("MINIZINC_HOME", "/mnt/fire/6-datasource/minizinc-bundle/x/MiniZincIDE-2.11.0-x86_64-linux-gnu")
work = Path.join(System.tmp_dir!(), "turbo_blocks_check")
File.mkdir_p!(work)
elixir = fn args -> System.cmd("elixir", args, env: [{"ELIXIR_ERL_OPTIONS", "+fnu"}], stderr_to_stdout: true) end

# the kernel and the host are built once, from the fixture
{built, 0} = elixir.([Path.join(root, "tools/turbo_gpu.exs"), Path.join(root, "frontend/fixtures/scout.cp"), "--prepare", "--blocks", "1", "--power", "0"])
[cubin, host, _] = built |> String.split("\n", trim: true) |> Enum.take(-3)

dump = fn size, seed ->
  name = "world_#{size}_#{seed}"
  [dzn, fzn, ozn, cp] = for extension <- ~w(dzn fzn ozn cp), do: Path.join(work, name <> "." <> extension)
  {_, 0} = elixir.([Path.join(root, "tools/party_saga.exs"), "dump", "scout", "#{size}", "#{seed}", dzn])
  {_, 0} = System.cmd(Path.join(minizinc_home, "bin/minizinc"), ["--solver", "org.minizinc.mzn-fzn", "-c", "--fzn", fzn, "--ozn", ozn,
    Path.join(root, "entities/fixtures/minizinc/party-saga/party-saga.mzn"), dzn], env: [{"LD_LIBRARY_PATH", Path.join(minizinc_home, "lib")}], stderr_to_stdout: true)
  {text, 0} = System.cmd(Path.join(root, ".lake/build/bin/frontier_frontend"), ["--dump", fzn])
  File.write!(cp, text)
  cp
end

# One run: {objective or :none, all blocks exhaustive?, nodes, handoffs}
solve = fn cp, blocks, power ->
  {out, 0} = elixir.([Path.join(root, "tools/turbo_solve.exs"), cp, "--input-only", "--power", "#{power}"])
  input = Path.join(out |> String.split("\n", trim: true) |> List.last(), "input.txt")
  {text, status} = System.cmd("nice", ["-n", "19", host, cubin, input, "#{blocks}", "1000"], stderr_to_stdout: true)
  field = fn pattern -> case Regex.run(pattern, text) do [_, value] -> String.to_integer(value); _ -> nil end end
  done = status == 0 and String.contains?(text, "status done")
  exhaustive = Regex.run(~r/exhaustive blocks (\d+) of (\d+)/, text)
  %{done: done, objective: field.(~r/error 0 approx (-?\d+)/), exhaustive: match?([_, same, same], exhaustive), nodes: field.(~r/status done nodes (\d+)/),
    handoffs: field.(~r/handoffs between blocks (\d+)/) || 0}
end

sizes = opts |> Keyword.get(:sizes, "1,2") |> String.split(",") |> Enum.map(&String.to_integer/1)
results =
  for size <- sizes, seed <- 1..Keyword.get(opts, :worlds, 25) do
    cp = dump.(size, seed)
    [one, eight, many] = for {blocks, power} <- [{1, 0}, {8, 0}, {64, 0}], do: solve.(cp, blocks, power)
    same = Enum.all?([one, eight, many], &(&1.done and &1.exhaustive)) and eight.objective == one.objective and many.objective == one.objective
    IO.puts("#{if same, do: "ok  ", else: "FAIL"} size #{size} seed #{seed}: objective #{inspect(one.objective)} / #{inspect(eight.objective)} / #{inspect(many.objective)}" <>
            "  nodes #{one.nodes} / #{eight.nodes} / #{many.nodes}  handoffs #{eight.handoffs} / #{many.handoffs}")
    same
  end
IO.puts("blocks check: #{Enum.count(results, & &1)} of #{length(results)} worlds give the one-block optimum on 8 and on 64 blocks")
if not Enum.all?(results), do: System.halt(1)
