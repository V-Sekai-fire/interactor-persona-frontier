# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
defmodule Frontier.MixProject do
  use Mix.Project

  def project do
    [
      app: :frontier,
      version: "0.1.0",
      elixir: "~> 1.18",
      compilers: [:leanler] ++ Mix.compilers(),
      deps: deps(),
      leanler: leanler()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  # LEANLER_PATH points at a local checkout of leanler while it is developed.
  defp deps do
    leanler =
      case System.get_env("LEANLER_PATH") do
        nil -> {:leanler, github: "V-Sekai-fire/leanler"}
        path -> {:leanler, path: path}
      end

    [leanler, {:stream_data, "~> 1.1", only: [:dev, :test]}]
  end

  # The planner's answer as a BEAM function: the Lean library holds Frontier.Guest and what it imports,
  # which is the generator and the planner, and no store.
  defp leanler do
    [
      mode: :nif,
      module: Frontier.Native,
      package: "frontier",
      modules: ["Frontier.Guest"],
      exports: [
        answer: [symbol: "frontier_answer_text", args: [:string, :string], returns: :string]
      ]
    ]
  end
end
