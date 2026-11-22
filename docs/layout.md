# Layout and where things live

What the README leaves out because it changes: file names, deployment and costs. Edit this file, not the README.

## What a goal is

The things it makes are `character`, `prop` and `world`; a goal is one of those words, or one with a stage after it (`prop gpu-motion`, `character garments`, `reach-character-runtime`; the old numbers, `prop 7` and `reach-character-10`, still answer) to stop early. The answer is the exact ordered list of what to do: which stages to settle, in what order, from which repositories, with the durations measured so far. A goal the pipeline does not have is refused by name. Props and worlds run their own subsets of the stages, GPU-skinned like the characters.

## How it learns

The plan comes from a planning domain of the pipeline, not from a language model, so it is the same every time and it is checkable. Report what a real stage run did and the domain learns from it, a requirement it was missing or a duration it had wrong, each landing only through a gate with a positive and a negative control. The authored data is the numbered YAML-LD seed files in `seeds/` (applied once each, like database migrations; a change is a new seed), and what it learns is kept in the store only.

## The repository

- `entities/` is the pure core and its spec, `repositories/` the store port, `datasources/` the C under it, `transports/` the HTTP server, `deploy/` the box.
- The routes and the store are documented at the top of `transports/Main.lean`. In Elixir, `Frontier.plan/2` answers in-process through leanler, with no node and no port.
- `.github/workflows/flake.yml` runs `nix flake check`: the package with its witness, and the NixOS test with FoundationDB and the HTTP checks.
- `deploy/cloud-init.yaml` builds that box as DigitalOcean's `s-1vcpu-2gb` droplet ($12.00/mo); the challenge's thresholds (p95 < 500 ms, p99 < 1 s, < 1 % failed) are the load target.
- `deploy/weights.exs` is every weight in one place, preloaded by hash so a 4090 box runs offline.
- `docs/` holds the grading of the stages, the repository survey, the token ledger (`docs/tokens.exs`, run it), the judge probe, the serving strategy (`docs/serving.md`) and the one-release plan (`docs/release.md`).
