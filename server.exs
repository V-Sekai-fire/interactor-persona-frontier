# The persona as an A2A webserver that improves its own domain from experience.
#
# The domain covers three subjects, character, prop and world, each with its own stage
# subset; all three are GPU-skinned and GPU-animated (stages 4 and 7), after Remedy's
# large-scale GPU skinning for Alan Wake 2's vegetation (GDC Vault 1034310).
#
# Transport: HTTP/1.1 over :gen_tcp, no dependencies. The answer to a goal is
# exactly what `persona_plan` prints for the generated domain; the server adds
# the frontier loop around it. Run: elixir server.exs --port 9920
#
#   GET  /.well-known/agent-card.json   the Agent Card
#   POST /                              A2A JSON-RPC: message/send with a goal as text
#   GET  /frontier                      the level table and the next level to practice
#   POST /practice                      one frontier cycle: pick a level, plan it, record
#   POST /experience                    an experience report from a real stage run
#   POST /learn                         fold traces into knowledge, regenerate, gate, commit
# ## What it is for
#
# `interactor-taskweft-persona` answers from a planning domain instead of a neural network, and every capability it has is one somebody authored as an action. This server closes that gap the way the Bitter Lesson asks: the planner stays the fixed meta-method, and the domain's content (which stage requires which, how long each takes) is induced from experience reports and from frontier practice, landing only through a gate with a positive and a negative control. The IEC 60848 GRAFCET persona controllers of `interactor-taskweft-nmm-personas` are retired in favour of this loop; only their MaskScore traces survive, as experience. The stage 1 image model is OmniGen2-EditScore7B-v1.1. The domain is the ten-stage look-dev to character-persona pipeline; `docs/stack.md` grades the stages and `docs/repo-inventory.md` holds the repository survey.
#
# Three pieces:
#
# - `frontier/knowledge.json`, the learned content: per stage its requirements, the repositories it draws on (tokens) and a measured duration. `learned` names the requirements experience added, apart from the authored ones.
# - `tools/gen_domain.exs`, the fixed meta-method: knowledge in, a RECTGTN JSON-LD domain in the engine shape out (`settle-N` actions, `acquire-token-R` actions, `reach-stage-N` methods with a `held` alternative first).
# - `server.exs`, the HTTP/1.1 A2A peer and the frontier loop, over `:gen_tcp` with no dependencies. Plans come from the persona repository's `persona_plan`, byte for byte.
#
# | Route | Answer |
# | --- | --- |
# | `GET /.well-known/agent-card.json` | the Agent Card |
# | `POST /` with `message/send` | the plan to the goal in the text part (`reach-stage-N`, a stage name, or empty for stage 10), or `{"refused":"undeclared_goal"}` |
# | `GET /frontier` | the 55 levels (goal stage × stages already held), attempts and reaches, and the next level to practise |
# | `POST /practice` | one frontier cycle: pick the least-attempted level at the edge of competence, instantiate a problem with the held stages' repositories acquired and 30 % of the rest, plan it, record the trace |
# | `POST /experience` | a report from a real stage run: `{"action":"settle-7","held_before":["1","2","3","4","5"],"settled":true,"duration":"PT4H"}` |
# | `POST /learn` | fold experience into knowledge: a stage that settled only when X held requires X; a reported duration becomes the action's; regenerate the domain; land it only if the gate holds |
#
# The gate: the cold problem (nothing held, goal stage 10) still reaches with all ten `settle` steps (positive control), and a domain where stage 10 forgets its requirements yields a different plan (negative control). A revision that fails either is discarded and the knowledge file is untouched. Frontier learning follows the Alyx-planner hypothesis: weights frozen (here, none), the planner improves by iterating its RECTGTN elements, and level search picks the practice tasks.
#
# ## Measured
#
# `PERSONA_PLAN` overrides the planner path. Measured 2026-11-04 on osx-arm64: `lake build persona_plan` 12 s; a plan answers in about 35 ms; 55 practice cycles reach 55 of 55 levels on the authored domain; the two experience reports above make `/learn` land revision 1 with stage 7 requiring stage 5 and `PT4H`, after which the plan for `motion` settles garments first and totals `PT4H1M30S`. The committed knowledge is the authored revision 0; those reports were synthetic and did not land.
#
# ## What it does not do
#
# Practice uses the domain as its own simulator, so on its own it measures reachability and plan length, not truth about the pipeline; truth enters only through `/experience` from a real stage run (a CI job of the owning repository is the intended reporter). No action is ever invented: a report that names an action the domain lacks is refused. Traces are JSON lines under `traces/`, not parquet, and the server holds no task state.

Process.put(:gen_domain_lib, true)
Code.require_file("tools/gen_domain.exs", __DIR__)

defmodule Persona do
  def plan_exe, do: Path.expand(System.get_env("PERSONA_PLAN", "../persona/.lake/build/bin/persona_plan"))

  def knowledge, do: File.read!("frontier/knowledge.json") |> JSON.decode!()

  def plan(problem) do
    path = "problems/.request-#{System.unique_integer([:positive])}.jsonld"
    File.write!(path, JSON.encode!(problem))
    t0 = System.monotonic_time(:millisecond)
    {out, code} = System.cmd(plan_exe(), ["domains/character-stack.jsonld", path], stderr_to_stdout: true)
    File.rm(path)
    ms = System.monotonic_time(:millisecond) - t0
    case {code, JSON.decode(out)} do
      {0, {:ok, plan}} -> {plan, ms}
      _ -> {%{"refused" => "bad_problem", "stderr" => String.slice(out, 0, 400)}, ms}
    end
  end

  def subjects(k), do: k["subjects"] || %{"character" => %{"stages" => Map.keys(k["stages"])}}

  # A goal is `reach-<subject>-N`, `<subject> N`, `<subject>` (its last stage), a stage number
  # or stage name (the character's), or empty (the character's stage 10). Subjects are the
  # knowledge file's: character, prop, world.
  def goal_of(text) do
    k = knowledge()
    subs = subjects(k)
    t = text |> String.trim() |> String.downcase()
    stage_of = fn w ->
      cond do
        Map.has_key?(k["stages"], w) -> w
        true -> case Enum.find(k["stages"], fn {_, s} -> s["name"] == w end), do: ({n, _} -> n; nil -> nil)
      end
    end
    {subj, rest} =
      case Regex.run(~r/^(?:reach-)?(\w+)[- ](.+)$/, t) do
        [_, a, b] when is_map_key(subs, a) -> {a, b}
        _ -> if Map.has_key?(subs, t), do: {t, ""}, else: {"character", t}
      end
    n = if rest == "", do: List.last(subs[subj]["stages"]), else: stage_of.(String.replace_prefix(rest, "stage-", "") |> String.replace_prefix("stage ", ""))
    if n != nil and n in subs[subj]["stages"], do: {:ok, subj, n}, else: :undeclared
  end

  def answer(text) do
    case goal_of(text) do
      :undeclared -> {%{"refused" => "undeclared_goal"}, 0}
      {:ok, subj, n} -> plan(Gen.problem(knowledge(), "request", [], [], "reach-#{subj}-#{n}"))
    end
  end
end

defmodule Frontier do
  # A level is a task template: the goal stage and how many stages already hold.
  # A problem is one instance of it. Level search (frontier learning) practices the
  # levels at the edge of competence: attempted and not always reached, or never
  # attempted but adjacent to a reached level.
  @traces "traces/experience.jsonl"

  def traces, do: if(File.exists?(@traces), do: File.stream!(@traces) |> Enum.map(&JSON.decode!/1), else: [])

  def record(t), do: File.write!(@traces, JSON.encode!(Map.put(t, "at", DateTime.to_iso8601(DateTime.utc_now()))) <> "\n", [:append])

  # A level is (subject, goal position, held prefix) over that subject's own stage list.
  def levels do
    k = Persona.knowledge()
    stats = traces() |> Enum.filter(&(&1["kind"] == "practice")) |> Enum.group_by(&{&1["subject"], &1["goal"], &1["held"]})
    for {subj, sd} <- Persona.subjects(k), g <- 1..length(sd["stages"]), h <- 0..(g - 1) do
      ts = Map.get(stats, {subj, g, h}, [])
      %{"subject" => subj, "goal" => g, "held" => h, "attempts" => length(ts), "reached" => Enum.count(ts, & &1["reached"])}
    end
  end

  def next_level do
    ls = levels()
    reached = MapSet.new(ls |> Enum.filter(&(&1["reached"] > 0)) |> Enum.map(&{&1["subject"], &1["goal"], &1["held"]}))
    edge = Enum.filter(ls, fn l ->
      (l["attempts"] > 0 and l["reached"] < l["attempts"]) or
        (l["attempts"] == 0 and (MapSet.member?(reached, {l["subject"], l["goal"] - 1, l["held"]}) or MapSet.member?(reached, {l["subject"], l["goal"], l["held"] - 1}) or l["goal"] == 1))
    end)
    Enum.min_by(edge, &{&1["attempts"], &1["goal"], -&1["held"], &1["subject"]}, fn -> nil end)
  end

  def practice do
    case next_level() do
      nil -> %{"done" => true}
      l ->
        k = Persona.knowledge()
        subj = l["subject"]
        list = Persona.subjects(k)[subj]["stages"]
        held_n = Enum.take(list, l["held"])
        held = Enum.map(held_n, &"#{subj}-#{&1}")
        goal_n = Enum.at(list, l["goal"] - 1)
        # tokens of held stages are held; the rest are drawn at random, so the plan must acquire them
        tokens = k["stages"] |> Enum.filter(fn {n, _} -> n in held_n end) |> Enum.flat_map(fn {_, s} -> s["tokens"] end)
        extra = k["stages"] |> Enum.flat_map(fn {_, s} -> s["tokens"] end) |> Enum.filter(fn _ -> :rand.uniform() < 0.3 end)
        {plan, ms} = Persona.plan(Gen.problem(k, "practice", held, Enum.uniq(tokens ++ extra), "reach-#{subj}-#{goal_n}"))
        steps = plan["steps"] || []
        t = %{"kind" => "practice", "subject" => subj, "goal" => l["goal"], "held" => l["held"], "reached" => plan["reached"] == true,
              "refused" => plan["refused"], "steps" => length(steps), "ms" => ms,
              "settled" => steps |> Enum.map(& &1["action"]) |> Enum.filter(&String.starts_with?(&1, "settle-"))}
        record(t)
        t
    end
  end

  # An experience report from a stage that ran for real: which stages held before, which action
  # ran, whether it settled its stage, and how long it took (ISO 8601 duration).
  def experience(%{"action" => "settle-" <> rest, "held_before" => hb, "settled" => s} = r) when is_list(hb) and is_boolean(s) do
    {subj, n} = case String.split(rest, "-", parts: 2), do: ([a, b] -> {a, b}; [b] -> {"character", b})
    t = %{"kind" => "experience", "subject" => subj, "stage" => n, "held_before" => Enum.map(hb, &to_string/1), "settled" => s, "duration" => r["duration"]}
    record(t)
    %{"recorded" => t}
  end
  def experience(_), do: %{"refused" => "bad_experience"}

  # Learning folds experience into knowledge and lands a new domain revision only when the
  # gate holds: the cold gold plan still reaches stage 10 (positive control) and a domain
  # with one requirement removed yields a different plan (negative control).
  def learn do
    k = Persona.knowledge()
    ex = traces() |> Enum.filter(&(&1["kind"] == "experience"))
    k2 = Enum.reduce(ex, k, fn e, acc ->
      n = e["stage"]
      acc = if e["duration"], do: put_in(acc, ["durations", n], e["duration"]), else: acc
      # a stage that settled only when stage X held, across every report, requires X
      reports = Enum.filter(ex, &(&1["stage"] == n))
      ok = Enum.filter(reports, & &1["settled"]); bad = Enum.reject(reports, & &1["settled"])
      if ok != [] and bad != [] do
        # a held stage is reported as "<subject>-N" or "N"; the requirement learned is the stage N
        bare = fn hb -> MapSet.new(hb, &String.replace(&1, ~r/^[a-z]+-/, "")) end
        always = ok |> Enum.map(&bare.(&1["held_before"])) |> Enum.reduce(&MapSet.intersection/2)
        never = bad |> Enum.map(&bare.(&1["held_before"])) |> Enum.reduce(&MapSet.union/2)
        learned = MapSet.difference(always, never) |> MapSet.delete(n) |> Enum.filter(&Map.has_key?(acc["stages"], &1))
        acc |> update_in(["stages", n, "requires"], &Enum.uniq(&1 ++ learned)) |> update_in(["learned", n], &Enum.uniq((&1 || []) ++ learned))
      else
        acc
      end
    end)
    k2 = Map.put(k2, "revision", k["revision"] + 1)
    File.write!("domains/.candidate.jsonld", JSON.encode!(Gen.domain(k2)))
    gate = gate("domains/.candidate.jsonld", k2)
    if gate["pass"] do
      File.write!("frontier/knowledge.json", JSON.encode!(k2))
      File.rename!("domains/.candidate.jsonld", "domains/character-stack.jsonld")
      File.write!("plans/character-stack-cold.jsonld", JSON.encode!(gate["gold"]))
    else
      File.rm("domains/.candidate.jsonld")
    end
    %{"revision" => (if gate["pass"], do: k2["revision"], else: k["revision"]), "gate" => Map.delete(gate, "gold"),
      "requires" => Map.new(k2["stages"], fn {n, s} -> {n, s["requires"]} end), "durations" => k2["durations"]}
  end

  def gate(domain_path, k) do
    plan = Persona.plan_exe()
    run = fn d, p -> {out, _} = System.cmd(plan, [d, p], stderr_to_stdout: true); JSON.decode(out) end
    File.write!("problems/.gate.jsonld", JSON.encode!(Gen.problem(k, "gate", [], [], "reach-character-10")))
    {:ok, gold} = run.(domain_path, "problems/.gate.jsonld")
    positive = gold["reached"] == true and Enum.count(gold["steps"], &String.starts_with?(&1["action"], "settle-")) == length(Persona.subjects(k)["character"]["stages"])
    # planted fault: stage 10 forgets every requirement, so its plan must shrink
    broken = update_in(k, ["stages", "10", "requires"], fn _ -> [] end)
    File.write!("domains/.broken.jsonld", JSON.encode!(Gen.domain(broken)))
    {:ok, bad} = run.("domains/.broken.jsonld", "problems/.gate.jsonld")
    negative = bad["steps"] != gold["steps"]
    Enum.each(["problems/.gate.jsonld", "domains/.broken.jsonld"], &File.rm/1)
    %{"pass" => positive and negative, "positive" => positive, "negative" => negative, "gold" => gold}
  end
end

defmodule Web do
  def card(url) do
    %{"name" => "persona-frontier", "version" => "0.1.0", "url" => url, "protocolVersion" => "1.0",
      "description" => "Answers from a planning domain, not a neural network, and improves that domain from experience: a stage goal goes in, the exact plan comes out, and the frontier loop practises the levels at the edge of what the domain reaches.",
      "capabilities" => %{"streaming" => false, "pushNotifications" => false},
      "defaultInputModes" => ["text/plain"], "defaultOutputModes" => ["application/json"],
      "skills" => [%{"id" => "plan", "name" => "Plan to a stage", "tags" => ["planning", "taskweft", "frontier"],
                     "description" => "Send a goal as text: reach-<subject>-N (subjects: character, prop, world), a subject alone for its last stage, a stage name alone for the character, or empty.", "examples" => ["reach-character-10", "world", "prop 7", "garments"]}]}
  end

  def rpc(body) do
    case JSON.decode(body) do
      {:ok, %{"method" => m, "id" => id, "params" => %{"message" => %{"parts" => parts}}}} when m in ["message/send", "SendMessage"] ->
        case Enum.find_value(parts, & &1["text"]) do
          nil -> err(id, -32602, "message has no text part")
          text ->
            {ans, ms} = Persona.answer(text)
            Frontier.record(%{"kind" => "request", "text" => text, "reached" => ans["reached"] == true, "refused" => ans["refused"], "ms" => ms})
            %{"jsonrpc" => "2.0", "id" => id, "result" => %{"message" => %{"messageId" => "a2a-#{id}", "role" => "ROLE_AGENT", "parts" => [%{"text" => JSON.encode!(ans)}]}}}
        end
      {:ok, %{"method" => m, "id" => id}} when m in ["GetTask", "CancelTask", "tasks/get", "tasks/cancel"] -> err(id, -32001, "the persona keeps no task")
      {:ok, %{"method" => m, "id" => id}} when m in ["SendStreamingMessage", "SubscribeToTask", "message/stream"] -> err(id, -32004, "nothing to stream")
      {:ok, %{"id" => id}} -> err(id, -32601, "method not found")
      _ -> err(nil, -32700, "parse error")
    end
  end

  defp err(id, code, msg), do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => msg}}

  def route("GET", "/.well-known/agent-card.json", _, url), do: {200, card(url)}
  def route("POST", "/", body, _), do: {200, rpc(body)}
  def route("GET", "/frontier", _, _), do: {200, %{"levels" => Frontier.levels(), "next" => Frontier.next_level(), "revision" => Persona.knowledge()["revision"]}}
  def route("POST", "/practice", _, _), do: {200, Frontier.practice()}
  def route("POST", "/experience", body, _), do: {200, (case JSON.decode(body), do: ({:ok, r} -> Frontier.experience(r); _ -> %{"refused" => "bad_experience"}))}
  def route("POST", "/learn", _, _), do: {200, Frontier.learn()}
  def route(_, _, _, _), do: {404, %{"error" => "not found"}}

  def serve(port) do
    {:ok, l} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    IO.puts("persona-frontier on http://127.0.0.1:#{port} (HTTP/1.1)")
    loop(l, "http://127.0.0.1:#{port}/")
  end

  defp loop(l, url) do
    {:ok, s} = :gen_tcp.accept(l)
    spawn(fn -> handle(s, url) end)
    loop(l, url)
  end

  defp handle(s, url) do
    with {:ok, req} <- read(s, "") do
      [head, body] = String.split(req, "\r\n\r\n", parts: 2)
      [line | hs] = String.split(head, "\r\n")
      [meth, path | _] = String.split(line, " ")
      len = hs |> Enum.find_value(0, fn h -> case String.split(String.downcase(h), ":", parts: 2) do ["content-length", v] -> String.to_integer(String.trim(v)); _ -> nil end end)
      body = read_body(s, body, len)
      {code, json} = try do route(meth, path, body, url) rescue e -> {500, %{"error" => Exception.message(e)}} end
      out = JSON.encode!(json)
      :gen_tcp.send(s, "HTTP/1.1 #{code} #{if code == 200, do: "OK", else: "Error"}\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(out)}\r\nConnection: close\r\n\r\n#{out}")
    end
    :gen_tcp.close(s)
  end

  defp read(s, acc) do
    if String.contains?(acc, "\r\n\r\n"), do: {:ok, acc}, else: (case :gen_tcp.recv(s, 0, 5000), do: ({:ok, d} -> read(s, acc <> d); e -> e))
  end
  defp read_body(_s, body, len) when byte_size(body) >= len, do: body
  defp read_body(s, body, len), do: (case :gen_tcp.recv(s, len - byte_size(body), 5000), do: ({:ok, d} -> body <> d; _ -> body))
end

File.cd!(__DIR__)
port = case System.argv(), do: (["--port", p] -> String.to_integer(p); _ -> 9920)
if not File.exists?("domains/character-stack.jsonld"), do: File.write!("domains/character-stack.jsonld", JSON.encode!(Gen.domain(Persona.knowledge())))
Web.serve(port)
