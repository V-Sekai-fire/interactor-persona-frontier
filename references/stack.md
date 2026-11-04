# Look dev to game character-persona stack

A ten-stage stack from a concept image to an in-game character that talks, moves and is driven by an agent, built from repositories the five orgs already hold. Each stage names the general method that scales (search or learning), the human knowledge that ships it today, and the trigger that retires that knowledge. The ordering principle is Sutton's: keep the meta-method, treat the content as replaceable.

Evidence base: repository names and descriptions of V-Sekai-fire (81), chibifire-stages (34), V-Sekai-archive (919), V-Sekai (237), fire (329), filtered to 223 character-relevant non-forks, plus `weftspun/src/decisions/AVATAR_PIPELINE.md` and RFD 0005. READMEs, CI state and builds are unread.

## Data flow

```
concept image / text
  │ 1 look dev          see-through-ggml · cyclegan-style-transfer · EditScore/MaskScore ladder
  ▼
textured mesh (PBR)
  │ 2 image→3D          trellis2 / pixal3d image-to-textured-mesh · voxhammer edit · contract-orbit-views
  ▼
parametric body + head
  │ 3 body fit          interactor-anny-fit (L-BFGS) · interactor-headfit · contract-anny-kernels · entities-anny-creator
  ▼
rigged, skinned body
  │ 4 rig/skin          interactor-skintokens-{guest,rig,auto-rig} · interactor-cage · interactor-character-domain-c-abi
  ▼
dressed body
  │ 5 garments          p3sam-mesh-segmentation → interactor-remesh → garment-fit → cloth-fit-guest → drape → bake
  ▼
shaded character
  │ 6 materials         entities-godot-toon-shaders · contract-materialx-shaders-lean · godot-sheen-look-up-table
  ▼
moving character
  │ 7 motion            kimodo-text-to-motion · interactor-motion-guest · motion-retarget (SOMA30) · motion-matching-guest
  ▼
speaking face
  │ 8 face/voice        headfit expression transfer · mfcc-viseme-gan / visemenet-data · interactor-voice (Opus)
  ▼
persona
  │ 9 agent             interactor-taskweft-persona · taskweft-nmm-personas · interactor-a2a · multimodal-semantic-ids · weftspun-character-taxonomy
  ▼
in-game entity
    10 runtime          godot-sandbox guests · contract-command · ggml-rd · interactor-usd-guest · godot-vrm · entities-model-explorer · v-sekai-game / uro
```

Interchange between stages: OpenUSD (`.usda`, UsdSkel sublayer from skintokens-auto-rig), glTF/VRM for game delivery, ZStandard parquet for corpora. Guests speak `contract-command` (command in, reply bytes out) and share `contract-guest-common` (blake3, mesh wire format). Weights and corpora sit on Hugging Face under `chibifire/*`, code on GitHub.

## Stage table

| # | Stage | Scales by | Human knowledge shipping today | Retire when |
|---|---|---|---|---|
| 1 | Look dev | Learning (image model) + search (best-of-N under EditScore/MaskScore learned judge) | Prompt templates, style-transfer pairs, layer-decomposition network for anime cels | A general image-edit model scores above the ladder's top rank on held-out pairs |
| 2 | Image→3D | Learning (TRELLIS2, Pixal3D) + search (orbit-view consistency across `sphere_hammersley_sequence` cameras) | Fixed PBR channel set; voxhammer edit prompts | Model emits UsdSkel-ready topology without stage 3 |
| 3 | Body fit | Search (in-guest L-BFGS over ANNY sliders; Lean-emitted forward/backward kernels) | ANNY parametric body itself: a hand-built prior with ~100 sliders | A learned body model fitted on `datasource-anny-render-corpus` beats ANNY on keypoint reprojection |
| 4 | Rig/skin | Learning (SkinTokens auto-rig) | Humanoid bone naming; biharmonic cage bind; Delta Mush (DQS blocklisted) | SkinTokens weights pass the range-of-motion test bank with no cage |
| 5 | Garments | Search (PolyFEM/IPC fit, AVBD drape: physics as a solver, GPU-only) | Segmentation labels (P3-SAM), remesh targets, body-only fit rule | A learned draper reproduces the AVBD result at interactive rate |
| 6 | Materials | None yet: hand-written shader ports | MToon 0.x/10 parameter map, MaterialX in Lean, sheen LUT | Toon-to-PBR chart is regressed from renders instead of hand-charted |
| 7 | Motion | Learning (Kimodo, MotionBricks on ggml-rd) + search (motion matching over a clip database) | SOMA30→humanoid retarget tables; G1 sim-to-real joint envelopes | Text-to-motion clips outscore the matched database on the walk-mode baseline |
| 8 | Face/voice | Learning (MFCC→viseme GAN; unified expression transfer) | ARKit/Vive 124-morph template; viseme set | A speech-conditioned face model drives the template without the viseme intermediate |
| 9 | Persona | Search (HTN / RECTGTN planner; GRAFCET personas over the bus) | **The planning domain is hand-written content.** `interactor-taskweft-persona` answers "from a planning domain instead of a neural network" | Domains are induced from MaskScore traces and play logs, not authored |
| 10 | Runtime | Compute (RISC-V guests, ggml on RenderingDevice; WebGPU/Vulkan/Metal) | Guest ABI, wire formats, USD stream | n/a: this is the substrate that lets 1–9 spend more compute |

## Where the stack is bitter-lesson-pilled and where it is not

Pilled. Stages 1, 2, 4, 7 and 8 are learned models, and the stack already pairs them with inference-time search: a learned scorer picks among samples (stage 1), orbit views vote (stage 2), motion matching searches a clip set (stage 7). Stage 3's L-BFGS fit and stage 5's physics solvers are search over a model; their performance grows with GPU time, which is why `cloth-fit-guest` has no CPU path. Stage 10 exists to keep the compute axis open: guest ELFs run the same kernel on three GPU APIs.

Not pilled, by choice. ANNY (stage 3), the toon shader map (stage 6) and the planning domains (stage 9) are hand-encoded content. ANNY is the defensible case, Brooks's objection in practice: a low-parameter body prior makes the fit data-cheap, the same way convolution made vision cheap, and the render corpus exists to replace it. The shader map is a port, not a method, and has no scaling axis. The persona domain is the exposed position: a planner is a general method, but a domain written by hand plateaus exactly where Sutton says it does. Silver and Sutton's "era of experience" reading points at the fix the stack already half-holds: `interactor-taskweft-nmm-personas` records MaskScore traces of play, so the domain can be learned from those traces while the planner stays.

Binding constraint. For stages 1–2 and 7–8 the limit is licensed training data, not compute: the blocklist and dataset allow/blocklist directories gate every corpus, the COCO holdout is blinded, and generated data carries four conditions. More compute does not lift that limit, so the scaling plan for those stages is "more constructed data from assets we hold" (ANNY renders, orbit views), which is the GPU-bound path.

## Lineage (what each generation replaced)

| Era | Rig | Avatar source | Motion | Face |
|---|---|---|---|---|
| V-Sekai 2020–23 | renik, many_bone_ik (hand IK), vsk_avatar | VRM import (godot-vrm), unidot | Mixamo retarget, root-motion-extractor | MMD/VRM blend shapes |
| V-Sekai-archive 2024–25 | godot_motion_matching | blue-zinc-pelican / open-character-creator | ShaderMotion video→anim | visemenet, mfcc-viseme-gan |
| Weftspun 2026 | SkinTokens auto-rig, cage bind | TRELLIS2/Pixal3D + ANNY fit | Kimodo text-to-motion on ggml-rd | headfit expression transfer |

Each row swaps hand-written knowledge for a learned or searched method and leaves the older one in `V-Sekai-archive`; the lineage is the essay's four-step cycle run three times.

## Gaps

- Stage 6 has no learned or searched component and no corpus to grow one.
- Stage 9's trace-to-domain induction has no repository.
- No end-to-end gate runs a photo through stages 1–10 to a loaded guest; per-stage probes exist (Gate 0G for usd.elf, rig contract `[API-Contract] PASS` in the older web studio).
- `persona-fire` (chibifire-stages, 2023) carries no description; its relation to `interactor-taskweft-persona` is unknown.

Unchecked: READMEs, CI, releases, licences on the Tencent-derived model images (P3-SAM review pending), and whether the 2026 web studio (`Weftspun3DStudio`) is retired or parallel.
