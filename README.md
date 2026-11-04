# interactor-persona-frontier

Want a character?

## What it is for

You have a picture in your head and no idea where to begin.

Ask for the goal (`character`, or `world`, `prop 7`, `garments`, `reach-character-10`) and the answer is the exact ordered list of what to do: which stages to settle, in what order, from which repositories, with the durations measured so far. A goal the pipeline does not have is refused by name. The plan comes from a planning domain of the pipeline, not from a language model, so it is the same every time and it is checkable. Report what a real stage run did and the domain learns from it, a requirement it was missing or a duration it had wrong, each landing only through a gate with a positive and a negative control.

Run `elixir build.exs` once, ask for `character`, do the first step it names, report that run, and read `entities/knowledge/knowledge.json` to see what changed.

Props and worlds run their own subsets of the stages, GPU-skinned like the characters. The repository is laid out as a hexagon: `entities/` is the pure core and its spec, `repositories/` the store port, `datasources/` the C under it, `transports/` the HTTP server and the Erlang node, `deploy/` the box. The routes, the node and the store are documented at the top of `transports/Main.lean` and `transports/Frontier/Dist.lean`; `.github/workflows/node.yml` is the one-box run (FoundationDB, the store's VFS, the node, a PropCheck peer), `deploy/cloud-init.yaml` builds that box as DigitalOcean's `s-1vcpu-2gb` droplet ($12.00/mo) and the challenge's thresholds (p95 < 500 ms, p99 < 1 s, < 1 % failed) are the load target; the grading of the stages, the repository survey, the token ledger (`docs/tokens.exs`, run it), the judge probe, the serving strategy (`docs/serving.md`) and the one-release plan (`docs/release.md`) sit in `docs/`.

## Licence

MIT
