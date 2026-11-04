# The persona as an A2A webserver that improves its own domain from experience.
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

  # A goal is `reach-stage-N`, `stage N`, `N`, a stage name, or empty (stage 10).
  def goal_of(text) do
    k = knowledge()
    t = text |> String.trim() |> String.downcase()
    cond do
      t == "" -> {:ok, "10"}
      Map.has_key?(k["stages"], t) -> {:ok, t}
      m = Regex.run(~r/^(?:reach-)?stage[- ]?(\d+)$/, t) -> if Map.has_key?(k["stages"], Enum.at(m, 1)), do: {:ok, Enum.at(m, 1)}, else: :undeclared
      true ->
        case Enum.find(k["stages"], fn {_, s} -> s["name"] == t end) do
          {n, _} -> {:ok, n}
          nil -> :undeclared
        end
    end
  end

  def answer(text) do
    case goal_of(text) do
      :undeclared -> {%{"refused" => "undeclared_goal"}, 0}
      {:ok, n} -> plan(Gen.problem(knowledge(), "request", [], [], "reach-stage-#{n}"))
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

  def levels do
    k = Persona.knowledge()
    n = map_size(k["stages"])
    stats = traces() |> Enum.filter(&(&1["kind"] == "practice")) |> Enum.group_by(&{&1["goal"], &1["held"]})
    for g <- 1..n, h <- 0..(g - 1) do
      ts = Map.get(stats, {g, h}, [])
      reached = Enum.count(ts, & &1["reached"])
      %{"goal" => g, "held" => h, "attempts" => length(ts), "reached" => reached}
    end
  end

  def next_level do
    ls = levels()
    reached = MapSet.new(ls |> Enum.filter(&(&1["reached"] > 0)) |> Enum.map(&{&1["goal"], &1["held"]}))
    edge = Enum.filter(ls, fn l ->
      (l["attempts"] > 0 and l["reached"] < l["attempts"]) or
        (l["attempts"] == 0 and (MapSet.member?(reached, {l["goal"] - 1, l["held"]}) or MapSet.member?(reached, {l["goal"], l["held"] - 1}) or l["goal"] == 1))
    end)
    Enum.min_by(edge, &{&1["attempts"], &1["goal"], -&1["held"]}, fn -> nil end)
  end

  def practice do
    case next_level() do
      nil -> %{"done" => true}
      l ->
        k = Persona.knowledge()
        held = Enum.map(1..l["held"]//1, &Integer.to_string/1)
        # tokens of held stages are held; the rest are drawn at random, so the plan must acquire them
        tokens = k["stages"] |> Enum.filter(fn {n, _} -> n in held end) |> Enum.flat_map(fn {_, s} -> s["tokens"] end)
        extra = k["stages"] |> Enum.flat_map(fn {_, s} -> s["tokens"] end) |> Enum.filter(fn _ -> :rand.uniform() < 0.3 end)
        {plan, ms} = Persona.plan(Gen.problem(k, "practice", held, Enum.uniq(tokens ++ extra), "reach-stage-#{l["goal"]}"))
        steps = plan["steps"] || []
        t = %{"kind" => "practice", "goal" => l["goal"], "held" => l["held"], "reached" => plan["reached"] == true,
              "refused" => plan["refused"], "steps" => length(steps), "ms" => ms,
              "settled" => steps |> Enum.map(& &1["action"]) |> Enum.filter(&String.starts_with?(&1, "settle-"))}
        record(t)
        t
    end
  end

  # An experience report from a stage that ran for real: which stages held before, which action
  # ran, whether it settled its stage, and how long it took (ISO 8601 duration).
  def experience(%{"action" => "settle-" <> n, "held_before" => hb, "settled" => s} = r) when is_list(hb) and is_boolean(s) do
    t = %{"kind" => "experience", "stage" => n, "held_before" => Enum.map(hb, &to_string/1), "settled" => s, "duration" => r["duration"]}
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
        always = ok |> Enum.map(&MapSet.new(&1["held_before"])) |> Enum.reduce(&MapSet.intersection/2)
        never = bad |> Enum.map(&MapSet.new(&1["held_before"])) |> Enum.reduce(&MapSet.union/2)
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
    File.write!("problems/.gate.jsonld", JSON.encode!(Gen.problem(k, "gate", [], [], "reach-stage-10")))
    {:ok, gold} = run.(domain_path, "problems/.gate.jsonld")
    positive = gold["reached"] == true and Enum.count(gold["steps"], &String.starts_with?(&1["action"], "settle-")) == map_size(k["stages"])
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
                     "description" => "Send a stage goal as text: reach-stage-N, a stage name, or empty for stage 10.", "examples" => ["reach-stage-10", "garments"]}]}
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
