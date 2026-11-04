# Token inventory

The ledger's rule: a token is a substrate, the thing a failure takes down with it, not a feature. The org spends two innovation tokens: guest ELFs on the pinned double engine (Token 1) and one store, SQLite with its pages in FoundationDB (Token 2). Boring technology is `Stock` or `Already paid`; a capability is what the server lets a caller do and what guards it. One row per substrate or capability in this repository.

## Innovation tokens

| Row | Substrate | Status | Why, and what fails with it |
| --- | --- | --- | --- |
| Store | SQLite through `c/sql.c`; pages in FoundationDB when `FRONTIER_VFS_EXT` loads datasource-store's `libweftfdb` | Token 2 | The one store. Traces and knowledge live there; the knowledge seed is the only thing that survives it. |
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
| DigitalOcean `s-1vcpu-2gb` | the box, $12.00/mo | Stock | A supplier, not a substrate. |
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
| stage:character-1 (look-dev) | — | token:omnigen2-editscore7b-v1.1, token:interactor-see-through-ggml, token:interactor-omnigen2-editscore-space |
| stage:character-2 (image-to-3d) | stage:character-1 | token:interactor-trellis2-image-to-textured-mesh, token:contract-orbit-views |
| stage:character-3 (body) | stage:character-2 | token:interactor-anny-fit, token:interactor-headfit, token:contract-anny-kernels |
| stage:character-4 (gpu-skin) | stage:character-3 | token:interactor-skintokens-auto-rig, token:interactor-skintokens-guest, token:interactor-cage, token:contract-ggml-rd |
| stage:character-5 (garments) | stage:character-4 | token:interactor-p3sam-mesh-segmentation, token:interactor-remesh, token:interactor-garment-fit, token:interactor-cloth-fit-guest, token:interactor-drape, token:interactor-bake |
| stage:character-6 (look-render) | stage:character-2, stage:character-5 | token:interactor-slughorn, token:thorvg |
| stage:character-7 (gpu-motion) | stage:character-4 | token:interactor-kimodo-text-to-motion, token:interactor-motion-retarget, token:interactor-motion-matching-guest |
| stage:character-8 (face-voice) | stage:character-3, stage:character-4 | token:interactor-headfit, token:mfcc-viseme-gan, token:interactor-voice |
| stage:character-9 (persona) | stage:character-8 | token:interactor-taskweft-persona, token:interactor-a2a, token:weftspun-character-taxonomy |
| stage:character-10 (runtime) | stage:character-6, stage:character-7, stage:character-8, stage:character-9 | token:contract-ggml-rd, token:contract-command, token:interactor-usd-guest, token:godot-vrm |
| stage:prop-1 (look-dev) | — | token:omnigen2-editscore7b-v1.1, token:interactor-see-through-ggml, token:interactor-omnigen2-editscore-space |
| stage:prop-2 (image-to-3d) | stage:prop-1 | token:interactor-trellis2-image-to-textured-mesh, token:contract-orbit-views |
| stage:prop-4 (gpu-skin) | — | token:interactor-skintokens-auto-rig, token:interactor-skintokens-guest, token:interactor-cage, token:contract-ggml-rd |
| stage:prop-6 (look-render) | stage:prop-2 | token:interactor-slughorn, token:thorvg |
| stage:prop-7 (gpu-motion) | stage:prop-4 | token:interactor-kimodo-text-to-motion, token:interactor-motion-retarget, token:interactor-motion-matching-guest |
| stage:prop-10 (runtime) | stage:prop-6, stage:prop-7 | token:contract-ggml-rd, token:contract-command, token:interactor-usd-guest, token:godot-vrm |
| stage:world-1 (look-dev) | — | token:omnigen2-editscore7b-v1.1, token:interactor-see-through-ggml, token:interactor-omnigen2-editscore-space |
| stage:world-2 (image-to-3d) | stage:world-1 | token:interactor-trellis2-image-to-textured-mesh, token:contract-orbit-views |
| stage:world-4 (gpu-skin) | — | token:interactor-skintokens-auto-rig, token:interactor-skintokens-guest, token:interactor-cage, token:contract-ggml-rd |
| stage:world-6 (look-render) | stage:world-2 | token:interactor-slughorn, token:thorvg |
| stage:world-7 (gpu-motion) | stage:world-4 | token:interactor-kimodo-text-to-motion, token:interactor-motion-retarget, token:interactor-motion-matching-guest |
| stage:world-10 (runtime) | stage:world-6, stage:world-7 | token:contract-ggml-rd, token:contract-command, token:interactor-usd-guest, token:godot-vrm |

### Tuples: tokens (`acquire-token-<repo>` is the verb; the object is the repository, a row of the two tables above)

| object | class | acquired by |
| --- | --- | --- |
| token:contract-anny-kernels | Token 1 (Lean→Slang kernels) | subject:character |
| token:contract-command | Token 1 (guest contract) | subject:character, subject:prop, subject:world |
| token:contract-ggml-rd | Token 1 (guest substrate) | subject:character, subject:prop, subject:world |
| token:contract-orbit-views | boring (standard) | subject:character, subject:prop, subject:world |
| token:godot-vrm | boring (stock addon) | subject:character, subject:prop, subject:world |
| token:interactor-a2a | already paid (A2A library) | subject:character |
| token:interactor-anny-fit | Token 1 (guest) | subject:character |
| token:interactor-bake | Token 1 (guest) | subject:character |
| token:interactor-cage | Token 1 (guest) | subject:character, subject:prop, subject:world |
| token:interactor-cloth-fit-guest | Token 1 (guest, GPU only) | subject:character |
| token:interactor-drape | Token 1 (guest) | subject:character |
| token:interactor-garment-fit | Token 1 (guest) | subject:character |
| token:interactor-headfit | Token 1 (guest) | subject:character |
| token:interactor-kimodo-text-to-motion | innovation (model image) | subject:character, subject:prop, subject:world |
| token:interactor-motion-matching-guest | Token 1 (guest) | subject:character, subject:prop, subject:world |
| token:interactor-motion-retarget | already paid (Lean) | subject:character, subject:prop, subject:world |
| token:interactor-omnigen2-editscore-space | boring (static Space) | subject:character, subject:prop, subject:world |
| token:interactor-p3sam-mesh-segmentation | innovation (model image, licence pending) | subject:character |
| token:interactor-remesh | Token 1 (guest) | subject:character |
| token:interactor-see-through-ggml | innovation (ggml guest) | subject:character, subject:prop, subject:world |
| token:interactor-skintokens-auto-rig | innovation (model image) | subject:character, subject:prop, subject:world |
| token:interactor-skintokens-guest | Token 1 (guest) | subject:character, subject:prop, subject:world |
| token:interactor-slughorn | innovation (Slug vector renderer) | subject:character, subject:prop, subject:world |
| token:interactor-taskweft-persona | already paid (planner) | subject:character |
| token:interactor-trellis2-image-to-textured-mesh | innovation (model image) | subject:character, subject:prop, subject:world |
| token:interactor-usd-guest | Token 1 (guest) | subject:character, subject:prop, subject:world |
| token:interactor-voice | Token 1 (guest) | subject:character |
| token:mfcc-viseme-gan | innovation (archived model) | subject:character |
| token:omnigen2-editscore7b-v1.1 | innovation (image model, HF weights) | subject:character, subject:prop, subject:world |
| token:thorvg | boring (stock) | subject:character, subject:prop, subject:world |
| token:weftspun-character-taxonomy | boring (Elixir service) | subject:character |

### Tuples: the node and the store

```
store:sqlite-fdb#writer@node:frontier
node:frontier#http_caller@anyone               # 127.0.0.1 by default; --host 0.0.0.0 in the container
node:frontier#erlang_peer@cookie_holder:*       # --cookie, --cookie-file, or ~/.erlang.cookie
```

Three gaps read straight off the schema: `http_caller` is `anyone`, so `learn` and `experience` have no stronger guard than the socket; the Erlang side has one credential, the cookie; and nothing distinguishes a reporter (the owning repository's CI) from a reader.
