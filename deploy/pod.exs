#!/usr/bin/env elixir
# One cell: FoundationDB + epmd + the node, colocated in one pod, sized to one s-1vcpu-2gb.
#   elixir deploy/pod.exs up [name]      elixir deploy/pod.exs down [name]     elixir deploy/pod.exs smoke [name]
# The box is 1 vCPU and 2 GB; the three containers get constant shares of it that sum to the box,
# so load on one never starves another and a second box is a second cell, never a bigger one:
#   fdbserver   0.45 cpu   1024 MiB   (storage_memory 512 MiB inside; the memory engine)
#   frontier    0.45 cpu    768 MiB
#   epmd        0.10 cpu     64 MiB
# More capacity is more cells, each with its own FoundationDB and its own node; nothing is shared.
defmodule Cell do
  @fdb "docker.io/foundationdb/foundationdb:7.3.63"
  @erlang "docker.io/library/erlang:27-alpine"
  @image System.get_env("FRONTIER_IMAGE", "localhost/frontier:alma10")

  def run(args) do
    case System.cmd("podman", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, code} -> {:error, "podman #{Enum.join(args, " ")} (#{code}): #{String.trim(out)}"}
    end
  end

  def ready(name, 0), do: {:error, "#{name}: FoundationDB not available within 60 s"}
  def ready(name, n) do
    case run(["exec", "#{name}-fdb", "fdbcli", "--exec", "status minimal", "--timeout", "5"]) do
      {:ok, out} when is_binary(out) -> if out =~ "available", do: {:ok, out}, else: (Process.sleep(2000); ready(name, n - 1))
      _ -> Process.sleep(2000); ready(name, n - 1)
    end
  end

  def up(name, http_port) do
    with {:ok, _} <- run(["pod", "create", "--name", name, "-p", "#{http_port}:9920"]),
         {:ok, _} <- run(["run", "-d", "--pod", name, "--name", "#{name}-fdb", "--cpus", "0.45", "--memory", "1024m",
                          "-e", "FDB_NETWORKING_MODE=host", "-e", "FDB_COORDINATOR=127.0.0.1", "-e", "FDB_PORT=4500", @fdb]),
         _ <- Process.sleep(6000),
         {:ok, _} <- run(["exec", "#{name}-fdb", "fdbcli", "--exec", "configure new single memory", "--timeout", "30"]),
         {:ok, _} <- ready(name, 30),
         {:ok, _} <- run(["run", "-d", "--pod", name, "--name", "#{name}-epmd", "--cpus", "0.10", "--memory", "64m", @erlang, "epmd", "-d"]),
         {:ok, _} <- run(["run", "-d", "--pod", name, "--name", "#{name}-node", "--cpus", "0.45", "--memory", "768m", "-v", "#{name}-data:/data",
                          "-e", "FRONTIER_DB=file:frontier?vfs=weft_fdb", "-e", "WEFT_FDB_CLUSTER_FILE=/data/fdb.cluster",
                          "--entrypoint", "sh", @image, "-c",
                          "echo docker:docker@127.0.0.1:4500 > /data/fdb.cluster; [ -f /data/cookie ] || head -c 24 /dev/urandom | base64 > /data/cookie; exec /app/frontier --host 0.0.0.0 --port 9920 --dist-port 9930 --cookie-file /data/cookie"]) do
      {:ok, "cell #{name} up: http :#{http_port}, FoundationDB and the node in one pod"}
    end
  end

  def down(name) do
    with {:ok, _} <- run(["pod", "rm", "-f", name]), {:ok, _} <- run(["volume", "rm", "-f", "#{name}-data"]), do: {:ok, "cell #{name} down"}
  end

  # the pages are in FoundationDB: a practice trace is readable back under weft/db/frontier/, and /data has no SQLite file
  def smoke(name, http_port) do
    body = ~s({"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"text":"world"}]}}})
    with {:ok, plan} <- curl(["-s", "-m", "20", "-X", "POST", "http://127.0.0.1:#{http_port}/", "-d", body]),
         true <- plan =~ ~S(\"reached\":true) || {:error, "no plan: #{String.slice(plan, 0, 120)}"},
         {:ok, trace} <- curl(["-s", "-m", "20", "-X", "POST", "http://127.0.0.1:#{http_port}/practice"]),
         true <- trace =~ ~s("kind":"practice") || {:error, "no trace: #{trace}"},
         {:ok, files} <- run(["exec", "#{name}-node", "ls", "/data"]),
         true <- not (files =~ "sqlite") || {:error, "a SQLite file appeared in /data: the VFS was not used"},
         {:ok, keys} <- run(["exec", "#{name}-fdb", "fdbcli", "--exec", "getrange weft/db/frontier/ weft/db/frontier0 20", "--timeout", "10"]),
         true <- keys =~ "weft/db/frontier/HEAD" || {:error, "no store keys in FoundationDB"},
         true <- keys =~ ~s("kind":"practice") || {:error, "the trace text is not in the FoundationDB pages"} do
      {:ok, "smoke #{name}: plan answered, trace written, pages in FoundationDB, no local file"}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, "smoke: unexpected #{inspect(other)}"}
    end
  end

  def curl(args) do
    case System.cmd("curl", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, "curl (#{code}): #{out}"}
    end
  end
end

{cmd, name} = case System.argv() do
  [c] -> {c, "frontier"}
  [c, n] -> {c, n}
  _ -> {"usage", nil}
end
port = String.to_integer(System.get_env("FRONTIER_HTTP_PORT", "9920"))
result = case cmd do
  "up" -> Cell.up(name, port)
  "down" -> Cell.down(name)
  "smoke" -> Cell.smoke(name, port)
  _ -> {:error, "usage: elixir deploy/pod.exs up|down|smoke [name]"}
end
case result do
  {:ok, msg} -> IO.puts("OK: #{msg}")
  {:error, reason} -> IO.puts(:stderr, "FAIL: #{reason}"); System.halt(1)
end
