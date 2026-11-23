import Frontier.Store
/-! The stored planner documents: `frontier_store migrate`, `domain NAME`, `problem NAME`, `plan PROBLEM`. -/
open Lean Frontier

def main (args : List String) : IO UInt32 := do
  Db.init
  match args with
  | ["migrate"] => pure 0
  | ["domain", name] => IO.println (← Store.domainJson name).compress; pure 0
  | ["problem", name] => IO.println (← Store.problemJson name).compress; pure 0
  | ["plan", name] => IO.println (← Store.plan name); pure 0
  | _ => IO.eprintln "usage: frontier_store migrate | domain NAME | problem NAME | plan PROBLEM"; pure 2
