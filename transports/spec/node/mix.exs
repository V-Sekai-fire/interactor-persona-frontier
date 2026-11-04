defmodule FrontierNode.MixProject do
  use Mix.Project

  # The property tests that drive the Lean node as an Erlang peer. `mix test` here needs the node
  # up (`frontier --dist-port 9941 --cookie <cookie>`) and epmd running.
  def project do
    [app: :frontier_node, version: "0.1.0", elixir: "~> 1.18", start_permanent: false, deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps, do: [{:propcheck, "~> 1.5", only: [:test, :dev]}, {:jason, "~> 1.4"}]
end
