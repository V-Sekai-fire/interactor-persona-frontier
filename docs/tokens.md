# Token inventory

The ledger's rule: a token is a substrate, the thing a failure takes down with it, not a feature. The org spends two innovation tokens: guest ELFs on the pinned double engine (Token 1) and one store, SQLite with its pages in FoundationDB (Token 2). Boring technology is `Stock` or `Already paid`; a capability is what the server lets a caller do and what guards it. One row per substrate or capability in this repository.

## Innovation tokens

| Row | Substrate | Status | Why, and what fails with it |
| --- | --- | --- | --- |
| Store | SQLite (vendored amalgamation) through `c/sql.c`; datasource-store's `fdb_vfs.c` linked in with `-Kfdb`, pages in FoundationDB | Token 2 | The one store. Traces and knowledge live there; the knowledge seed is the only thing that survives it. Smoke-tested 2026-11-04: a practice trace read back from `weft/db/frontier/DELTA/` by `fdbcli`, no local file. |
| Planner | `interactor-taskweft-persona` (RECTGTN over JSON-LD) as a Lean library | Already paid | The same Lean toolchain and planner Token 1's guests pay for; here as a host library, no guest ELF. |
| Erlang node in Lean | `Frontier/Dist.lean`: EPMD ALIVE2, the v6 handshake, pass-through ETF, REG_SEND in, SEND out | **Not spent, and the ledger has no third token** | A hand-rolled distribution peer. Its failure takes down every Elixir caller of the node. The boring substitute is a BEAM-side port or `erl_interface` C node; this row is the one to retire or to claim against a token before a rung pins it. |
| MD5 in Lean | `Frontier/Md5.lean`, for the handshake digest only | Not spent (part of the row above) | Dies with the Erlang-node row. A shim over libcrypto is the stock route if the row stays. |
| HTTP server | `Std.Http` from the Lean toolchain | Already paid | The A2A library already serves on it. |

## Boring technology

| Row | What | Status | Notes |
| --- | --- | --- | --- |
| BEAM | Elixir for `build.exs`, PropCheck/PropEr in `test/node` | Stock | Tools and gates only; nothing ships into the product. |
| epmd | Erlang's port mapper, from the Erlang install | Stock | The node registers with it; the container starts it. |
| SQLite | libsqlite3 from Homebrew or the distro | Stock | Linked by the shim. |
| C | one 60-line shim (`c/sql.c`) | Stock | Where a C ABI is unavoidable. |
| elan, lake | Lean toolchain management, pinned by `lean-toolchain` | Already paid | |
| k6 | `deploy/k6.js`, the challenge's thresholds | Stock | The measurement tool, not shipped. |
| cloud-init, systemd | `deploy/cloud-init.yaml` | Stock | |
| AlmaLinux 10 container | `Containerfile`, two stages | Stock | |
| DigitalOcean `s-1vcpu-2gb` | the box, $12.00/mo; one box is one cell (`deploy/pod.exs`): FoundationDB 0.45 cpu/1024 MiB, node 0.45/768, epmd 0.10/64, constant; more capacity is more cells | Stock | A supplier, not a substrate. |
| GitHub Actions | `.github/workflows/node.yml` | Stock | Blocked by billing on this private repo. |
| JSON-LD | the domain, problem and plan documents | Already paid | The persona's own interchange. |

## Capabilities, as relationships

Capability tokens are the planner's actions, and an action is a verb between a subject and an object. Boring and innovation tokens are the subjects and objects; a relationship tuple is `object#verb@subject`, and a permission is a verb computed from other relationships, in the Zanzibar shape. The schema below is the RECTGTN domain read as a ReBAC schema; the tuples are generated from `knowledge/knowledge.json`.

```
definition subject {}                      # character, prop, world
definition token {                         # a repository the pipeline draws on (a boring or innovation token)
  relation acquired: subject
  permission acquire = nil                 # action acquire-token-<repo>: anyone planning for the subject
}
definition stage {                         # <subject>-<N>
  relation owner: subject
  relation requires: stage
  relation draws_on: token
  relation settled: subject
  permission settle = requires->settled & draws_on->acquired   # action settle-<subject>-<N>
  permission reach = settled | settle                           # method reach-<subject>-<N>: held, else settle
}
definition store {                         # Token 2: SQLite, pages in FoundationDB
  relation writer: node
  permission record = writer           # a trace
  permission learn = writer            # knowledge, after the gate
}
definition node {                          # the frontier process
  relation http_caller: anyone         # loopback by default; no bearer token
  relation erlang_peer: cookie_holder  # the distribution cookie
  permission plan = http_caller | erlang_peer
  permission practice = http_caller | erlang_peer
  permission experience = http_caller | erlang_peer
  permission learn = http_caller | erlang_peer   # gated: positive and negative control
}
```

### Tuples: stages (`settle-<subject>-N` needs every `requires` settled and every `draws_on` acquired)

| object | requires (stage#settled) | draws_on (token#acquired) |
| --- | --- | --- |
| stage:world-1 (look-dev) | — | token:omnigen2-editscore7b-v1.1, token:interactor-omnigen2-editscore-space |
| stage:world-2 (image-to-3d) | stage:world-1 | token:interactor-trellis2-image-to-textured-mesh, token:contract-orbit-views |
| stage:world-4 (gpu-skin) | — | token:interactor-skintokens-auto-rig, token:interactor-skintokens-guest, token:interactor-cage, token:contract-ggml-rd |
| stage:world-6 (look-render) | stage:world-2 | token:interactor-slughorn, token:thorvg |
| stage:world-7 (gpu-motion) | stage:world-4 | token:interactor-kimodo-text-to-motion, token:interactor-motion-retarget, token:interactor-motion-matching-guest |
| stage:world-10 (runtime) | stage:world-6, stage:world-7 | token:contract-ggml-rd, token:contract-command, token:interactor-usd-guest, token:godot-vrm |
| stage:prop-1 (look-dev) | — | token:omnigen2-editscore7b-v1.1, token:interactor-omnigen2-editscore-space |
| stage:prop-2 (image-to-3d) | stage:prop-1 | token:interactor-trellis2-image-to-textured-mesh, token:contract-orbit-views |
| stage:prop-4 (gpu-skin) | — | token:interactor-skintokens-auto-rig, token:interactor-skintokens-guest, token:interactor-cage, token:contract-ggml-rd |
| stage:prop-6 (look-render) | stage:prop-2 | token:interactor-slughorn, token:thorvg |
| stage:prop-7 (gpu-motion) | stage:prop-4 | token:interactor-kimodo-text-to-motion, token:interactor-motion-retarget, token:interactor-motion-matching-guest |
| stage:prop-10 (runtime) | stage:prop-6, stage:prop-7 | token:contract-ggml-rd, token:contract-command, token:interactor-usd-guest, token:godot-vrm |
| stage:character-1 (look-dev) | — | token:omnigen2-editscore7b-v1.1, token:interactor-omnigen2-editscore-space |
| stage:character-2 (image-to-3d) | stage:character-1 | token:interactor-trellis2-image-to-textured-mesh, token:contract-orbit-views |
| stage:character-3 (body) | stage:character-2 | token:interactor-anny-fit, token:interactor-headfit, token:contract-anny-kernels |
| stage:character-4 (gpu-skin) | stage:character-3 | token:interactor-skintokens-auto-rig, token:interactor-skintokens-guest, token:interactor-cage, token:contract-ggml-rd |
| stage:character-5 (garments) | stage:character-4 | token:interactor-p3sam-mesh-segmentation, token:interactor-remesh, token:interactor-garment-fit, token:interactor-cloth-fit-guest, token:interactor-drape, token:interactor-bake |
| stage:character-6 (look-render) | stage:character-2, stage:character-5 | token:interactor-slughorn, token:thorvg |
| stage:character-7 (gpu-motion) | stage:character-4 | token:interactor-kimodo-text-to-motion, token:interactor-motion-retarget, token:interactor-motion-matching-guest |
| stage:character-8 (face-voice) | stage:character-3, stage:character-4 | token:interactor-headfit, token:mfcc-viseme-gan, token:interactor-voice |
| stage:character-9 (persona) | stage:character-8 | token:interactor-taskweft-persona, token:interactor-a2a, token:weftspun-character-taxonomy |
| stage:character-10 (runtime) | stage:character-6, stage:character-7, stage:character-8, stage:character-9 | token:contract-ggml-rd, token:contract-command, token:interactor-usd-guest, token:godot-vrm |

### Tuples: tokens (`acquire-token-<repo>` is the verb; the object is the repository)

| object | class | acquired by |
| --- | --- | --- |
| token:contract-anny-kernels | Token 1 (Lean→Slang kernels) | subject:character |
| token:contract-command | Token 1 (guest contract) | subject:world, subject:prop, subject:character |
| token:contract-ggml-rd | Token 1 (guest substrate) | subject:world, subject:prop, subject:character |
| token:contract-orbit-views | boring (standard) | subject:world, subject:prop, subject:character |
| token:godot-vrm | boring (stock addon) | subject:world, subject:prop, subject:character |
| token:interactor-a2a | already paid (A2A library) | subject:character |
| token:interactor-anny-fit | Token 1 (guest) | subject:character |
| token:interactor-bake | Token 1 (guest) | subject:character |
| token:interactor-cage | Token 1 (guest) | subject:world, subject:prop, subject:character |
| token:interactor-cloth-fit-guest | Token 1 (guest, GPU only) | subject:character |
| token:interactor-drape | Token 1 (guest) | subject:character |
| token:interactor-garment-fit | Token 1 (guest) | subject:character |
| token:interactor-headfit | Token 1 (guest) | subject:character |
| token:interactor-kimodo-text-to-motion | innovation (model image) | subject:world, subject:prop, subject:character |
| token:interactor-motion-matching-guest | Token 1 (guest) | subject:world, subject:prop, subject:character |
| token:interactor-motion-retarget | already paid (Lean) | subject:world, subject:prop, subject:character |
| token:interactor-omnigen2-editscore-space | boring (static Space) | subject:world, subject:prop, subject:character |
| token:interactor-remesh | Token 1 (guest) | subject:character |
| token:interactor-skintokens-auto-rig | innovation (model image) | subject:world, subject:prop, subject:character |
| token:interactor-skintokens-guest | Token 1 (guest) | subject:world, subject:prop, subject:character |
| token:interactor-slughorn | innovation (Slug vector renderer) | subject:world, subject:prop, subject:character |
| token:interactor-taskweft-persona | already paid (planner) | subject:character |
| token:interactor-trellis2-image-to-textured-mesh | innovation (model image) | subject:world, subject:prop, subject:character |
| token:interactor-usd-guest | Token 1 (guest) | subject:world, subject:prop, subject:character |
| token:interactor-voice | Token 1 (guest) | subject:character |
| token:interactor-p3sam-mesh-segmentation | innovation (model image; licence review pending) | subject:character |
| token:sherpa-onnx-zipformer | boring (streaming Zipformer transducer on CPU via sherpa-onnx; replaces mfcc-viseme-gan) | subject:character |
| token:silero-vad | boring (speech gate ahead of the recognizer) | subject:character |
| token:omnigen2-editscore7b-v1.1 | innovation (image model, HF weights; replaces interactor-see-through-ggml) | subject:world, subject:prop, subject:character |
| token:thorvg | boring (stock) | subject:world, subject:prop, subject:character |
| token:weftspun-character-taxonomy | boring (Elixir service) | subject:character |

### Tuples: the node and the store

```
store:sqlite-fdb#writer@node:frontier
node:frontier#http_caller@anyone               # 127.0.0.1 by default; --host 0.0.0.0 in the container
node:frontier#erlang_peer@cookie_holder:*       # --cookie, --cookie-file, or ~/.erlang.cookie
```

Three gaps read straight off the schema: `http_caller` is `anyone`, so `learn` and `experience` have no stronger guard than the socket; the Erlang side has one credential, the cookie; and nothing distinguishes a reporter (the owning repository's CI) from a reader.

## Language models, as tokens

Every model is a token too: weights are a substrate whose licence, size and host decide what can be shipped. Collected from this desk's skills, facts and the stack grading, not from a repository scan; a row without a repository is a model we run as a tool or a judge.

| token | kind | where it stands | class |
| --- | --- | --- | --- |
| OmniGen2/OmniGen2-EditScore7B-v1.1 | image generation + edit, EditScore reward head | stage 1 image model and judge (operator, 2026-11-04) | innovation, in the product path |
| EditScore-7B | pairwise image-edit judge | the MaskScore / EditScore ladders; `vlm-image-scoring` (Qwen3-VL-4B LoRA head) runs it locally | boring: a gate |
| LLaDA-o | diffusion LM, image edit | logbook: beats OmniGen2 on one subject_remove pair at 14× wall, n=1 | not spent; parked |
| TRELLIS2, Pixal3D | image → textured mesh (PBR) | stage 2 model images; Pixal3D as a ggml-rd guest (RFD 2336) | innovation |
| DINOv3, BiRefNet HR | encoder, matting | inside the Pixal3D guest (RFD 2336) | already paid with Pixal3D |
| SkinTokens (TokenRig) | auto-rig | stage 4 model image; logbook: first forward pass | innovation |
| P3-SAM | mesh segmentation | stage 5 model image; Tencent licence review pending (replacement rescinded 2026-11-04) | innovation |
| Kimodo, MotionBricks | text → motion, motion on ggml-rd | stage 7 model images and guest | innovation |
| Zipformer (streaming transducer, sherpa-onnx) | speech → phoneme posteriors, CPU, ~5–10 ms per 160 ms chunk | stage 8 (operator, 2026-11-04): replaces mfcc-viseme-gan; phonemes map to the viseme set, EMA α≈0.65 over a 2-frame lookahead, 150–210 ms end to end | boring: ONNX on CPU, off the GPU the renderer holds |
| Silero VAD | speech gate | stage 8, ahead of Zipformer so ambient noise never twitches the mouth | boring |
| XLS-R | speech encoder | considered for stage 8 and rejected: bidirectional attention and memory footprint miss the 150 ms budget | not spent |
| mfcc-viseme-gan, visemenet | speech → viseme | stage 8, archived 2021–22 models; replaced by Zipformer | retired |
| Bonsai 27B | language model | `bonsai-steamframe-vulkan`, `ninfer-bonsai-artifacts`: a serving target, frozen weights in the Alyx planner hypothesis | boring: a tool, not in the product |
| Qwen3.5-27B (turboquant, Hermes) | language model | `turboquant-qwen35-27b`: local server on this desk | boring: a tool |
| Gemma (ASR track) | speech recognition | logbook RFD 1171 rerank; RFD 2180 dropped the gemma-auto track | retired |
| CycleGAN style transfer | image restyle | stage 1; retired by the OmniGen2 decision | retired |
| interactor-see-through-ggml | anime cel layer decomposition | stage 1; retired by the OmniGen2 decision | retired |
| The persona (RECTGTN) | not a model: an exact planner | the thing this repository serves; no weights | already paid |
