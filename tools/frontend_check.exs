# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Compare the Lean front end with Turbo's statistics for a FlatZinc file: frontier_frontend --stats FILE.fzn against frontend/expected/LEVEL.stats.
# Usage: elixir tools/frontend_check.exs LEVEL FILE.fzn   (LEVEL is scout, party or saga); exits 1 on a difference.
[level, fzn] = System.argv()
root = File.cwd!()
parse = fn text -> text |> String.split("\n", trim: true) |> Map.new(fn line -> [k, v] = String.split(line, "=", parts: 2); {k, v} end) end
expected = parse.(File.read!(Path.join(root, "frontend/expected/#{level}.stats")))
{out, 0} = System.cmd(Path.join(root, ".lake/build/bin/frontier_frontend"), ["--stats", fzn])
got = parse.(out)
bad =
  for key <- ["parsed_variables", "parsed_constraints", "tnf_variables", "tnf_constraints"], reduce: 0 do
    acc ->
      ok = got[key] == expected[key]
      IO.puts("#{if ok, do: "ok  ", else: "FAIL"} #{key}: got #{got[key]}, Turbo #{expected[key]}")
      if ok, do: acc, else: acc + 1
  end
System.halt(if bad == 0, do: 0, else: 1)
