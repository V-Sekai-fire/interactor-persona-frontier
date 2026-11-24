# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-FileCopyrightText: 2025 Pierre Talbot
# SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
# SPDX-License-Identifier: Apache-2.0 AND MIT
# Run the Lean-emitted Gauss-Seidel fixpoint (turbo/Turbo/Fixpoint.lean, CPU target) on a problem dumped from Turbo's PIR
# (slang/turbo/oracle/dump.cpp) and compare the final store with Turbo's own fixpoint.
# Usage: elixir tools/turbo_fixpoint.exs <problem.dump>
[dump_path] = System.argv()
root = File.cwd!()
sdk = Path.join(root, ".slang/2026.20")
env = [{"LD_LIBRARY_PATH", Path.join(sdk, "lib")}]
codes = %{"+" => 0, "*" => 1, "min" => 2, "max" => 3, "=" => 4, "≤" => 5}
lines = dump_path |> File.read!() |> String.split("\n", trim: true)

section = fn header, rest ->
  [count_line | tail] = Enum.drop_while(rest, &(not String.starts_with?(&1, header)))
  count = count_line |> String.split() |> List.last() |> String.to_integer()
  {Enum.take(tail, count), Enum.drop(tail, count)}
end

{before, rest} = section.("store_before", lines)
{bytecodes, rest} = section.("bytecodes", rest)
{after_store, _} = section.("store_after", rest)

pairs = fn rows -> Enum.map(rows, fn row -> row |> String.split() |> Enum.map(&String.to_integer/1) end) end
code_rows =
  Enum.map(bytecodes, fn row ->
    [op, x, y, z] = String.split(row)
    [Map.fetch!(codes, op), String.to_integer(x), String.to_integer(y), String.to_integer(z)]
  end)

scratch = Path.join(System.tmp_dir!(), "turbo_fixpoint")
File.mkdir_p!(scratch)

input =
  [length(before), length(code_rows)] ++ List.flatten(pairs.(before)) ++ List.flatten(code_rows)

File.write!(Path.join(scratch, "input.txt"), Enum.join(input, " ") <> "\n")

File.write!(Path.join(scratch, "driver.cpp"), """
#include "slang-cpp-prelude.h"
#include <cstdio>
#include <vector>
struct Span { void* data; size_t count; };
struct Globals { Span lower, upper, code, control; };
extern "C" void fixpoint(ComputeVaryingInput*, void*, void*);
int main() {
    int n, m;
    if (scanf("%d %d", &n, &m) != 2) return 2;
    std::vector<int> lower(n), upper(n), code(4 * m), control(4, 0);
    for (int i = 0; i < n; ++i) scanf("%d %d", &lower[i], &upper[i]);
    for (int i = 0; i < 4 * m; ++i) scanf("%d", &code[i]);
    control[0] = m;
    Globals g{{lower.data(), (size_t)n}, {upper.data(), (size_t)n}, {code.data(), (size_t)m}, {control.data(), 4}};
    ComputeVaryingInput input = {};
    input.startGroupID = {0, 0, 0};
    input.endGroupID = {1, 1, 1};
    fixpoint(&input, nullptr, &g);
    printf("rounds %d bot %d\\n", control[1], control[2]);
    for (int i = 0; i < n; ++i) printf("%d %d\\n", lower[i], upper[i]);
}
""")

{text, 0} = System.cmd(Path.join(root, ".lake/build/bin/turbo_emit"), [])
File.write!(Path.join(scratch, "fixpoint.slang"), text)
run = fn cmd, args ->
  {out, status} = System.cmd(cmd, args, env: env, stderr_to_stdout: true)
  if status != 0, do: raise("#{cmd}: #{String.slice(out, 0, 800)}")
  out
end
run.(Path.join(sdk, "bin/slangc"), [Path.join(scratch, "fixpoint.slang"), "-target", "cpp", "-entry", "fixpoint", "-stage", "compute", "-o", Path.join(scratch, "fixpoint.cpp")])
run.("g++", ["-std=c++17", "-O2", "-I", Path.join(sdk, "include"), Path.join(scratch, "fixpoint.cpp"), Path.join(scratch, "driver.cpp"), "-o", Path.join(scratch, "fixpoint")])
{started, _} = {System.monotonic_time(:millisecond), nil}
{out, 0} = System.cmd("sh", ["-c", "#{Path.join(scratch, "fixpoint")} < #{Path.join(scratch, "input.txt")}"])
elapsed = System.monotonic_time(:millisecond) - started
[head | rows] = String.split(out, "\n", trim: true)
ours = pairs.(rows)
theirs = pairs.(after_store)
differ = Enum.zip(ours, theirs) |> Enum.with_index() |> Enum.reject(fn {{a, b}, _} -> a == b end)
IO.puts("#{head}; #{length(before)} variables, #{length(code_rows)} bytecodes; #{elapsed} ms")
IO.puts("final store equals Turbo's: #{length(ours) - length(differ)} of #{length(theirs)} variables")
for {{a, b}, i} <- Enum.take(differ, 5), do: IO.puts("  variable #{i}: ours #{inspect(a)}, Turbo #{inspect(b)}")
