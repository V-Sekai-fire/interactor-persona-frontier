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

## Phases (status)
- P0 measure what Party Saga needs (operators, baselines): not started.
- P1 toolchain gate: compile passed for CUDA and SPIR-V and for the CPU target without atomics; nothing executed.
- P2 format and kernel, P3 search and objective, P4 targets and numbers: not started.
