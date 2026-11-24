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
Not covered: `FDIV` and `CDIV` (no FlatZinc name reaches them), one-sided unbounds, the division operators with unbounded variables, `ask` (only `deduce` is compared), many-step fixpoints.
