import Lean.Data.Json
/-!
# The knowledge file, the generated domain, and the frontier loop.

`knowledge/knowledge.json` is the learned content: per stage its requirements, the repositories it
draws on (tokens) and a measured duration; `subjects` names which stages a character, a prop and a
world own. `Gen.domain` is the fixed meta-method that turns it into a RECTGTN JSON-LD domain in the
engine shape, `Gen.problem` one problem over it. The frontier loop (levels, practice, experience,
learn with its gate) lives here too, over `Persona.Jsonld.planOf`.
-/
namespace Frontier

open Lean

abbrev Knowledge := Json


def obj (j : Json) : List (String × Json) :=
  match j with
  | .obj kvs => kvs.toList
  | _ => []

def field (j : Json) (k : String) : Json := (j.getObjVal? k).toOption.getD .null
def strs (j : Json) : List String := ((j.getArr?).toOption.getD #[]).toList.filterMap (·.getStr?.toOption)
def str (j : Json) : String := j.getStr?.toOption.getD ""
def nat (j : Json) : Nat := (j.getNat?).toOption.getD 0

/-- Stage ids in the knowledge file's order, numeric. -/
def stageIds (k : Knowledge) : List String :=
  (obj (field k "stages")).map (·.1) |>.toArray.qsort (fun a b => a.toNat! < b.toNat!) |>.toList

def subjects (k : Knowledge) : List (String × List String) :=
  let s := obj (field k "subjects")
  if s.isEmpty then [("character", stageIds k)] else s.map fun (n, v) => (n, strs (field v "stages"))

def tokensOf (k : Knowledge) (n : String) : List String := strs (field (field (field k "stages") n) "tokens")
def requiresOf (k : Knowledge) (n : String) : List String := strs (field (field (field k "stages") n) "requires")
def allTokens (k : Knowledge) : List String := ((stageIds k).flatMap (tokensOf k)).eraseDups

namespace Gen

def ge (ptr : String) : Json :=
  Json.mkObj [("eval", Json.mkObj [("type", "math/ge"), ("a", Json.mkObj [("type", "pointer/get"), ("pointer", ptr)]), ("b", 1)])]
def set (ptr : String) : Json := Json.mkObj [("pointer/set", ptr), ("value", 1)]
def ctx : Json := Json.mkObj [("VSEKAI", "https://v-sekai.org/"), ("domain", "VSEKAI:planning/domain/")]

def domain (k : Knowledge) : Json :=
  let subs := subjects k
  let pairs := subs.flatMap fun (s, ns) => ns.map (s, ·)
  let req (s n : String) : List String := (requiresOf k n).filter fun r => ((subs.lookup s).getD []).contains r
  let tokenActs := (allTokens k).map fun t => (s!"acquire-token-{t}", Json.mkObj [("params", Json.arr #[]), ("body", Json.arr #[set s!"/token/{t}"])])
  let stageActs := pairs.map fun (s, n) =>
    let body := (req s n).map (fun r => ge s!"/stage/{s}-{r}") ++ (tokensOf k n).map (fun t => ge s!"/token/{t}") ++ [set s!"/stage/{s}-{n}"]
    let a := [("params", Json.arr #[]), ("body", Json.arr body.toArray)]
    let a := match field (field k "durations") n with | .str d => a ++ [("duration", Json.str d)] | _ => a
    (s!"settle-{s}-{n}", Json.mkObj a)
  let held (ptr : String) : Json := Json.mkObj [("name", "held"), ("check", Json.arr #[ge ptr]), ("subtasks", Json.arr #[])]
  let tokenMeths := (allTokens k).map fun t =>
    (s!"reach-token-{t}", Json.mkObj [("params", Json.arr #[]), ("alternatives", Json.arr #[held s!"/token/{t}",
      Json.mkObj [("name", "acquire"), ("subtasks", Json.arr #[Json.arr #[Json.str s!"acquire-token-{t}"]])]])])
  let stageMeths := pairs.map fun (s, n) =>
    let subs := (req s n).map (fun r => Json.arr #[Json.str s!"reach-{s}-{r}"]) ++ (tokensOf k n).map (fun t => Json.arr #[Json.str s!"reach-token-{t}"]) ++ [Json.arr #[Json.str s!"settle-{s}-{n}"]]
    (s!"reach-{s}-{n}", Json.mkObj [("params", Json.arr #[]), ("alternatives", Json.arr #[held s!"/stage/{s}-{n}",
      Json.mkObj [("name", "settle"), ("subtasks", Json.arr subs.toArray)]])])
  Json.mkObj [("@context", ctx), ("@type", "domain:Definition"), ("name", "character_stack"), ("source", "interactor-persona-frontier"),
    ("version", Json.str s!"0.1.{nat (field k "revision")}"),
    ("description", "The look-dev pipeline for characters, props and worlds, all GPU-skinned: settle-<subject>-N holds when the stages it requires are settled and the repositories it draws on are acquired. Requirements and durations are learned from experience reports; see knowledge/knowledge.json."),
    ("variables", Json.arr #[
      Json.mkObj [("name", "stage"), ("type", "int"), ("description", "1 when a pipeline stage is settled for a subject (character, prop or world)."), ("init", Json.mkObj [])],
      Json.mkObj [("name", "token"), ("type", "int"), ("description", "1 when a repository is acquired."), ("init", Json.mkObj [])]]),
    ("actions", Json.mkObj (tokenActs ++ stageActs)), ("methods", Json.mkObj (tokenMeths ++ stageMeths))]

def problem (k : Knowledge) (name : String) (heldStages heldTokens : List String) (goal : String) : Json :=
  let keys := (subjects k).flatMap fun (s, ns) => ns.map fun n => s!"{s}-{n}"
  let init (xs : List String) (held : List String) : Json := Json.mkObj (xs.map fun x => (x, if held.contains x then (1 : Json) else (0 : Json)))
  Json.mkObj [("@context", ctx), ("@type", "domain:Problem"), ("name", name), ("source", "interactor-persona-frontier"), ("version", "0.1.0"),
    ("description", Json.str s!"Stages {heldStages} held; goal {goal}."),
    ("variables", Json.arr #[Json.mkObj [("name", "stage"), ("type", "int"), ("init", init keys heldStages)],
                            Json.mkObj [("name", "token"), ("type", "int"), ("init", init (allTokens k) heldTokens)]]),
    ("capabilities", Json.mkObj [("entities", Json.mkObj []), ("graph", Json.mkObj [("edges", Json.arr #[])])]),
    ("todo_list", Json.arr #[Json.arr #[Json.str goal]]), ("domain", "character_stack")]

end Gen
end Frontier
