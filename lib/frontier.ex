defmodule Frontier do
  @moduledoc "Plan to a goal from the knowledge file, in-process: no node, no port."

  @knowledge Path.join(["entities", "knowledge", "knowledge.json"])

  @doc "`{:ok, plan}` or `{:ok, %{\"refused\" => name}}`; `{:error, reason}` when the knowledge file or the call fails."
  def plan(goal, knowledge_path \\ @knowledge) when is_binary(goal) do
    with {:ok, text} <- File.read(knowledge_path),
         {:ok, json} <- Frontier.Native.answer(text, goal) do
      JSON.decode(json)
    end
  end
end
