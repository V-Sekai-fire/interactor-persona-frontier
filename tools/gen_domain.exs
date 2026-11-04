# Emits domains/character-stack.jsonld from frontier/knowledge.json.
# The knowledge file is the learned content: stage requirements, tokens (owning repos) and
# durations. This script is the fixed meta-method that turns it into a RECTGTN domain.
defmodule Gen do
  def ge(ptr), do: %{"eval" => %{"type" => "math/ge", "a" => %{"type" => "pointer/get", "pointer" => ptr}, "b" => 1}}
  def set(ptr), do: %{"pointer/set" => ptr, "value" => 1}

  def domain(k) do
    stages = k["stages"]
    tokens = stages |> Enum.flat_map(fn {_, s} -> s["tokens"] end) |> Enum.uniq() |> Enum.sort()
    actions =
      Map.new(tokens, fn t -> {"acquire-token-#{t}", %{"params" => [], "body" => [set("/token/#{t}")]}} end)
      |> Map.merge(Map.new(stages, fn {n, s} ->
        body = Enum.map(s["requires"], &ge("/stage/#{&1}")) ++ Enum.map(s["tokens"], &ge("/token/#{&1}")) ++ [set("/stage/#{n}")]
        a = %{"params" => [], "body" => body}
        a = case k["durations"][n], do: (nil -> a; d -> Map.put(a, "duration", d))
        {"settle-#{n}", a}
      end))
    methods =
      Map.new(tokens, fn t ->
        {"reach-token-#{t}", %{"params" => [], "alternatives" => [
          %{"name" => "held", "check" => [ge("/token/#{t}")], "subtasks" => []},
          %{"name" => "acquire", "subtasks" => [["acquire-token-#{t}"]]}]}}
      end)
      |> Map.merge(Map.new(stages, fn {n, s} ->
        subs = Enum.map(s["requires"], &["reach-stage-#{&1}"]) ++ Enum.map(s["tokens"], &["reach-token-#{&1}"]) ++ [["settle-#{n}"]]
        {"reach-stage-#{n}", %{"params" => [], "alternatives" => [
          %{"name" => "held", "check" => [ge("/stage/#{n}")], "subtasks" => []},
          %{"name" => "settle", "subtasks" => subs}]}}
      end))
    %{"@context" => %{"VSEKAI" => "https://v-sekai.org/", "domain" => "VSEKAI:planning/domain/"},
      "@type" => "domain:Definition", "name" => "character_stack", "source" => "interactor-persona-frontier",
      "version" => "0.1.#{k["revision"]}",
      "description" => "The look-dev to character-persona pipeline: settle-N holds when the stages it requires are settled and the repositories it draws on are acquired. Requirements and durations are learned from experience reports; see frontier/knowledge.json.",
      "variables" => [
        %{"name" => "stage", "type" => "int", "description" => "1 when a pipeline stage is settled.", "init" => %{}},
        %{"name" => "token", "type" => "int", "description" => "1 when a repository is acquired.", "init" => %{}}],
      "actions" => actions, "methods" => methods}
  end

  def problem(k, name, held_stages, held_tokens, goal) do
    stages = k["stages"]
    tokens = stages |> Enum.flat_map(fn {_, s} -> s["tokens"] end) |> Enum.uniq()
    %{"@context" => %{"VSEKAI" => "https://v-sekai.org/", "domain" => "VSEKAI:planning/domain/"},
      "@type" => "domain:Problem", "name" => name, "source" => "interactor-persona-frontier", "version" => "0.1.0",
      "description" => "Stages #{inspect(held_stages)} held; goal #{goal}.",
      "variables" => [
        %{"name" => "stage", "type" => "int", "init" => Map.new(Map.keys(stages), &{&1, (if &1 in held_stages, do: 1, else: 0)})},
        %{"name" => "token", "type" => "int", "init" => Map.new(tokens, &{&1, (if &1 in held_tokens, do: 1, else: 0)})}],
      "capabilities" => %{"entities" => %{}, "graph" => %{"edges" => []}},
      "todo_list" => [[goal]], "domain" => "character_stack"}
  end
end

unless Process.get(:gen_domain_lib) do
case System.argv() do
  [] ->
    k = File.read!("frontier/knowledge.json") |> JSON.decode!()
    File.write!("domains/character-stack.jsonld", JSON.encode!(Gen.domain(k)))
    File.write!("problems/character-stack-cold.jsonld", JSON.encode!(Gen.problem(k, "character_stack_cold", [], [], "reach-stage-10")))
    IO.puts("domains/character-stack.jsonld revision #{k["revision"]}")
  _ -> IO.puts("usage: elixir tools/gen_domain.exs"); System.halt(2)
end
end
