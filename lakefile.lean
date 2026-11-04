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

-- The server: HTTP/1.1 A2A on --port, and an Erlang distribution node on --dist-port.
@[default_target]
lean_exe «frontier» where
  root := `Main
  moreLinkArgs := #["-L/opt/homebrew/opt/sqlite/lib", "-lsqlite3"]

-- The green gate: the domain plans cold for every subject, the learn gate holds, MD5 and ETF
-- round-trip, and a planted fault fails each.
@[default_target]
lean_exe «frontier_witness» where
  root := `Witness
  moreLinkArgs := #["-L/opt/homebrew/opt/sqlite/lib", "-lsqlite3"]
