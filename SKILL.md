---
name: look-dev-character-persona-stack
description: "Use when placing character work (look dev, body, rig, garments, motion, face, persona, runtime) in our orgs, or grading a stage against the Bitter Lesson."
version: 0.1.0
author: "K. S. Ernest (iFire) Lee"
license: MIT
metadata:
  hermes:
    tags: [avatar, character, persona, look-dev, godot, anny, skintokens, bitter-lesson, v-sekai-fire]
    related_skills: [chibifire-smoke-water, github-org-study, avatar-garment-fitting, uv-patterns-avbd-drape, motion-matching]
---

# Look dev to game character-persona stack

Ten stages from a concept image to an in-game character that moves, speaks and is driven by an agent, each mapped to repositories in V-Sekai-fire, V-Sekai, V-Sekai-archive, chibifire-stages and fire. Each stage carries its scaling axis (search or learning), the hand-written knowledge that ships it today, and the trigger that retires that knowledge. The full table, data-flow diagram and verdict are in `references/stack.md`; the repository survey behind it is `references/repo-inventory.md`.

## When to use

- A task names a character stage (body fit, auto-rig, drape, retarget, viseme, persona) and needs the repository that owns it.
- A new model, solver or table is proposed for a stage: grade it with the three questions below before adding it.
- A survey of the five orgs is needed and the inventory here is older than the question; re-run the survey, do not reuse stale counts.

## The ten stages, one line each

| # | Stage | Owning repos | Scales by |
|---|---|---|---|
| 1 | Look dev | interactor-see-through-ggml, interactor-cyclegan-style-transfer, EditScore/MaskScore ladder | learned judge over N samples |
| 2 | Image to 3D | interactor-trellis2-/pixal3d-image-to-textured-mesh, contract-orbit-views, voxhammer edits | learned model, view voting |
| 3 | Body | interactor-anny-fit, interactor-headfit, contract-anny-kernels, entities-anny-creator, datasource-anny-render-corpus | L-BFGS search on GPU |
| 4 | Rig and skin | interactor-skintokens-guest / -rig / -auto-rig, interactor-cage, interactor-character-domain-c-abi | learned rig |
| 5 | Garments | interactor-p3sam-mesh-segmentation, -remesh, -garment-fit, -cloth-fit-guest, -drape, -bake | physics solve, GPU only |
| 6 | Materials | entities-godot-toon-shaders, contract-materialx-shaders-lean, godot-sheen-look-up-table | none (hand ports) |
| 7 | Motion | interactor-kimodo-text-to-motion, -motion-guest, -motion-retarget, -motion-matching-guest | learned clips, database search |
| 8 | Face and voice | interactor-headfit expression transfer, mfcc-viseme-gan, visemenet-data, interactor-voice | learned |
| 9 | Persona | interactor-taskweft-persona, interactor-taskweft-nmm-personas, interactor-a2a, interactor-multimodal-semantic-ids, weftspun-character-taxonomy | HTN search over an authored domain |
| 10 | Runtime | godot-sandbox guests, contract-command, contract-guest-common, contract-ggml-rd, interactor-usd-guest, godot-vrm, entities-model-explorer | compute substrate |

Interchange: OpenUSD between stages (UsdSkel sublayer from the auto-rig), glTF/VRM to the game, ZStandard parquet for corpora, `contract-command` bytes between guests. Weights and corpora on Hugging Face `chibifire/*`, code on GitHub.

## Grading a stage (the Bitter Lesson, applied)

Ask three questions of any component before it enters a stage:

1. **What grows when it gets more compute?** A learned model or a solver (search) qualifies. A lookup table, a hand-tuned parameter map or an authored rule set does not; it may ship, but it is marked as content to be replaced, with the replacement trigger written down.
2. **Does it compose with inference-time search?** Prefer components that can be sampled N times and scored by a learned judge (stage 1), voted across views (stage 2), or searched over a database (stage 7). Test-time compute is the second scaling axis.
3. **What is the binding constraint?** For stages 1, 2, 7 and 8 the limit is licensed data, not compute: the dataset blocklists, the blinded COCO holdout and the four generated-data conditions gate every corpus. The growth path there is constructed data from assets we hold (ANNY renders, orbit views), which is GPU-bound and allowed.

Current verdict: stages 1-5, 7, 8 and 10 are on the scaling path. ANNY (3) is hand-built but defensible as a cheap prior with a render corpus built to replace it. The toon shader map (6) has no scaling axis. The persona domain (9) is the exposed position: the planner is a general method, the domain is authored and plateaus; the MaskScore play traces in `interactor-taskweft-nmm-personas` are the material to induce domains from, and no repository does that yet.

## Standing rules that bind this stack

- Dual-quaternion skinning is blocklisted; Delta Mush and Direct Delta Mush are approved.
- glTF carries data only: weights, samplers, morph targets; no runtime modifiers or custom extensions.
- Rendered views use `sphere_hammersley_sequence`, never a hand-picked front view.
- Latents pass between stages; VAE decode once, at final output.
- Integration runs go to a GPU; the CPU runs unit tests with planted faults only.
- Writes land only in V-Sekai-fire (and the chibifire orgs); V-Sekai and V-Sekai-archive are read-only, and the App has no installation on V-Sekai-archive.

## Re-running the survey

`github-org-study` holds the procedure. Unauthenticated, the five owners cost 19 list calls (`/users/<o>/repos` for V-Sekai-fire and fire, `/orgs/<o>/repos` for the rest, 100 per page). Filter with the keyword regex in `references/repo-inventory.md`'s header, print one line per repo, and refresh `references/repo-inventory.md` in a `dev/*` branch. READMEs are not read by the survey; say so in anything derived from it.

## Gaps on record

- Stage 6 has no learned or searched component and no corpus to grow one.
- Stage 9's trace-to-domain induction has no repository.
- No end-to-end gate runs a photo through stages 1-10 into a loaded guest; per-stage probes exist (Gate 0G for usd.elf, the older web studio's `[API-Contract] PASS`).
- `chibifire-stages/persona-fire` (2023) has no description; its relation to `interactor-taskweft-persona` is unknown.
