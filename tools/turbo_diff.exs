# Compare one deduce step of three implementations on the same boxes: Turbo's pir.hpp (reference file),
# the hand-written slang/turbo/pir.slang, and the Lean-emitted module (.lake/build/bin/turbo_emit).
# Usage: elixir tools/turbo_diff.exs <reference.txt> ; lines are "name xl xu yl yu zl zu | rxl rxu ryl ryu rzl rzu".
[reference_path] = System.argv()
root = File.cwd!()
codes = %{"int_plus" => 0, "int_times" => 1, "int_min" => 2, "int_max" => 3, "int_div" => 6, "int_ediv" => 9, "int_mod" => 10, "int_eq_reif" => 4, "int_le_reif" => 5}
env = [{"LD_LIBRARY_PATH", Path.join(root, ".slang/2026.20/lib")}]

rows =
  reference_path
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.map(fn line ->
    [left, right] = String.split(line, " | ")
    [name | box] = String.split(left)
    {name, Enum.map(box, &String.to_integer/1), Enum.map(String.split(right), &String.to_integer/1)}
  end)

cases = rows |> Enum.map(fn {name, box, _} -> Enum.join([Map.fetch!(codes, name) | box], " ") end) |> Enum.join("\n")
sdk = Path.join(root, ".slang/2026.20")
scratch = Path.join(System.tmp_dir!(), "turbo_diff")
File.mkdir_p!(scratch)
File.write!(Path.join(scratch, "cases.txt"), cases <> "\n")

driver = """
#include <cstdint>
#include <cstdio>
extern "C" void step(int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t*);
int main() {
    int32_t a[7], out[6];
    while (scanf("%d %d %d %d %d %d %d", a, a + 1, a + 2, a + 3, a + 4, a + 5, a + 6) == 7) {
        step(a[0], a[1], a[2], a[3], a[4], a[5], a[6], out);
        printf("%d %d %d %d %d %d\\n", out[0], out[1], out[2], out[3], out[4], out[5]);
    }
}
"""
File.write!(Path.join(scratch, "driver.cpp"), driver)

run = fn label, head, make ->
  text = head <> """

  [DllExport] void step(int op, int xl, int xu, int yl, int yu, int zl, int zu, int* out) {
      Itv r1 = #{make}(xl, xu); Itv r2 = #{make}(yl, yu); Itv r3 = #{make}(zl, zu);
      deduce(op, r1, r2, r3);
      out[0] = r1.lower; out[1] = r1.upper; out[2] = r2.lower; out[3] = r2.upper; out[4] = r3.lower; out[5] = r3.upper;
  }
  """
  source = Path.join(scratch, "#{label}.slang")
  cpp = Path.join(scratch, "#{label}.cpp")
  binary = Path.join(scratch, label)
  File.write!(source, text)
  {out, status} = System.cmd(Path.join(sdk, "bin/slangc"), [source, "-target", "cpp", "-o", cpp], env: env, stderr_to_stdout: true)
  if status != 0, do: raise("#{label} slangc: #{String.slice(out, 0, 600)}")
  {out, status} = System.cmd("g++", ["-std=c++17", "-O1", "-I", Path.join(sdk, "include"), cpp, Path.join(scratch, "driver.cpp"), "-o", binary], stderr_to_stdout: true)
  if status != 0, do: raise("#{label} g++: #{String.slice(out, 0, 600)}")
  {out, 0} = System.cmd("sh", ["-c", "#{binary} < #{Path.join(scratch, "cases.txt")}"])
  out |> String.split("\n", trim: true) |> Enum.map(fn l -> l |> String.split() |> Enum.map(&String.to_integer/1) end)
end

{lean_text, 0} = System.cmd(Path.join(root, ".lake/build/bin/turbo_emit"), [])
hand = run.("hand", "#include \"#{Path.join(root, "slang/turbo/pir.slang")}\"\n", "Itv.make")
lean = run.("lean", lean_text, "itv_make")
reference = Enum.map(rows, fn {_, _, result} -> result end)

# Turbo embeds each result into the store, which meets it with the stored interval; the Slang deduce leaves that meet to the caller.
embed = fn [_ | box], [a, b, c, d, e, f] ->
  [bx, by, bz] = Enum.chunk_every(Enum.take(box, 6), 2)
  [[xl, xu], [yl, yu], [zl, zu]] = [bx, by, bz]
  [max(a, xl), min(b, xu), max(c, yl), min(d, yu), max(e, zl), min(f, zu)]
end
hand = Enum.zip_with(rows, hand, fn {_, box, _}, r -> embed.([0 | box], r) end)
lean = Enum.zip_with(rows, lean, fn {_, box, _}, r -> embed.([0 | box], r) end)

bot? = fn [a, b, c, d, e, f] -> a > b or c > d or e > f end
same = fn x, y -> x == y or (bot?.(x) and bot?.(y)) end

for {label, left, right} <- [{"reference vs hand", reference, hand}, {"reference vs lean", reference, lean}, {"hand vs lean", hand, lean}] do
  triples = Enum.zip([rows, left, right])
  bad = Enum.reject(triples, fn {_, a, b} -> same.(a, b) end)
  IO.puts("#{label}: #{length(triples) - length(bad)} of #{length(triples)} agree")
  bad |> Enum.group_by(fn {{name, _, _}, _, _} -> name end) |> Enum.each(fn {name, list} -> IO.puts("  #{name}: #{length(list)} differ") end)
  for {{name, box, _}, a, b} <- Enum.take(bad, 3), do: IO.puts("  e.g. #{name} #{inspect(box)}: #{inspect(a)} vs #{inspect(b)}")
end
