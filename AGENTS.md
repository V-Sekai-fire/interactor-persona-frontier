# Agent rules

The standing rules of the Chibifire Hair Cards project are in the viewer repository's `AGENTS.md` ("Every repository" and "Work flow") with their reasons in its `docs/rules.md`: https://github.com/V-Sekai-fire/interactor-hair-cards-viewer (local `/mnt/fire/3-interactor/interactor-hair-cards-viewer`). The workspace `AGENTS.md` of the manuals checkout binds too. In short: comments at most 3% of code lines; per-function branching at most 1.5 mean and 4 peak; a README is one 280-character blurb; scripts are Elixir or engine GDScript; read a LICENSE before using a model; every service has an AsyncAPI document; ENet is blocklisted; commits are authored as the owner with no agent credit and no trailing period; work lands on `dev/` branches that the viewer repository's `tools/automerge.exs` merges to main.

## This repository

- The planner. Compose methods from the actions that exist first; a new action only when no composition reaches the goal; a refused goal names the smallest set of missing actions.
- Checks: `nix flake check -L`, which builds the planner, runs the witness and runs the NixOS test with FoundationDB. CI runs the same command. The planner replay (`elixir /mnt/fire/3-interactor/interactor-hair-cards-viewer/tools/serve.exs replay`) is the second check. Run the planner from the repository root with `FRONTIER_DB` set, and never call `/learn` or `/practice`: they write into the repository.
