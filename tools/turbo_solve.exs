# Solve a problem dumped from Turbo's preprocessing (slang/turbo/oracle/cp_dump.cpp) with the Lean-emitted barebones search (turbo/Turbo/Solve.lean) on the CPU.
# Usage: elixir tools/turbo_solve.exs <problem.cp> [--blocks N] [--power P] [--stop-nodes N] [--max-depth D]
{opts, [dump_path], _} = OptionParser.parse(System.argv(), strict: [blocks: :integer, power: :integer, stop_nodes: :integer, max_depth: :integer, eps: :boolean])
blocks = Keyword.get(opts, :blocks, 1)
power = Keyword.get(opts, :power, 0)
stop_nodes = Keyword.get(opts, :stop_nodes, 2_147_483_647)
max_depth = Keyword.get(opts, :max_depth, 10_000)
eps = if Keyword.get(opts, :eps, false), do: 1, else: 0
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
code = Enum.flat_map(bytecodes, fn row -> [op, x, y, z] = String.split(row); [Map.fetch!(codes, op), String.to_integer(x), String.to_integer(y), String.to_integer(z)] end)
{strategies, strategy_vars, _} =
  Enum.reduce(strategy_rows, {[], [], 0}, fn row, {acc, vars, offset} ->
    [order, value, count | members] = ints.(row)
    {acc ++ [order, value, offset, count], vars ++ members, offset + count}
  end)
strategy_count = div(length(strategies), 4)
strategy_vars = if strategy_vars == [], do: [0], else: strategy_vars

scratch = Path.join(System.tmp_dir!(), "turbo_solve")
File.mkdir_p!(scratch)
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
int main() {
    int h[10];
    for (int i = 0; i < 10; ++i) if (scanf("%d", &h[i]) != 1) return 2;
    int n = h[0], m = h[1], ns = h[2], objective = h[3], power = h[4], max_depth = h[5], blocks = h[6], nvars = h[9];
    std::vector<int> root_lower(n), root_upper(n), code(4 * m), strategies(4 * ns), strategy_vars(nvars);
    for (int i = 0; i < n; ++i) scanf("%d %d", &root_lower[i], &root_upper[i]);
    for (auto& x : code) scanf("%d", &x);
    for (auto& x : strategies) scanf("%d", &x);
    for (auto& x : strategy_vars) scanf("%d", &x);
    size_t cells = (size_t)blocks * n;
    std::vector<int> lower(cells), upper(cells), snap_lower(cells), snap_upper(cells), best_lower(cells), best_upper(cells);
    std::vector<int> decisions((size_t)blocks * max_depth * 8), state((size_t)blocks * 16, 0), control(16, 0);
    control[0] = m; control[1] = n; control[2] = ns; control[3] = objective; control[4] = power; control[5] = max_depth;
    control[6] = blocks; control[7] = h[7]; control[8] = h[8]; control[9] = 0; control[10] = blocks; control[11] = INT_MAX; control[12] = 0;
    Globals g{{lower.data(), cells}, {upper.data(), cells}, {root_lower.data(), (size_t)n}, {root_upper.data(), (size_t)n},
      {snap_lower.data(), cells}, {snap_upper.data(), cells}, {best_lower.data(), cells}, {best_upper.data(), cells},
      {code.data(), (size_t)m}, {strategies.data(), (size_t)ns}, {strategy_vars.data(), strategy_vars.size()},
      {decisions.data(), decisions.size()}, {state.data(), state.size()}, {control.data(), control.size()}};
    ComputeVaryingInput input = {};
    input.startGroupID = {0, 0, 0};
    input.endGroupID = {(uint32_t)blocks, 1, 1};
    solve(&input, nullptr, &g);
    printf("error %d approx %d next %d\\n", control[12], control[11], control[10]);
    int best = -1;
    for (int b = 0; b < blocks; ++b) {
        int* s = &state[b * 16];
        printf("block %d solutions %d bound %d nodes %d fails %d depth_max %d exhaustive %d\\n", b, s[6], s[5], s[7], s[8], s[11], s[10]);
        if (s[6] > 0 && (best < 0 || s[5] < state[best * 16 + 5])) best = b;
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
run.(Path.join(sdk, "bin/slangc"), [Path.join(scratch, "solve.slang"), "-target", "cpp", "-entry", "solve", "-stage", "compute", "-o", Path.join(scratch, "solve.cpp")])
run.("g++", ["-std=c++17", "-O2", "-I", Path.join(sdk, "include"), Path.join(scratch, "solve.cpp"), Path.join(scratch, "driver.cpp"), "-o", Path.join(scratch, "solve")])
started = System.monotonic_time(:millisecond)
{out, 0} = System.cmd("sh", ["-c", "#{Path.join(scratch, "solve")} < #{Path.join(scratch, "input.txt")}"])
elapsed = System.monotonic_time(:millisecond) - started
out_lines = String.split(out, "\n", trim: true)
{summary, rest} = Enum.split_while(out_lines, &(not String.starts_with?(&1, "best ")))
IO.puts("#{n} variables, #{m} bytecodes, #{elapsed} ms")
Enum.each(summary, &IO.puts/1)
[best_line | store_rows] = rest
IO.puts(best_line)
[_, best_block] = String.split(best_line)
if best_block != "-1" and objective >= 0 do
  final = store_rows |> Enum.at(objective) |> ints.()
  IO.puts("objective #{inspect(final)}")
end
File.write!(Path.join(scratch, "best_store.txt"), Enum.join(store_rows, "\n") <> "\n")
