import Frontier.Answer
import Lean.Data.Json
/-!
# The exported planner call for `leanler`.
`frontier_answer_text knowledge goal` returns the plan, or a refusal by name, as JSON text. Pure: the caller reads
`entities/knowledge/knowledge.json` and passes its text, so no store is linked into the library.
-/
namespace Frontier.Guest

open Lean

@[export frontier_answer_text]
def answerText (knowledge goal : String) : String :=
  match Json.parse knowledge with
  | .ok k => (Frontier.Loop.answer k goal).compress
  | .error _ => "{\"refused\":\"bad_knowledge\"}"

end Frontier.Guest
