import Lake
open Lake DSL

package «frontier» where
  leanOptions := #[⟨`autoImplicit, false⟩]

-- The planner and its JSON-LD domain reader, as a library.
require persona from git "https://github.com/V-Sekai-fire/interactor-taskweft-persona" @ "main"

-- `lake build -Kfdb=/usr/lib64/libfdb_c.so` links datasource-store's weft_fdb VFS in directly.
def fdbLib : Option String := get_config? fdb

-- The C shim: SQLite in, JSON rows out (c/sql.c), with the vendored SQLite amalgamation compiled
-- beside it, so the node links no system SQLite on any platform.
target sql.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "sql.o"
  let srcJob ← inputTextFile <| pkg.dir / "c" / "sql.c"
  let leanInc := (← getLeanIncludeDir).toString
  let fdbFlag := if fdbLib.isSome then #["-DFRONTIER_WITH_FDB"] else #[]
  buildO oFile srcJob (#["-I", leanInc, "-I", (pkg.dir / "thirdparty" / "sqlite").toString, "-fPIC", "-O2"] ++ fdbFlag) #[] "cc"

target sqlite3.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "sqlite3.o"
  let srcJob ← inputTextFile <| pkg.dir / "thirdparty" / "sqlite" / "sqlite3.c"
  buildO oFile srcJob #["-fPIC", "-O2", "-DSQLITE_THREADSAFE=1"] #[] "cc"

-- The VFS object (the store's rung 11 shape), against FoundationDB's client library named by
-- path. Without -Kfdb the VFS still loads as the store's `weftfdb` extension through FRONTIER_VFS_EXT.
target fdb_vfs.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "fdb_vfs.o"
  let srcJob ← inputTextFile <| pkg.dir / "thirdparty" / "datasource-store" / "fdb_vfs.c"
  buildO oFile srcJob #["-I", (pkg.dir / "thirdparty" / "sqlite").toString, "-I", "/usr/include/foundationdb", "-I", "/usr/local/include/foundationdb",
    "-DFDB_API_VERSION=730", "-D_POSIX_C_SOURCE=200809L", "-fPIC", "-O2"] #[] "cc"

extern_lib libfrontier_sql pkg := do
  let name := nameToStaticLib "frontier_sql"
  let a ← fetch <| pkg.target ``sql.o
  let b ← fetch <| pkg.target ``sqlite3.o
  let objs ← if fdbLib.isSome then do let f ← fetch <| pkg.target ``fdb_vfs.o; pure #[a, b, f] else pure #[a, b]
  buildStaticLib (pkg.staticLibDir / name) objs

lean_lib «Frontier» where
  srcDir := "."

-- SQLite is vendored and compiled in; only libdl and libm are needed beside it on Linux.
def sqliteLink : Array String :=
  (if System.Platform.isOSX then #[] else #["-ldl", "-lm", "-lpthread"]) ++ (fdbLib.map (#[·])).getD #[]

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
