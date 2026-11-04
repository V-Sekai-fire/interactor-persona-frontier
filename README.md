# interactor-persona-frontier

Which stage of your character, prop or world comes next, and what does it need first?

## What it is for

A look-dev pipeline of ten stages, three subjects and dozens of repositories has no one place that says what to run next, so each run is a guess.

Ask for a goal (`world`, `prop 7`, `garments`, `reach-character-10`) and the answer is the exact ordered plan to it: which stages to settle, in what order, from which repositories, with the durations measured so far; a goal the pipeline does not have is refused by name. The plan comes from a planning domain of the pipeline, not from a language model, so it is the same every time and it is checkable. Report what a real stage run did and the domain learns from it: a requirement it was missing, a duration it had wrong, each landing only through a gate with a positive and a negative control. Props and worlds run their own subsets of the stages, GPU-skinned like the characters. The routes, the gate, the measurements and the limits are documented at the top of `server.exs`; the grading of the stages and the repository survey sit in `docs/`.

## Build and run

```
git clone https://github.com/V-Sekai-fire/interactor-taskweft-persona ../persona
(cd ../persona && lake build persona_plan)
elixir tools/gen_domain.exs
elixir server.exs --port 9920
```

```
curl -s -X POST localhost:9920/ -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"text":"world"}]}}}'
curl -s -X POST localhost:9920/experience -d '{"action":"settle-world-7","held_before":["world-1","world-2","world-4","world-6"],"settled":true,"duration":"PT2H"}'
curl -s -X POST localhost:9920/learn
```

Ask for your own goal, then report one real stage run and read `frontier/knowledge.json` to see what changed.

## Licence

MIT
