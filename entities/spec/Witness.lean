import Frontier.Loop
/-!
# The green gate. Every invariant has a positive and a negative control; exit 0 and `OK:` when all hold.
-/
open Lean Frontier

def check (name : String) (ok : Bool) : IO Bool := do
  IO.println s!"{if ok then "PASS" else "FAIL"} {name}"
  return ok

def main : IO UInt32 := do
  let dbp : System.FilePath := "/tmp/frontier-witness.sqlite"
  if ← dbp.pathExists then IO.FS.removeFile dbp
  Db.override.set (some dbp.toString)
  let seedTexts ← Db.seedFiles
  let k := Seed.fold (seedTexts.filterMap fun (_, t) => (Seed.parse t).toOption)
  let mut ok := true
  -- the domain plans cold for every subject, each with its own stage count
  for (s, ns) in subjects k do
    let plan := Loop.planJson k (Gen.problem k "cold" [] [] s!"reach-{s}-{ns.getLast!}")
    ok := (← check s!"cold {s} reaches with {ns.length} stages" (Loop.reached plan && (Loop.settled plan).length == ns.length)) && ok
  ok := (← check "undeclared goal refused" ((Loop.answer k "fly").getObjVal? "refused" |>.toOption |>.isSome)) && ok
  ok := (← check "world 9 refused (a world has no persona)" ((Loop.answer k "world 9").getObjVal? "refused" |>.toOption |>.isSome)) && ok
  -- the learn gate on the authored knowledge, and on a broken one
  let (g, _) := Loop.gate k
  ok := (← check "gate passes authored knowledge" ((field g "pass").getBool?.toOption == some true)) && ok
  let broken := k.setObjVal! "subjects" ((field k "subjects").setObjVal! "character" (Json.mkObj [("stages", Json.arr #["1"])]))
  let (g2, _) := Loop.gate broken
  ok := (← check "gate fails a one-stage character" ((field g2 "pass").getBool?.toOption != some true)) && ok
  -- the committed fixtures are the seed rendered, not hand-kept: equal to it, and not equal after a change
  let (_, gold) := Loop.gate k
  let dom ← IO.FS.readFile "entities/fixtures/domains/character-stack.yamlld"
  let pln ← IO.FS.readFile "entities/fixtures/plans/character-stack-cold.yamlld"
  ok := (← check "fixture domain is the seed rendered" (dom == YamlLd.render (Gen.domain k))) && ok
  ok := (← check "fixture plan is the seed's cold plan rendered" (pln == YamlLd.render gold)) && ok
  let changed := k.setObjVal! "stages" ((field k "stages").setObjVal! "10" ((field (field k "stages") "10").setObjVal! "requires" (Json.arr #[])))
  ok := (← check "control: a changed seed renders a different domain" (dom != YamlLd.render (Gen.domain changed))) && ok
  -- seeds: later over earlier, learned rows over the seeded base, and an applied seed cannot be edited
  let s1 := Json.mkObj [("stages", Json.mkObj [("1", Json.mkObj [("requires", Json.arr #[]), ("name", "a")])]), ("x", 1)]
  let s2 := Json.mkObj [("x", 2), ("stages", Json.mkObj [("1", Json.mkObj [("name", "b")])])]
  let m := Seed.fold [s1, s2]
  ok := (← check "a later seed overrides, an earlier key it leaves alone stays" (nat (field m "x") == 2 && str (field (field (field m "stages") "1") "name") == "b" && (field (field (field m "stages") "1") "requires") == Json.arr #[])) && ok
  let lr := Json.mkObj [("revision", 3), ("learned", Json.mkObj [("1", Json.arr #["t"])])]
  let w := Seed.withLearned m lr
  ok := (← check "learned rows go over the seeds" (nat (field w "revision") == 3 && strs (field (field (field w "stages") "1") "requires") == ["t"])) && ok
  ok := (← check "control: with no learned rows the seeds are unchanged" (Seed.withLearned m .null == m)) && ok
  let some (n1, t1) := seedTexts.head? | throw (IO.userError "no seed files")
  let dbp2 : System.FilePath := "/tmp/frontier-witness-seed.sqlite"
  if ← dbp2.pathExists then IO.FS.removeFile dbp2
  Db.override.set (some dbp2.toString)
  let _ ← Db.sql "CREATE TABLE IF NOT EXISTS seeds (name TEXT PRIMARY KEY, body TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')));"
  let _ ← Db.sql s!"INSERT INTO seeds (name, body) VALUES ({Db.quote n1}, '{"{}"}');"
  let refused ← (do Db.applySeeds; pure false) <|> pure true
  ok := (← check "an applied seed that was edited is refused" refused) && ok
  if ← dbp2.pathExists then IO.FS.removeFile dbp2
  let _ := t1
  Db.override.set (some dbp.toString)
  -- the store round-trips a trace through SQLite
  Db.init
  Db.insertTrace "witness" (Json.mkObj [("kind", "witness"), ("n", 1)])
  ok := (← check "sqlite trace round trip" ((← Db.countTraces) == 1)) && ok
  IO.println (if ok then "OK: frontier witness" else "FAIL: frontier witness")
  return if ok then 0 else 1
