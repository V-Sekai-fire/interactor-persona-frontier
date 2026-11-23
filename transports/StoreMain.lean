import Frontier.Import
/-! The stored planner documents: `frontier_store migrate | domain NAME | problem NAME | plan PROBLEM | import FILE... | fixtures ROOT`. -/
open Lean Frontier

def readJson (path : String) : IO Json := do
  match Json.parse (← IO.FS.readFile path) with
  | .ok j => pure j
  | .error e => throw (IO.userError s!"{path}: {e}")

def jsonldIn (dir : String) : IO (List String) := do
  if !(← System.FilePath.isDir dir) then return []
  let es ← System.FilePath.readDir dir
  let names := es.toList.map (·.path.toString) |>.filter (·.endsWith ".jsonld")
  pure (names.toArray.qsort (· < ·)).toList

def normalized (text : String) : String := ((Json.parse text).toOption.map (·.compress)).getD text

def clip (s : String) : String := if s.length > 220 then (s.take 220).toString ++ "..." else s

def importAll (files : List String) : IO (List (String × String)) := do
  let mut done : List (String × String) := []
  for f in files do
    let doc ← readJson f
    done := done ++ [(Import.str doc "@type", ← Import.importDocument doc)]
  pure done

def stem (path : String) : String := ((System.FilePath.mk path).fileStem).getD path

/-- A plan fixture is paired with the problem fixture of the same file name; the plan's own `problem` field is
replaced by that problem's name, and a difference is reported, because it is an inconsistency in the fixtures. -/
def pairedPlan (problemFiles : List String) (f : String) : IO Json := do
  let doc ← readJson f
  let some pf := problemFiles.find? (stem · == stem f) | pure doc
  let name := Import.str (← readJson pf) "name"
  if name != Import.str doc "problem" then
    IO.println s!"  note  plan {stem f} names the problem {Import.str doc "problem"}; the problem file {stem pf} is named {name}"
  pure (doc.setObjVal! "problem" (Json.str name))

/-- Import every fixture into an empty database, then plan each problem from the stored documents and from the files. -/
def fixtures (root : String) : IO UInt32 := do
  let used ← Db.sql "SELECT count(*) AS n FROM domain;"
  if (Store.number (used[0]!) "n") != 0 then
    IO.eprintln "FAILED the database is not empty; point FRONTIER_DB at a new file"; return 2
  let domainFiles := (← jsonldIn s!"{root}/domains") ++ (← jsonldIn s!"{root}/fixtures/domains")
  let problemFiles ← jsonldIn s!"{root}/fixtures/problems"
  let planFiles ← jsonldIn s!"{root}/fixtures/plans"
  let _ ← importAll domainFiles
  let _ ← importAll problemFiles
  let paired ← planFiles.mapM (pairedPlan problemFiles)
  let mut plans : List Json := []
  for doc in paired do
    try
      let _ ← Import.importDocument doc
      plans := plans ++ [doc]
    catch e =>
      if (toString e).endsWith "is not an action of the domain" then
        IO.println s!"  SKIP  plan of {Import.str doc "problem"} is stale: {e}"
      else throw e
  let mut failures := 0
  let mut checks := 0
  let domainTexts ← domainFiles.mapM fun f => do pure (Import.str (← readJson f) "name", ← IO.FS.readFile f)
  for f in problemFiles do
    let text ← IO.FS.readFile f
    let doc ← readJson f
    let some (_, dtext) := domainTexts.find? (·.1 == Import.str doc "domain") | IO.eprintln s!"FAIL {f}: no domain file"; failures := failures + 1; continue
    let want := normalized (Persona.Jsonld.planOf dtext text)
    let got := normalized (← Store.plan (Import.str doc "name"))
    checks := checks + 1
    if want == got then IO.println s!"  ok   plan of {Import.str doc "name"} is the same from the tables"
    else IO.println s!"  FAIL plan of {Import.str doc "name"}\n    files:  {clip want}\n    tables: {clip got}"; failures := failures + 1
  for doc in plans do
    let want := doc.compress
    let got := (← Store.planDocJson (Import.str doc "problem")).compress
    checks := checks + 1
    if want == got then IO.println s!"  ok   plan document of {Import.str doc "problem"} round trips"
    else IO.println s!"  FAIL plan document of {Import.str doc "problem"}\n    file:   {clip want}\n    tables: {clip got}"; failures := failures + 1
  IO.println (if failures == 0 then s!"OK: {checks} checks" else s!"FAILED: {failures} of {checks}")
  pure (if failures == 0 then 0 else 1)

def main (args : List String) : IO UInt32 := do
  Db.init
  match args with
  | ["migrate"] => pure 0
  | ["domain", name] => IO.println (← Store.domainJson name).compress; pure 0
  | ["problem", name] => IO.println (← Store.problemJson name).compress; pure 0
  | ["plan", name] => IO.println (← Store.plan name); pure 0
  | "import" :: files => for (kind, name) in ← importAll files do IO.println s!"{kind} {name}"
                         pure 0
  | ["fixtures", root] => fixtures root
  | _ => IO.eprintln "usage: frontier_store migrate | domain NAME | problem NAME | plan PROBLEM | import FILE... | fixtures ROOT"; pure 2
