# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# The cluster's fault tests on the smallest level (scout, 32 subproblems, the fixture input). A scenario is data: which workers there are and what the coordinator
# must then say. Nothing in a scenario depends on speed: a worker dies, lies or is honest by an option, and the coordinator decides by counts.
#   clean     two honest workers, one that dies on its first job, one more honest: no fraud, nobody banned, objective 511
#   liar      the last worker lies about every answer: at least three fraud lines, it is banned, objective 511
#   flaky     the last worker lies once: one fraud line, nobody banned, it is forgiven, objective 511
#   noquorum  one honest worker, one that dies, one liar: no two equal answers can exist, so the coordinator must stop with "no quorum" and a failure code
# Usage: elixir tools/cluster_test.exs run SCENARIO HOST_BINARY GUEST.elf [--addresses COORDINATOR,W1,W2,W3,W4]   start the nodes here and judge
#        elixir tools/cluster_test.exs judge SCENARIO COORDINATOR.log --exit CODE                                  judge a log made elsewhere (the CI containers)
{opts, [mode, scenario | rest], _} = OptionParser.parse(System.argv(), strict: [addresses: :string, exit: :integer])
root = Path.expand("..", __DIR__)

defmodule ClusterTest do
  @die ["--die-at-first-job"]
  @scenarios %{
    "clean" => %{workers: [[], [], @die, []], exit: 0, objective: true, frauds: 0..0, banned: 0, forgiven: false, no_quorum: false},
    "liar" => %{workers: [[], [], @die, ["--lie"]], exit: 0, objective: true, frauds: 3..1000, banned: 1, forgiven: false, no_quorum: false},
    "flaky" => %{workers: [[], [], @die, ["--lie-times", "1"]], exit: 0, objective: true, frauds: 1..1, banned: 0, forgiven: true, no_quorum: false},
    "noquorum" => %{workers: [[], @die, ["--lie"]], exit: 1, objective: false, frauds: 0..1000, banned: 0, forgiven: false, no_quorum: true}
  }
  def scenario(name), do: Map.fetch!(@scenarios, name)

  # What the coordinator's output must show for the scenario; every line of the list is one named check.
  def checks(expected, lines, exit_code) do
    has = fn text -> Enum.any?(lines, &String.contains?(&1, text)) end
    frauds = Enum.count(lines, &String.starts_with?(&1, "fraud:"))
    [
      {"exit code #{expected.exit}", exit_code == expected.exit},
      {"objective 511 #{if expected.objective, do: "reported", else: "not reported"}", has.("objective [511, 511]") == expected.objective},
      {"fraud lines in #{inspect(expected.frauds)} (#{frauds})", frauds in expected.frauds},
      {"#{expected.banned} node(s) banned", expected.no_quorum or has.(" #{expected.banned} node(s) banned")},
      {"forgiven #{expected.forgiven}", Enum.any?(lines, &String.starts_with?(&1, "forgiven:")) == expected.forgiven},
      {"a lost node's subproblem requeued", expected.no_quorum or has.("lost; subproblem")},
      {"subproblems accepted by two equal answers", expected.no_quorum or Enum.any?(lines, &(&1 =~ ~r/\d+ of 32 subproblems accepted with 2 equal answers/))},
      {"no quorum #{expected.no_quorum}", has.("no quorum for subproblem") == expected.no_quorum}
    ]
  end

  def judge(name, lines, exit_code) do
    results = checks(scenario(name), lines, exit_code)
    for {check, ok} <- results, do: IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} #{check}")
    passed = Enum.all?(results, &elem(&1, 1))
    IO.puts("cluster test #{name}: #{if passed, do: "ok", else: "FAILED"}")
    passed
  end

  # Lines of a port until it exits; the first line is handed to `on_first` (the coordinator says when it is ready for workers).
  def collect(port, lines, on_first) do
    receive do
      {^port, {:data, {_, line}}} ->
        if lines == [], do: on_first.()
        collect(port, [line | lines], on_first)
      {^port, {:exit_status, code}} -> {Enum.reverse(lines), code}
    end
  end
end

case mode do
  "judge" ->
    [log] = rest
    lines = log |> File.read!() |> String.split("\n")
    unless ClusterTest.judge(scenario, lines, Keyword.fetch!(opts, :exit)), do: System.halt(1)
  "run" ->
    [host, guest] = rest
    expected = ClusterTest.scenario(scenario)
    [coordinator | addresses] = opts |> Keyword.get(:addresses, "127.0.0.1,127.0.0.1,127.0.0.1,127.0.0.1,127.0.0.1") |> String.split(",")
    elixir = System.find_executable("elixir")
    script = Path.join(root, "tools/turbo_cluster.exs")
    fixtures = Path.join(root, "frontend/fixtures")
    # the port mapper must run before a node is started inside a running VM
    epmd = Path.join([:code.root_dir(), "erts-#{:erlang.system_info(:version)}", "bin", "epmd"])
    System.cmd(epmd, ["-daemon"])
    node = fn name, address, args ->
      Port.open({:spawn_executable, elixir}, [:binary, :exit_status, :stderr_to_stdout, {:line, 4096}, {:cd, root},
        {:env, [{~c"NODE_NAME", ~c"#{name}@#{address}"}, {~c"ELIXIR_ERL_OPTIONS", ~c"+fnu"}]}, {:args, [script | args]}])
    end
    port = node.("coord", coordinator, ["coordinator", Path.join(fixtures, "scout.cp"), "--power", "5", "--workers", "#{length(expected.workers)}", "--replicas", "2",
                                        "--problem", Path.join(fixtures, "scout.power5.input.txt"), "--cookie", "ci"])
    start_workers = fn ->
      for {{extra, address}, number} <- Enum.with_index(Enum.zip(expected.workers, addresses), 1),
          do: node.("w#{number}", address, ["worker", "coord@#{coordinator}", guest, host, "--kind", "cpu", "--cookie", "ci"] ++ extra)
    end
    {lines, code} = ClusterTest.collect(port, [], start_workers)
    Enum.each(lines, &IO.puts/1)
    unless ClusterTest.judge(scenario, lines, code), do: System.halt(1)
end
