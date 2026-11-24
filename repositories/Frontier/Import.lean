-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: Apache-2.0 OR MIT
import Lean.Data.Json
import Frontier.Db
import Frontier.Store
/-!
# JSON-LD documents into the planner's tables.
One transaction per document. Keys are UUIDv7: the time from the database clock, the rest random. A document that
uses something the schema does not hold (domain capabilities, entity capabilities) is refused, not half stored.
-/
namespace Frontier.Import

open Lean Frontier.Db Frontier.Store

def items (j : Json) : List Json := (j.getArr?.toOption.map (·.toList)).getD []
def members (j : Json) : List (String × Json) := (j.getObj?.toOption.map (·.toList)).getD []
def str (j : Json) (k : String) : String := ((j.getObjVal? k).toOption >>= (·.getStr?.toOption)).getD ""
def has (j : Json) (k : String) : Option Json := (j.getObjVal? k).toOption

def text : Json → String
  | .str s => s
  | .num n => toString n
  | .bool b => toString b
  | other => other.compress

def hexOf (bs : List UInt8) : String :=
  String.join (bs.map fun b => (if b.toNat < 16 then "0" else "") ++ String.ofList (Nat.toDigits 16 b.toNat))

def uuid7 : IO String := do
  let rows ← sql "SELECT CAST(unixepoch('subsec') * 1000 AS INTEGER) AS ms;"
  let ms := (number (rows[0]!) "ms").toNat
  let r := (← IO.getRandomBytes 10).toList
  let head := (List.range 6).map fun i => ((ms >>> (8 * (5 - i))) % 256).toUInt8
  pure (hexOf (head ++ [(0x70 : UInt8) ||| (r[0]! &&& (0x0F : UInt8)), r[1]!, (0x80 : UInt8) ||| (r[2]! &&& (0x3F : UInt8))] ++ r.drop 3))

def ins (table : String) (cols vals : List String) : String :=
  s!"INSERT INTO {table} ({", ".intercalate cols}) VALUES ({", ".intercalate vals});"

def commit (st : Array String) : IO Unit := do
  let _ ← sql ("BEGIN;\n" ++ "\n".intercalate st.toList ++ "\nCOMMIT;")

def refuse {α : Type} (why : String) : IO α := throw (IO.userError why)

def parameters (owner id : String) (enumIds : List (String × String)) (ps : List Json) : IO (Array String) := do
  let mut out : Array String := #[]
  for (p, i) in ps.zipIdx do
    let (name, en) := match p with
      | .str s => (s, none)
      | o => (str o "name", (has o "enum").bind (·.getStr?.toOption))
    out := out.push (ins s!"{owner}_parameter" [s!"{owner}_id", "position", "name"] [keyOf id, toString i, quote name])
    if let some e := en then
      let some eid := enumIds.lookup e | refuse s!"parameter {name} names the enumeration {e}, which the domain does not declare"
      out := out.push (ins s!"{owner}_parameter_enumeration" [s!"{owner}_id", "position", "enumeration_id"] [keyOf id, toString i, keyOf eid])
  pure out

def enumerationRows (d : String) (doc : Json) : IO (Array String × List (String × String)) := do
  let mut st : Array String := #[]
  let mut ids : List (String × String) := []
  for (en, v) in members (doc.getObjValD "enums") do
    let e ← uuid7
    ids := ids ++ [(en, e)]
    st := st.push (ins "enumeration" ["id", "domain_id", "name"] [keyOf e, keyOf d, quote en])
    let ms : List (String × Int) := match v.getArr? with
      | .ok a => (a.toList.filterMap fun x => x.getStr?.toOption).zipIdx.map fun (m, i) => (m, (i : Int))
      | .error _ => (members v).filterMap fun (m, x) => x.getInt?.toOption.map (m, ·)
    for (m, val) in ms do
      st := st.push (ins "enumeration_member" ["enumeration_id", "name", "value"] [keyOf e, quote m, toString val])
  pure (st, ids)

def actionRows (d : String) (doc : Json) (enumIds : List (String × String)) : IO (Array String × List (String × String)) := do
  let mut st : Array String := #[]
  let mut ids : List (String × String) := []
  for (an, a) in members (doc.getObjValD "actions") do
    let id ← uuid7
    ids := ids ++ [(an, id)]
    st := st.push (ins "action" ["id", "domain_id", "name"] [keyOf id, keyOf d, quote an])
    for (k, t, c) in [("duration", "action_duration", "duration"), ("description", "action_description", "description"),
                      ("x-operation", "action_operation", "operation"), ("x-duration", "action_duration_basis", "basis")] do
      if let some v := has a k then st := st.push (ins t ["action_id", c] [keyOf id, quote (text v)])
    st := st ++ (← parameters "action" id enumIds (items (a.getObjValD "params")))
    for (step, i) in (items (a.getObjValD "body")).zipIdx do
      st := st.push (ins "action_step" ["action_id", "position", "step"] [keyOf id, toString i, quote step.compress])
  pure (st, ids)

def methodRows (d : String) (doc : Json) (enumIds actionIds : List (String × String)) : IO (Array String) := do
  let mut st : Array String := #[]
  for (mn, m) in members (doc.getObjValD "methods") do
    let id ← uuid7
    st := st.push (ins "method" ["id", "domain_id", "name"] [keyOf id, keyOf d, quote mn])
    if let some w := has m "x-wraps" then
      let some aid := actionIds.lookup (text w) | refuse s!"method {mn} wraps {text w}, which is not an action"
      st := st.push (ins "method_wraps" ["method_id", "action_id"] [keyOf id, keyOf aid])
    st := st ++ (← parameters "method" id enumIds (items (m.getObjValD "params")))
    for (alt, i) in (items (m.getObjValD "alternatives")).zipIdx do
      let body := Json.mkObj ((members alt).filter (·.1 != "name"))
      st := st.push (ins "alternative" ["method_id", "position", "name", "body"] [keyOf id, toString i, quote (str alt "name"), quote body.compress])
  pure st

def domainVariableRows (d : String) (doc : Json) : Array String := Id.run do
  let mut st : Array String := #[]
  for v in items (doc.getObjValD "variables") do
    let vn := str v "name"
    st := st.push (ins "domain_variable" ["domain_id", "name", "type"] [keyOf d, quote vn, quote (str v "type")])
    if let some x := has v "description" then
      st := st.push (ins "domain_variable_description" ["domain_id", "variable", "description"] [keyOf d, quote vn, quote (text x)])
    for (k, x) in members (v.getObjValD "init") do
      st := st.push (ins "domain_variable_init" ["domain_id", "variable", "key", "value"] [keyOf d, quote vn, quote k, toString (x.getInt?.toOption.getD 0)])
  return st

def importDomain (doc : Json) : IO String := do
  let name := str doc "name"
  if !(members ((doc.getObjValD "capabilities").getObjValD "actions")).isEmpty then
    refuse s!"domain {name} declares capabilities.actions; the importer does not read that form"
  let d ← uuid7
  let mut st : Array String := #[ins "domain" ["id", "name", "version"] [keyOf d, quote name, quote (str doc "version")]]
  for (k, t) in [("description", "domain_description"), ("source", "domain_source")] do
    if let some v := has doc k then st := st.push (ins t ["domain_id", k] [keyOf d, quote (text v)])
  let (er, enumIds) ← enumerationRows d doc
  let (ar, actionIds) ← actionRows d doc enumIds
  commit (st ++ er ++ ar ++ (← methodRows d doc enumIds actionIds) ++ domainVariableRows d doc)
  pure name

def taskRows (p : String) (i : Nat) (item : Json) : IO (Array String) := do
  let t ← uuid7
  let mut st : Array String := #[ins "problem_task" ["id", "problem_id", "position"] [keyOf t, keyOf p, toString i]]
  match item with
  | .arr a =>
    let some head := a[0]? | refuse "an empty task"
    st := st.push (ins "task_call" ["task_id", "name"] [keyOf t, quote (text head)])
    for (x, k) in (a.toList.drop 1).zipIdx do
      st := st.push (ins "task_call_argument" ["task_id", "argument_position", "value"] [keyOf t, toString k, quote (text x)])
  | o =>
    if let some g := has o "goal" then
      for (b, k) in (items g).zipIdx do
        st := st.push (ins "task_goal_binding" ["task_id", "binding_position", "pointer", "desired"] [keyOf t, toString k, quote (str b "pointer"), quote (b.getObjValD "eq").compress])
    else if let some m := has o "multigoal" then
      for (v, ks) in members m do
        for (k, x) in members ks do
          st := st.push (ins "task_multigoal_binding" ["task_id", "variable", "key", "desired"] [keyOf t, quote v, quote k, quote x.compress])
    else refuse s!"a task that is neither a call, a goal nor a multigoal: {o.compress}"
  pure st

def importProblem (doc : Json) : IO String := do
  let name := str doc "name"
  let some dr ← one s!"SELECT hex(id) AS id FROM domain WHERE name = {quote (str doc "domain")};"
    | refuse s!"problem {name}: the domain {str doc "domain"} is not stored"
  let caps := doc.getObjValD "capabilities"
  if !(members (caps.getObjValD "entities")).isEmpty then
    refuse s!"problem {name} declares capabilities.entities; the importer does not read that form"
  let p ← uuid7
  let mut st : Array String := #[ins "problem" ["id", "domain_id", "name", "version"] [keyOf p, keyOf (field dr "id"), quote name, quote (str doc "version")]]
  for (k, t) in [("description", "problem_description"), ("source", "problem_source"), ("origin", "problem_origin")] do
    if let some v := has doc k then st := st.push (ins t ["problem_id", k] [keyOf p, quote (text v)])
  for v in items (doc.getObjValD "variables") do
    let vn := str v "name"
    st := st.push (ins "problem_variable" ["problem_id", "name", "type"] [keyOf p, quote vn, quote (str v "type")])
    for (k, x) in members (v.getObjValD "init") do
      st := st.push (ins "variable_init" ["problem_id", "variable", "key", "value"] [keyOf p, quote vn, quote k, toString (x.getInt?.toOption.getD 0)])
  for (item, i) in (items (doc.getObjValD "todo_list")).zipIdx do
    st := st ++ (← taskRows p i item)
  for e in items ((caps.getObjValD "graph").getObjValD "edges") do
    st := st.push (ins "problem_edge" ["problem_id", "subject", "relation", "object"] [keyOf p, quote (str e "subject"), quote (str e "rel"), quote (str e "object")])
  commit st
  pure name

def importPlan (doc : Json) : IO String := do
  let pname := str doc "problem"
  let some pr ← one s!"SELECT hex(id) AS id, hex(domain_id) AS domain FROM problem WHERE name = {quote pname};"
    | refuse s!"plan for {pname}: the problem is not stored"
  let pl ← uuid7
  let mut st : Array String := #[ins "plan" ["id", "problem_id"] [keyOf pl, keyOf (field pr "id")]]
  if let some n := has doc "name" then st := st.push (ins "plan_name" ["plan_id", "name"] [keyOf pl, quote (text n)])
  if let some r := has doc "refused" then
    st := st.push (ins "plan_refusal" ["plan_id", "reason"] [keyOf pl, quote (text r)])
  else
    if (doc.getObjValD "reached") != Json.bool true then refuse s!"plan for {pname} is neither reached nor refused"
    let t := doc.getObjValD "temporal"
    st := st.push (ins "plan_reached" ["plan_id", "consistent", "total"] [keyOf pl, if (t.getObjValD "consistent") == Json.bool true then "1" else "0", quote (str t "total")])
    let actions ← sql s!"SELECT name, hex(id) AS id FROM action WHERE domain_id = {keyOf (field pr "domain")};"
    for (s, i) in (items (doc.getObjValD "steps")).zipIdx do
      let some a := actions.find? (field · "name" == str s "action") | refuse s!"plan step {str s "action"} is not an action of the domain"
      st := st.push (ins "plan_step" ["plan_id", "position", "action_id", "duration"] [keyOf pl, toString i, keyOf (field a "id"), quote (str s "duration")])
      for (x, k) in (items (s.getObjValD "params")).zipIdx do
        st := st.push (ins "plan_step_parameter" ["plan_id", "position", "argument_position", "value"] [keyOf pl, toString i, toString k, quote (text x)])
  commit st
  pure pname

/-- Import one document, by its `@type`. -/
def importDocument (doc : Json) : IO String :=
  match str doc "@type" with
  | "domain:Definition" => importDomain doc
  | "domain:Problem" => importProblem doc
  | "domain:Plan" => importPlan doc
  | other => refuse s!"unknown document type {other}"

end Frontier.Import
