-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2024 Thibault Falque, Pierre Talbot
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Fzn
import Frontend.Simplify
/-! `SolverOutput::print_solution_flatzinc` (lala-parsing `solver_output.hpp`) with `Simplifier::print_variable` (lala-core `simplifier.hpp`): the value of each
    output variable is read from the final store through the representative of its equivalence class, or from the constant of the class when the
    representative was eliminated; a Boolean prints as `false` when its interval is empty or `[0,0]`, otherwise as `true`; any other sort prints the lower bound.
    The text ends with the MiniZinc separator `----------` that `print_solution` of Turbo adds. -/
open Std
namespace Frontend

def printValue (so : Srt) (d : Itv) : String :=
  if so == .bool then (if d.lo > d.hi || (d.lo == 0 && d.hi == 0) then "false" else "true")
  else s!"{d.lo}"

/-- `print_variable(name, env, best)`: `values[k]` is the best store's interval of the final variable `k`. -/
def printVariable (info : SolInfo) (values : Array Itv) (name : String) : String :=
  let i := info.idx.getD name 0
  let r := info.eqc[i]!
  if !info.elimV[r]! && info.newIdx[r]! < values.size then printValue info.sorts[r]! values[info.newIdx[r]!]!
  else printValue info.sorts[i]! info.consts[r]!

/-- The dimensions of an output array: every interval of every range, as `(lb, ub)`. -/
def arrayDims (ranges : Array F) : Array (Int × Int) :=
  ranges.foldl (init := #[]) fun acc r =>
    match r with
    | .s _ ivs => ivs.foldl (init := acc) fun a (lo, hi) =>
        match lo, hi with
        | .z _ l, .z _ h => a.push (l, h)
        | _, _ => a
    | _ => acc

def solutionText (out : Output) (info : SolInfo) (values : Array Itv) : String := Id.run do
  let mut text := ""
  for v in out.vars do
    text := text ++ s!"{v}={printVariable info values v};\n"
  for (name, ranges, els) in out.arrays do
    let dims := arrayDims ranges
    text := text ++ s!"{name}=array{dims.size}d("
    for (lo, hi) in dims do text := text ++ s!"{lo}..{hi},"
    text := text ++ "[" ++ ",".intercalate (els.toList.map (printVariable info values)) ++ "]);\n"
  return text ++ "----------\n"

/-- The player's result file: after the line that starts with `best`, one `lb ub` pair per variable of the dump. -/
def parseResult (text : String) : Array Itv := Id.run do
  let mut vals : Array Itv := #[]
  let mut seen := false
  for line in text.splitOn "\n" do
    if !seen then
      if line.startsWith "best" then seen := true
    else
      match line.trimAscii.toString.splitOn " " with
      | [a, b] =>
        match a.toInt?, b.toInt? with
        | some l, some h => vals := vals.push ⟨Int32.ofInt l, Int32.ofInt h⟩
        | _, _ => pure ()
      | _ => pure ()
  return vals

end Frontend
