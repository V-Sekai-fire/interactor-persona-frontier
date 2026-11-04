# interactor-persona-frontier

Which stage of your character, prop or world comes next, and what does it need first?

## What it is for

A look-dev pipeline of ten stages, three subjects and dozens of repositories has no one place that says what to run next, so each run is a guess.

Ask for a goal (`world`, `prop 7`, `garments`, `reach-character-10`) and the answer is the exact ordered plan to it: which stages to settle, in what order, from which repositories, with the durations measured so far; a goal the pipeline does not have is refused by name. The plan comes from a planning domain of the pipeline, not from a language model, so it is the same every time and it is checkable. Report what a real stage run did and the domain learns from it: a requirement it was missing, a duration it had wrong, each landing only through a gate with a positive and a negative control. Props and worlds run their own subsets of the stages, GPU-skinned like the characters. The routes, the gate, the measurements and the limits are documented at the top of `server.exs`. The grading of the stages and the repository survey sit in `docs/`.

Start the server (the header of `server.exs` has the four commands), ask for your own goal, then report one real stage run and read `frontier/knowledge.json` to see what changed.

## Licence

MIT
