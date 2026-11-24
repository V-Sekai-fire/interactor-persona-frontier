# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Summarize a TURBO_TRACE file: the host's "launch HLC START_NS DURATION_NS NODES" lines and the player's "slice HLC PLAN_MS RUN_MS" lines.
# The stamps are the entity packet's hybrid logical clock, so the check is that they only grow when the lines are sorted by arrival, and the split is
# GPU launch time against host gaps (duty sleeps, status copies) against planner time. Usage: elixir tools/turbo_profile.exs TRACE
[path] = System.argv()
lines = path |> File.stream!() |> Enum.map(&String.split(String.trim(&1)))
launches = for ["launch", h, start, dur, nodes] <- lines, do: {String.to_integer(h), String.to_integer(start), String.to_integer(dur), String.to_integer(nodes)}
slices = for ["slice", h, plan, run] <- lines, do: {String.to_integer(h), String.to_float(plan), String.to_float(run)}
pct = fn sorted, p -> Enum.at(sorted, min(length(sorted) - 1, round(p * (length(sorted) - 1)))) end
ordered? = fn xs -> xs |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a <= b end) end
if launches != [] do
  durs = launches |> Enum.map(fn {_, _, d, _} -> d / 1.0e6 end) |> Enum.sort()
  total = Enum.sum(durs)
  {_, first, _, _} = hd(launches)
  {_, last, last_dur, last_nodes} = List.last(launches)
  span = (last + last_dur - first) / 1.0e6
  IO.puts("launches #{length(launches)}  nodes #{last_nodes}  GPU time #{Float.round(total, 1)} ms of #{Float.round(span, 1)} ms span (#{Float.round(100 * total / span, 1)} percent)")
  IO.puts("launch ms: mean #{Float.round(total / length(durs), 3)}  p50 #{Float.round(pct.(durs, 0.5), 3)}  p99 #{Float.round(pct.(durs, 0.99), 3)}  max #{Float.round(List.last(durs), 3)}")
  IO.puts("hlc stamps nondecreasing over launches: #{ordered?.(Enum.map(launches, &elem(&1, 0)))}")
end
if slices != [] do
  plan = Enum.sum(for {_, p, _} <- slices, do: p)
  run = Enum.sum(for {_, _, r} <- slices, do: r)
  IO.puts("slices #{length(slices)}  planner #{Float.round(plan, 1)} ms  host run #{Float.round(run, 1)} ms  (planner share #{Float.round(100 * plan / (plan + run), 1)} percent)")
  IO.puts("hlc stamps nondecreasing over slices: #{ordered?.(Enum.map(slices, &elem(&1, 0)))}")
end
