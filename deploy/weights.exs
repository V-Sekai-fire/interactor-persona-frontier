#!/usr/bin/env elixir
# Every weight the pipeline runs, in one place, so one 4090 box can preload them and go offline.
#   elixir deploy/weights.exs list                 the table: repo, files, bytes, which are not yet on hf:chibifire
#   elixir deploy/weights.exs fetch <dir>          download everything into <dir>/<repo>/, resumable, then verify
#   elixir deploy/weights.exs verify <dir>         sha256 every file against the hub's LFS hash; exit 1 on any miss
#   elixir deploy/weights.exs self-test <dir>      verify must FAIL on a planted corrupt byte (the gate's control)
#
# Code is on GitHub; weights are on Hugging Face. The rule: every row is mirrored under hf:chibifire
# (the "home" column), so the fetch needs one token and one org and the upstream can vanish. Rows whose
# home is still the upstream org are the mirroring work left. Hashes come from the hub's LFS metadata at
# fetch time and are written to <dir>/SHA256SUMS; verify reads that file, so an offline box re-checks itself.
# The token comes from `bao-hf-token` (stdin), never argv. No raises: every step returns {:ok, _} | {:error, _}.

defmodule Weights do
  @rows [
    # {stage, name, home repo on hf, upstream repo, files (nil = every weight file), note}
    {1, :bonsai2_pq2_0, "OS-Software/Ternary-Bonsai-2-27B-Uncensored-Heretic-v2-GGUF", nil,
      ~w(Ternary-Bonsai-2-27B-Uncensored-Heretic-v2-PQ2_0.gguf mmproj-Q8_0.gguf), "resident: scorer and stage-1 judge; 7.2 + 0.6 GB; NOT yet mirrored to chibifire"},
    {1, :omnigen2, "chibifire/omnigen2-base-df5dca8a", "OmniGen2/OmniGen2", nil, "4B DiT + Qwen2.5-VL-3B, fp32 31.2 GB; mirrored"},
    {1, :omnigen2_editscore_lora, "OmniGen2/OmniGen2-EditScore7B-v1.1", nil, ~w(pytorch_lora_weights.safetensors), "0.08 GB; NOT yet mirrored"},
    {2, :trellis2, "chibifire/TRELLIS.2-4B", "microsoft/TRELLIS.2-4B", nil, "16.2 GB with both resolutions; mirrored"},
    {2, :dinov3_vitl16, "facebook/dinov3-vitl16-pretrain-lvd1689m", nil, ~w(model.safetensors), "Pixal3D encoder, 1.21 GB; NOT yet mirrored"},
    {2, :birefnet_hr, "ZhengPeng7/BiRefNet_HR", nil, ~w(model.safetensors), "Pixal3D matting, 0.44 GB; NOT yet mirrored"},
    {4, :skintokens, "chibifire/SkinTokens-GGUF-BF16", nil, nil, "tokenrig + skin-vae + mesh-encoder, 1.25 GB; chibifire is the home"},
    {5, :point_sam, "yuchen0187/Point-SAM", nil, ~w(model.safetensors), "coarse pass, ViT-L, 1.24 GB; NOT yet mirrored"},
    {5, :geosam2, "VAST-AI/GeoSAM2", nil, ~w(geosam2-bf16.pt), "fine pass on rendered views, bf16 0.31 GB; NOT yet mirrored"},
    {7, :kimodo_llama3, "chibifire/Llama-3-Kimodo-GGML", nil, nil, "8B body split per layer, 15.2 GB; chibifire is the home"},
    {7, :kimodo_soma, "chibifire/Kimodo-SOMA-RP-v1.1-gguf", nil, nil, "1.13 GB; chibifire is the home"},
    {7, :motionbricks, "chibifire/MotionBricks-G1-GGML", nil, nil, "0.73 GB; chibifire is the home"},
    {8, :zipformer_en, "csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26", nil,
      ~w(encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx decoder-epoch-99-avg-1-chunk-16-left-128.onnx joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx tokens.txt), "int8 streaming encoder; NOT yet mirrored"},
    {8, :silero_vad, "onnx-community/silero-vad", nil, ~w(onnx/model.onnx), "2 MB; NOT yet mirrored"},
  ]
  @weight ~r/\.(safetensors|gguf|onnx|bin|pt|pth|txt|json)$/

  # WEIGHTS_ONLY=silero_vad,zipformer_en limits a run to named rows (a smoke of the fetch, not a release)
  def rows do
    case System.get_env("WEIGHTS_ONLY") do
      nil -> @rows
      only -> names = only |> String.split(",") |> Enum.map(&String.to_atom/1); Enum.filter(@rows, fn {_, n, _, _, _, _} -> n in names end)
    end
  end
  def token do
    case System.cmd("bao-hf-token", [], stderr_to_stdout: true) do
      {t, 0} -> {:ok, t |> String.split("\n", trim: true) |> List.last() |> String.trim()}   # the helper prints a host line first
      {out, _} -> {:error, "no hf token: #{String.trim(out)}"}
    end
  end

  def listing(repo, tok) do
    url = "https://huggingface.co/api/models/#{repo}?blobs=true"
    case System.cmd("curl", ["-s", "-m", "60", "-H", "Authorization: Bearer #{tok}", url]) do
      {body, 0} ->
        case Jason.decode(body) do
          {:ok, %{"siblings" => s}} -> {:ok, Enum.map(s, &{&1["rfilename"], &1["size"] || 0, get_in(&1, ["lfs", "sha256"])})}
          {:ok, %{"error" => e}} -> {:error, "#{repo}: #{e}"}
          _ -> {:error, "#{repo}: unreadable listing"}
        end
      {out, _} -> {:error, "#{repo}: curl #{String.slice(out, 0, 80)}"}
    end
  end

  def wanted({_, _, repo, _, files, _}, tok) do
    with {:ok, all} <- listing(repo, tok) do
      pick = if files, do: Enum.filter(all, fn {f, _, _} -> f in files end), else: Enum.filter(all, fn {f, _, _} -> f =~ @weight end)
      missing = if files, do: files -- Enum.map(pick, &elem(&1, 0)), else: []
      if missing == [], do: {:ok, pick}, else: {:error, "#{repo}: not on the hub: #{inspect(missing)}"}
    end
  end

  def list do
    with {:ok, tok} <- token() do
      IO.puts("stage  model                    home                                                          files      GB  mirrored")
      total = Enum.reduce(rows(), 0, fn {st, name, repo, _, _, _} = row, acc ->
        case wanted(row, tok) do
          {:ok, pick} ->
            gb = Enum.sum(Enum.map(pick, &elem(&1, 1))) / 1.0e9
            IO.puts(:io_lib.format("~5w  ~-24s ~-60s ~5w  ~6.2f  ~s", [st, name, repo, length(pick), gb, if(String.starts_with?(repo, "chibifire/"), do: "yes", else: "NO")]) |> to_string())
            acc + gb
          {:error, e} -> IO.puts("#{st}  #{name}  ERROR #{e}"); acc
        end
      end)
      IO.puts(:io_lib.format("total ~.2f GB; not mirrored: ~w of ~w rows", [total / 1, Enum.count(rows(), fn {_, _, r, _, _, _} -> not String.starts_with?(r, "chibifire/") end), length(rows())]) |> to_string())
      {:ok, total}
    end
  end

  def fetch(dir) do
    with {:ok, tok} <- token() do
      File.mkdir_p!(dir)
      sums = File.open!(Path.join(dir, "SHA256SUMS"), [:write])
      res = Enum.reduce_while(rows(), :ok, fn {_, name, repo, _, _, _} = row, _ ->
        case wanted(row, tok) do
          {:ok, pick} ->
            Enum.reduce_while(pick, {:cont, :ok}, fn {f, _, sha}, _ ->
              dest = Path.join([dir, repo, f]); File.mkdir_p!(Path.dirname(dest))
              url = "https://huggingface.co/#{repo}/resolve/main/#{f}"
              case System.cmd("curl", ["-sL", "-C", "-", "--retry", "5", "-H", "Authorization: Bearer #{tok}", "-o", dest, url]) do
                {_, 0} ->
                  if sha, do: IO.write(sums, "#{sha}  #{repo}/#{f}\n")
                  IO.puts("#{name}: #{f} (#{File.stat!(dest).size} bytes)"); {:cont, {:cont, :ok}}
                {out, c} -> {:halt, {:halt, {:error, "#{repo}/#{f}: curl #{c} #{String.slice(out, 0, 80)}"}}}
              end
            end)
          {:error, e} -> {:halt, {:error, e}}
        end
      end)
      File.close(sums)
      case res do
        {:error, e} -> {:error, e}
        _ -> verify(dir)
      end
    end
  end

  # sha256 each listed file; the hub's LFS sha256 is the truth it is checked against
  def verify(dir) do
    path = Path.join(dir, "SHA256SUMS")
    with {:ok, body} <- File.read(path) do
      bad = body |> String.split("\n", trim: true) |> Enum.reject(fn line ->
        [sha, rel] = String.split(line, "  ", parts: 2)
        case File.read(Path.join(dir, rel)) do
          {:ok, bytes} -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == sha
          _ -> false
        end
      end)
      if bad == [], do: {:ok, "verify: every file in #{path} matches"}, else: {:error, "verify: #{length(bad)} file(s) differ or are missing: #{Enum.map_join(bad, ", ", &(String.split(&1, "  ") |> List.last()))}"}
    end
  end

  # the gate's control: flip one byte of the smallest listed file; verify must fail; then restore it
  def self_test(dir) do
    path = Path.join(dir, "SHA256SUMS")
    with {:ok, body} <- File.read(path),
         {:ok, _} <- verify(dir) do
      rel = body |> String.split("\n", trim: true) |> Enum.map(&(String.split(&1, "  ", parts: 2) |> List.last())) |> Enum.min_by(&File.stat!(Path.join(dir, &1)).size)
      file = Path.join(dir, rel); orig = File.read!(file)
      <<h, rest::binary>> = orig
      File.write!(file, <<Bitwise.bxor(h, 1), rest::binary>>)
      r = verify(dir)
      File.write!(file, orig)
      case r do
        {:error, _} -> {:ok, "self-test: verify failed on the planted byte in #{rel}, and the file is restored"}
        {:ok, _} -> {:error, "self-test: verify PASSED a corrupt #{rel}; the gate cannot see a bad file"}
      end
    end
  end
end

Mix.install([{:jason, "~> 1.4"}])
result = case System.argv() do
  ["list"] -> Weights.list()
  ["fetch", dir] -> Weights.fetch(dir)
  ["verify", dir] -> Weights.verify(dir)
  ["self-test", dir] -> Weights.self_test(dir)
  _ -> {:error, "usage: elixir deploy/weights.exs list | fetch <dir> | verify <dir> | self-test <dir>"}
end
case result do
  {:ok, msg} when is_binary(msg) -> IO.puts("OK: #{msg}")
  {:ok, _} -> :ok
  {:error, e} -> IO.puts(:stderr, "FAIL: #{e}"); System.halt(1)
end
