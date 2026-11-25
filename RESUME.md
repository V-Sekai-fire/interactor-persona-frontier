# RESUME (interactor-persona-frontier, parked 2026-11-25)

The Party Saga planner (RECTGTN in SQLite, `docs/party-saga.md`, `docs/solver-spec.md`, `AGENTS.md` for the rules) and, since this week, a port of Turbo's constraint solver to Slang. The running log with every number and every correction is `docs/turbo-slang.md`; read its sections from the newest.

## State
- `main` has everything: the solver (PR #13), the Byzantine cluster (#14), many blocks and one handoff rule (#15), the launch as a time budget (#17) and the launch derived from the 64 Hz frame and the duty (#18). No branch of this work is open. Nothing is deployed; the GPU runs happen on a machine with an NVIDIA card when it is free.
- **Parked on 2026-11-25.** The shared mission is now the fabric beta (RFD66606-2490, 2360, 2436): two people in one campus zone see each other's avatars. The solver port is not a step of its attack, so it waits, and none of it is abandoned. Resume it when the owner says so, or when the beta needs it: the nearest link is RFD66606-2436's frontier-learning runs (levels with planted defects, regret over the last eight runs), which this repository's frontier loop could schedule.

## On another computer
Machine-specific, not in git: an NVIDIA GPU and `nvcc` (this desk used `/mnt/fire/6-datasource/turbo-build/cuda/.pixi`), the Slang SDK (`tools/slang_vendor.exs` fetches it into `.slang/`), a MiniZinc 2.11 bundle (`MINIZINC_HOME`), Lean 4 through elan, Elixir, and the level files `/mnt/fire/6-datasource/turbo-runs/{scout,party,saga}.cp`, which you regenerate with `MiniZinc` to `.fzn` and then `frontier_frontend --dump LEVEL.fzn`. FoundationDB is only needed for the NixOS test (`nix flake check -L`). The shell on this desk is dash: scripts that use `pipefail` run with bash.

## What runs, and the numbers (equal to Turbo's counts on one block)
| level | Turbo | one GPU block | 64 blocks |
|---|---|---|---|
| scout | 629 nodes, 8 solutions, objective 511 | same | same optimum |
| party | 1,058,921 nodes, objective 795, 953 s | same counts, 616 s | 3.5 s |
| saga | 10,551 nodes, objective 1537, 113 s | same counts, 30 s | 13.2 s (16 blocks: 11.6 s) |
Pipeline with no Turbo code in it: `.mzn` compiled by MiniZinc's own library, `frontier_frontend --dump` (Lean: parse, ternarize, simplifier, byte-equal to Turbo's dump), the Slang kernel on the GPU, `frontier_frontend --solution` prints the MiniZinc solution. `tools/turbo_player.exs` runs it under the planner (`turbo_solve` domain) in free time.

## How to reproduce
- Build: `lake build frontier_frontend turbo_emit`; GPU kernel and host build themselves on first use (`tools/turbo_gpu.exs`, needs nvcc from `/mnt/fire/6-datasource/turbo-build/cuda/.pixi` and the Slang SDK in `.slang/`, fetched by `tools/slang_vendor.exs`).
- A level to a proof: `elixir tools/turbo_player.exs LEVEL.cp --engine gpu --duty 50 [--blocks 64] [--checkpoint FILE]` (`LEVEL.cp` from `frontier_frontend --dump LEVEL.fzn`; the numbers above are from `/mnt/fire/6-datasource/turbo-runs/{scout,party,saga}.cp`).
- Many blocks are right: `elixir tools/turbo_blocks_check.exs` (50 generated worlds on 1, 8 and 64 blocks, local, needs the GPU).
- The front end is right: `elixir tools/frontend_check.exs LEVEL FILE.fzn ORACLE.cp` against Turbo's oracle (`slang/turbo/oracle/cp_dump.cpp`).
- The cluster: `elixir tools/cluster_replay.exs`, `elixir tools/cluster_test.exs run clean|liar|flaky|noquorum HOST GUEST` (on `dev/cluster-byzantine`), and the `cluster` workflow (scout only).
- Profile: `TURBO_EVENTS=FILE` on the player or the cluster, then `elixir tools/turbo_profile.exs FILE`.
- Checks that must stay green: `reuse lint`, `elixir tools/party_saga.exs check` (21 tests), the `flake`, `prek` and `cluster` workflows.

## What bounds a slice
One GPU launch at the default 64 blocks takes about 10 ms; the player's slice is 500 launches (about 5 s of launch time at duty 50) and the planner decides once per slice (about 120 ms, 9.3 percent). The CPU host keeps 64 Hz frames by instruction windows inside one process (worst window 2.83 ms against a 2 ms target). Against the solvers bundled with MiniZinc this solver is roughly on par (party 3.5 s against Chuffed 1.3 s and Gecode 91 s; saga 13.2 s against 15.9 s and 11.2 s), see `docs/turbo-slang.md`.

## Rules that decide how things are done here
Mission first. Constant work: one code path, special cases as data, no modes. No delays: queues and state machines (`gen_statem`). CI runs the smallest level only; GPU and multi-machine tests are local. Long jobs are systemd units; the machine also runs the owner's game, so one niced thread and the GPU only when it is free.

## Open, in order
1. The edge of this solver on the frontier ladder (`elixir tools/party_saga.exs edge turbo-slang`), set against CP-SAT's table in `docs/party-saga.md`; then whether clause learning or more blocks is the lever. Missing options in the table of `docs/turbo-slang.md`: `-a`, `-n`, `-i`, `-eps_var_order`, `-f`; the global-constraint predicates are not read yet.
2. An on-disk checkpoint of the CPU guest (`turbo_host` keeps the guest between 64 Hz windows in one process only; the GPU host has `save` and `load`, verified on many blocks).
3. A resident planner (the `frontier` service would have to take the `turbo_solve` problem over A2A).
Parked: bounds backed by a checked solution in the replicated cluster, coordinator replication, joining by tokens and bonds; the viewer's planner replay difference for `character` and `world`; the SPDX-header reading (the owner can overrule).
