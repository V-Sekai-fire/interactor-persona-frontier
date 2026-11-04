#!/usr/bin/env elixir
# One command, no arguments: a fresh clone builds the node and its gates and runs them.
#   elixir build.exs
# Installs what is missing through brew (macOS) or apt (Debian/Ubuntu): elan (the Lean toolchain
# named in lean-toolchain), SQLite headers, Erlang and Elixir's epmd, a C compiler. Then: lake build,
# the Lean witness, and the PropCheck suite against a node started on scratch ports with its own
# SQLite file. FoundationDB is not installed here; the FDB-backed run is deploy/cloud-init.yaml and
# .github/workflows/node.yml. Every step returns {:ok, _} or {:error, reason}; the first error exits.
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

  def wait_registered(0), do: {:error, "the node did not register with epmd within 30 s"}
  def wait_registered(n) do
    case System.cmd("epmd", ["-names"], stderr_to_stdout: true) do
      {out, 0} when is_binary(out) -> if out =~ "name frontier at port 9951", do: {:ok, :registered}, else: (Process.sleep(1000); wait_registered(n - 1))
      _ -> Process.sleep(1000); wait_registered(n - 1)
    end
  end

  # the node under test: scratch ports, a scratch database, a random cookie; killed when done
  def propcheck do
    db = Path.join(System.tmp_dir!(), "frontier-build-#{System.unique_integer([:positive])}.sqlite")
    cookie = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    _ = System.cmd("epmd", ["-daemon"])
    port = Port.open({:spawn_executable, Path.join(@root, ".lake/build/bin/frontier")},
      [:binary, :exit_status, args: ["--port", "9950", "--dist-port", "9951", "--cookie", cookie], env: [{~c"FRONTIER_DB", String.to_charlist(db)}], cd: @root])
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    result =
      with {:ok, _} <- wait_registered(30),
           {:ok, _} <- run("mix", ["deps.get"], cd: Path.join(@root, "test/node")),
           {:ok, _} <- run("elixir", ["--name", "probe@127.0.0.1", "--cookie", cookie, "-S", "mix", "test"], cd: Path.join(@root, "test/node")) do
        {:ok, :propcheck}
      end
    System.cmd("kill", [Integer.to_string(os_pid)])
    File.rm(db)
    result
  end

  def main do
    steps = [
      fn -> elan() end,
      fn -> need("erl", "erlang", "erlang-dev") end,
      fn -> need("epmd", "erlang", "erlang-epmd") end,
      fn -> need("cc", "gcc", "build-essential") end,
      fn -> run("lake", ["build"]) end,
      fn -> run(Path.join(@root, ".lake/build/bin/frontier_witness"), []) end,
      fn -> run("elixir", ["docs/tokens.exs"]) end,
      fn -> propcheck() end
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
