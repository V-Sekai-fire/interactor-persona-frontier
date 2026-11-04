# inventory-character-persona-stack

Inventory of the repositories across V-Sekai-fire, V-Sekai, V-Sekai-archive, chibifire-stages and fire that make up the look-dev to game character-persona pipeline.

## What it is for

One table per pipeline stage naming the repository that owns each piece, its owner, language and last push, so a task that names a stage finds its repository without a search. `docs/stack.md` grades each stage against the Bitter Lesson; `docs/repo-inventory.md` is the raw keyword survey the tables are drawn from. Writes land only in V-Sekai-fire and chibifire-stages; V-Sekai and V-Sekai-archive rows are read-only.

## Stages

### 1. Look dev

Scales by: image model + learned judge over N samples.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-archive | [interactor-see-through-ggml](https://github.com/V-Sekai-archive/interactor-see-through-ggml) | C | 2026-10-24 | Single-image layer decomposition for anime characters, over ggml, answering on the weft command bus. The C++ half of an A/B pair; a run belo |
| V-Sekai-archive | [interactor-cyclegan-style-transfer](https://github.com/V-Sekai-archive/interactor-cyclegan-style-transfer) | Python | 2026-10-24 | Model image for cyclegan_style_transfer: ukiyo-e and Monet restyling of ANNY renders, BSD upstream, non-diffusion by design. |
| V-Sekai-archive | [interactor-multimodal-semantic-ids](https://github.com/V-Sekai-archive/interactor-multimodal-semantic-ids) | Python | 2026-10-24 | Multimodal FOSS encoders + concat-vector ResidualFSQ semantic IDs (text/image/mesh/audio/body-phenotype); successor to vsk-session-item-reco |

### 2. Image to 3D

Scales by: learned model, orbit-view voting.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-archive | [interactor-trellis2-image-to-textured-mesh](https://github.com/V-Sekai-archive/interactor-trellis2-image-to-textured-mesh) | Python | 2026-10-24 | Model image for trellis2_image_to_textured_mesh (image to 3D, PBR). RFD 0036/0038 packaging convention. Base image for 4 other catalog model |
| V-Sekai-archive | [interactor-pixal3d-image-to-textured-mesh](https://github.com/V-Sekai-archive/interactor-pixal3d-image-to-textured-mesh) | Python | 2026-10-24 | Model image for pixal3d_image_to_textured_mesh (image to 3D, PBR). RFD 0036/0040 packaging convention -- the worked example, ported verbatim |
| V-Sekai-archive | [interactor-trellis2-image-mesh-painting](https://github.com/V-Sekai-archive/interactor-trellis2-image-mesh-painting) | Python | 2026-10-24 | Model image for trellis2_image_mesh_painting. RFD 0036/0039. No weights of its own -- builds on interactor-trellis2-image-to-textured-mesh. |
| V-Sekai-archive | [interactor-voxhammer-text-mesh-editing](https://github.com/V-Sekai-archive/interactor-voxhammer-text-mesh-editing) | Elixir | 2026-10-24 | Model image for voxhammer_text_mesh_editing. RFD 0036/0037/0047. Composite: real taskweft domain, ported verbatim. |
| V-Sekai-archive | [interactor-voxhammer-image-mesh-editing](https://github.com/V-Sekai-archive/interactor-voxhammer-image-mesh-editing) | Python | 2026-10-24 | Model image for voxhammer_image_mesh_editing. RFD 0036/0037/0048. Shares RFD 0047's domain; only mode.conditioning differs. |
| V-Sekai-archive | [contract-orbit-views](https://github.com/V-Sekai-archive/contract-orbit-views) | Python | 2026-10-24 | The orbit-view standard: one subject seen from cameras spread evenly around it, as a still sheet or a clip. |
| V-Sekai-archive | [pixal3d-cuda-wheels](https://github.com/V-Sekai-archive/pixal3d-cuda-wheels) | Shell | 2026-10-27 | CUDA wheels (FlexGEMM, CuMesh, o-voxel) for Pixal3D on RTX 30/40/50 cards, built by GitHub Actions |

### 3. Body and head

Scales by: L-BFGS search over ANNY sliders, GPU kernels.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-fire | [interactor-anny-fit](https://github.com/V-Sekai-fire/interactor-anny-fit) | NASL | 2026-11-03 | The ANNY-SOMA-X body fit as a godot-sandbox guest: sliders fitted with the in-guest L-BFGS-B on the CPU and on RenderingDevice |
| V-Sekai-fire | [interactor-headfit](https://github.com/V-Sekai-fire/interactor-headfit) | C++ | 2026-11-03 | The head fit as a godot-sandbox guest: the ANNY head fit and the unified-expression transfer |
| V-Sekai-archive | [contract-anny-kernels](https://github.com/V-Sekai-archive/contract-anny-kernels) | C++ | 2026-10-25 | The ANNY body model's forward and backward kernels in Lean, emitted through Slang for the in-guest fits |
| V-Sekai-archive | [entities-anny-creator](https://github.com/V-Sekai-archive/entities-anny-creator) | GDScript | 2026-10-24 | A character creator with sliders over a parametric human |
| V-Sekai-archive | [datasource-anny-render-corpus](https://github.com/V-Sekai-archive/datasource-anny-render-corpus) | Python | 2026-10-24 | The ANNY render corpus pipeline: ETNF schema, identity sampling, the audits that gate a render run, and a Mitsuba render pass pinned by pixi |
| V-Sekai-archive | [datasource-anny-soma-corpus](https://github.com/V-Sekai-archive/datasource-anny-soma-corpus) | Python | 2026-10-24 | ANNY-SOMA keypoint corpus. Task #67 render side. First-subset row shape per RFD 2203. |
| chibifire-stages | [thebasemesh-stage](https://github.com/chibifire-stages/thebasemesh-stage) | Python | 2026-10-05 | thebasemesh.com CC0 base meshes |

### 4. Rig and skin

Scales by: learned rig.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-fire | [interactor-skintokens-guest](https://github.com/V-Sekai-fire/interactor-skintokens-guest) | C++ | 2026-11-03 |  |
| V-Sekai-fire | [interactor-skintokens-rig](https://github.com/V-Sekai-fire/interactor-skintokens-rig) | GDScript | 2026-11-01 | Godot host that runs the SkinTokens rig guest on WebGPU, Vulkan or Metal |
| V-Sekai-fire | [interactor-skintokens-auto-rig](https://github.com/V-Sekai-fire/interactor-skintokens-auto-rig) | Python | 2026-10-24 | Model image for skintokens_auto_rig. RFD 0036/0046. UsdSkel rig sublayer; MIT license confirmed. |
| V-Sekai-fire | [interactor-cage](https://github.com/V-Sekai-fire/interactor-cage) | C++ | 2026-10-24 | The cage stage as a godot-sandbox guest: the (1,3) biharmonic bind and the in-motion cage fit on L-BFGS-B |
| V-Sekai-archive | [interactor-character-domain-c-abi](https://github.com/V-Sekai-archive/interactor-character-domain-c-abi) | Lean | 2026-10-29 | A pure-Lean character model whose rig, skin and pose goals the RECTGTN planner solves unchanged. |
| V-Sekai | [many_bone_ik](https://github.com/V-Sekai/many_bone_ik) | C++ | 2025-09-04 | A custom inverse kinematics system solver for multi-chain skeletons and with constraints. |
| V-Sekai | [godot-renik](https://github.com/V-Sekai/godot-renik) | C++ | 2025-11-19 |  |
| V-Sekai | [godot-humanoid](https://github.com/V-Sekai/godot-humanoid) | GDScript | 2025-08-10 |  |

### 5. Garments

Scales by: physics solve (PolyFEM/IPC, AVBD), GPU only.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-archive | [interactor-p3sam-mesh-segmentation](https://github.com/V-Sekai-archive/interactor-p3sam-mesh-segmentation) | Python | 2026-10-24 | Model image for p3sam_mesh_segmentation. RFD 0036/0041. License: review pending (Tencent Community License, not MIT as RFD 0041 states -- co |
| V-Sekai-fire | [interactor-remesh](https://github.com/V-Sekai-fire/interactor-remesh) | C++ | 2026-10-24 | meshoptimizer's voxel remesher and simplifier as a godot-sandbox guest, the remesh stage of RFD 2284 |
| V-Sekai-fire | [interactor-garment-fit](https://github.com/V-Sekai-fire/interactor-garment-fit) | C++ | 2026-10-24 | The fit stage as a godot-sandbox guest: cloth-fit's PolyFEM garment solve with the Lean SDF sampler |
| V-Sekai-fire | [interactor-cloth-fit-guest](https://github.com/V-Sekai-fire/interactor-cloth-fit-guest) | Lean | 2026-11-01 | The cloth-fit stage as a godot-sandbox guest whose compute runs on the GPU (no CPU path) |
| V-Sekai-fire | [interactor-drape](https://github.com/V-Sekai-fire/interactor-drape) | C++ | 2026-10-18 | The drape stage as a godot-sandbox guest: AVBD cloth from Lean kernels on the CPU and on RenderingDevice |
| V-Sekai-fire | [interactor-bake](https://github.com/V-Sekai-fire/interactor-bake) | C++ | 2026-11-01 | Alpha culling and texture atlases for avatar meshes as a godot-sandbox guest, the CPU part of RFD 2284's bake stage |
| V-Sekai-fire | [contract-guest-common](https://github.com/V-Sekai-fire/contract-guest-common) | C++ | 2026-11-01 | The shared headers the dress-on guests include: blake3 and the mesh wire format |
| V-Sekai | [TOOL_cloth_dynamics](https://github.com/V-Sekai/TOOL_cloth_dynamics) | C++ | 2026-11-03 |  |
| chibifire-stages | [elaina-summerwhitedress-stage](https://github.com/chibifire-stages/elaina-summerwhitedress-stage) | Python | 2026-10-29 | Elaina - The Witch's Journey (Summer White Dress): the Sketchfab stage (ScarletJadeDream, CC-BY-4.0) and our cleaned, English-named OpenUSD  |

### 6. Materials

Scales by: none: hand ports.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-fire | [entities-godot-toon-shaders](https://github.com/V-Sekai-fire/entities-godot-toon-shaders) | GDScript | 2026-11-01 | Godot ports + a shared parameter map for avatar toon shaders (MToon 0.x / MToon10, with planned SCSS and lilToon ports) to ease cross-shader |
| V-Sekai-archive | [contract-materialx-shaders-lean](https://github.com/V-Sekai-archive/contract-materialx-shaders-lean) | Lean | 2026-10-11 |  |
| fire | [godot-sheen-look-up-table](https://github.com/fire/godot-sheen-look-up-table) | Lean | 2026-06-18 |  |
| V-Sekai | [Godot-MToon-Shader](https://github.com/V-Sekai/Godot-MToon-Shader) | GDScript | 2026-07-08 | Port of MToon to Godot Engine |

### 7. Motion

Scales by: learned clips + motion-matching search.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-archive | [interactor-kimodo-text-to-motion](https://github.com/V-Sekai-archive/interactor-kimodo-text-to-motion) | Python | 2026-10-24 | Model image for kimodo_text_to_motion. RFD 0036/0045. Ships Kimodo-SOMA; retargets via LabRCSF joints.csv. |
| V-Sekai-archive | [interactor-motion-guest](https://github.com/V-Sekai-archive/interactor-motion-guest) | C++ | 2026-10-25 | Kimodo and MotionBricks motion on ggml-rd as a godot-sandbox guest, for the in-motion dress fit |
| V-Sekai-archive | [interactor-motion-retarget](https://github.com/V-Sekai-archive/interactor-motion-retarget) | Lean | 2026-10-25 | Retargets a SOMA30 motion clip onto a humanoid rig in Lean 4, in a workspace whose size is proved constant. |
| V-Sekai-archive | [interactor-motion-matching-guest](https://github.com/V-Sekai-archive/interactor-motion-matching-guest) | C++ | 2026-10-26 | Motion matching (a port of godot-motion-matching) as a godot-sandbox guest ELF |
| V-Sekai-archive | [interactor-g1-sim-to-real](https://github.com/V-Sekai-archive/interactor-g1-sim-to-real) | Python | 2026-10-24 | The G1 humanoid sim-to-real environment: MuJoCo rig, joint-range envelope, PPO task with GGUF policy export |
| V-Sekai | [godot_motion_matching](https://github.com/V-Sekai/godot_motion_matching) | C++ | 2024-02-01 | Pre-release port of https://github.com/Remi123/MotionMatching to a C++ module |
| V-Sekai | [root-motion-extractor](https://github.com/V-Sekai/root-motion-extractor) | GDScript | 2023-02-14 | Custom post-import script functions and template for Godot for extracting specific root motion data from hips into skeleton |

### 8. Face and voice

Scales by: learned.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-fire | [interactor-headfit](https://github.com/V-Sekai-fire/interactor-headfit) | C++ | 2026-11-03 | The head fit as a godot-sandbox guest: the ANNY head fit and the unified-expression transfer |
| V-Sekai-fire | [interactor-voice](https://github.com/V-Sekai-fire/interactor-voice) | C++ | 2026-11-02 | Voice as sequenced Opus packets in a godot-sandbox guest |
| chibifire-stages | [mfcc-viseme-gan](https://github.com/chibifire-stages/mfcc-viseme-gan) | Python | 2021-01-20 |  |
| chibifire-stages | [visemenet-data](https://github.com/chibifire-stages/visemenet-data) |  | 2022-08-12 |  |
| chibifire-stages | [SK_VRM1_Constraint_Twist_Sample](https://github.com/chibifire-stages/SK_VRM1_Constraint_Twist_Sample) |  | 2026-10-05 |  |

### 9. Persona

Scales by: HTN / RECTGTN search over an authored domain.

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-fire | [interactor-taskweft-persona](https://github.com/V-Sekai-fire/interactor-taskweft-persona) | Lean | 2026-11-02 | A persona that answers from a planning domain instead of a neural network: a domain and a goal in, an exact plan out. |
| V-Sekai-archive | [interactor-taskweft-nmm-personas](https://github.com/V-Sekai-archive/interactor-taskweft-nmm-personas) | Elixir | 2026-10-24 | IEC 60848 GRAFCET personas playing Neural MMO 2 over 2-contract/bus, with MaskScore traces. |
| V-Sekai-fire | [interactor-a2a](https://github.com/V-Sekai-fire/interactor-a2a) | Lean | 2026-10-30 | Agent2Agent (A2A) v1.0 server in Lean 4: Agent Card, JSON-RPC, HTTP/1.1 with bearer token |
| V-Sekai-archive | [weftspun-character-taxonomy](https://github.com/V-Sekai-archive/weftspun-character-taxonomy) | Elixir | 2026-10-24 | RFD 0065 character taxonomy: headless-CMS JSON route, static randomizer page, MCP server. |
| V-Sekai-archive | [interactor-taskweft-mmog-agent](https://github.com/V-Sekai-archive/interactor-taskweft-mmog-agent) | Elixir | 2026-10-18 | ArtifactsMMO Multiplayer Fabric agent — HTN planning (Taskweft) + ex_ratatui TUI |
| V-Sekai-fire | [interactor-xr-pilot](https://github.com/V-Sekai-fire/interactor-xr-pilot) | C++ | 2026-10-25 | Lets an AI agent see and drive OpenXR apps |
| chibifire-stages | [persona-fire](https://github.com/chibifire-stages/persona-fire) |  | 2023-12-17 |  |

### 10. Runtime

Scales by: compute substrate (RISC-V guests, ggml on RenderingDevice).

| owner | repo | lang | pushed | description |
|---|---|---|---|---|
| V-Sekai-fire | [contract-ggml-rd](https://github.com/V-Sekai-fire/contract-ggml-rd) | C++ | 2026-11-03 | ggml's backend on Godot's RenderingDevice for godot-sandbox guests: Lean-emitted kernels, a CPU fallback, L2 and graph oracles |
| V-Sekai-archive | [contract-command](https://github.com/V-Sekai-archive/contract-command) | C | 2026-10-24 | The interactor contract: a command in, reply bytes out, and nothing about how it arrived. What interactors and transports compose against, s |
| V-Sekai-fire | [interactor-usd-guest](https://github.com/V-Sekai-fire/interactor-usd-guest) | C++ | 2026-11-03 |  |
| V-Sekai-archive | [weftspun-usd-viewer](https://github.com/V-Sekai-archive/weftspun-usd-viewer) | JavaScript | 2026-10-24 | usd_viewer_app: static server for the RFD 0073 billboard gallery's usd-viewer WASM build, its own Fly deploy target. |
| V-Sekai | [godot-vrm](https://github.com/V-Sekai/godot-vrm) | GDScript | 2026-07-08 | Importer/Exporter for VRM avatars and MToon shader. Available for Godot 4.1+ and 3.2+ in the Asset Library. |
| V-Sekai | [entities-model-explorer](https://github.com/V-Sekai/entities-model-explorer) | GDScript | 2026-10-28 | 🌟 View models, materials & animations. Quick texture view & wireframe mode. Supports .vrm, .glb, .gltf, .fbx. |
| V-Sekai | [godot-usd](https://github.com/V-Sekai/godot-usd) | GDScript | 2025-11-24 |  |
| V-Sekai | [v-sekai-game](https://github.com/V-Sekai/v-sekai-game) | GDScript | 2026-07-21 | Open-source VR socials |
| fire | [lean-gltf](https://github.com/fire/lean-gltf) | Lean | 2026-06-18 | A dependency-free Lean 4 library for building and serializing glTF 2.0 / GLB 3D assets |

## Interchange

OpenUSD between stages (UsdSkel sublayer from the auto-rig), glTF/VRM to the game, ZStandard parquet for corpora, `contract-command` bytes between guests. Weights and corpora live on Hugging Face under `chibifire/*`.

## Refreshing

`docs/repo-inventory.md` names the five list endpoints and the keyword regex; 19 unauthenticated calls refresh it. The survey reads names and descriptions only, not READMEs.

## Licence

MIT
