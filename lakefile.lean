import Lake
open Lake DSL

package «frontier» where
  leanOptions := #[⟨`autoImplicit, false⟩]

-- The planner and its JSON-LD domain reader, as a library.
require persona from git "https://github.com/V-Sekai-fire/interactor-taskweft-persona" @ "main"

-- The C shim: SQLite in, JSON rows out (c/sql.c), with the vendored SQLite amalgamation compiled
-- beside it, so the node links no system SQLite on any platform.
target sql.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "sql.o"
  let srcJob ← inputTextFile <| pkg.dir / "c" / "sql.c"
  let leanInc := (← getLeanIncludeDir).toString
  buildO oFile srcJob #["-I", leanInc, "-I", (pkg.dir / "thirdparty" / "sqlite").toString, "-fPIC", "-O2"] #[] "cc"

target sqlite3.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "sqlite3.o"
  let srcJob ← inputTextFile <| pkg.dir / "thirdparty" / "sqlite" / "sqlite3.c"
  buildO oFile srcJob #["-fPIC", "-O2", "-DSQLITE_THREADSAFE=1", "-DSQLITE_OMIT_LOAD_EXTENSION=0", "-DSQLITE_ENABLE_LOAD_EXTENSION=1"] #[] "cc"

extern_lib libfrontier_sql pkg := do
  let name := nameToStaticLib "frontier_sql"
  let a ← fetch <| pkg.target ``sql.o
  let b ← fetch <| pkg.target ``sqlite3.o
  buildStaticLib (pkg.staticLibDir / name) #[a, b]

lean_lib «Frontier» where
  srcDir := "."

-- SQLite is vendored and compiled in; only libdl and libm are needed beside it on Linux.
def sqliteLink : Array String := if System.Platform.isOSX then #[] else #["-ldl", "-lm", "-lpthread"]

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
