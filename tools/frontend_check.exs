# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Compare the Lean front end with Turbo's statistics for a FlatZinc file: frontier_frontend --stats FILE.fzn against frontend/expected/LEVEL.stats.
# Every key of the expected file is compared: the parse and TNF counts, the simplifier's per-iteration and total eliminations, the variable and constraint counts.
# With a third argument (the oracle's dump, for instance /mnt/fire/6-datasource/turbo-runs/scout.cp) `frontier_frontend --dump` must also be byte equal.
# Usage: elixir tools/frontend_check.exs LEVEL FILE.fzn [ORACLE.cp]   (LEVEL is scout, party or saga); exits 1 on a difference.
[level, fzn | rest] = System.argv()
root = File.cwd!()
parse = fn text -> text |> String.split("\n", trim: true) |> Map.new(fn line -> [k, v] = String.split(line, "=", parts: 2); {k, v} end) end
expected = parse.(File.read!(Path.join(root, "frontend/expected/#{level}.stats")))
{out, 0} = System.cmd(Path.join(root, ".lake/build/bin/frontier_frontend"), ["--stats", fzn])
got = parse.(out)
bad =
  for key <- Map.keys(expected) |> Enum.sort(), reduce: 0 do
    acc ->
      ok = got[key] == expected[key]
      IO.puts("#{if ok, do: "ok  ", else: "FAIL"} #{key}: got #{got[key]}, Turbo #{expected[key]}")
      if ok, do: acc, else: acc + 1
  end
dump_bad =
  case rest do
    [oracle] ->
      {mine, 0} = System.cmd(Path.join(root, ".lake/build/bin/frontier_frontend"), ["--dump", fzn])
      ok = mine == File.read!(oracle)
      IO.puts("#{if ok, do: "ok  ", else: "FAIL"} dump equals #{oracle}")
      if ok, do: 0, else: 1
    _ -> 0
  end
bad = bad + dump_bad
System.halt(if bad == 0, do: 0, else: 1)
