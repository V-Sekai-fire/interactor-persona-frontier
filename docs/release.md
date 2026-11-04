# The one release

Decision (operator, 2026-11-04): serving Bonsai 2 is done, so it is not R&D; `ninfer-all`
`windows-service-v1.0.0` (15 assets, 14.3 GiB, the MSI, the runtime split in 4, the model split in
6) installs it offline on a Windows box. What is R&D is **one release that carries every part**:
the engine, every guest ELF, every GGUF, the language model's service, and the planner node, with
one `SHA256SUMS` over all of them. The PQ2_0 Slang kernel is not the gap; the single release is.

## What ships today, measured from the GitHub releases

| repository | release | assets | what it carries |
| --- | --- | --- | --- |
| `ninfer-all` | `windows-service-v1.0.0` 2026-10-29 | 15, 14.3 GiB | the Bonsai 2 service, Windows only |
| `transport-meshing-pen` | `v20261002-dev.2` 2026-10-03 | 11 | engines for macOS arm64 and Windows x86_64 (double), `libgodot_riscv`, and five guests: `curvenet`, `dress_on`, `mujoco`, `rd_worker`, `usd`, with `SHA256SUMS` |
| `entities-model-explorer` | `v0.0.0-20261103213837-a3fd94eefd97` | 1 | the macOS DMG, 207 MB |
| the guest and model repositories: `skintokens-guest`, `skin-tokens-ggml`, `kimodo-ggml`, `motion-creation-guest`, `voice`, `usd-guest`, `cloth-fit-guest`, `garment-fit`, `drape`, `bake`, `contract-ggml-rd`, `skintokens-rig` | **none** | built from source only |

So: two partial releases and one language-model release, on two platforms, and twelve repositories
with no release at all. Nothing today lets a player or a box take one download and run the stack.

## The shape of the one release

The pen's `v20261002-dev.2` is the pattern: one tag, one `SHA256SUMS`, engines per platform and
every guest ELF beside them. The one release is that list completed, as one tag on one repository
(the pen, which already carries the engines and the first five guests), with every row below present
and summed:

| part | source | today |
| --- | --- | --- |
| engine, macOS arm64 and Windows x86_64 double | `service-godot-build` | in the pen release |
| `libgodot_riscv` per platform | `service-godot-build` | in the pen release |
| guests: curvenet, dress_on, mujoco, rd_worker, usd | the pen's build | in the pen release |
| guests: skintokens, motion (Kimodo + MotionBricks), voice, cloth-fit, garment-fit, drape, bake, remesh, cage, anny-fit, headfit | their repositories' `tools/build.exs` | **missing**: no release builds them |
| every weight, 14 rows, 77 GB (`deploy/weights.exs list`) | `hf:chibifire` by hash; 8 rows still live on upstream orgs and are the mirroring left | **the one place**: `deploy/weights.exs fetch <dir>` preloads all of it with `SHA256SUMS` from the hub's LFS hashes, `verify` re-checks offline, `self-test` proves verify fails on a planted byte (passed on the two smallest rows). GitHub's 2 GiB cap keeps weights off the release assets; the release pins the manifest and its sums |
| the language model's service and its model (Bonsai 2 PQ2_0, 7.2 GB) | `ninfer-all` | released alone, Windows only; the one release carries the same assets or pins that tag by hash |
| the planner node (`frontier`) and its knowledge seed | this repository, `deploy/Containerfile` | built, never released |
| `SHA256SUMS` over all of it, and a `CITATION.cff` with the tag as a Go pseudo-version (RFD 2312) | the release job | per part today, never once |

## Gates the one release must pass before it is called one

1. Every asset in `SHA256SUMS` downloads and matches, checked by a script that also fails on a
   planted wrong hash.
2. Each guest ELF runs under the sandbox translated and interpreted and the two agree
   (`check_bintr.exs`, as the motion guest does today).
3. The language model answers the 48-pair judge probe (`docs/judge/judge.py`) at the measured
   0.927 within noise, from the release's own service, not from a desk install.
4. The planner node starts from the release's binary and seed and answers `world` (`deploy/pod.exs smoke`).

## What this repository does about it

Nothing in the planner changes. This file is the ledger's row for the release; `docs/tokens.exs`
names the release as the thing that is not spent, and the "PQ2_0 in Slang" line is withdrawn: the
kernel exists in NInfer and in the Prism llama.cpp on `entities-godot` `dev/language-model`
(`GGML_TYPE_PQ2_0 = 142`), so it is a port that can wait until a guest needs it.
