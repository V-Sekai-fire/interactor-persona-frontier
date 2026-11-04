# interactor-persona-frontier

Can a persona that answers from a planning domain learn the domain itself?

## What it is for

Every capability the persona has is one somebody authored as an action, so it plateaus where the authoring stops.

The planner stays the fixed meta-method; the domain's content, which stage requires which and how long each takes, comes from experience reports and frontier practice and lands only through a gate with a positive and a negative control. The domain is the look-dev pipeline for characters, props and worlds, all GPU-skinned. The routes, the gate, the measurements and the limits are documented at the top of `server.exs`; the grading of the stages and the repository survey sit in `docs/`.

## Build and run

```
git clone https://github.com/V-Sekai-fire/interactor-taskweft-persona ../persona
(cd ../persona && lake build persona_plan)
elixir tools/gen_domain.exs
elixir server.exs --port 9920
```

```
curl -s -X POST localhost:9920/ -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"text":"world"}]}}}'
curl -s -X POST localhost:9920/practice
curl -s -X POST localhost:9920/experience -d '{"action":"settle-world-7","held_before":["world-1","world-2","world-4","world-6"],"settled":true,"duration":"PT2H"}'
curl -s -X POST localhost:9920/learn
```

Run those four calls, then read `frontier/knowledge.json` to see what the domain learned.

## Licence

MIT
