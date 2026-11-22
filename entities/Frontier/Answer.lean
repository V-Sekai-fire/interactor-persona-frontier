import Frontier.Gen
import Persona.Jsonld
/-!
# The answer to a goal, pure.
Knowledge text and a goal in, the plan or a refusal by name out. It imports no store, so the Lean library
that `leanler` builds for Elixir holds only this and the generator. It lives in `Frontier.Loop`'s namespace
so the loop and the transports call it as before.
-/
namespace Frontier.Loop

open Lean Frontier

def dropN (s : String) (n : Nat) : String := (s.toSubstring.drop n).toString

def planText (k : Knowledge) (problem : Json) : String :=
  Persona.Jsonld.planOf (Gen.domain k).compress problem.compress

def planJson (k : Knowledge) (problem : Json) : Json :=
  (Json.parse (planText k problem)).toOption.getD (Json.mkObj [("refused", "bad_plan")])

def settled (plan : Json) : List String :=
  (strsOf (field plan "steps")).filter (·.startsWith "settle-")
where strsOf (j : Json) : List String := ((j.getArr?).toOption.getD #[]).toList.map fun s => str (field s "action")

def reached (plan : Json) : Bool := (field plan "reached").getBool?.toOption.getD false

/-- `reach-<subject>-N`, `<subject> N`, `<subject>` (its last stage), a stage number or stage name
(the character's), or empty (the character's last stage). -/
def goalOf (k : Knowledge) (text : String) : Option (String × String) := do
  let subs := subjects k
  let t := text.trimAscii.toString.toLower
  let stageOf (w : String) : Option String :=
    if (stageIds k).contains w then some w
    else (obj (field k "stages")).find? (fun (_, v) => str (field v "name") == w) |>.map (·.1)
  let (subj, rest) :=
    match t.splitOn " " with
    | [a, b] => if (subs.lookup a).isSome then (a, b) else ("character", t)
    | [a] =>
      let a' := if a.startsWith "reach-" then dropN a 6 else a
      match a'.splitOn "-" with
      -- `look-dev` is a stage name, not the subject `look` and a stage `dev`: split only when the second part is a stage
      | [s, n] => if (subs.lookup s).isSome && (stageOf n).isSome then (s, n) else ("character", a')
      | _ => if (subs.lookup a').isSome then (a', "") else ("character", a')
    | _ => ("character", t)
  let stages ← subs.lookup subj
  let n ← if rest == "" then stages.getLast? else stageOf rest
  if stages.contains n then pure (subj, n) else none

def answer (k : Knowledge) (text : String) : Json :=
  match goalOf k text with
  | none => Json.mkObj [("refused", "undeclared_goal")]
  | some (s, n) => planJson k (Gen.problem k "request" [] [] s!"reach-{s}-{n}")

end Frontier.Loop
