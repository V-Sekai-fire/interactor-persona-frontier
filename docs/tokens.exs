# The token ledger of interactor-persona-frontier, as an Elixir DSL.
#
#   elixir docs/tokens.exs            prints the schema and every tuple, and checks that each
#                                     stage's draws_on names a declared token (exit 1 otherwise)
#
# The ledger's rule: a token is a substrate, the thing a failure takes down with it, not a feature.
# Boring and innovation tokens are the subjects and objects; capability tokens are the planner's
# actions, and an action is a verb between a subject and an object. A relationship tuple is
# `object#verb@subject`, a permission is a verb computed from other relationships (Zanzibar shape),
# and the RECTGTN domain read that way is the schema. Statuses: :token_1 (guest ELFs on the pinned
# double engine), :token_2 (one store, SQLite with pages in FoundationDB), :paid (the same substrate
# as a token, counted once), :boring, :not_spent, :retired.

defmodule Ledger do
  defmacro __using__(_), do: quote(do: import Ledger)

  defmacro ledger(do: block) do
    quote do
      Module.register_attribute(__MODULE__, :rows, accumulate: true)
      unquote(block)
      def rows, do: Enum.reverse(@rows)
    end
  end

  defmacro token(name, status, note \\ nil), do: quote(do: @rows({:token, unquote(name), unquote(status), unquote(note)}))
  # params: parameters in billions; weights: the shipped weight files in GB (as published); bits:
  # average bits per parameter of that shipping (weights x 8 / params, or measured when given).
  # Two projections and no more: bf16 (params x 2 GB) is always reachable; 4-bit (params / 2 GB) is
  # sometimes reachable and is marked so. A model already below bf16 keeps its shipped size in both.
  defmacro model(name, status, note, sizes \\ []), do: quote(do: @rows({:model, unquote(name), unquote(status), unquote(note), unquote(sizes)}))
  defmacro subject(name, opts), do: quote(do: @rows({:subject, unquote(name), unquote(opts[:stages])}))
  defmacro stage(n, name, opts), do: quote(do: @rows({:stage, unquote(n), unquote(name), unquote(opts[:requires] || []), unquote(opts[:draws_on] || [])}))
  defmacro definition(name, do: block), do: quote(do: @rows({:definition, unquote(name), unquote(Macro.escape(block))}))
  defmacro tuple(object, verb, subj), do: quote(do: @rows({:tuple, unquote(object), unquote(verb), unquote(subj)}))
  defmacro gap(text), do: quote(do: @rows({:gap, unquote(text)}))
end

defmodule Frontier.Tokens do
  use Ledger

  ledger do
    # ---- innovation tokens: substrates this repository runs on
    token :store, :token_2, "SQLite (vendored amalgamation) through datasources/sqlite/sql.c; datasource-store's fdb_vfs.c linked in with -Kfdb, pages in FoundationDB. Smoke-tested 2026-11-04: a practice trace read back from weft/db/frontier/DELTA/, no local file."
    token :planner, :paid, "interactor-taskweft-persona (RECTGTN over JSON-LD) as a Lean library: the toolchain and planner Token 1's guests pay for, here as a host library"
    token :erlang_node_in_lean, :not_spent, "transports/Frontier/Dist.lean: EPMD ALIVE2, v6 handshake, pass-through ETF, REG_SEND in, SEND out. The ledger has no third token; retire or claim before a rung pins it. Boring substitute: a BEAM-side port or erl_interface C node."
    token :the_one_release, :not_spent, "one tag that carries engine, every guest ELF, every GGUF, the Bonsai 2 service and the planner node under one SHA256SUMS (docs/release.md). Today: ninfer-all windows-service-v1.0.0 (15 assets), transport-meshing-pen v20261002-dev.2 (11 assets, five guests), model-explorer (1 DMG), and twelve guest/model repositories with no release. This is the R&D; serving Bonsai 2 is done."
    token :md5_in_lean, :not_spent, "entities/Frontier/Md5.lean, the handshake digest only; dies with :erlang_node_in_lean"
    token :http_server, :paid, "Std.Http from the Lean toolchain"

    # ---- boring technology
    token :beam, :boring, "Elixir for build.exs, deploy/pod.exs, PropCheck in transports/spec/node; tools and gates only"
    token :epmd, :boring, "Erlang's port mapper; runs beside the node in the pod from erlang:27-alpine"
    token :c_shim, :boring, "one 60-line shim, datasources/sqlite/sql.c"
    token :elan_lake, :paid, "pinned by lean-toolchain"
    token :cloud_init_systemd, :boring, "deploy/cloud-init.yaml"
    token :almalinux_10_container, :boring, "Containerfile, two stages, FoundationDB client linked"
    token :digitalocean_s_1vcpu_2gb, :boring, "the box, $12.00/mo; one box is one cell (deploy/pod.exs): fdb 0.45 cpu/1024 MiB, node 0.45/768, epmd 0.10/64, constant; more capacity is more cells"
    token :github_actions, :boring, ".github/workflows/node.yml; blocked by billing on this private repo"
    token :json_ld, :paid, "the domain, problem and plan documents"


    # ---- language models and model images, as tokens
    model :omnigen2_editscore7b_v1_1, :innovation, "image generation + edit with the EditScore head; stage 1 model and judge (2026-11-04)", params: 7.7, weights: 31.3, source: "OmniGen2/OmniGen2 (4B DiT + Qwen2.5-VL-3B MLLM, stored fp32, 31.22 GB) + the v1.1 LoRA 0.08 GB"
    model :editscore_7b, :retiring, "pairwise image-edit judge (Qwen2.5-VL-7B + adapter). Bonsai 2 now answers in its shape too (docs/judge/score.py: {PF, SC, PQ, overall} on 0-25, preferred edit higher on 35/48, 0.875 excluding ties, source control PF 3.1); retires after the 350-pair comparison", params: 8.3, weights: 16.9, source: "Qwen2.5-VL-7B-Instruct 16.58 GB bf16 + adapter 0.32 GB"
    model :llada_o, :retired, "diffusion LM image edit; beat OmniGen2 on one pair at 14x wall, n=1; retired 2026-11-04, OmniGen2-EditScore7B-v1.1 is the image model", params: 8.0, weights: 16.0, source: "LLaDA-8B base 16.03 GB bf16; LLaDA-O-8B weights gated"
    model :trellis2, :innovation, "image to textured mesh, stage 2", params: 4.0, weights: 8.1, source: "microsoft/TRELLIS.2-4B: 1.3B img2shape + 1.3B imgshape2tex DiTs at one resolution plus encoders, bf16; repo 16.24 GB with both 512 and 1024 variants"
    model :pixal3d, :innovation, "image to PBR mesh as a ggml-rd guest (RFD 2336); DINOv3 and BiRefNet HR paid with it", params: 0.55, weights: 1.65, source: "DINOv3 ViT-L 0.3B 1.21 GB fp32 + BiRefNet HR 0.22B 0.44 GB; Pixal3D head not published"
    model :skintokens_tokenrig, :innovation, "auto-rig, stage 4; first forward pass logged", params: 0.62, weights: 1.25, source: "chibifire/SkinTokens-GGUF-BF16: tokenrig.gguf 0.95 + skin-vae.gguf 0.24 + mesh-encoder.gguf 0.06 GB, bf16"
    model :point_sam, :innovation, "coarse pass: promptable point-cloud segmentation, ViT-L encoder (SAM, Uni3D lineage), stage 5; its labels seed GeoSAM2; replaces P3-SAM (operator, 2026-11-04); no ggml port yet", params: 0.311, weights: 1.24, source: "yuchen0187/Point-SAM model.safetensors 1.24 GB, 311 M params, fp32"
    model :geosam2, :innovation, "fine pass, stage 5: SAM2 (Hiera image encoder + memory attention) on 12 rendered views, per-face labels by back-projection; the stock 2D SAM2 shape, so sam3.cpp-style ggml is the port path; prompted by the coarse labels", params: 0.155, weights: 0.62, source: "VAST-AI/GeoSAM2 geosam2.pt 0.62 GB fp32 (geosam2-bf16.pt 0.31 GB)"
    model :p3_sam, :retired, "mesh segmentation (Tencent Hunyuan3D-Part, Sonata backbone); replaced by Point-SAM over the licence", params: 0.11, weights: 0.45, source: "tencent/Hunyuan3D-Part p3sam.safetensors 0.45 GB (fp32)"
    model :kimodo_motionbricks, :innovation, "text to motion and motion on ggml-rd, stage 7", params: 8.65, weights: 17.04, source: "chibifire/Llama-3-Kimodo-GGML 15.18 GB (Llama-3-8B base, bf16, split per layer) + Kimodo-SOMA-RP-v1.1 0.283 B 1.13 GB + MotionBricks-G1-GGML 0.73 GB (pose 0.55, root 0.14, vq-decoder 0.05)"
    model :zipformer_sherpa_onnx, :boring, "Zipformer (Icefall/k2, trained with augmentation: SpecAugment and speed perturbation) exported to ONNX and run as a streaming transducer on CPU via sherpa-onnx, 5-10 ms per 160 ms chunk; phonemes to visemes, 2-frame EMA, 150-210 ms end to end; stage 8", params: 0.066, weights: 0.26, source: "streaming-zipformer-en-2023-06-26 encoder fp32 0.26 GB, int8 0.07 GB"
    model :silero_vad, :boring, "speech gate ahead of Zipformer", params: 0.0018, weights: 0.002, source: "onnx-community/silero-vad model.onnx"
    model :xls_r, :not_spent, "rejected for stage 8: bidirectional attention misses the 150 ms budget", params: 0.3, weights: 1.27, source: "facebook/wav2vec2-xls-r-300m fp32"
    model :mfcc_viseme_gan_visemenet, :retired, "stage 8, replaced by Zipformer", source: "small archived GAN; size unmeasured"
    model :bonsai_2_27b_heretic_v2, :boring, "OS-Software/Ternary-Bonsai-2-27B-Uncensored-Heretic-v2-GGUF: ternary Bonsai 2 with the Heretic OT-Ridge LoRA baked in (1/100 refusals, KL 0.0256), served by Prism llama.cpp or NInfer (RFD 2311, bonsai2-27b-heretic.ninfer); the local language model, a tool and a scorer, not in the product. Measured 2026-11-04 (docs/judge/): zero-shot pairwise judge 89/96 = 0.927 on 48 editreward-bench pairs, blind control 0.500, source-vs-edit 0.948; it is the stage-1 judge, and EditScore-7B leaves the rotation", params: 26.9, weights: 7.21, bits: 2.14, source: "PQ2_0 7.21 GB (2.14 bits/param), PTQ1_0 5.95 GB (1.77); the F16 original is 53.81 GB; mmproj Q8_0 0.63 GB"
    model :claude, :boring, "Anthropic Claude through Hermes: the agent that does this work; a tool, nothing of it ships", source: "parameter count and weights undisclosed by Anthropic; served, never downloaded"
    model :gemma_asr, :retired, "RFD 2180 dropped the gemma-auto track", source: "retired track; version and size not recorded"
    model :cyclegan_style_transfer, :retired, "stage 1, retired by the OmniGen2 decision", params: 0.011, weights: 0.045, source: "one ResNet generator, fp32"
    model :see_through_ggml, :retired, "anime cel layer decomposition, stage 1, retired by the OmniGen2 decision", source: "ggml guest; size unmeasured"
    model :persona_rectgtn, :paid, "not a model: the exact planner this repository serves", params: 0.0, weights: 0.0, source: "no weights"

    # ---- the schema: the RECTGTN domain read as ReBAC definitions (verbs are the planner's actions)
    definition :subject do
      # character, prop, world
    end
    definition :token do
      relation :acquired, :subject
      permission :acquire, nil                      # action acquire-token-<repo>
    end
    definition :stage do
      relation :owner, :subject
      relation :requires, :stage
      relation :draws_on, :token
      relation :settled, :subject
      permission :settle, {:and, {:arrow, :requires, :settled}, {:arrow, :draws_on, :acquired}}   # action settle-<subject>-N
      permission :reach, {:or, :settled, :settle}                                                    # method reach-<subject>-N
    end
    definition :store do
      relation :writer, :node
      permission :record, :writer
      permission :learn, :writer
    end
    definition :node do
      relation :http_caller, :anyone          # loopback by default; no bearer token
      relation :erlang_peer, :cookie_holder   # the distribution cookie
      permission :plan, {:or, :http_caller, :erlang_peer}
      permission :practice, {:or, :http_caller, :erlang_peer}
      permission :experience, {:or, :http_caller, :erlang_peer}
      permission :learn, {:or, :http_caller, :erlang_peer}   # gated: positive and negative control
    end

    # ---- subjects and stages, from entities/knowledge/knowledge.json
    subject :world, stages: ["1", "2", "4", "6", "7", "10"]
    subject :prop, stages: ["1", "2", "4", "6", "7", "10"]
    subject :character, stages: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
    stage 1, :"look-dev", requires: [], draws_on: [:omnigen2_editscore7b_v1_1, :interactor_omnigen2_editscore_space]
    stage 2, :"image-to-3d", requires: ["1"], draws_on: [:interactor_trellis2_image_to_textured_mesh, :contract_orbit_views]
    stage 3, :"body", requires: ["2"], draws_on: [:interactor_anny_fit, :interactor_headfit, :contract_anny_kernels]
    stage 4, :"gpu-skin", requires: ["3"], draws_on: [:interactor_skintokens_auto_rig, :interactor_skintokens_guest, :interactor_cage, :contract_ggml_rd]
    stage 5, :"garments", requires: ["4"], draws_on: [:point_sam, :geosam2, :interactor_remesh, :interactor_garment_fit, :interactor_cloth_fit_guest, :interactor_drape, :interactor_bake]
    stage 6, :"look-render", requires: ["2", "5"], draws_on: [:interactor_slughorn, :thorvg]
    stage 7, :"gpu-motion", requires: ["4"], draws_on: [:interactor_kimodo_text_to_motion, :interactor_motion_retarget, :interactor_motion_matching_guest]
    stage 8, :"face-voice", requires: ["3", "4"], draws_on: [:interactor_headfit, :sherpa_onnx_zipformer, :interactor_voice, :silero_vad]
    stage 9, :"persona", requires: ["8"], draws_on: [:interactor_taskweft_persona, :interactor_a2a, :weftspun_character_taxonomy]
    stage 10, :"runtime", requires: ["6", "7", "8", "9"], draws_on: [:contract_ggml_rd, :contract_command, :interactor_usd_guest, :godot_vrm]

    # ---- repository tokens the stages draw on (object, class, note)
    token :contract_anny_kernels, :token_1, "Lean to Slang kernels"
    token :contract_command, :token_1, "guest contract"
    token :contract_ggml_rd, :token_1, "guest substrate"
    token :contract_orbit_views, :boring, "standard"
    token :godot_vrm, :boring, "stock addon"
    token :interactor_a2a, :paid, "A2A library"
    token :interactor_anny_fit, :token_1, "guest"
    token :interactor_bake, :token_1, "guest"
    token :interactor_cage, :token_1, "guest"
    token :interactor_cloth_fit_guest, :token_1, "guest, GPU only"
    token :interactor_drape, :token_1, "guest"
    token :interactor_garment_fit, :token_1, "guest"
    token :interactor_headfit, :token_1, "guest"
    token :interactor_kimodo_text_to_motion, :innovation, "model image"
    token :interactor_motion_matching_guest, :token_1, "guest"
    token :interactor_motion_retarget, :paid, "Lean"
    token :interactor_omnigen2_editscore_space, :boring, "static Space"
    token :point_sam, :innovation, "zyc00/Point-SAM (ICLR 2025, MIT): promptable 3D segmentation on point clouds, mesh labels by sampling and propagation; replaces interactor-p3sam-mesh-segmentation (Tencent licence)"
    token :geosam2, :innovation, "VAST-AI-Research/GeoSAM2 (CVPR 2026, Apache-2.0): SAM2 lifted to meshes; 12 rendered colour, depth and normal views, a click or mask on one view propagates across views and back-projects to per-face labels, so quad faces keep their edge flow. Stage 5 fine pass over Point-SAM's coarse labels, ahead of remesh"
    token :interactor_remesh, :token_1, "guest"
    token :interactor_skintokens_auto_rig, :innovation, "model image"
    token :interactor_skintokens_guest, :token_1, "guest"
    token :interactor_slughorn, :innovation, "Slug vector renderer"
    token :interactor_taskweft_persona, :paid, "planner"
    token :interactor_trellis2_image_to_textured_mesh, :innovation, "model image"
    token :interactor_usd_guest, :token_1, "guest"
    token :interactor_voice, :token_1, "guest"
    token :omnigen2_editscore7b_v1_1, :innovation, "image model, HF weights; replaces interactor-see-through-ggml"
    token :sherpa_onnx_zipformer, :boring, "streaming Zipformer (Icefall/k2) transducer on CPU; replaces mfcc-viseme-gan"
    token :silero_vad, :boring, "speech gate ahead of the recognizer"
    token :thorvg, :boring, "stock"
    token :weftspun_character_taxonomy, :boring, "Elixir service"

    # ---- the node and the store
    tuple "store:sqlite-fdb", :writer, "node:frontier"
    tuple "node:frontier", :http_caller, "anyone"                 # 127.0.0.1 by default; --host 0.0.0.0 in the container
    tuple "node:frontier", :erlang_peer, "cookie_holder:*"        # --cookie, --cookie-file, or ~/.erlang.cookie

    gap "http_caller is anyone, so learn and experience have no stronger guard than the socket"
    gap "the Erlang side has one credential, the cookie"
    gap "nothing distinguishes a reporter (the owning repository's CI) from a reader"
  end
end

# ---- render: every stage tuple expands to object#verb@subject rows; a draws_on naming no token fails
rows = Frontier.Tokens.rows()
tokens = for {:token, n, _, _} <- rows, into: MapSet.new(), do: n
stages = for {:stage, n, name, req, draws} <- rows, do: {n, name, req, draws}
subjects = for {:subject, s, ss} <- rows, do: {s, ss}

IO.puts("# tokens")
for {:token, n, status, note} <- rows, do: IO.puts("token:#{n}  #{status}  #{note || ""}")
bf16 = fn sz -> p = sz[:params]; w = sz[:weights]; if p && w, do: min(w, p * 2.0), else: nil end
q4 = fn sz -> p = sz[:params]; w = sz[:weights]; if p && w, do: min(w, p / 2.0), else: nil end
IO.puts("\n# models  (params B · shipped GB · avg bits/param · at bf16 GB · at 4-bit GB, where reachable)")
fmt = fn
  nil -> "   ?  "
  x when is_float(x) -> :io_lib.format("~6.2f", [x]) |> to_string()
  x -> :io_lib.format("~6.2f", [x / 1]) |> to_string()
end
for {:model, n, status, note, sz} <- rows do
  p = sz[:params]; w = sz[:weights]
  bits = sz[:bits] || (if p && w && p > 0, do: w * 8 / p, else: nil)
  IO.puts("model:#{n}  #{status}  params #{fmt.(p)} B · shipped #{fmt.(w)} GB · #{fmt.(bits)} bits/param · bf16 #{fmt.(bf16.(sz))} GB · 4-bit #{fmt.(q4.(sz))} GB")
  IO.puts("    #{note}" <> if(sz[:source], do: "\n    sizes: #{sz[:source]}", else: ""))
end
# ---- what serving costs: the models a running pipeline must hold, as shipped
served = for {:model, n, st, _, sz} <- rows, st in [:innovation, :boring, :paid], sz[:weights] != nil, do: {n, sz}
tools = [:bonsai_2_27b_heretic_v2, :claude, :editscore_7b]          # scorer, agent, judge: run beside the pipeline, not in a player's path
{pipeline, beside} = Enum.split_with(served, fn {n, _} -> n not in tools end)
sum = fn xs, k -> xs |> Enum.map(fn {_, sz} -> sz[k] || 0 end) |> Enum.sum() end
sumf = fn xs, f -> xs |> Enum.map(fn {_, sz} -> f.(sz) || 0 end) |> Enum.sum() end
unmeasured = for {:model, n, st, _, sz} <- rows, st in [:innovation, :boring, :paid], sz[:weights] == nil, n != :claude, do: n
IO.puts("\n# total size to serve (GB)")
IO.puts("pipeline (stages 1-10, a player's path): shipped #{fmt.(sum.(pipeline, :weights))} GB · bf16 #{fmt.(sumf.(pipeline, bf16))} GB · 4-bit #{fmt.(sumf.(pipeline, q4))} GB · #{length(pipeline)} models")
IO.puts("beside it (judge, scorer):               shipped #{fmt.(sum.(beside, :weights))} GB · bf16 #{fmt.(sumf.(beside, bf16))} GB · 4-bit #{fmt.(sumf.(beside, q4))} GB")
IO.puts("everything measured:                     shipped #{fmt.(sum.(served, :weights))} GB · bf16 #{fmt.(sumf.(served, bf16))} GB · 4-bit #{fmt.(sumf.(served, q4))} GB")
IO.puts("not in the sum (unmeasured):             #{Enum.join(unmeasured, ", ")}")
IO.puts("the box: s-1vcpu-2gb has 50 GB SSD and 2 GB RAM, so no model in the pipeline runs on the cell; the cell serves plans, the models run where their GPU is")

# ---- residency on one RTX 4090 (24 GB): what stays, what rotates; shipped, at bf16 (always), at 4-bit (sometimes)
# Rule: the scorer and the planner stay resident; every stage model loads for its stage and
# unloads after (rotating residency). The budget per rotation is the largest stage, not the sum.
vram = 24.0
resident = [:bonsai_2_27b_heretic_v2]
stage_of = %{omnigen2_editscore7b_v1_1: 1, trellis2: 2, pixal3d: 2, skintokens_tokenrig: 4, point_sam: 5, geosam2: 5, kimodo_motionbricks: 7, zipformer_sherpa_onnx: 8, silero_vad: 8, editscore_7b: 1}
by_stage = served |> Enum.reject(fn {n, _} -> n in resident or stage_of[n] == nil end) |> Enum.group_by(fn {n, _} -> stage_of[n] end)
res_shipped = sum.(Enum.filter(served, fn {n, _} -> n in resident end), :weights)
IO.puts("\n# rotating residency on one 4090 (#{vram} GB)")
IO.puts("resident: #{Enum.join(resident, ", ")}  shipped #{fmt.(res_shipped)} GB  (plus the planner, no weights)")
for {st, ms} <- Enum.sort(by_stage) do
  fit = fn x -> if x + res_shipped + 2.0 <= vram, do: "fits", else: "DOES NOT FIT" end
  sh_ = sum.(ms, :weights); b = sumf.(ms, bf16); q = sumf.(ms, q4)
  IO.puts("stage #{st}: #{Enum.map_join(ms, ", ", &elem(&1, 0))}  shipped #{fmt.(sh_)} GB #{fit.(sh_)} · bf16 #{fmt.(b)} GB #{fit.(b)} · 4-bit #{fmt.(q)} GB #{fit.(q)}")
end
peak_sh = by_stage |> Enum.map(fn {_, ms} -> sum.(ms, :weights) end) |> Enum.max()
peak_b = by_stage |> Enum.map(fn {_, ms} -> sumf.(ms, bf16) end) |> Enum.max()
peak_q = by_stage |> Enum.map(fn {_, ms} -> sumf.(ms, q4) end) |> Enum.max()
IO.puts("peak rotation + resident + 2 GB activations: shipped #{fmt.(peak_sh + res_shipped + 2)} GB · bf16 #{fmt.(peak_b + res_shipped + 2)} GB · 4-bit #{fmt.(peak_q + res_shipped + 2)} GB  against #{vram} GB")

# ---- the same rotation once Bonsai 2 is the judge: EditScore-7B leaves stage 1
by_stage2 = Map.update(by_stage, 1, [], fn ms -> Enum.reject(ms, fn {n, _} -> n == :editscore_7b end) end)
peak = fn f -> by_stage2 |> Enum.map(fn {_, ms} -> sumf.(ms, f) end) |> Enum.max() end
s1 = by_stage2[1]
IO.puts("\n# the same rotation with Bonsai 2 trained as the judge (EditScore-7B out of stage 1)")
IO.puts("stage 1: #{Enum.map_join(s1, ", ", &elem(&1, 0))}  shipped #{fmt.(sum.(s1, :weights))} GB · bf16 #{fmt.(sumf.(s1, bf16))} GB #{if sumf.(s1, bf16) + res_shipped + 2 <= vram, do: "fits", else: "DOES NOT FIT"} · 4-bit #{fmt.(sumf.(s1, q4))} GB")
IO.puts("peak rotation + resident + 2 GB activations: bf16 #{fmt.(peak.(bf16) + res_shipped + 2)} GB · 4-bit #{fmt.(peak.(q4) + res_shipped + 2)} GB  against #{vram} GB; the bf16 peak is then Kimodo (stage 7), the one 4-bit that is still required")

IO.puts("\n# tuples")
missing =
  for {s, ss} <- subjects, {n, _name, req, draws} <- stages, Integer.to_string(n) in ss, reduce: [] do
    acc ->
      for r <- req, r in ss, do: IO.puts("stage:#{s}-#{n}#requires@stage:#{s}-#{r}")
      for d <- draws, do: IO.puts("stage:#{s}-#{n}#draws_on@token:#{d}")
      IO.puts("stage:#{s}-#{n}#owner@subject:#{s}")
      acc ++ Enum.reject(draws, &MapSet.member?(tokens, &1))
  end
for {:tuple, o, v, s} <- rows, do: IO.puts("#{o}##{v}@#{s}")
IO.puts("\n# gaps")
for {:gap, g} <- rows, do: IO.puts("- #{g}")

case Enum.uniq(missing) do
  [] -> IO.puts("\nOK: every draws_on names a declared token")
  m -> IO.puts(:stderr, "FAIL: draws_on without a token row: #{inspect(m)}"); System.halt(1)
end
