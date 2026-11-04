# interactor-persona-frontier

Can a persona that answers from a planning domain learn the domain itself?

## What it is for

Every capability the persona has is one somebody authored as an action, so it plateaus where the authoring stops. This repository keeps the planner as the fixed meta-method and lets the domain's content (which stage requires which, how long each takes) come from experience reports and frontier practice, landing only through a gate with a positive and a negative control. The domain is the ten-stage look-dev to character-persona pipeline, and props and worlds run their own subsets of it, GPU-skinned like the characters (Alan Wake 2's vegetation recipe, GDC Vault 1034310). The routes, the gate, the measurements and the limits are documented at the top of `server.exs`; `docs/stack.md` grades the stages and `docs/repo-inventory.md` holds the repository survey.

## Build and run

```
git clone https://github.com/V-Sekai-fire/interactor-taskweft-persona ../persona
(cd ../persona && lake build persona_plan)
elixir tools/gen_domain.exs
elixir server.exs --port 9920
```

```
curl -s -X POST localhost:9920/ -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"kind":"text","text":"garments"}]}}}'
curl -s -X POST localhost:9920/ -d '{"jsonrpc":"2.0","id":2,"method":"message/send","params":{"message":{"role":"user","parts":[{"text":"world"}]}}}'
curl -s -X POST localhost:9920/practice
curl -s -X POST localhost:9920/experience -d '{"action":"settle-7","held_before":["1","2","3","4"],"settled":false}'
curl -s -X POST localhost:9920/experience -d '{"action":"settle-7","held_before":["1","2","3","4","5"],"settled":true,"duration":"PT4H"}'
curl -s -X POST localhost:9920/learn
```

Run those six calls, then read `frontier/knowledge.json` to see what the domain learned.

## Licence

MIT
