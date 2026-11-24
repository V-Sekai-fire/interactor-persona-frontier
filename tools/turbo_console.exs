# A local web console for the time-sliced solver: the free-time gate (load and GPU), each level's player log, progress against Turbo's node count and the planner's step.
# Usage: elixir tools/turbo_console.exs [RUN_DIR] [--port 9931]   RUN_DIR holds the *.player.log files (default /mnt/fire/6-datasource/turbo-runs). Listens on 127.0.0.1 only.
{opts, args, _} = OptionParser.parse(System.argv(), strict: [port: :integer])
run_dir = List.first(args) || "/mnt/fire/6-datasource/turbo-runs"
port = Keyword.get(opts, :port, 9931)
app = Path.join(__DIR__, "turbo_console")
design = System.get_env("DESIGN_DIR", "/mnt/fire/2-contract/contract-design-chibifire")
types = %{".css" => "text/css; charset=utf-8", ".js" => "text/javascript; charset=utf-8", ".html" => "text/html; charset=utf-8", ".ttf" => "font/ttf", ".woff2" => "font/woff2"}
styles = ~w(tokens.css paper-and-ink.css)
references = %{"scout" => %{nodes: 629, objective: 511}, "party" => %{nodes: 469_302, objective: 795}}
nvidia_smi = System.find_executable("nvidia-smi") || (if File.exists?("/usr/lib/wsl/lib/nvidia-smi"), do: "/usr/lib/wsl/lib/nvidia-smi")
{:ok, samples} = Agent.start_link(fn -> %{} end)

gpu = fn ->
  with true <- nvidia_smi != nil,
       {out, 0} <- System.cmd(nvidia_smi, ["--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"], stderr_to_stdout: true),
       [u, used, total] <- out |> String.split("\n", trim: true) |> hd() |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.to_integer())) do
    %{percent: u, memory_used: used, memory_total: total}
  else
    _ -> nil
  end
end

unit_state = fn level ->
  case System.cmd("systemctl", ["--user", "is-active", "turbo-player-#{level}"], stderr_to_stdout: true) do
    {out, _} -> String.trim(out)
  end
end

result_of = fn level ->
  path = "/tmp/turbo_solve/#{level}/result.txt"
  with {:ok, text} <- File.read(path),
       [_, value] <- Regex.run(~r/approx (-?\d+)/, text) do
    String.to_integer(value)
  else
    _ -> nil
  end
end

run_status = fn log ->
  level = log |> Path.basename() |> String.split(".") |> hd()
  lines = log |> File.read!() |> String.split("\n", trim: true)
  slices = Enum.filter(lines, &String.starts_with?(&1, "slice "))
  nodes = case List.last(slices) && Regex.run(~r/nodes (\d+)/, List.last(slices)) do
    [_, n] -> String.to_integer(n)
    _ -> 0
  end
  last = List.last(lines) || ""
  now = System.system_time(:millisecond)
  history = Agent.get_and_update(samples, fn all ->
    kept = all |> Map.get(level, []) |> Enum.filter(fn {t, _} -> now - t < 300_000 end)
    kept = if kept == [] or elem(List.last(kept), 1) != nodes, do: kept ++ [{now, nodes}], else: kept
    {kept, Map.put(all, level, kept)}
  end)
  rate = case history do
    [{t0, n0} | rest] when rest != [] -> {t1, n1} = List.last(rest); if t1 > t0, do: Float.round((n1 - n0) * 1000 / (t1 - t0), 1), else: 0
    _ -> 0
  end
  ref = Map.get(references, level)
  done = String.starts_with?(last, "done after")
  state = cond do
    done -> "done"
    unit_state.(level) != "active" -> "stopped"
    String.starts_with?(last, "waiting") -> "waiting"
    true -> "running"
  end
  plan = case state do
    "waiting" -> ["wait-free", "solve-slice"]
    "running" -> ["solve-slice"]
    _ -> []
  end
  %{level: level, state: state, nodes: nodes, slices: length(slices), rate: rate, reference: ref, objective: result_of.(level), plan: plan, last: last, tail: Enum.take(lines, -14)}
end

status = fn ->
  load = "/proc/loadavg" |> File.read!() |> String.split() |> Enum.take(3) |> Enum.map(&String.to_float/1)
  logs = run_dir |> Path.join("*.player.log") |> Path.wildcard() |> Enum.sort()
  g = gpu.()
  limit_load = 4.0
  limit_gpu = 30
  free = hd(load) < limit_load and (g == nil or g.percent < limit_gpu)
  %{now: System.system_time(:millisecond), threads: System.schedulers_online(), load: load, load_limit: limit_load, gpu: g, gpu_limit: limit_gpu, free: free, runs: Enum.map(logs, run_status)}
end

respond = fn socket, code, type, body ->
  csp = "default-src 'self'; style-src 'self'; script-src 'self'; font-src 'self'; connect-src 'self'"
  head = "HTTP/1.1 #{code}\r\ncontent-type: #{type}\r\ncontent-length: #{byte_size(body)}\r\ncache-control: no-store\r\nx-content-type-options: nosniff\r\ncontent-security-policy: #{csp}\r\nconnection: close\r\n\r\n"
  :gen_tcp.send(socket, [head, body])
  :gen_tcp.close(socket)
end

file = fn socket, path ->
  case File.read(path) do
    {:ok, body} -> respond.(socket, "200 OK", Map.get(types, Path.extname(path), "application/octet-stream"), body)
    _ -> respond.(socket, "404 Not Found", "text/plain", "not found")
  end
end

serve = fn socket ->
  case :gen_tcp.recv(socket, 0, 5000) do
    {:ok, request} ->
      case String.split(request, " ", parts: 3) do
        ["GET", "/api/status" <> _ | _] -> respond.(socket, "200 OK", "application/json", JSON.encode!(status.()))
        ["GET", "/app.css" <> _ | _] -> file.(socket, Path.join(app, "app.css"))
        ["GET", "/app.js" <> _ | _] -> file.(socket, Path.join(app, "app.js"))
        ["GET", "/dist/css/" <> rest | _] ->
          name = rest |> String.split(" ") |> hd()
          if name in styles, do: file.(socket, Path.join([design, "dist/css", name])), else: respond.(socket, "404 Not Found", "text/plain", "not found")
        ["GET", "/fonts/" <> rest | _] ->
          name = rest |> String.split(" ") |> hd()
          if Regex.match?(~r/^[A-Za-z0-9\[\]_.-]+$/, name) and not String.contains?(name, ".."), do: file.(socket, Path.join([design, "fonts", name])), else: respond.(socket, "404 Not Found", "text/plain", "not found")
        ["GET", "/" | _] -> file.(socket, Path.join(app, "index.html"))
        _ -> respond.(socket, "404 Not Found", "text/plain", "not found")
      end
    _ -> :gen_tcp.close(socket)
  end
end

{:ok, listener} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
IO.puts("console on http://127.0.0.1:#{port}/ reading #{run_dir}")
accept = fn accept ->
  {:ok, socket} = :gen_tcp.accept(listener)
  spawn(fn -> serve.(socket) end)
  accept.(accept)
end
accept.(accept)
