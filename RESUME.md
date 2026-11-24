# RESUME (interactor-persona-frontier, 2026-11-23)

What to do next. Background: `docs/party-saga.md`, `docs/solver-spec.md`, `docs/rectgtn.md`, and `AGENTS.md` for the rules.

## State
- Branch `dev/party-saga` (local, not pushed; pushing a `dev/` branch lets `tools/automerge.exs` merge it to main).
  The persona change is on `dev/graph-state-writes` in `interactor-taskweft-persona` (local, not pushed).
- Checks that pass: `lake build frontier_store frontier_packets`, `elixir tools/party_saga.exs check` (21 tests),
  `frontier_store fixtures entities` on a new database (11 checks).
- Deployed unit `party-saga-frontier` matches `deploy/`. Long jobs are named oneshot units.

## Turbo (GPU solver, outside this repository: `/mnt/fire/6-datasource/turbo-build`, notes in its `PARKED.md`)
- Works: `-arch barebones -timeout 30000` solves the control (objective 8) and Party Saga `t01` (objective 6), as Gecode and CP-SAT do.
- `-arch hybrid` and `-arch gpu` are compiled out in this branch. Use `-timeout`, not `-t`. Short timeouts give `UNKNOWN`
  because a solve has a fixed cost of 2.5 to 3.8 s even for 12 variables (not load: six runs at 48 to 95% GPU use; cause untested,
  suspects: the 97% device-heap limit at `barebones_dive_and_solve.hpp:578`, pinned memory). Small levels will not be fast.
- Next: add `turbo.gpu.release` as a fourth solver in `tools/party_saga.exs`, run `agree` and compare the frontier.
  Not measured yet: any Party Saga level above `t01`, and speed against CP-SAT.

## Plan from the owner
- Port Turbo to shader-slang (the repo has a `lean4-gpu-pipeline` route with `slangc`), and only then try a CPU Turbo from the same
  kernels. Until then Turbo's own `-arch cpu` is the only CPU mode (it passed both controls); it is a separate code path, not the port.

## Next step (Turbo to Slang)
Faithful copy of `pir.hpp` and the helpers it uses into `slang/`, all operators, before any trimming; see `docs/turbo-slang.md`
("Rule from the owner: copy first"). `slangc` is at `/mnt/fire/6-datasource/slang-2026.20/x/bin/slangc` (needs `LD_LIBRARY_PATH=<x>/lib`);
its C++ target rejects buffer atomics. `tools/party_saga.exs dump TRACK G SEED OUT.dzn` writes a generated level.

## Open
- Hugging Face: the owner asked for the weights and auxiliary files to be on `hf:chibifire`, enough to restart the experiments.
  Not done: `hf` is not logged in (`hf auth login` or `HF_TOKEN`), and which weights is not settled (the ternary student weights in
  `/mnt/fire/persona-stream/kimodo/ternary/out`, the Party Saga files, or both). Check what chibifire already holds before pushing.
- Backlog B1 to B9 is in the plan; B9 (pushing and merging) is the owner's own action.
- Unread sources: the original lazy clause generation papers, Shaw 1998, the Chu thesis, the Springer retrospective.
- 2026-11-24: slang/turbo/pir.slang copies pir.hpp; entry-point compile fails on recursion in den_fdiv/den_cdiv (E55201). Next: unroll to depth two, then run probe.slang on cpp against Turbo values.
- 2026-11-24: Turbo propagator now written in Lean with contract-lean-slang (turbo/Turbo/Pir.lean, lake build turbo_emit); ADD slice compiles on spirv/cpp/cuda. Next: port ask/deduce for the remaining operators, keep the den_* call tree small, compare against slang/turbo/pir.slang.
