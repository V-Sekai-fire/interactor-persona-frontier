import Frontier.Gen
import Persona.Jsonld
import Frontier.Db
import Frontier.Answer
import YamlLd
/-!
# The frontier loop: plan, levels, practice, experience, learn with its gate.
A level is (subject, goal position, held prefix) over that subject's own stage list. Level search
practises the levels at the edge of competence. Experience reports from real stage runs are the
only truth; learning folds them into the knowledge file and lands a revision only through the gate.
-/
namespace Frontier.Loop

open Lean Frontier

def record (t : Json) : IO Unit := Db.insertTrace (str (field t "kind")) t

def traces : IO (List Json) := Db.traces

structure Level where
  subject : String
  goal : Nat
  held : Nat
  attempts : Nat := 0
  reached : Nat := 0

def Level.toJson (l : Level) : Json :=
  Json.mkObj [("subject", l.subject), ("goal", l.goal), ("held", l.held), ("attempts", l.attempts), ("reached", l.reached)]

def levels (k : Knowledge) : IO (List Level) := do
  let ts := (← traces).filter fun t => str (field t "kind") == "practice"
  return (subjects k).flatMap fun (s, ns) =>
    (List.range ns.length).flatMap fun g0 => (List.range (g0 + 1)).map fun h =>
      let g := g0 + 1
      let mine := ts.filter fun t => str (field t "subject") == s && nat (field t "goal") == g && nat (field t "held") == h
      { subject := s, goal := g, held := h, attempts := mine.length, reached := (mine.filter fun t => (field t "reached").getBool?.toOption.getD false).length }

def nextLevel (k : Knowledge) : IO (Option Level) := do
  let ls ← levels k
  let hit (s : String) (g h : Nat) : Bool := ls.any fun l => l.subject == s && l.goal == g && l.held == h && l.reached > 0
  let edge := ls.filter fun l =>
    (l.attempts > 0 && l.reached < l.attempts) ||
    (l.attempts == 0 && (l.goal == 1 || hit l.subject (l.goal - 1) l.held || (l.held > 0 && hit l.subject l.goal (l.held - 1))))
  let better (l b : Level) : Bool :=
    l.attempts < b.attempts || (l.attempts == b.attempts && (l.goal < b.goal || (l.goal == b.goal && (l.held > b.held || (l.held == b.held && l.subject < b.subject)))))
  return edge.foldl (fun best l => match best with
    | none => some l
    | some b => if better l b then some l else some b) none

def practice (k : Knowledge) : IO Json := do
  match ← nextLevel k with
  | none => return Json.mkObj [("done", true)]
  | some l =>
    let list := ((subjects k).lookup l.subject).getD []
    let heldN := list.take l.held
    let held := heldN.map fun n => s!"{l.subject}-{n}"
    let goalN := (list[l.goal - 1]?).getD "1"
    let mut toks := heldN.flatMap (tokensOf k)
    for t in allTokens k do
      if (← IO.rand 0 9) < 3 then toks := toks ++ [t]
    let t0 ← IO.monoMsNow
    let plan := planJson k (Gen.problem k "practice" held toks.eraseDups s!"reach-{l.subject}-{goalN}")
    let ms := (← IO.monoMsNow) - t0
    let t := Json.mkObj [("kind", "practice"), ("subject", l.subject), ("goal", l.goal), ("held", l.held), ("reached", reached plan),
      ("refused", field plan "refused"), ("steps", ((field plan "steps").getArr?.toOption.getD #[]).size), ("ms", ms),
      ("settled", Json.arr (settled plan |>.map Json.str).toArray)]
    record t
    return t

def experience (r : Json) : IO Json := do
  let action := str (field r "action")
  let hb := strs (field r "held_before")
  match (field r "settled").getBool?.toOption, action.startsWith "settle-" with
  | some s, true =>
    let rest := dropN action 7
    let (subj, n) := match rest.splitOn "-" with | [a, b] => (a, b) | _ => ("character", rest)
    let t := Json.mkObj [("kind", "experience"), ("subject", subj), ("stage", n), ("held_before", Json.arr (hb.map Json.str).toArray),
      ("settled", s), ("duration", field r "duration")]
    record t
    return Json.mkObj [("recorded", t)]
  | _, _ => return Json.mkObj [("refused", "bad_experience")]

/-- The gate: the cold character problem reaches with every character stage settled (positive
control), and a domain where stage 10 forgets its requirements plans differently (negative). -/
def gate (k : Knowledge) : Json × Json :=
  let cold := Gen.problem k "gate" [] [] "reach-character-10"
  let gold := planJson k cold
  let nChar := ((subjects k).lookup "character").getD [] |>.length
  let positive := reached gold && (settled gold).length == nChar
  let broken := k.setObjVal! "stages" ((field k "stages").setObjVal! "10" ((field (field k "stages") "10").setObjVal! "requires" (Json.arr #[])))
  let bad := planJson broken cold
  let negative := field bad "steps" != field gold "steps"
  (Json.mkObj [("pass", positive && negative), ("positive", positive), ("negative", negative)], gold)

def bare (hb : List String) : List String := hb.map fun h => match h.splitOn "-" with | [_, n] => n | _ => h

def learn (k : Knowledge) : IO Json := do
  let ex := (← traces).filter fun t => str (field t "kind") == "experience"
  let mut k2 := k
  for e in ex do
    let n := str (field e "stage")
    if let .str d := field e "duration" then
      k2 := k2.setObjVal! "durations" ((field k2 "durations").setObjVal! n (Json.str d))
    let reports := ex.filter fun t => str (field t "stage") == n
    let ok := reports.filter fun t => (field t "settled").getBool?.toOption.getD false
    let badR := reports.filter fun t => !((field t "settled").getBool?.toOption.getD false)
    if !ok.isEmpty && !badR.isEmpty then
      let always := (ok.map fun t => bare (strs (field t "held_before"))).foldl (fun acc s => acc.filter s.contains) (bare (strs (field ok.head! "held_before")))
      let never := badR.flatMap fun t => bare (strs (field t "held_before"))
      let learned := (always.filter fun x => !never.contains x && x != n && (stageIds k).contains x).eraseDups
      let st := field k2 "stages"
      let cur := field st n
      let reqs := ((requiresOf k2 n) ++ learned).eraseDups
      k2 := k2.setObjVal! "stages" (st.setObjVal! n (cur.setObjVal! "requires" (Json.arr (reqs.map Json.str).toArray)))
      let prev := strs (field (field k2 "learned") n)
      k2 := k2.setObjVal! "learned" ((field k2 "learned").setObjVal! n (Json.arr ((prev ++ learned).eraseDups.map Json.str).toArray))
  k2 := k2.setObjVal! "revision" (toJson (nat (field k "revision") + 1))
  let (g, gold) := gate k2
  let pass := (field g "pass").getBool?.toOption.getD false
  if pass then
    -- what is learned lives in the store only; `seeds/` is the authored data and the fixtures are
    -- rendered from it, so a learned duration never changes a tracked file
    Db.putKnowledge k2
  return Json.mkObj [("revision", if pass then field k2 "revision" else field k "revision"), ("gate", g),
    ("requires", Json.mkObj ((stageIds k2).map fun n => (n, Json.arr ((requiresOf k2 n).map Json.str).toArray))), ("durations", field k2 "durations")]

end Frontier.Loop
