# Solve a problem dumped from Turbo's preprocessing (slang/turbo/oracle/cp_dump.cpp) with the Lean-emitted barebones search (turbo/Turbo/Solve.lean) on the CPU.
# The search is reentrant: it runs `--slice N` nodes, writes its whole state to the checkpoint file and returns; the next call resumes from the file, so it can be
# timesliced, paused for hours and restarted. Without `--once` this tool calls it again until the search is done (`--pause-ms` between slices).
# `--sort-ops` orders the bytecodes by operator (stable): neighbouring GPU threads then run the same operator. The fixpoint, and so every node, is unchanged.
# `--prepare` only builds the solver and its input (under the temp directory, one folder per problem) and prints that folder: the binary there takes `input.txt CHECKPOINT SLICE`.
# Usage: elixir tools/turbo_solve.exs <problem.cp> [--blocks N] [--power P] [--stop-nodes N] [--max-depth D] [--slice N] [--checkpoint FILE] [--once] [--pause-ms M]
{opts, [dump_path], _} = OptionParser.parse(System.argv(), strict: [blocks: :integer, power: :integer, stop_nodes: :integer, max_depth: :integer, eps: :boolean, prepare: :boolean, sort_ops: :boolean, slice: :integer, checkpoint: :string, once: :boolean, pause_ms: :integer])
blocks = Keyword.get(opts, :blocks, 1)
power = Keyword.get(opts, :power, 0)
stop_nodes = Keyword.get(opts, :stop_nodes, 2_147_483_647)
max_depth = Keyword.get(opts, :max_depth, 10_000)
eps = if Keyword.get(opts, :eps, false), do: 1, else: 0
slice = Keyword.get(opts, :slice, 0)
once = Keyword.get(opts, :once, false)
prepare = Keyword.get(opts, :prepare, false)
pause_ms = Keyword.get(opts, :pause_ms, 0)
root = File.cwd!()
sdk = Path.join(root, ".slang/2026.20")
env = [{"LD_LIBRARY_PATH", Path.join(sdk, "lib")}]
codes = %{"+" => 0, "*" => 1, "min" => 2, "max" => 3, "=" => 4, "≤" => 5}
lines = dump_path |> File.read!() |> String.split("\n", trim: true)

[_, bot] = lines |> Enum.find(&String.starts_with?(&1, "bot ")) |> String.split()
if bot == "1", do: (IO.puts("the problem is bot at the root"); System.halt(0))

section = fn header, rest ->
  [count_line | tail] = Enum.drop_while(rest, &(not String.starts_with?(&1, header)))
  count = count_line |> String.split() |> List.last() |> String.to_integer()
  {Enum.take(tail, count), Enum.drop(tail, count)}
end

ints = fn row -> row |> String.split() |> Enum.map(&String.to_integer/1) end
{store, rest} = section.("variables", lines)
{bytecodes, rest} = section.("bytecodes", rest)
{strategy_rows, rest} = section.("strategies", rest)
[objective_line] = Enum.filter(rest, &String.starts_with?(&1, "objective "))
[_, untyped, objective_var] = String.split(objective_line)
objective = if untyped == "1", do: -1, else: String.to_integer(objective_var)

n = length(store)
m = length(bytecodes)
code_rows_list = Enum.map(bytecodes, fn row -> [op, x, y, z] = String.split(row); [Map.fetch!(codes, op), String.to_integer(x), String.to_integer(y), String.to_integer(z)] end)
code_rows_list = if Keyword.get(opts, :sort_ops, false), do: Enum.sort_by(code_rows_list, &hd/1), else: code_rows_list
code = List.flatten(code_rows_list)
{strategies, strategy_vars, _} =
  Enum.reduce(strategy_rows, {[], [], 0}, fn row, {acc, vars, offset} ->
    [order, value, count | members] = ints.(row)
    {acc ++ [order, value, offset, count], vars ++ members, offset + count}
  end)
strategy_count = div(length(strategies), 4)
strategy_vars = if strategy_vars == [], do: [0], else: strategy_vars

scratch = Path.join([System.tmp_dir!(), "turbo_solve", Path.basename(dump_path, ".cp")])
File.mkdir_p!(scratch)
checkpoint = Keyword.get(opts, :checkpoint, Path.join(scratch, "checkpoint.bin"))
header = [n, m, strategy_count, objective, power, max_depth, blocks, stop_nodes, eps, length(strategy_vars)]
File.write!(Path.join(scratch, "input.txt"), Enum.join(header ++ List.flatten(Enum.map(store, ints)) ++ code ++ strategies ++ strategy_vars, " ") <> "\n")

File.write!(Path.join(scratch, "driver.cpp"), """
#include "slang-cpp-prelude.h"
#include <cstdio>
#include <vector>
#include <climits>
struct Span { void* data; size_t count; };
struct Globals { Span lower, upper, root_lower, root_upper, snap_lower, snap_upper, best_lower, best_upper, code, strategies, strategy_vars, decisions, state, control; };
extern "C" void solve(ComputeVaryingInput*, void*, void*);
static const int STATE = 24;
template <class T> static bool save(FILE* f, std::vector<T>& v) { return fwrite(v.data(), sizeof(T), v.size(), f) == v.size(); }
template <class T> static bool load(FILE* f, std::vector<T>& v) { return fread(v.data(), sizeof(T), v.size(), f) == v.size(); }
int main(int argc, char** argv) {
    if (argc < 4) return 2;
    FILE* in = fopen(argv[1], "r");
    int h[10];
    for (int i = 0; i < 10; ++i) if (fscanf(in, "%d", &h[i]) != 1) return 2;
    int n = h[0], m = h[1], ns = h[2], objective = h[3], power = h[4], max_depth = h[5], blocks = h[6], nvars = h[9];
    std::vector<int> root_lower(n), root_upper(n), code(4 * m), strategies(4 * ns), strategy_vars(nvars);
    for (int i = 0; i < n; ++i) fscanf(in, "%d %d", &root_lower[i], &root_upper[i]);
    for (auto& x : code) fscanf(in, "%d", &x);
    for (auto& x : strategies) fscanf(in, "%d", &x);
    for (auto& x : strategy_vars) fscanf(in, "%d", &x);
    fclose(in);
    size_t cells = (size_t)blocks * n;
    std::vector<int> lower(cells), upper(cells), snap_lower(cells), snap_upper(cells), best_lower(cells), best_upper(cells);
    std::vector<int> decisions((size_t)blocks * max_depth * 8), state((size_t)blocks * STATE, 0), control(16, 0);
    control[0] = m; control[1] = n; control[2] = ns; control[3] = objective; control[4] = power; control[5] = max_depth;
    control[6] = blocks; control[7] = h[7]; control[8] = h[8]; control[9] = 0; control[10] = blocks; control[11] = INT_MAX; control[12] = 0;
    FILE* cp = fopen(argv[2], "rb");
    if (cp) {
        bool ok = load(cp, lower) && load(cp, upper) && load(cp, snap_lower) && load(cp, snap_upper) && load(cp, best_lower) && load(cp, best_upper) && load(cp, decisions) && load(cp, state) && load(cp, control);
        fclose(cp);
        if (!ok) { fprintf(stderr, "checkpoint %s does not match the problem\\n", argv[2]); return 3; }
    }
    control[13] = atoi(argv[3]);
    Globals g{{lower.data(), cells}, {upper.data(), cells}, {root_lower.data(), (size_t)n}, {root_upper.data(), (size_t)n},
      {snap_lower.data(), cells}, {snap_upper.data(), cells}, {best_lower.data(), cells}, {best_upper.data(), cells},
      {code.data(), (size_t)m}, {strategies.data(), (size_t)ns}, {strategy_vars.data(), strategy_vars.size()},
      {decisions.data(), decisions.size()}, {state.data(), state.size()}, {control.data(), control.size()}};
    ComputeVaryingInput input = {};
    input.startGroupID = {0, 0, 0};
    input.endGroupID = {(uint32_t)blocks, 1, 1};
    solve(&input, nullptr, &g);
    cp = fopen(argv[2], "wb");
    bool saved = save(cp, lower) && save(cp, upper) && save(cp, snap_lower) && save(cp, snap_upper) && save(cp, best_lower) && save(cp, best_upper) && save(cp, decisions) && save(cp, state) && save(cp, control);
    fclose(cp);
    if (!saved) return 4;
    bool done = true;
    long nodes = 0;
    for (int b = 0; b < blocks; ++b) { done = done && state[b * STATE + 16] == 5; nodes += state[b * STATE + 7]; }
    printf("status %s nodes %ld\\n", done ? "done" : "running", nodes);
    if (!done) return 0;
    printf("error %d approx %d next %d\\n", control[12], control[11], control[10]);
    int best = -1;
    for (int b = 0; b < blocks; ++b) {
        int* s = &state[b * STATE];
        printf("block %d solutions %d bound %d nodes %d fails %d depth_max %d exhaustive %d\\n", b, s[6], s[5], s[7], s[8], s[11], s[10]);
        if (s[6] > 0 && (best < 0 || s[5] < state[best * STATE + 5])) best = b;
    }
    printf("best %d\\n", best);
    if (best >= 0) for (int i = 0; i < n; ++i) printf("%d %d\\n", best_lower[(size_t)best * n + i], best_upper[(size_t)best * n + i]);
}
""")

{text, 0} = System.cmd(Path.join(root, ".lake/build/bin/turbo_emit"), ["solve"])
File.write!(Path.join(scratch, "solve.slang"), text)
run = fn cmd, args ->
  {out, status} = System.cmd(cmd, args, env: env, stderr_to_stdout: true)
  if status != 0, do: raise("#{cmd}: #{String.slice(out, 0, 800)}")
  out
end
text_hash = :crypto.hash(:sha256, text <> File.read!(Path.join(scratch, "driver.cpp"))) |> Base.encode16()
hash_file = Path.join(scratch, "solve.hash")
if not (File.exists?(Path.join(scratch, "solve")) and File.read(hash_file) == {:ok, text_hash}) do
  run.(Path.join(sdk, "bin/slangc"), [Path.join(scratch, "solve.slang"), "-target", "cpp", "-entry", "solve", "-stage", "compute", "-o", Path.join(scratch, "solve.cpp")])
  run.("g++", ["-std=c++17", "-O2", "-I", Path.join(sdk, "include"), Path.join(scratch, "solve.cpp"), Path.join(scratch, "driver.cpp"), "-o", Path.join(scratch, "solve")])
  File.write!(hash_file, text_hash)
end
if prepare do
  IO.puts(scratch)
  System.halt(0)
end
if not once, do: File.rm(checkpoint)
started = System.monotonic_time(:millisecond)
binary = Path.join(scratch, "solve")
input = Path.join(scratch, "input.txt")
step = fn ->
  {out, 0} = System.cmd(binary, [input, checkpoint, Integer.to_string(slice)])
  out
end
loop = fn loop, slices ->
  out = step.()
  [status | _] = String.split(out, "\n", trim: true)
  cond do
    String.starts_with?(status, "status done") -> {out, slices}
    once -> {out, slices}
    true -> (if pause_ms > 0, do: Process.sleep(pause_ms)); loop.(loop, slices + 1)
  end
end
{out, slices} = loop.(loop, 1)
elapsed = System.monotonic_time(:millisecond) - started
out_lines = String.split(out, "\n", trim: true)
[status_line | out_lines] = out_lines
IO.puts("#{n} variables, #{m} bytecodes, #{elapsed} ms in #{slices} slice(s); #{status_line}")
if String.contains?(status_line, "running") do
  System.halt(0)
end
{summary, rest} = Enum.split_while(out_lines, &(not String.starts_with?(&1, "best ")))
Enum.each(summary, &IO.puts/1)
[best_line | store_rows] = rest
IO.puts(best_line)
[_, best_block] = String.split(best_line)
if best_block != "-1" and objective >= 0 do
  final = store_rows |> Enum.at(objective) |> ints.()
  IO.puts("objective #{inspect(final)}")
end
File.write!(Path.join(scratch, "best_store.txt"), Enum.join(store_rows, "\n") <> "\n")
