import Lean.Data.Json
import Persona.Jsonld
import Frontier.Db
/-!
# The planner's documents, read from SQLite.
`domainJson` and `problemJson` build the JSON-LD the planner reads from the tables. Capabilities come out
in both forms from the same rows: the guard steps and `HAS_CAPABILITY` edges the planner enforces, and the
`capabilities.actions` and `capabilities.entities` objects.
-/
namespace Frontier.Store

open Lean Frontier.Db

def field (r : Json) (k : String) : String :=
  ((r.getObjVal? k).toOption >>= (·.getStr?.toOption)).getD ""

def number (r : Json) (k : String) : Int := (field r k).toInt?.getD 0

def parsed (text : String) : Json := (Json.parse text).toOption.getD Json.null

def keyOf (id : String) : String := s!"X'{id}'"

def grouped (rows : Array Json) (key : String) (item : Json → Json) : List (String × List Json) :=
  rows.foldl (init := []) fun acc r =>
    let k := field r key
    if acc.any (·.1 == k) then acc.map fun (n, v) => if n == k then (n, v ++ [item r]) else (n, v)
    else acc ++ [(k, [item r])]

def pairsOf (js : List Json) : List (String × Json) :=
  js.flatMap fun j => (j.getObj?.toOption.map (·.toList)).getD []

def lookupAll (g : List (String × List Json)) (k : String) : List Json := (g.find? (·.1 == k)).map (·.2) |>.getD []

def present (k v : String) : List (String × Json) := if v.isEmpty then [] else [(k, Json.str v)]

def one (q : String) : IO (Option Json) := return (← sql q)[0]?

def domainRow (name : String) : IO (String × String) := do
  match ← one s!"SELECT hex(id) AS id, version FROM domain WHERE name = {quote name};" with
  | some r => pure (field r "id", field r "version")
  | none => throw (IO.userError s!"no domain {name}")

def enumerations (d : String) : IO Json := do
  let rows ← sql s!"SELECT e.name AS enumeration, m.name AS member, m.value AS value FROM enumeration e JOIN enumeration_member m ON m.enumeration_id = e.id WHERE e.domain_id = {keyOf d} ORDER BY e.name, m.value, m.name;"
  let g := grouped rows "enumeration" fun r => Json.mkObj [(field r "member", toJson (number r "value"))]
  pure (Json.mkObj (g.map fun (n, ms) => (n, Json.mkObj (pairsOf ms))))

def parameterJson (r : Json) : Json :=
  if (field r "enumeration").isEmpty then Json.str (field r "parameter")
  else Json.mkObj [("name", Json.str (field r "parameter")), ("enum", Json.str (field r "enumeration"))]

def guard (agent capability : String) : Json :=
  Json.mkObj [("eval", Json.mkObj [("type", "rebac/check"), ("subject", Json.str s!"[{agent}]"),
    ("rel", "HAS_CAPABILITY"), ("object", Json.str capability)])]

def agentName (ps : List Json) : String :=
  match ps.head? with
  | some (Json.str s) => s
  | some o => field o "name"
  | none => ""

def guards (params capabilities : List Json) : IO (List Json) := do
  if capabilities.isEmpty then return []
  if (agentName params).isEmpty then throw (IO.userError "an action with a capability needs a first parameter")
  pure (capabilities.map fun c => guard (agentName params) (field c "capability"))

def actionJson (d : String) : IO (List (String × Json) × List (String × Json)) := do
  let acts ← sql s!"SELECT a.name AS name, COALESCE(u.duration, '') AS duration, COALESCE(x.description, '') AS description, COALESCE(o.operation, '') AS operation, COALESCE(b.basis, '') AS basis FROM action a LEFT JOIN action_duration u ON u.action_id = a.id LEFT JOIN action_description x ON x.action_id = a.id LEFT JOIN action_operation o ON o.action_id = a.id LEFT JOIN action_duration_basis b ON b.action_id = a.id WHERE a.domain_id = {keyOf d} ORDER BY a.name;"
  let ps ← sql s!"SELECT a.name AS action, p.name AS parameter, COALESCE(e.name, '') AS enumeration FROM action_parameter p JOIN action a ON a.id = p.action_id LEFT JOIN action_parameter_enumeration pe ON pe.action_id = p.action_id AND pe.position = p.position LEFT JOIN enumeration e ON e.id = pe.enumeration_id WHERE a.domain_id = {keyOf d} ORDER BY a.name, p.position;"
  let ss ← sql s!"SELECT a.name AS action, s.step AS step FROM action_step s JOIN action a ON a.id = s.action_id WHERE a.domain_id = {keyOf d} ORDER BY a.name, s.position;"
  let cs ← sql s!"SELECT a.name AS action, c.name AS capability FROM action_capability ac JOIN action a ON a.id = ac.action_id JOIN capability c ON c.id = ac.capability_id WHERE a.domain_id = {keyOf d} ORDER BY a.name, c.name;"
  let params := grouped ps "action" parameterJson
  let steps := grouped ss "action" fun r => parsed (field r "step")
  let caps := grouped cs "action" id
  let built ← acts.toList.mapM fun a => do
    let n := field a "name"
    let ps := lookupAll params n
    let gs ← guards ps (lookupAll caps n)
    let body := Json.arr (gs ++ lookupAll steps n).toArray
    pure (n, Json.mkObj ([("params", Json.arr ps.toArray), ("body", body)]
      ++ present "duration" (field a "duration") ++ present "description" (field a "description") ++ present "x-operation" (field a "operation")
      ++ present "x-duration" (field a "basis")))
  let declared := caps.map fun (n, cs) => (n, Json.arr (cs.map fun c => Json.str (field c "capability")).toArray)
  pure (built, declared)

def methodsJson (d : String) : IO (List (String × Json)) := do
  let ms ← sql s!"SELECT m.name AS name, COALESCE(a.name, '') AS wraps FROM method m LEFT JOIN method_wraps w ON w.method_id = m.id LEFT JOIN action a ON a.id = w.action_id WHERE m.domain_id = {keyOf d} ORDER BY m.name;"
  let ps ← sql s!"SELECT m.name AS method, p.name AS parameter, COALESCE(e.name, '') AS enumeration FROM method_parameter p JOIN method m ON m.id = p.method_id LEFT JOIN method_parameter_enumeration pe ON pe.method_id = p.method_id AND pe.position = p.position LEFT JOIN enumeration e ON e.id = pe.enumeration_id WHERE m.domain_id = {keyOf d} ORDER BY m.name, p.position;"
  let alts ← sql s!"SELECT m.name AS method, l.name AS name, l.body AS body FROM alternative l JOIN method m ON m.id = l.method_id WHERE m.domain_id = {keyOf d} ORDER BY m.name, l.position;"
  let params := grouped ps "method" parameterJson
  let alternatives := grouped alts "method" fun r => (parsed (field r "body")).setObjVal! "name" (Json.str (field r "name"))
  pure (ms.toList.map fun m =>
    let n := field m "name"
    (n, Json.mkObj ([("params", Json.arr (lookupAll params n).toArray), ("alternatives", Json.arr (lookupAll alternatives n).toArray)]
      ++ present "x-wraps" (field m "wraps"))))

def optional (table column idColumn id : String) : IO (List (String × Json)) := do
  match ← one s!"SELECT {column} AS value FROM {table} WHERE {idColumn} = {keyOf id};" with
  | some r => pure [(column, Json.str (field r "value"))]
  | none => pure []

def header (name : String) : List (String × Json) :=
  [("@context", Json.mkObj [("VSEKAI", "https://v-sekai.org/"), ("domain", "VSEKAI:planning/domain/")]), ("name", Json.str name)]

def domainVariablesJson (d : String) : IO (List (String × Json)) := do
  let vs ← sql s!"SELECT v.name AS name, v.type AS type, COALESCE(x.description, '') AS description FROM domain_variable v LEFT JOIN domain_variable_description x ON x.domain_id = v.domain_id AND x.variable = v.name WHERE v.domain_id = {keyOf d} ORDER BY v.name;"
  let inits ← sql s!"SELECT variable, key, value FROM domain_variable_init WHERE domain_id = {keyOf d} ORDER BY variable, key;"
  let byVariable := grouped inits "variable" fun r => Json.mkObj [(field r "key", toJson (number r "value"))]
  if vs.isEmpty then return []
  pure [("variables", Json.arr (vs.map fun v =>
    Json.mkObj ([("name", Json.str (field v "name")), ("type", Json.str (field v "type")),
      ("init", Json.mkObj (pairsOf (lookupAll byVariable (field v "name"))))] ++ present "description" (field v "description"))))]

def domainJson (name : String) : IO Json := do
  let (d, version) ← domainRow name
  let enums ← enumerations d
  let (actions, declared) ← actionJson d
  let methods ← methodsJson d
  let description ← optional "domain_description" "description" "domain_id" d
  let source ← optional "domain_source" "source" "domain_id" d
  let variables ← domainVariablesJson d
  pure (Json.mkObj (header name ++ [("@type", Json.str "domain:Definition"), ("version", Json.str version), ("enums", enums),
    ("actions", Json.mkObj actions), ("methods", Json.mkObj methods),
    ("capabilities", Json.mkObj [("actions", Json.mkObj declared)])] ++ description ++ source ++ variables))

def variablesJson (p : String) : IO Json := do
  let vs ← sql s!"SELECT name, type FROM problem_variable WHERE problem_id = {keyOf p} ORDER BY name;"
  let inits ← sql s!"SELECT variable, key, value FROM variable_init WHERE problem_id = {keyOf p} ORDER BY variable, key;"
  let byVariable := grouped inits "variable" fun r => Json.mkObj [(field r "key", toJson (number r "value"))]
  pure (Json.arr (vs.map fun v => Json.mkObj [("name", Json.str (field v "name")), ("type", Json.str (field v "type")),
    ("init", Json.mkObj (pairsOf (lookupAll byVariable (field v "name"))))]))

def scalar (text : String) : Json := match text.toInt? with | some n => toJson n | none => Json.str text

def tasksJson (p : String) : IO Json := do
  let ts ← sql s!"SELECT hex(id) AS id FROM problem_task WHERE problem_id = {keyOf p} ORDER BY position;"
  let calls ← sql s!"SELECT hex(c.task_id) AS id, c.name AS name FROM task_call c JOIN problem_task t ON t.id = c.task_id WHERE t.problem_id = {keyOf p};"
  let args ← sql s!"SELECT hex(task_id) AS id, value FROM task_call_argument WHERE task_id IN (SELECT id FROM problem_task WHERE problem_id = {keyOf p}) ORDER BY task_id, argument_position;"
  let goals ← sql s!"SELECT hex(task_id) AS id, pointer, desired FROM task_goal_binding WHERE task_id IN (SELECT id FROM problem_task WHERE problem_id = {keyOf p}) ORDER BY task_id, binding_position;"
  let multi ← sql s!"SELECT hex(task_id) AS id, variable, key, desired FROM task_multigoal_binding WHERE task_id IN (SELECT id FROM problem_task WHERE problem_id = {keyOf p}) ORDER BY task_id, variable, key;"
  let argumentsOf := grouped args "id" fun r => scalar (field r "value")
  let goalsOf := grouped goals "id" fun r => Json.mkObj [("pointer", Json.str (field r "pointer")), ("eq", parsed (field r "desired"))]
  let multiOf := grouped multi "id" fun r => Json.mkObj [(field r "variable", Json.mkObj [(field r "key", parsed (field r "desired"))])]
  let items ← ts.toList.mapM fun t => do
    let id := field t "id"
    match calls.find? (field · "id" == id) with
    | some c => pure (Json.arr ((Json.str (field c "name")) :: lookupAll argumentsOf id).toArray)
    | none => pure (← kindless id (lookupAll goalsOf id) (lookupAll multiOf id))
  pure (Json.arr items.toArray)
where
  kindless (id : String) (goals multi : List Json) : IO Json :=
    if !goals.isEmpty then pure (Json.mkObj [("goal", Json.arr goals.toArray)])
    else if !multi.isEmpty then pure (Json.mkObj [("multigoal", mergeVariables multi)])
    else throw (IO.userError s!"task {id} has no kind")
  mergeVariables (items : List Json) : Json :=
    let entries := pairsOf items
    let names := entries.foldl (fun acc (n, _) => if acc.contains n then acc else acc ++ [n]) ([] : List String)
    Json.mkObj (names.map fun n => (n, Json.mkObj (pairsOf ((entries.filter (·.1 == n)).map (·.2)))))

def holdings (p : String) : IO (List Json) := do
  let rows ← sql s!"SELECT ec.entity AS entity, m.value AS value, c.name AS capability FROM entity_capability ec JOIN enumeration_member m ON m.enumeration_id = ec.enumeration_id AND m.name = ec.entity JOIN capability c ON c.id = ec.capability_id WHERE ec.problem_id = {keyOf p} ORDER BY ec.entity, c.name;"
  pure rows.toList

def edgeJson (subject relation object : String) : Json :=
  Json.mkObj [("subject", Json.str subject), ("rel", Json.str relation), ("object", Json.str object)]

def problemJson (name : String) : IO Json := do
  let some r ← one s!"SELECT hex(p.id) AS id, p.version AS version, d.name AS domain FROM problem p JOIN domain d ON d.id = p.domain_id WHERE p.name = {quote name};"
    | throw (IO.userError s!"no problem {name}")
  let p := field r "id"
  let edges ← sql s!"SELECT subject, relation, object FROM problem_edge WHERE problem_id = {keyOf p} ORDER BY subject, relation, object;"
  let held ← holdings p
  let entities := grouped held.toArray "entity" fun h => Json.str (field h "capability")
  let held_edges := held.map fun h => edgeJson (toString (number h "value")) "HAS_CAPABILITY" (field h "capability")
  let own := edges.toList.map fun e => edgeJson (field e "subject") (field e "relation") (field e "object")
  let optionals ← ["problem_description:description", "problem_source:source", "problem_origin:origin"].mapM fun t =>
    match t.splitOn ":" with
    | [table, column] => optional table column "problem_id" p
    | _ => pure []
  pure (Json.mkObj (header name ++ [("@type", Json.str "domain:Problem"), ("domain", Json.str (field r "domain")),
    ("version", Json.str (field r "version")), ("variables", ← variablesJson p), ("todo_list", ← tasksJson p),
    ("capabilities", Json.mkObj [("entities", Json.mkObj (entities.map fun (n, cs) => (n, Json.arr cs.toArray))),
      ("graph", Json.mkObj [("edges", Json.arr (own ++ held_edges).toArray)])])] ++ optionals.flatten))

/-- The stored plan of a problem, as the plan document: reached with its steps and timing, or refused. -/
def planDocJson (problem : String) : IO Json := do
  let some r ← one s!"SELECT hex(pl.id) AS id, p.name AS problem, d.name AS domain FROM plan pl JOIN problem p ON p.id = pl.problem_id JOIN domain d ON d.id = p.domain_id WHERE p.name = {quote problem};"
    | throw (IO.userError s!"no plan for {problem}")
  let id := field r "id"
  let named ← optional "plan_name" "name" "plan_id" id
  let base := header (field r "domain") |>.filter (·.1 != "name")
  let head := base ++ [("@type", Json.str "domain:Plan"), ("domain", Json.str (field r "domain")), ("problem", Json.str problem)]
  match ← one s!"SELECT reason FROM plan_refusal WHERE plan_id = {keyOf id};" with
  | some x => pure (Json.mkObj (head ++ named ++ [("refused", Json.str (field x "reason"))]))
  | none =>
    let t ← one s!"SELECT consistent, total FROM plan_reached WHERE plan_id = {keyOf id};"
    let steps ← sql s!"SELECT s.position AS position, a.name AS action, s.duration AS duration FROM plan_step s JOIN action a ON a.id = s.action_id WHERE s.plan_id = {keyOf id} ORDER BY s.position;"
    let params ← sql s!"SELECT position, value FROM plan_step_parameter WHERE plan_id = {keyOf id} ORDER BY position, argument_position;"
    let byStep := grouped params "position" fun p => Json.str (field p "value")
    let temporal := match t with
      | some x => Json.mkObj [("consistent", Json.bool (field x "consistent" == "1")), ("total", Json.str (field x "total"))]
      | none => Json.null
    pure (Json.mkObj (head ++ named ++ [("reached", Json.bool true), ("temporal", temporal),
      ("steps", Json.arr (steps.map fun st => Json.mkObj [("action", Json.str (field st "action")), ("duration", Json.str (field st "duration")),
        ("params", Json.arr (lookupAll byStep (field st "position")).toArray)]))]))

/-- The plan for a stored problem, from the stored domain it belongs to. -/
def plan (problem : String) : IO String := do
  let p ← problemJson problem
  let d ← domainJson (((p.getObjVal? "domain").toOption >>= (·.getStr?.toOption)).getD "")
  pure (Persona.Jsonld.planOf d.compress p.compress)

end Frontier.Store
