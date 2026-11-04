defmodule FrontierNodeTest do
  @moduledoc """
  The Lean server is an Erlang node, and the answers hold for every goal PropCheck can generate.

  Each property is one invariant of the node, with the negative side built into the generator:
  a goal the pipeline has is planned, a goal it has not is refused by name, and every answer is
  one message back to the sender, as a binary. A third test is the gate the properties stand on:
  when the node is down, the suite fails rather than skips.
  """
  use ExUnit.Case
  use PropCheck

  @node :"frontier@127.0.0.1"
  @stages_for %{"character" => Enum.map(1..10, &Integer.to_string/1), "prop" => ~w(1 2 4 6 7 10), "world" => ~w(1 2 4 6 7 10)}
  @names %{"1" => "look-dev", "2" => "image-to-3d", "3" => "body", "4" => "gpu-skin", "5" => "garments", "6" => "look-render", "7" => "gpu-motion", "8" => "face-voice", "9" => "persona", "10" => "runtime"}

  setup_all do
    true = Node.alive?() or raise "run with --name probe@127.0.0.1 --cookie <cookie>"
    true = Node.connect(@node) or raise "the frontier node is not up at #{@node}"
    :ok
  end

  defp ask(text) do
    send({:frontier, @node}, {self(), text})
    receive do
      reply when is_binary(reply) -> Jason.decode!(reply)
    after
      15_000 -> flunk("no answer to #{inspect(text)} within 15 s")
    end
  end

  defp settled(plan), do: for(%{"action" => "settle-" <> rest} <- plan["steps"], do: rest)

  # a goal the pipeline has: `reach-<subject>-N`, `<subject> N`, or a stage name for the character
  def declared_goal do
    let subject <- oneof(Map.keys(@stages_for)) do
      let n <- oneof(@stages_for[subject]) do
        let g <- oneof(["reach-#{subject}-#{n}", "#{subject} #{n}"] ++ if(subject == "character", do: [@names[n]], else: [])) do
          {subject, n, g}
        end
      end
    end
  end

  property "a declared goal is planned, and the plan ends by settling that goal for that subject", [:verbose, numtests: 60] do
    forall {subject, n, goal} <- declared_goal() do
      plan = ask(goal)
      plan["reached"] == true and List.last(settled(plan)) == "#{subject}-#{n}"
    end
  end

  property "a world or prop never settles a body, garment, face or persona stage" do
    forall {subject, n} <- {oneof(["prop", "world"]), oneof(~w(1 2 4 6 7 10))} do
      plan = ask("reach-#{subject}-#{n}")
      Enum.all?(settled(plan), fn s -> String.starts_with?(s, subject <> "-") and not (s in ~w(prop-3 prop-5 prop-8 prop-9 world-3 world-5 world-8 world-9)) end)
    end
  end

  property "an undeclared goal is refused by name, never planned" do
    forall text <- such_that(t <- utf8(), when: not Regex.match?(~r/^\s*(reach-)?(character|prop|world)?[- ]?(\d+|look-dev|image-to-3d|body|gpu-skin|garments|look-render|gpu-motion|face-voice|persona|runtime)?\s*$/i, t)) do
      ask(text) == %{"refused" => "undeclared_goal"}
    end
  end

  property "a stage out of a subject's set is refused" do
    forall {subject, n} <- {oneof(["prop", "world"]), oneof(~w(3 5 8 9))} do
      ask("reach-#{subject}-#{n}") == %{"refused" => "undeclared_goal"}
    end
  end

  test "frontier lists 55 character, 21 prop and 21 world levels" do
    levels = ask("frontier")["levels"]
    assert Enum.frequencies_by(levels, & &1["subject"]) == %{"character" => 55, "prop" => 21, "world" => 21}
  end
end
