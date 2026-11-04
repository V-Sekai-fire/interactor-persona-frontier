# interactor-persona-frontier

The persona as an A2A webserver that learns its planning domain from experience: a stage goal in, an exact plan out, the frontier practised.

## What it is for

`interactor-taskweft-persona` answers from a planning domain instead of a neural network, and every capability it has is one somebody authored as an action. This server closes that gap the way the Bitter Lesson asks: the planner stays the fixed meta-method, and the domain's content (which stage requires which, how long each takes) is induced from experience reports and from frontier practice, landing only through a gate with a positive and a negative control. The IEC 60848 GRAFCET persona controllers of `interactor-taskweft-nmm-personas` are retired in favour of this loop; only their MaskScore traces survive, as experience. The domain is the ten-stage look-dev to character-persona pipeline; `docs/stack.md` grades the stages and `docs/repo-inventory.md` holds the repository survey.

Three pieces:

- `frontier/knowledge.json`, the learned content: per stage its requirements, the repositories it draws on (tokens) and a measured duration. `learned` names the requirements experience added, apart from the authored ones.
- `tools/gen_domain.exs`, the fixed meta-method: knowledge in, a RECTGTN JSON-LD domain in the engine shape out (`settle-N` actions, `acquire-token-R` actions, `reach-stage-N` methods with a `held` alternative first).
- `server.exs`, the HTTP/1.1 A2A peer and the frontier loop, over `:gen_tcp` with no dependencies. Plans come from the persona repository's `persona_plan`, byte for byte.

| Route | Answer |
| --- | --- |
| `GET /.well-known/agent-card.json` | the Agent Card |
| `POST /` with `message/send` | the plan to the goal in the text part (`reach-stage-N`, a stage name, or empty for stage 10), or `{"refused":"undeclared_goal"}` |
| `GET /frontier` | the 55 levels (goal stage × stages already held), attempts and reaches, and the next level to practise |
| `POST /practice` | one frontier cycle: pick the least-attempted level at the edge of competence, instantiate a problem with the held stages' repositories acquired and 30 % of the rest, plan it, record the trace |
| `POST /experience` | a report from a real stage run: `{"action":"settle-7","held_before":["1","2","3","4","5"],"settled":true,"duration":"PT4H"}` |
| `POST /learn` | fold experience into knowledge: a stage that settled only when X held requires X; a reported duration becomes the action's; regenerate the domain; land it only if the gate holds |

The gate: the cold problem (nothing held, goal stage 10) still reaches with all ten `settle` steps (positive control), and a domain where stage 10 forgets its requirements yields a different plan (negative control). A revision that fails either is discarded and the knowledge file is untouched. Frontier learning follows the Alyx-planner hypothesis: weights frozen (here, none), the planner improves by iterating its RECTGTN elements, and level search picks the practice tasks.

## Build and run

```
git clone https://github.com/V-Sekai-fire/interactor-taskweft-persona ../persona
(cd ../persona && lake build persona_plan)
elixir tools/gen_domain.exs
elixir server.exs --port 9920
```

```
curl -s -X POST localhost:9920/ -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"kind":"text","text":"garments"}]}}}'
curl -s -X POST localhost:9920/practice
curl -s -X POST localhost:9920/experience -d '{"action":"settle-7","held_before":["1","2","3","4"],"settled":false}'
curl -s -X POST localhost:9920/experience -d '{"action":"settle-7","held_before":["1","2","3","4","5"],"settled":true,"duration":"PT4H"}'
curl -s -X POST localhost:9920/learn
```

`PERSONA_PLAN` overrides the planner path. Measured 2026-11-04 on osx-arm64: `lake build persona_plan` 12 s; a plan answers in about 35 ms; 55 practice cycles reach 55 of 55 levels on the authored domain; the two experience reports above make `/learn` land revision 1 with stage 7 requiring stage 5 and `PT4H`, after which the plan for `motion` settles garments first and totals `PT4H1M30S`. The committed knowledge is the authored revision 0; those reports were synthetic and did not land.

## What it does not do

Practice uses the domain as its own simulator, so on its own it measures reachability and plan length, not truth about the pipeline; truth enters only through `/experience` from a real stage run (a CI job of the owning repository is the intended reporter). No action is ever invented: a report that names an action the domain lacks is refused. Traces are JSON lines under `traces/`, not parquet, and the server holds no task state.

## Licence

MIT
