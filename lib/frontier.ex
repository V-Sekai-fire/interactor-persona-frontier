defmodule Frontier do
  @moduledoc "Plan to a goal from the seed files, in-process: no node, no port."

  @seeds "seeds"

  @doc "`{:ok, plan}` or `{:ok, %{\"refused\" => name}}`; `{:error, reason}` when a seed file or the call fails."
  def plan(goal, seeds_dir \\ @seeds) when is_binary(goal) do
    with {:ok, text} <- seeds_text(seeds_dir),
         {:ok, json} <- Frontier.Native.answer(text, goal) do
      JSON.decode(json)
    end
  end

  @doc "The seed files in name order as one YAML stream, a document per seed, the form the Lean side folds."
  def seeds_text(dir \\ @seeds) do
    with {:ok, names} <- File.ls(dir) do
      names |> Enum.filter(&String.ends_with?(&1, ".yamlld")) |> Enum.sort() |> read_all(dir, [])
    end
  end

  defp read_all([], _dir, acc), do: {:ok, acc |> Enum.reverse() |> Enum.join("\n---\n")}

  defp read_all([name | rest], dir, acc) do
    with {:ok, text} <- File.read(Path.join(dir, name)), do: read_all(rest, dir, [text | acc])
  end
end
