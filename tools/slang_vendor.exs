# Put the Slang SDK where contract-lean-slang's extern_lib looks for slang.h: <package>/vendor/{include,lib}.
# Run after the dependencies are fetched (`lake resolve-deps`). The SDK is unpacked once into .slang/.
version = "2026.20"
root = File.cwd!()
sdk = Path.join([root, ".slang", version])
package = Path.join([root, ".lake", "packages", "LeanSlang"])

unless File.dir?(package), do: raise("run `lake resolve-deps` first: #{package} is missing")

unless File.exists?(Path.join([sdk, "include", "slang.h"])) do
  File.mkdir_p!(sdk)
  url = "https://github.com/shader-slang/slang/releases/download/v#{version}/slang-#{version}-linux-x86_64.tar.gz"
  archive = Path.join(sdk, "slang.tar.gz")
  {_, 0} = System.cmd("curl", ["-fsSL", "-o", archive, url])
  {_, 0} = System.cmd("tar", ["xzf", archive, "-C", sdk])
  File.rm!(archive)
end

vendor = Path.join(package, "vendor")
File.mkdir_p!(vendor)

for name <- ["include", "lib"] do
  link = Path.join(vendor, name)
  File.rm_rf!(link)
  File.ln_s!(Path.join(sdk, name), link)
end

IO.puts("Slang #{version} linked into #{vendor}")
