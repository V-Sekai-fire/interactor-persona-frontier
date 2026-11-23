import Lean.Data.Json
import Frontier.Seed
/-!
# The store: SQLite through one C shim, pages in FoundationDB when datasource-store's VFS is loaded.
`FRONTIER_DB` is the database URL (default `frontier.sqlite`; `file:frontier?vfs=weft_fdb` with
`FRONTIER_VFS_EXT` pointing at `fdb_vfs_ext`). Two tables: `traces` (kind, body) and `knowledge`
(one row, body). Every query goes through `sql`, which returns the rows as JSON.
-/
namespace Frontier.Db

open Lean

@[extern "frontier_sql"] opaque sqlRaw : @& String → @& String → String

/-- A path set in-process (the witness uses it) wins over `FRONTIER_DB`. -/
initialize override : IO.Ref (Option String) ← IO.mkRef none

def url : IO String := do
  match ← override.get with
  | some u => pure u
  | none => return (← IO.getEnv "FRONTIER_DB").getD "frontier.sqlite"

def quote (s : String) : String := "'" ++ s.replace "'" "''" ++ "'"

def sql (q : String) : IO (Array Json) := do
  let out := sqlRaw (← url) q
  match Json.parse out with
  | .ok j => match j.getObjVal? "rows" with
    | .ok (.arr rows) => pure rows
    | _ => throw (IO.userError s!"sql: {out}")
  | .error e => throw (IO.userError s!"sql: {e}: {out}")

/-- The numbered `.sql` files of `datasources/sqlite/migrations`, in order. -/
def migrationFiles : IO (Array System.FilePath) := do
  let entries ← System.FilePath.readDir "datasources/sqlite/migrations"
  let files := entries.filter (·.path.extension == some "sql") |>.map (·.path)
  pure (files.qsort (·.toString < ·.toString))

def applied (name : String) : IO Bool := do
  let rows ← sql s!"SELECT 1 FROM schema_migrations WHERE name = {quote name};"
  pure (!rows.isEmpty)

/-- One migration and its ledger row in one transaction, so a failed file leaves nothing behind. -/
def migrate (file : System.FilePath) : IO Unit := do
  let name := file.fileName.getD file.toString
  if !(← applied name) then
    let text ← IO.FS.readFile file
    let _ ← sql s!"BEGIN; {text}\nINSERT INTO schema_migrations (name) VALUES ({quote name}); COMMIT;"

def init : IO Unit := do
  let _ ← sql "CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')));"
  let _ ← sql "CREATE TABLE IF NOT EXISTS traces (id INTEGER PRIMARY KEY, at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), kind TEXT NOT NULL, body TEXT NOT NULL); CREATE TABLE IF NOT EXISTS knowledge (id INTEGER PRIMARY KEY CHECK (id = 1), body TEXT NOT NULL, revision INTEGER NOT NULL);"
  for f in ← migrationFiles do migrate f

def insertTrace (kind : String) (body : Json) : IO Unit := do
  let _ ← sql s!"INSERT INTO traces (kind, body) VALUES ({quote kind}, {quote body.compress});"

def traces : IO (List Json) := do
  let rows ← sql "SELECT at, body FROM traces ORDER BY id;"
  return rows.toList.filterMap fun r => do
    let body ← (r.getObjVal? "body").toOption >>= (·.getStr?.toOption)
    let stamp ← (r.getObjVal? "at").toOption
    (Json.parse body).toOption.map (·.setObjVal! "at" stamp)

def countTraces : IO Nat := do
  let rows ← sql "SELECT count(*) AS n FROM traces;"
  return (rows[0]? >>= fun r => (r.getObjVal? "n").toOption >>= (·.getStr?.toOption) >>= String.toNat?).getD 0

/-- The numbered seed files, in name order. -/
def seedFiles : IO (List (String × String)) := do
  let ents ← (System.FilePath.mk "seeds").readDir
  let names : List String := (ents.toList.map fun (e : IO.FS.DirEntry) => e.fileName).filter (fun (n : String) => n.endsWith ".yamlld")
  let sorted : List String := (names.toArray.qsort (fun (a b : String) => a < b)).toList
  sorted.mapM fun (n : String) => do
    let text ← IO.FS.readFile (System.FilePath.mk "seeds" / n)
    return (n, text)

/-- Apply each seed file once, in order. A file already applied must still match what was applied: a change
goes in a new seed, so an edit to an old one is refused, as a migration's checksum would be. -/
def applySeeds : IO Unit := do
  let _ ← sql "CREATE TABLE IF NOT EXISTS seeds (name TEXT PRIMARY KEY, body TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')));"
  for (name, text) in ← seedFiles do
    let body ← match Frontier.Seed.parse text with
      | .ok j => pure j.compress
      | .error e => throw (IO.userError s!"seed {name}: {e}")
    let rows ← sql s!"SELECT body FROM seeds WHERE name = {quote name};"
    match rows[0]? >>= fun r => (r.getObjVal? "body").toOption >>= (·.getStr?.toOption) with
    | none => let _ ← sql s!"INSERT INTO seeds (name, body) VALUES ({quote name}, {quote body});"
    | some old =>
      if old != body then throw (IO.userError s!"seed {name} was edited after it was applied; add a new seed instead")

/-- The knowledge: the applied seeds in order, with the learned rows over them. -/
def knowledge : IO Json := do
  applySeeds
  let rows ← sql "SELECT body FROM seeds ORDER BY name;"
  let seeds := rows.toList.filterMap fun r => (r.getObjVal? "body").toOption >>= (·.getStr?.toOption) >>= fun b => (Json.parse b).toOption
  let learned ← sql "SELECT body FROM knowledge WHERE id = 1;"
  let ov := (learned[0]? >>= fun r => (r.getObjVal? "body").toOption >>= (·.getStr?.toOption) >>= fun b => (Json.parse b).toOption).getD .null
  return Frontier.Seed.withLearned (Frontier.Seed.fold seeds) ov

/-- Only the learned rows are stored; the seeds are not copied into the knowledge row. -/
def putKnowledge (k : Json) : IO Unit := do
  let l := Frontier.Seed.learnedOf k
  let rev := ((l.getObjVal? "revision").toOption >>= (·.getNat?.toOption)).getD 0
  let _ ← sql s!"INSERT INTO knowledge (id, body, revision) VALUES (1, {quote l.compress}, {rev}) ON CONFLICT(id) DO UPDATE SET body = excluded.body, revision = excluded.revision;"

end Frontier.Db
