# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# The property the cluster's fault checks rest on: a subproblem's answer depends only on the problem, the subproblem's index and the bound it is assigned with.
# Three guest hosts each run every subproblem under every bound, in three different orders (ascending, descending, scattered), so each host has a different history
# before each job. Every (subproblem, bound) must get the same answer (skip, best bound, solutions found, nodes searched) from all three, or the tool fails.
# Usage: elixir tools/cluster_replay.exs INPUT.txt HOST_BINARY GUEST.elf [--power P] [--bounds 2147483647,600,520,511]
{opts, [input, host, guest], _} = OptionParser.parse(System.argv(), strict: [power: :integer, bounds: :string])
text = File.read!(input)
jobs = Bitwise.bsl(1, Keyword.get(opts, :power, 5))
bounds = opts |> Keyword.get(:bounds, "2147483647,600,520,511") |> String.split(",") |> Enum.map(&String.to_integer/1)

defmodule Replay do
  # One frame from the host; a host that says nothing for five minutes has hung, which is a failure of the test and not part of its logic.
  def frame(port) do
    receive do
      {^port, {:data, data}} -> data
      {^port, {:exit_status, code}} -> raise("the host exited with #{code}")
    after 300_000 -> raise("the host is silent")
    end
  end

  # The next waiting frame: "A skip bound solutions nodes" (bound reports in between are not part of an answer).
  def waiting(port) do
    case frame(port) do
      <<"A ", rest::binary>> -> rest |> String.split() |> Enum.map(&String.to_integer/1)
      _ -> waiting(port)
    end
  end

  def start(host, guest, text) do
    port = Port.open({:spawn_executable, System.find_executable("nice")}, [:binary, :exit_status, {:packet, 4}, {:args, ["-n", "19", host, guest, "50000000"]}])
    "H" = frame(port)
    Port.command(port, "P " <> text)
    waiting(port)
    port
  end

  # Run the jobs in the given order; each waiting frame is the answer of the job just run.
  def run(port, order) do
    answers =
      for {index, bound} <- order do
        Port.command(port, "S #{index} #{bound}")
        {{index, bound}, List.to_tuple(waiting(port))}
      end
    Port.command(port, "D")
    Map.new(answers)
  end
end

all = for bound <- bounds, index <- 0..(jobs - 1), do: {index, bound}
orders = %{
  "ascending" => all,
  "descending" => Enum.reverse(all),
  "scattered" => Enum.sort_by(all, fn {index, bound} -> {rem(index * 7 + 3, jobs), -bound} end)
}
results = Map.new(orders, fn {name, order} -> {name, Replay.run(Replay.start(host, guest, text), order)} end)
reference = results["ascending"]
differences =
  for {name, answers} <- results, name != "ascending", {job, answer} <- answers, reference[job] != answer do
    {index, bound} = job
    IO.puts("DIFFERENT: subproblem #{index} with bound #{bound}: ascending #{inspect(reference[job])}, #{name} #{inspect(answer)}")
    job
  end
nodes = reference |> Map.values() |> Enum.map(&elem(&1, 3)) |> Enum.sum()
IO.puts("replay: #{map_size(reference)} (subproblem, bound) pairs on #{map_size(results)} hosts in #{map_size(results)} orders, #{nodes} nodes in the reference order, #{length(differences)} differing answer(s)")
if differences != [], do: System.halt(1)
