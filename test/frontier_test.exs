defmodule FrontierTest do
  @moduledoc """
  The planner's answers hold for every goal StreamData can generate, called in-process through leanler.

  Each property is one invariant, with the negative side built into the generator: a goal the pipeline has is
  planned, a goal it has not is refused by name. Two tests are the gates the properties stand on: the library
  must be loaded (the suite fails rather than skips), and the declared-goal predicate must fail on broken knowledge.
  """
  use ExUnit.Case
  use ExUnitProperties

  # a stage is named by its id; the old number is an alias that still answers
  @character ~w(look-dev image-to-3d body gpu-skin garments look-render gpu-motion face-voice persona runtime)
  @shared ~w(look-dev image-to-3d gpu-skin look-render gpu-motion runtime)
  @stages_for %{"character" => @character, "prop" => @shared, "world" => @shared}
  @numbers Map.new(Enum.with_index(@character, 1), fn {id, i} -> {id, Integer.to_string(i)} end)
  @undeclared ~r/^\s*(reach-)?(character|prop|world)?[- ]?(\d+|look-dev|image-to-3d|body|gpu-skin|garments|look-render|gpu-motion|face-voice|persona|runtime)?\s*$/i

  setup_all do
    {:ok, text} = Frontier.seeds_text()
    {:ok, text: text}
  end

  defp ask(text, goal) do
    {:ok, json} = Frontier.Native.answer(text, goal)
    {:ok, plan} = JSON.decode(json)
    plan
  end

  defp settled(plan), do: for(%{"action" => "settle-" <> rest} <- plan["steps"] || [], do: rest)

  defp declared_ok?(text, subject, n, goal) do
    plan = ask(text, goal)
    plan["reached"] == true and List.last(settled(plan)) == "#{subject}-#{n}"
  end

  # "look-render" is both the id of character stage 6 and the subject `look` with its stage `render`;
  # the planner reads it as the second, as before, so the bare id goal leaves it out.
  defp declared_goal do
    gen all subject <- member_of(Map.keys(@stages_for)),
            n <- member_of(@stages_for[subject]),
            goal <- member_of(["reach-#{subject}-#{n}", "#{subject} #{n}", "reach-#{subject}-#{@numbers[n]}", "#{subject} #{@numbers[n]}"] ++ if(subject == "character" and n != "look-render", do: [n], else: [])) do
      {subject, n, goal}
    end
  end

  test "the library is loaded and answers (the gate: fail, never skip)", %{text: text} do
    assert Code.ensure_loaded?(Frontier.Native)
    assert %{"refused" => "undeclared_goal"} = ask(text, "fly")
  end

  property "a declared goal is planned, and the plan ends by settling that goal for that subject", %{text: text} do
    check all {subject, n, goal} <- declared_goal(), max_runs: 60 do
      assert declared_ok?(text, subject, n, goal)
    end
  end

  property "a world or prop never settles a body, garment, face or persona stage", %{text: text} do
    check all subject <- member_of(["prop", "world"]), n <- member_of(@shared) do
      plan = ask(text, "reach-#{subject}-#{n}")
      assert Enum.all?(settled(plan), &String.starts_with?(&1, subject <> "-"))
      refute Enum.any?(settled(plan), &(&1 in ~w(prop-body prop-garments prop-face-voice prop-persona world-body world-garments world-face-voice world-persona)))
    end
  end

  property "an undeclared goal is refused by name, never planned", %{text: text} do
    check all goal <- StreamData.filter(StreamData.string(:printable), &(not Regex.match?(@undeclared, &1))) do
      assert ask(text, goal) == %{"refused" => "undeclared_goal"}
    end
  end

  property "a stage out of a subject's set is refused", %{text: text} do
    check all subject <- member_of(["prop", "world"]), n <- member_of(~w(body garments face-voice persona 3 5 8 9)) do
      assert ask(text, "reach-#{subject}-#{n}") == %{"refused" => "undeclared_goal"}
    end
  end

  test "control: the declared-goal predicate fails on broken knowledge", %{text: text} do
    broken = text <> "\n---\n" <> JSON.encode!(%{"subjects" => %{"character" => %{"stages" => ["look-dev"]}}})
    assert declared_ok?(text, "character", "runtime", "reach-character-10")
    refute declared_ok?(broken, "character", "runtime", "reach-character-10")
  end

  test "control: a changed requirement changes the plan", %{text: text} do
    changed = text <> "\n---\n" <> JSON.encode!(%{"stages" => %{"runtime" => %{"requires" => []}}})
    refute ask(text, "reach-character-10") == ask(changed, "reach-character-10")
  end
end
