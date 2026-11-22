#!/usr/bin/env elixir
# One command, no arguments: a fresh clone builds the node and its gates and runs them.
#   elixir build.exs
# Installs what is missing through brew (macOS) or apt (Debian/Ubuntu): elan (the Lean toolchain
# named in lean-toolchain), SQLite headers, Erlang and Elixir, a C compiler. Then: lake build,
# the Lean witness, and the StreamData suite that calls the planner in-process through leanler. FoundationDB is not installed here; the FDB-backed run is deploy/cloud-init.yaml and
# .github/workflows/flake.yml. Every step returns {:ok, _} or {:error, reason}; the first error exits.
defmodule Build do
  @root Path.expand(__DIR__)

  def run(cmd, args, opts \\ []) do
    case System.cmd(cmd, args, Keyword.merge([cd: @root, into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)) do
      {_, 0} -> {:ok, cmd}
      {_, code} -> {:error, "#{cmd} #{Enum.join(args, " ")} exited #{code}"}
    end
  end

  def macos?, do: match?({:unix, :darwin}, :os.type())

  def need(exe, brew_pkg, apt_pkg) do
    if System.find_executable(exe) do
      {:ok, exe}
    else
      IO.puts("installing #{exe}")
      if macos?(), do: run("brew", ["install", brew_pkg]), else: run("sudo", ["apt-get", "install", "-y", apt_pkg])
    end
  end

  def elan do
    if System.find_executable("elan") do
      {:ok, :elan}
    else
      IO.puts("installing elan")
      System.put_env("PATH", Path.join([System.user_home!(), ".elan", "bin"]) <> ":" <> System.get_env("PATH"))
      run("sh", ["-c", "curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none"])
    end
  end

  def sqlite_headers do
    header = if macos?(), do: "/opt/homebrew/opt/sqlite/include/sqlite3.h", else: "/usr/include/sqlite3.h"
    if File.exists?(header), do: {:ok, header}, else: need("__sqlite_headers__", "sqlite", "libsqlite3-dev")
  end

  # the planner in-process through leanler: the StreamData suite and its controls
  def planner_suite do
    with {:ok, _} <- run("mix", ["deps.get"]),
         {:ok, _} <- run("mix", ["test"]) do
      {:ok, :planner_suite}
    end
  end

  def main do
    steps = [
      fn -> elan() end,
      fn -> need("erl", "erlang", "erlang-dev") end,
      fn -> need("cc", "gcc", "build-essential") end,
      fn -> run("lake", ["build"]) end,
      fn -> run(Path.join(@root, ".lake/build/bin/frontier_witness"), []) end,
      fn -> run("elixir", ["docs/tokens.exs"]) end,
      fn -> planner_suite() end
    ]
    Enum.reduce_while(steps, {:ok, :start}, fn step, _ ->
      case step.() do
        {:ok, _} = ok -> {:cont, ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end

case Build.main() do
  {:ok, _} -> IO.puts("OK: build.exs")
  {:error, reason} -> IO.puts(:stderr, "FAIL: #{reason}"); System.halt(1)
end
