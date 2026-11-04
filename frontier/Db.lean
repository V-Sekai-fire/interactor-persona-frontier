import Lean.Data.Json
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

def init : IO Unit := do
  let _ ← sql "CREATE TABLE IF NOT EXISTS traces (id INTEGER PRIMARY KEY, at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), kind TEXT NOT NULL, body TEXT NOT NULL); CREATE TABLE IF NOT EXISTS knowledge (id INTEGER PRIMARY KEY CHECK (id = 1), body TEXT NOT NULL, revision INTEGER NOT NULL);"

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

/-- The knowledge row; seeded from `frontier/knowledge.json` when the table is empty. -/
def knowledge : IO Json := do
  let rows ← sql "SELECT body FROM knowledge WHERE id = 1;"
  match rows[0]? >>= fun r => (r.getObjVal? "body").toOption >>= (·.getStr?.toOption) >>= fun b => (Json.parse b).toOption with
  | some k => pure k
  | none =>
    let text ← IO.FS.readFile "frontier/knowledge.json"
    let k ← match Json.parse text with | .ok k => pure k | .error e => throw (IO.userError s!"knowledge.json: {e}")
    let rev := ((k.getObjVal? "revision").toOption >>= (·.getNat?.toOption)).getD 0
    let _ ← sql s!"INSERT INTO knowledge (id, body, revision) VALUES (1, {quote k.compress}, {rev});"
    pure k

def putKnowledge (k : Json) : IO Unit := do
  let rev := ((k.getObjVal? "revision").toOption >>= (·.getNat?.toOption)).getD 0
  let _ ← sql s!"INSERT INTO knowledge (id, body, revision) VALUES (1, {quote k.compress}, {rev}) ON CONFLICT(id) DO UPDATE SET body = excluded.body, revision = excluded.revision;"

end Frontier.Db
