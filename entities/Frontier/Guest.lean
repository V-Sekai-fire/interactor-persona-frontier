import Frontier.Answer
import Frontier.Seed
import Lean.Data.Json
/-!
# The exported planner call for `leanler`.
`frontier_answer_text seeds goal` returns the plan, or a refusal by name, as JSON text. Pure: the caller reads
`seeds/*.yamlld` as one YAML stream, a document per seed in name order, and passes its text, so no store is linked into the library.
-/
namespace Frontier.Guest

open Lean

@[export frontier_answer_text]
def answerText (knowledge goal : String) : String :=
  match Frontier.Seed.parseAll knowledge with
  | .ok seeds => (Frontier.Loop.answer (Frontier.Seed.fold seeds) goal).compress
  | .error _ => "{\"refused\":\"bad_knowledge\"}"

end Frontier.Guest
