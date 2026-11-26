-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: Apache-2.0 OR MIT
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

/-- The plan, under the frontier's own context: the planner's context has no `@vocab`, so its plain keys would
expand to nothing. -/
def planJson (k : Knowledge) (problem : Json) : Json :=
  match Json.parse (planText k problem) with
  | .ok plan => if (plan.getObjVal? "@context").isOk then plan.setObjVal! "@context" Gen.ctx else plan
  | .error _ => Json.mkObj [("refused", "bad_plan")]

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
    -- by id (a pointer), else by name, else by alias (the old number, kept so `reach-character-10` still works)
    if (stageIds k).contains w then some w
    else ((obj (field k "stages")).find? (fun (_, v) => str (field v "name") == w)
      <|> (obj (field k "stages")).find? (fun (_, v) => str (field v "alias") == w)).map (·.1)
  let (subj, rest) :=
    match t.splitOn " " with
    | [a, b] => if (subs.lookup a).isSome then (a, b) else ("character", t)
    | [a] =>
      let a' := if a.startsWith "reach-" then dropN a 6 else a
      match a'.splitOn "-" with
      -- split at the first dash, because a stage id can hold dashes (`character-look-dev`); `look-dev` is a stage
      -- id, not the subject `look` and a stage `dev`, so split only when the rest is a stage
      | s :: r :: rs =>
        let n := "-".intercalate (r :: rs)
        if (subs.lookup s).isSome && (stageOf n).isSome then (s, n) else ("character", a')
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
