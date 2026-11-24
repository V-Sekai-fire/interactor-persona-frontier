# Turbo in shader-slang (plan and findings)

Goal (owner, 2026-11-24): port Turbo's solver core to shader-slang, then try a CPU Turbo. The plan is in `RESUME.md`; phases P0 to P4 below.
Turbo is Apache-2.0 (github.com/ptal/turbo, branch aaai2026).

## Toolchain (P1)
- Slang v2026.20 (2026-10-17), `slang-2026.20-linux-x86_64.tar.gz` from github.com/shader-slang/slang/releases, unpacked without root in
  `/mnt/fire/6-datasource/slang-2026.20/x`; run with `LD_LIBRARY_PATH=<x>/lib`. Its `LICENSE` reads `Apache-2.0 WITH LLVM-exception`
  (the GitHub API reports `NOASSERTION`; the file was read). `slangc -version` prints `2026.20`.
- `slang/hello/` holds a hello kernel (`x = y + z` over interval bounds, one thread per constraint).

## What compiled (measured)
| kernel | `-target cuda` | `-target spirv` | `-target cpp` |
|---|---|---|---|
| `propagate_atomic.slang` (`InterlockedMax`, `InterlockedMin`, `InterlockedAdd` on buffers) | yes | yes | **error E36107**: `InterlockedMax` is not available in the compute stage for the cpp target |
| `propagate_plain.slang` (plain writes) | not tried | not tried | yes (3,542 bytes of C++) |

Not run yet: none of the generated code was executed, only compiled; `host-callable` also fails on the atomic kernel with the same error.

## Consequence for the design
A CPU kernel must not rely on buffer atomics. Write the fixpoint so each variable's bounds are written by one thread (a gather per
variable, or one pass per constraint class) or keep the CPU loop single-writer, and keep a separate atomic path for CUDA. This is a
risk to the plan's "one source for CPU and GPU": the claim holds only for the non-atomic subset.

## Rule from the owner (2026-11-24): copy first
Copy Turbo's code faithfully into Slang before changing anything. Do not decide what is foundational: keep every operator (`ADD`, `MUL`,
`MIN`, `MAX`, `EQ`, `LEQ`, `TDIV`, `CDIV`, `FDIV`, `EDIV`, `EMOD`, with their `ask` and `deduce` rules and the interval helpers
`num_*`, `den_*`, `itv_div`), keep names and structure, and trim only afterwards, with tests. My first attempt wrote simplified rules
of my own (division left out because Party Saga's flattened constraints did not use it); that file is not in the repository.

Source to copy, in order: `lala_pc-src/include/lala/pir.hpp` (957 lines; `ask` at 418, `itv_div` at 451, `num_*` at 471, `den_*` at 522,
`deduce(bytecode)` at 723), then the arithmetic and interval types it uses from `lala_core-src` (`fdiv`, `cdiv`, `emod`, `Interval`, `join`, `meet`)
and `cuda_battery-src`. Under `/mnt/fire/6-datasource/turbo-build/src/build/gpu-release/_deps/`. Read them with the Read tool, not through a filter.

## What Party Saga uses (P0, measured, for later trimming only)
Across 21 generated levels (up to 82,828 constraints): `int_le_reif` 245,497; `bool2int` 123,620; `int_times` 122,892; `array_bool_and` 121,961;
`int_lin_le` 40,250; `bool_clause` 3,682; `int_lin_le_reif` 3,220; `int_eq_reif` 679; `int_lin_eq` 343; element 140; the rest under 100 each.
No division, modulo or absolute value reaches the flattened model.

## Phases (status)
- P0 measure what Party Saga needs: constraint kinds measured (above); baseline times not yet.
- P1 toolchain gate: compile passed for CUDA and SPIR-V and for the CPU target without atomics; nothing executed.
- P2 format and kernel, P3 search and objective, P4 targets and numbers: not started.
## P2 copy of pir.hpp (2026-11-24): `slang/turbo/pir.slang`, `slang/turbo/probe.slang`
Copied: `ask`, `itv_div`, `num_fdiv/cdiv/tdiv/ediv`, `den_fdiv/cdiv/tdiv/ediv`, `mul_inv`, `deduce`, the battery `tdiv/fdiv/cdiv/ediv/emod`, `fjoin`, and an `Itv` with `meet`/`join`.
Compiles to `-target cpp` and `-target cuda` as a library; **does not compile with an entry point** (`probe.slang`) because of recursion:
- spirv and cuda: `error[E55201]: recursion not allowed` in `den_fdiv`, `den_cdiv` (they call themselves on split intervals).
- cpp: `error[E99997] ... unexpected: circularity during codegen`.
Recursion depth in the source is at most two levels (a split of `x`, then a split of `y`), so the next step is to unroll those calls into
fixed-depth copies, keeping each rule's text. That is the first departure from a literal copy and is forced by the compiler.
Departures so far: `deduce` writes into the three intervals with `meet` instead of calling `sub->embed` (the caller stores them); `ask` for
`MUL` spells `r2 == 0` as both bounds equal 0; values are `int`. Nothing here has been run, and none of it is tested against Turbo.
## Use contract-lean-slang (owner, 2026-11-24)
The propagator is written in Lean with https://github.com/V-Sekai-fire/contract-lean-slang (MIT, pinned in `lakefile.lean` at `01dbd39`) and
printed as Slang, not kept as hand-written `.slang`. `turbo/Turbo/Pir.lean` builds the `SlangShaderModule`; `lake build turbo_emit` then
`.lake/build/bin/turbo_emit` prints it. First slice: the division helpers, `Itv`, and `ADD` (`ask`, `deduce`); the emitted text compiles with
`slangc` for spirv, cpp and cuda. The dependency's `extern_lib` needs `slang.h` under its `vendor/`; its `vendor/fetch.sh` is not run by CI, so `elixir tools/slang_vendor.exs` (after `lake resolve-deps`) unpacks Slang 2026.20 into `.slang/` and links it there. `.github/workflows/node.yml` runs both before `lake build`.
Limits of the Lean AST met so far: no `switch` (use `if` chains), only `uint` literals (write `int(1u)`), no static members (use free functions), no macros.
## Recursion, unrolled in the hand-written copy (`slang/turbo/pir.slang`, `den_levels.slang`)
`den_fdiv` and `den_cdiv` are three levels deep in `den_levels.slang`; `den_tdiv` calls `den_tdiv_zero` instead of itself. With the entry point
`probe.slang` it compiles for cpp and cuda; spirv compiles but takes about four minutes and writes 26 MB, because every level inlines the one below.
The Lean version must keep the call tree small (share the `y` split) before the spirv target is usable. The hand-written file stays as the reference to compare against.
## Differential test (2026-11-24)
`slang/turbo/oracle/oracle.cpp` runs one `deduce` step of Turbo's own `pir.hpp` (g++, `_DNDEBUG`, the build under `/mnt/fire/6-datasource/turbo-build`, gtest stubbed by `fake/`)
on 5,400 random boxes: `int_plus`, `int_times`, `int_min`, `int_max`, `int_div`, `int_ediv`, `int_mod`, `int_eq_reif`, `int_le_reif`; 600 each, bounds in -8..8, and about a sixth of the
variables unbounded except for the division operators (Turbo itself divides by zero there). Its output is `slang/turbo/oracle/reference.txt`.
`elixir tools/turbo_diff.exs slang/turbo/oracle/reference.txt` compiles the hand-written `pir.slang` and the Lean-emitted module to C++ with slangc and g++, runs both on the same boxes,
and meets each result with the input box as Turbo's store does. Result: reference vs hand 5,400 of 5,400, reference vs Lean 5,400 of 5,400, hand vs Lean 5,400 of 5,400.
It found one real fault, fixed: Turbo's macros read `r1` live, so `EMOD` sets `r1.ub() = xl` with the new lower bound. `deduce` now changes `r1`, `r2`, `r3` in place like the source.
Added 2026-11-24: `FDIV` and `CDIV` (the harness overwrites the operator of an `int_plus` bytecode in `pir.bytecodes`) and `ask` before and after `deduce`; 6,600 rows (600 per operator, 11 operators); reference, hand-written and Lean-emitted agree on 6,600 of 6,600 for bounds and both `ask` values. Not covered: the division operators with unbounded variables (Turbo itself divides by zero there), one-sided unbounds.
## P2 format and kernel (2026-11-24)
Format: store `lower[v]`, `upper[v]` (`int`), bytecodes `code[i] = (op, x, y, z)` meaning `x = y op z` with the operator codes of `turbo/Turbo/Pir.lean`, `control[0]` the bytecode count.
`turbo/Turbo/Fixpoint.lean` adds `embed`, `deduce_bytecode` (load three variables, `deduce`, embed the three results in order, as `PIR::deduce(bytecode)`) and the entry `fixpoint`:
Gauss-Seidel sweeps until one changes nothing or a variable is bot; it writes the rounds to `control[1]` and a bot flag to `control[2]`. One thread, no atomics, so it compiles for cpp.
Reference: `slang/turbo/oracle/dump.cpp` reads a FlatZinc file, ternarizes and interprets it into Turbo's `PIR` over a `VStore`, prints the store and the bytecodes, runs Turbo's `GaussSeidelIteration`, and prints the store again.
Steps for a level: `elixir tools/party_saga.exs dump TRACK G SEED OUT.dzn`; `minizinc -c --solver turbo.gpu.release --fzn L.fzn party-saga.mzn OUT.dzn` (Turbo's `msc` on `MZN_SOLVER_PATH`);
rewrite unit clauses `bool_clause([x],[])` to `bool_eq(x,true)` and the `solve` line to `solve satisfy` (the lala ternarizer rejects a unary `∨`, and `PIR` cannot interpret the search annotation);
`dump L.fzn > L.dump`; `elixir tools/turbo_fixpoint.exs L.dump`.
Result (CPU, one thread, `g++ -O2`): the final store equals Turbo's on every variable for
scout (g=2, seed 1) 4,869 variables and 4,544 bytecodes, 9 rounds, 6 ms; party (g=4, seed 2) 40,559 and 39,810, 11 rounds, 36 ms; saga (g=6, seed 3) 306,406 and 304,170, 13 rounds, 230 ms.
Not done: Turbo's simplifier and `preprocess_tcn` (the dump takes the plain ternarized formula), search, the objective, the GPU path (Jacobi sweeps with atomics), `ask`/extraction.
## P3 search and branch and bound (2026-11-24)
`turbo/Turbo/Solve.lean` is `barebones_dive_and_solve.hpp` for one thread per block on the CPU target: `propagate` (fixpoint, then the `ask` scan for a solution), `split` with the five variable orders and four value orders,
decisions with ropes, backtracking from the root snapshot, objective tightening from `appx_best_bound`, and the dive over `2^power` subproblems. `tools/turbo_solve.exs` runs it on a dump of Turbo's own preprocessing
(`slang/turbo/oracle/cp_dump.cpp`: parse, ternarize, simplify, strategies, objective), with `--blocks`, `--power`, `--stop-nodes`.
Two guarded departures from the source, both only on a path where the source reads out of range: a failed `split` is read from its return value (the source checks `decisions[depth-1]`, which is the previous decision), and a satisfaction problem (no objective) stops at its first solution (the source's barebones mode is minimization only).
Compared with Turbo's GPU solver (`-arch barebones -or 1 -sub 0`):
| level | Turbo | Slang |
|---|---|---|
| scout (3,220 variables after preprocessing) | 629 nodes, 8 solutions, objective 511 | 629 nodes, 8 solutions, 307 fails, objective 511, exhaustive |
| party, cut at 2,000 nodes (27,880 variables) | 2,000 nodes, 3 solutions, objective 809 | 2,000 nodes, 3 solutions, 995 fails, objective 809 |
Scout with 4 blocks and `--power 3` also reaches 511. The full party level takes Turbo's GPU 469,302 nodes and 763 s (objective 795); it was not run to the end on the CPU. Saga was not run.
## Timeslicing through the planner (owner, 2026-11-24)
The game on this machine is real time and the host has 8 threads, so the solver may use the machine only in free time, one bounded step at a time, planned by the planner and able to restart (owner: "ipyhop is reentrant and can restart").
- The search is a state machine (`turbo/Turbo/Solve.lean`, `state[b][phase]`): `solve` runs until a node budget (`control[13]`) is used and returns after any whole iteration; the next call continues. All state is in buffers; the driver (`tools/turbo_solve.exs`) writes them to a checkpoint file after each slice. Slices of 37, 150 or 1000 nodes, each a fresh process, give the same node count, solutions, fails and objective as one run (scout: 629, 8, 307, 511).
- Domain `turbo_solve` (`entities/domains/turbo-solve.jsonld`, imported into SQLite like the others): action `wait-free(m)` (the host load is under the limit) and `solve-slice(m, l)` (the effect claims the level is done; the runtime reads the real status and plans again), methods `wait-free-host`, `solve-slice-of`, `solve-level` with a `finished` alternative. Problems `turbo_solve_party_busy | free | done` plan to wait then slice, slice, and nothing.
- `tools/turbo_player.exs LEVEL.cp` is the loop: observe (load average under `--max-load`, default 4; GPU under `--max-gpu` percent, default 30), put the observation in a fresh database as a problem, ask the planner, run the first step (the slice runs niced, one thread), repeat. Tested on scout: waits while the GPU is busy, 5 slices of 150 nodes gives the same result, stopping after 2 slices and starting again resumes at node 300.
## Guest ELF under libriscv, nodes and work stealing (2026-11-24)
- The solver is a riscv64 static guest ELF: the Slang `-target cpp` text of `solve` plus `guest/guest_main.cpp`, compiled with `clang++ --target=riscv64-unknown-linux-gnu -march=rv64gc` against `/mnt/fire/5-repository/riscv64-sysroot` (the flags of its `toolchain.cmake`). `guest/host/turbo_host.cpp` runs it with libriscv (CMake project `guest/host`, libriscv at `/mnt/fire/6-datasource/libriscv`, binary translation off) and loops `machine.resume(budget)`, so a step is an instruction budget, deterministic and able to stop anywhere (libriscv `Machine::resume`, `instruction_limit_reached`, `serialize_to`).
- A libriscv option is required: `MachineOptions::ignore_text_section = true` (`rvlinux -I`). By default libriscv bounds jumps by `.text`, and a static glibc keeps `.iplt` beside it, so the guest died with "Illegal opcode executed" on its first `memcpy`. The `lean-guest` recipe (`cmake/run_guest.cmake`) names the same fix.
- Scout under the guest equals native: 629 nodes, 307 fails, 8 solutions, objective 511, exhaustive; the host reports the improving bound while it runs.
- `turbo/Turbo/Solve.lean` has an external mode (`control[14]`): at each subproblem boundary the block waits in `phaseAwait`, and `control[15]` cancels the subproblem in hand. `tools/turbo_cluster.exs` is a coordinator and worker nodes over Erlang distribution (cookie, `--name`, so a worker can be on another machine; `epmd` under `~/.pixi/envs/elixir/lib/erlang/erts-*/bin`), with the messages in `service/turbo-cluster.asyncapi.yaml`.
- Each node says `cpu` or `gpu`; the coordinator measures nodes per second per node. Work stealing is the failure path used on purpose: an idle node takes a subproblem from a node at least 1.5 times slower that has held it for `--steal-after-ms`, by presuming that node dead for it; the first copy to finish wins and the other is cancelled. A node that really dies is requeued the same way; a node with nothing to do waits while any subproblem is in flight.
- Tested on loopback with separate OS processes, scout: 1 node 629 nodes; 3 nodes, 8 subproblems, objective 511; 4 nodes, 32 subproblems, 511; one node killed at its first assignment, the survivors finish all subproblems, 511. One fast `gpu` node and two throttled `cpu` nodes (`--slow-us`), 32 subproblems: 3.6 s with stealing (one steal, one copy cancelled), 30.6 s without, objective 511 both. The `gpu` kind is a label and a speed prior today; the node behind it is the same guest. A real GPU node needs a Slang GPU kernel (or Turbo's GPU solver given the subproblem protocol) behind the same frames.
- Not tested: a second machine (loopback only).
- Turbo's own GPU solver on the free RTX 4090 for reference: scout 1 block 1.06 s, 256 blocks 0.004 s; party 1 block 2,000 nodes in 4.9 s (about 570 nodes/s, against about 180 on one CPU core here), 256 blocks and 8,192 subproblems it FOUND objective 795 at 0.234 s of solve time (138,126 nodes by then; only 7 subproblems searched, 8,184 skipped); that run had a 60 s limit and used it, so the optimum was not proven in that time (this line first said the level was solved in 0.234 s, which was wrong). One block, no split, proves it in 469,302 nodes and 763 s. That kernel is one long launch, which a 64 Hz game cannot take; a Slang GPU path has to launch short bounded kernels.
- Profiling: `bpftrace`, `perf` and the bcc tools are installed (apt, 2026-11-24, owner approved) for profiling the guest host and the cluster.
- eBPF profile (bpftrace, `profile:hz:499` on `comm == "turbo_host"`, 2,984 samples, party level under the guest, symbolized with `llvm-symbolizer` from the load address in `/proc/PID/maps`): 96.3% in `riscv::CPU<8>::simulate` (libriscv's interpreter loop), 1.5% and under in single-instruction handlers; nothing in syscalls, the frame I/O or the host code. The guest is bound by interpretation, so the next speed step is libriscv binary translation or running the same kernel natively where real time does not matter; the instruction budget stays the same.
- 64 Hz frames on the host (`TURBO_FRAME_MS`, `TURBO_FRAME_HZ`, `tools/turbo_cluster.exs --frame-ms`): each window gets an instruction budget calibrated to a compute time (default target 2 ms of the 15.6 ms frame), then the host sleeps to the frame edge. Scout under the guest: 2,341 windows, mean 2.02 ms, max 5.28 ms, 12 windows over 1.5 times the target, 3.03 billion guest instructions (about 500 million per second), final budget 1,030,895 instructions; the result is identical (629 nodes, 307 fails, 8 solutions, objective 511). Two frame-paced nodes on 8 subproblems reach 511 in 22 s. A frame-paced guest gets about one eighth of a core, so the long levels are hours of free time; the instruction budget does not change the search.

## GPU: the cooperative kernel (2026-11-24)
- `turbo/Turbo/Coop.lean` is the search for a 256-thread workgroup per block, as Turbo's own kernel: all threads share a node's fixpoint sweep, the unentailed-propagator scan, the variable selection and the store copies; thread 0 runs the serial search logic; control is uniform and barriers separate every write from the reads that follow. The store is changed with `InterlockedMax` (lower) and `InterlockedMin` (upper), the meet. The shared best bound and next-subproblem counter use `InterlockedMin`, `InterlockedAdd`, `InterlockedMax`. Entailed propagators leave the sweep (a per-block active list, reset after every restore, compacted by warp).
- Build: `turbo_emit solve-coop` then `slangc -target cuda -entry solve`, then `nvcc -arch=sm_89 -cubin` (nvcc from Turbo's pixi environment). `guest/gpu/turbo_gpu.cpp` is the CUDA driver-API host: it loads the cubin, fills the global parameter block, and runs bounded launches (`SLICE_NODES` nodes per block per launch). `TURBO_PROGRESS`, `TURBO_MAX_LAUNCHES` and the best-bound log help watching a run.
- Equal to Turbo: scout, one block: 629 nodes, 307 fails, 8 solutions, objective 511, exhaustive. Party, 2,000 nodes: 995 fails, 3 solutions, 809. With one block and a split (`power` 3, 5, 8) the node counts equal Turbo's exactly: 640, 658, 700, so the dive, the skipping of failed subtrees and the subproblem order are the same. With many blocks the counts differ with timing, as Turbo's do (scout, 256 blocks, 8,192 subproblems: 13,345 nodes against Turbo's 10,868).
- Speed: party, one block, one node per launch: mean 1.97 ms, max 7.4 ms per launch, 2,000 nodes in 4.3 s (Turbo 4.9 s with its fixed cost). 256 blocks, 8,192 subproblems, 50 nodes per launch: objective 795 at 1.04 s wall (launch 7). The entailed-propagator list, as first written with one atomic per kept propagator, made nodes slower (4.4 ms) because restores reset it every time; with warp compaction the mean is 4.6 ms, so it does not help in this search and is to be reconsidered.
- Not done: proving 795 optimal on the GPU with many blocks (one block was still working on subproblem 8191 after 188,000 nodes in total), a free-time gate around the launches, launches under 1 ms.
- Turbo's own reference, party, default 256 blocks and 8,192 subproblems, 600 s limit (2026-11-24): 609,299 nodes, objective 795 found at 2.34 s, 7 subproblems searched and 8,184 skipped, `num_blocks_done=255` of 256: one block never finishes, so Turbo does not prove optimality in this configuration either; it ends on the time limit. The Slang kernel shows the same shape (255 of 256 blocks done within a second, one block left on the all-right subproblem 8191). The party level is proven only by one block without a split (469,302 nodes, 763 s on Turbo's GPU kernel). A GPU speed target is therefore time to the best objective: Turbo 0.23 s of kernel time, the Slang kernel 0.33 s wall with 256 blocks.
- GPU through the planner (2026-11-24): `turbo_gpu` keeps one resident process (`TURBO_SERVE=1`) that answers `run N`, `status`, `save PATH`, `load PATH`, `result`, `quit` and keeps the search on the device; `tools/turbo_player.exs --engine gpu` asks the `turbo_solve` planner domain before every slice and runs `run 10` (ten launches of one node per block, about a millisecond each) under a duty cap (`--duty`, default 25 percent: after a launch of d ms the host sleeps d*3 ms). The gate is the GPU only, with this process's own recent share subtracted from the reading, and it waits while others use more than `--max-gpu` percent. The state is saved every `--save-every` slices and at a pause; starting again loads it. Scout, one block: 3 slices, save, restart, load, finish: 629 nodes, 8 solutions, objective 511, as in one run; the host's per-launch time was a mean of 0.15 ms and a maximum of 1.0 ms. With the gate at 0 it only waits.
- GPU embed reads before it does an atomic: party 2,000 nodes on one block 4.4 s down to 2.7 s (mean launch 1.15 ms, maximum 4.5 ms) with the same result. Sorting the bytecodes by operator (`tools/turbo_solve.exs --sort-ops`) changed nothing.
