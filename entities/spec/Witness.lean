-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: Apache-2.0 OR MIT
import Frontier.Loop
/-!
# The green gate. Every invariant has a positive and a negative control; exit 0 and `OK:` when all hold.
-/
open Lean Frontier

def check (name : String) (ok : Bool) : IO Bool := do
  IO.println s!"{if ok then "PASS" else "FAIL"} {name}"
  return ok

def main (args : List String) : IO UInt32 := do
  let dbp : System.FilePath := "/tmp/frontier-witness.sqlite"
  if ← dbp.pathExists then IO.FS.removeFile dbp
  Db.override.set (some dbp.toString)
  let seedTexts ← Db.seedFiles
  let k := Seed.fold (seedTexts.filterMap fun (_, t) => (Seed.parse t).toOption)
  let mut ok := true
  -- `frontier_witness write` renders the fixtures from the seeds; the checks below then hold them to it
  if args == ["write"] then
    let (_, g) := Loop.gate k
    IO.FS.writeFile "entities/fixtures/domains/character-stack.yamlld" (YamlLd.render (Gen.domain k))
    IO.FS.writeFile "entities/fixtures/plans/character-stack-cold.yamlld" (YamlLd.render g)
  -- the domain plans cold for every subject, each with its own stage count
  for (s, ns) in subjects k do
    let plan := Loop.planJson k (Gen.problem k "cold" [] [] s!"reach-{s}-{ns.getLast!}")
    ok := (← check s!"cold {s} reaches with {ns.length} stages" (Loop.reached plan && (Loop.settled plan).length == ns.length)) && ok
  ok := (← check "undeclared goal refused" ((Loop.answer k "fly").getObjVal? "refused" |>.toOption |>.isSome)) && ok
  ok := (← check "world 9 refused (a world has no persona)" ((Loop.answer k "world 9").getObjVal? "refused" |>.toOption |>.isSome)) && ok
  -- the learn gate on the authored knowledge, and on a broken one
  let (g, _) := Loop.gate k
  ok := (← check "gate passes authored knowledge" ((field g "pass").getBool?.toOption == some true)) && ok
  let broken := k.setObjVal! "subjects" ((field k "subjects").setObjVal! "character" (Json.mkObj [("stages", Json.arr #["look-dev"])]))
  let (g2, _) := Loop.gate broken
  ok := (← check "gate fails a one-stage character" ((field g2 "pass").getBool?.toOption != some true)) && ok
  -- the committed fixtures are the seed rendered, not hand-kept: equal to it, and not equal after a change
  let (_, gold) := Loop.gate k
  let dom ← IO.FS.readFile "entities/fixtures/domains/character-stack.yamlld"
  let pln ← IO.FS.readFile "entities/fixtures/plans/character-stack-cold.yamlld"
  ok := (← check "fixture domain is the seed rendered" (dom == YamlLd.render (Gen.domain k))) && ok
  ok := (← check "fixture plan is the seed's cold plan rendered" (pln == YamlLd.render gold)) && ok
  let changed := k.setObjVal! "stages" ((field k "stages").setObjVal! "runtime" ((field (field k "stages") "runtime").setObjVal! "requires" (Json.arr #[])))
  ok := (← check "control: a changed seed renders a different domain" (dom != YamlLd.render (Gen.domain changed))) && ok
  -- seeds: later over earlier, learned rows over the seeded base, and an applied seed cannot be edited
  let s1 := Json.mkObj [("stages", Json.mkObj [("1", Json.mkObj [("requires", Json.arr #[]), ("name", "a")])]), ("x", 1)]
  let s2 := Json.mkObj [("x", 2), ("stages", Json.mkObj [("1", Json.mkObj [("name", "b")])])]
  let m := Seed.fold [s1, s2]
  ok := (← check "a later seed overrides, an earlier key it leaves alone stays" (nat (field m "x") == 2 && str (field (field (field m "stages") "1") "name") == "b" && (field (field (field m "stages") "1") "requires") == Json.arr #[])) && ok
  let dropped := Seed.fold [s1, Json.mkObj [("x", .null), ("stages", Json.mkObj [("1", .null)])]]
  ok := (← check "a null in a later seed removes the key" ((field dropped "x") == .null && (obj (field dropped "stages")).isEmpty && (obj dropped).any (·.1 == "stages") && !(obj dropped).any (·.1 == "x"))) && ok
  ok := (← check "control: without the null the key stays" ((obj (Seed.fold [s1, Json.mkObj [("y", 1)]])).any (·.1 == "x"))) && ok
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
  -- stage ids are not numbers: pointer ids keep the authored order and answer to their old number as an alias
  let pk := Json.mkObj [
    ("subjects", Json.mkObj [("character", Json.mkObj [("stages", Json.arr #["/stage/z", "/stage/a"])])]),
    ("stages", Json.mkObj [("/stage/a", Json.mkObj [("name", "alpha"), ("alias", "2")]), ("/stage/z", Json.mkObj [("name", "zeta"), ("alias", "1")])])]
  ok := (← check "stage order is the authored list, not the key sort" (stageIds pk == ["/stage/z", "/stage/a"])) && ok
  ok := (← check "an old number resolves to its pointer stage" (Loop.goalOf pk "2" == some ("character", "/stage/a"))) && ok
  ok := (← check "control: a number with no alias is not a stage" (Loop.goalOf pk "3" == none)) && ok
  ok := (← check "bare keeps an id that holds dashes" (Loop.bare ["character-/stage/look-dev", "prop-7"] == ["/stage/look-dev", "7"])) && ok
  -- the store round-trips a trace through SQLite
  Db.init
  Db.insertTrace "witness" (Json.mkObj [("kind", "witness"), ("n", 1)])
  ok := (← check "sqlite trace round trip" ((← Db.countTraces) == 1)) && ok
  IO.println (if ok then "OK: frontier witness" else "FAIL: frontier witness")
  return if ok then 0 else 1
