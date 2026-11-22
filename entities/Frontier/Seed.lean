import Lean.Data.Json
import YamlLd
/-!
# Seeds, as in a database migration.
The authored data is a folder of numbered YAML-LD seed files (`seeds/0001_pipeline.yamlld`, ...), applied in name order,
each once, and never edited after it has been applied: a change is a new seed that overrides the earlier ones.
What the planner learns (revisions, durations, learned requirements) is not a seed; it lives in the store only.
Both steps here are pure: `fold` merges the seeds in order and `withLearned` puts the learned rows over the result,
so the Elixir caller and the store assemble the same knowledge from the same code.
-/
namespace Frontier.Seed

open Lean

private def entries (j : Json) : List (String × Json) :=
  match j with
  | .obj kvs => kvs.toList
  | _ => []

private def at? (j : Json) (k : String) : Json := (j.getObjVal? k).toOption.getD .null

private def strings (j : Json) : List String :=
  ((j.getArr?).toOption.getD #[]).toList.filterMap (·.getStr?.toOption)

/-- One seed file, YAML-LD text to JSON. -/
def parse (text : String) : Except String Json := YamlLd.parseYaml text

/-- A stream of seeds, as the Elixir caller sends them: YAML documents in order, one per seed. -/
def parseAll (text : String) : Except String (List Json) := (YamlLd.parseAllYaml text).map (·.toList)

/-- Objects merge key by key; anything else is replaced by the later seed. -/
partial def merge (a b : Json) : Json :=
  match a, b with
  | .obj _, .obj _ =>
    (entries b).foldl (fun acc (k, v) =>
      acc.setObjVal! k (match acc.getObjVal? k with | .ok old => merge old v | .error _ => v)) a
  | _, _ => b

/-- The seeds in order, later over earlier. -/
def fold (seeds : List Json) : Json := seeds.foldl merge (Json.mkObj [])

/-- The three learned rows: what the store keeps, and all it keeps. -/
def learnedOf (k : Json) : Json :=
  Json.mkObj (["revision", "durations", "learned"].map fun key => (key, at? k key))

/-- Learned rows over the seeded base: the counters replace, and each learned requirement joins its stage's own. -/
def withLearned (base learned : Json) : Json :=
  let k := ["revision", "durations", "learned"].foldl (fun acc key =>
    match learned.getObjVal? key with
    | .ok v => if v == .null then acc else acc.setObjVal! key v
    | .error _ => acc) base
  (entries (at? learned "learned")).foldl (fun acc (n, ids) =>
    let st := at? acc "stages"
    match at? st n with
    | .null => acc
    | cur =>
      let reqs := (strings (at? cur "requires") ++ strings ids).eraseDups
      acc.setObjVal! "stages" (st.setObjVal! n (cur.setObjVal! "requires" (Json.arr (reqs.map Json.str).toArray)))) k

end Frontier.Seed
