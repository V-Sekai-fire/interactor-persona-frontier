import Lake
open Lake DSL

package «frontier» where
  leanOptions := #[⟨`autoImplicit, false⟩]

-- The planner and its JSON-LD domain reader, as a library.
require persona from git "https://github.com/V-Sekai-fire/interactor-taskweft-persona" @ "main"

-- The C shim: SQLite in, JSON rows out (c/sql.c). Homebrew's sqlite on macOS, the system one on Linux.
target sql.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "sql.o"
  let srcJob ← inputTextFile <| pkg.dir / "c" / "sql.c"
  let leanInc := (← getLeanIncludeDir).toString
  let brew := "/opt/homebrew/opt/sqlite/include"
  buildO oFile srcJob #["-I", leanInc, "-I", brew, "-fPIC", "-O2"] #[] "cc"

extern_lib libfrontier_sql pkg := do
  let name := nameToStaticLib "frontier_sql"
  let job ← fetch <| pkg.target ``sql.o
  buildStaticLib (pkg.staticLibDir / name) #[job]

lean_lib «Frontier» where
  srcDir := "."

-- Lean's bundled clang/lld searches none of the distro library dirs, so name them.
def sqliteLink : Array String :=
  if System.Platform.isOSX then #["-L/opt/homebrew/opt/sqlite/lib", "-lsqlite3"]
  else #["-L/usr/lib64", "-L/usr/lib/x86_64-linux-gnu", "-L/usr/lib/aarch64-linux-gnu", "-lsqlite3"]

-- The server: HTTP/1.1 A2A on --port, and an Erlang distribution node on --dist-port.
@[default_target]
lean_exe «frontier» where
  root := `Main
  moreLinkArgs := sqliteLink

-- The green gate: the domain plans cold for every subject, the learn gate holds, MD5 and ETF
-- round-trip, and a planted fault fails each.
@[default_target]
lean_exe «frontier_witness» where
  root := `Witness
  moreLinkArgs := sqliteLink
