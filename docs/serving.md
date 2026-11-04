# Running the models: the strategy

One rule, then its consequences. **The planner never runs a model.** A plan names stages; a stage
is settled by its own repository, which owns the model, the runtime and the report that comes back
as an experience. This repository holds no weights and no CUDA, and `deploy/pod.exs` sizes the
cell with none. What follows is the shape each stage's runtime takes, where it is today, and the
order in which the Python images retire.

## Two runtimes, one direction

| runtime | what it is | where it runs | what it is for |
| --- | --- | --- | --- |
| **ggml guest** | the model as a ggml graph inside a godot-sandbox guest ELF, kernels on `contract-ggml-rd` (Lean to Slang to SPIR-V on Godot's RenderingDevice), weights as GGUF | the player's machine, any GPU Godot drives (Vulkan, Metal, WebGPU) | a player's path: anything that runs while someone wears, draws or speaks |
| **Python model image** | the upstream PyTorch code in a container, served over HTTP on a GPU box | the 4090 desk (today), a rented GPU cell later | authoring and scoring at the frontier: judges, generators whose ggml port is not done, anything measured rather than shipped |

The direction is Python to ggml, one stage at a time, and a stage moves when its ggml guest passes
parity against the Python image on a held-out set (the Pixal3D rule: per-stage parity vs PyTorch
before the Python path is removed). Until then both exist and the Python image is the oracle.

## Where each stage is

| stage | model | ggml guest | Python image | state |
| --- | --- | --- | --- | --- |
| 1 look dev | OmniGen2 + EditScore7B-v1.1 LoRA | none | `interactor-omnigen2-editscore-space`, `omnigen2-editscore-desktop` | **stays Python**: a 4B DiT + Qwen2.5-VL-3B at 1024², an authoring step, not in a player's path |
| 1 judge | Bonsai 2 Heretic v2 | NInfer artifact (`t2_g128_fp16`, ternary) | none needed | **done, resident**: 0.927 zero-shot on 48 pairs (`docs/judge/`); EditScore-7B retiring |
| 2 image to 3D | TRELLIS.2 / Pixal3D | `pixal3d-ggml` (trellis2.cpp, DINOv3 + BiRefNet on ggml-rd) | the Pixal3D Space | **porting**: parity per stage vs PyTorch is the gate |
| 4 auto-rig | SkinTokens / TokenRig | `skin-tokens-ggml`, `interactor-skintokens-guest`, host `interactor-skintokens-rig` (WebGPU/Vulkan/Metal), GGUF on `chibifire/SkinTokens-GGUF-BF16` | `interactor-skintokens-auto-rig` | **ported, Python still the oracle**: first forward pass logged; parity run not yet recorded |
| 5 garments | Point-SAM, remesh, garment-fit, cloth-fit, drape, bake | `interactor-cloth-fit-guest` (Lean, GPU only), `interactor-garment-fit`, `interactor-drape`, `interactor-bake` | Point-SAM (zyc00, MIT, ViT-L 311 M) | **guests except segmentation**: Point-SAM replaces P3-SAM (Tencent licence); a ViT-L over sampled points is a stock ggml shape, so its port is the easiest of the missing ones |
| 7 motion | Kimodo + MotionBricks | `kimodo-ggml`, `interactor-motion-guest` / `interactor-motion-creation-guest`, GGUF on `chibifire/{Llama-3-Kimodo-GGML, MotionBricks-G1-GGML}` | Kimodo PyTorch (DGX side, RFD 1092) | **ported**: the 8B body is the largest GGUF in the pipeline (15 GB bf16; 4-bit is the one quantization still required for the 4090 rotation) |
| 8 face, voice | Zipformer (Icefall/k2), Silero VAD; `interactor-voice` | ONNX via sherpa-onnx on CPU (already not Python); voice is a guest | none | **done**: 0.26 GB, 5-10 ms a chunk, off the GPU by design |
| 10 runtime | planner, USD guest, command contract | `interactor-usd-guest`, `contract-command`, this repository | none | **done** |

## The rules the table follows

1. **A player's path is a guest.** Stages 4, 5, 7, 8, 10 run where the player is. They ship as
   guest ELFs plus GGUF, run on ggml-rd, and nothing of them is a container. Residency on the
   player's GPU follows `docs/tokens.exs`: rotate per stage, bf16 always, 4-bit where measured.
2. **Authoring stays Python until a port pays.** Stage 1's generator is big, slow and run once per
   look; it stays a Python image on the authoring GPU. Its port is not scheduled.
3. **The judge is the resident language model.** Bonsai 2 already serves as scorer on the 4090 and
   judges at 0.927; one resident model does both. No second judge is loaded.
4. **The Python image is the oracle, never the product.** A stage's Python image is kept until its
   guest passes parity on a held-out set with a planted fault that fails, then the image is
   retired in the same change that lands the parity record.
5. **Experience comes from the stage repository's CI.** Each stage runs its own gate and posts
   `{action, held_before, settled, duration}` to this node's `/experience`; `learn` folds the
   measured durations and requirements back into the domain. The planner learns from runs it
   never performed.

## What this costs, and where

| where | what runs | box |
| --- | --- | --- |
| the cell ($12 droplet or a ~€4 Hetzner cell) | planner node + FoundationDB + epmd, constant shares | no GPU, no weights |
| the authoring GPU (4090 desk today) | Bonsai 2 resident (7.2 GB), stage 1 generator rotated in (15.4 GB bf16), judge calls | 24 GB; stage 1 at bf16 with the resident judge is 24.6 GB, so the VL-3B goes 4-bit or activations tighten |
| the player's GPU | stages 4, 5, 7, 8, 10 as guests, rotated per stage | Kimodo 4-bit (4.3 GB) is the ceiling; everything else under 2 GB |
| a rented GPU cell (RunPod serverless, allowed since 2026-11-04) | overflow of the authoring GPU only: stage 1 generation and the full-bench judge runs | per-second; never a player's path |

## The release is the work

Serving Bonsai 2 is done (`ninfer-all windows-service-v1.0.0`); the R&D is one release carrying every part, `docs/release.md`. The measurements below feed its gates.

## Next three measurements, in order

1. SkinTokens guest vs `interactor-skintokens-auto-rig` parity on held-out meshes, planted fault,
   then retire the Python image (rule 4).
2. Kimodo GGUF at 4-bit vs bf16 on the motion-matching gate; the 4090 rotation depends on it.
3. Bonsai 2 judge on the 350-pair sample with EditScore-7B on the same pairs, then retire EditScore.
