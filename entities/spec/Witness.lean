import Frontier.Loop
import Frontier.Dist
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
  let k ← match Json.parse (← IO.FS.readFile "knowledge/knowledge.json") with | .ok k => pure k | .error e => throw (IO.userError e)
  let mut ok := true
  -- MD5 against RFC 1321 vectors, and a planted fault
  ok := (← check "md5 empty" (Md5.hex (Md5.digest "".toUTF8) == "d41d8cd98f00b204e9800998ecf8427e")) && ok
  ok := (← check "md5 abc" (Md5.hex (Md5.digest "abc".toUTF8) == "900150983cd24fb0d6963f7d28e17f72")) && ok
  ok := (← check "md5 planted fault fails" (Md5.hex (Md5.digest "abd".toUTF8) != "900150983cd24fb0d6963f7d28e17f72")) && ok
  -- ETF round trip and a truncated term
  let t : Etf.Term := .tuple #[.int 6, .atom "", .bin "world".toUTF8, .list #[.int 1, .int 300], .nil]
  ok := (← check "etf round trip" ((Etf.unpack (Etf.pack t) 0).toOption.map (toString ·.1) == some (toString t))) && ok
  ok := (← check "etf truncated fails" ((Etf.unpack ((Etf.pack t).extract 0 6) 0).toOption.isNone)) && ok
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
  -- the store round-trips a trace through SQLite
  Db.init
  Db.insertTrace "witness" (Json.mkObj [("kind", "witness"), ("n", 1)])
  ok := (← check "sqlite trace round trip" ((← Db.countTraces) == 1)) && ok
  IO.println (if ok then "OK: frontier witness" else "FAIL: frontier witness")
  return if ok then 0 else 1
