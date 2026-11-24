-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Fzn
import Frontend.Ternarize
import Frontend.Simplify
import Frontend.Output
/-! `frontier_frontend --stats FILE.fzn`: the statistics Turbo prints after `parse_cn` and after ternarize and normalize; `--tnf FILE.fzn`: the ternary normal form as canonical text, one conjunct per line. -/
open Frontend

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--stats", path] =>
    let bytes ← IO.FS.readBinFile path
    match parseFlatzinc bytes with
    | .error e => IO.eprintln s!"Could not parse input file: {e}"; return 1
    | .ok p =>
      for w in p.warnings do IO.eprintln w
      IO.println s!"parsed_variables={F.numQuantifiedVars p.parsed}"
      IO.println s!"parsed_constraints={F.numConstraints p.parsed}"
      IO.println s!"constraints_after_eval={F.numConstraints p.formula}"
      IO.println s!"output_vars={p.out.vars.size}"
      IO.println s!"output_arrays={p.out.arrays.size}"
      let (tnf, extra) := normalizeWith (ternarizeFormula (F.withMinimizeObjective p.formula) #[0, 1, 2]) #[]
      IO.println s!"tnf_variables={F.numQuantifiedVars tnf}"
      IO.println s!"tnf_constraints={numTnfConstraints tnf}"
      let d := preprocessTcn tnf extra
      for (k, st) in d.per do
        IO.println s!"eliminated_entailed_constraints_fp_iter_{k}={st.entailed}"
        IO.println s!"eliminated_equality_constraints_fp_iter_{k}={st.eqs}"
        IO.println s!"eliminated_constraints_by_icse_fp_iter_{k}={st.icse}"
        IO.println s!"eliminated_constraints_by_as_fp_iter_{k}={st.alg}"
      IO.println s!"eliminated_entailed_constraints={d.total.entailed}"
      IO.println s!"eliminated_equality_constraints={d.total.eqs}"
      IO.println s!"eliminated_constraints_by_icse={d.total.icse}"
      IO.println s!"eliminated_constraints_by_as={d.total.alg}"
      IO.println s!"eliminated_variables={d.eliminatedVars}"
      IO.println s!"preprocessing_fixpoint_iterations={d.iters}"
      IO.println s!"variables_after_simplification={d.varsAfter}"
      IO.println s!"constraints_after_simplification={d.consAfter}"
      IO.println s!"variables={d.varsAfter}"
      IO.println s!"propagators={d.consAfter}"
      return 0
  | ["--tnf", path] =>
    let bytes ← IO.FS.readBinFile path
    match parseFlatzinc bytes with
    | .error e => IO.eprintln s!"Could not parse input file: {e}"; return 1
    | .ok p =>
      let tnf := (normalizeWith (ternarizeFormula (F.withMinimizeObjective p.formula) #[0, 1, 2]) #[]).1
      let out ← IO.getStdout
      for l in toLines tnf do out.putStrLn l
      return 0
  | ["--dump", path] => do
    let bytes ← IO.FS.readBinFile path
    match parseFlatzinc bytes with
    | .error e => IO.eprintln s!"Could not parse input file: {e}"; return 1
    | .ok p =>
      let (tnf, extra) := normalizeWith (ternarizeFormula (F.withMinimizeObjective p.formula) #[0, 1, 2]) #[]
      let out ← IO.getStdout
      out.putStr (preprocessTcn tnf extra).text
      return 0
  | ["--solution", path, result] => do
    let bytes ← IO.FS.readBinFile path
    match parseFlatzinc bytes with
    | .error e => IO.eprintln s!"Could not parse input file: {e}"; return 1
    | .ok p =>
      for w in p.warnings do IO.eprintln w
      let (tnf, extra) := normalizeWith (ternarizeFormula (F.withMinimizeObjective p.formula) #[0, 1, 2]) #[]
      let d := preprocessTcn tnf extra
      let values := parseResult (← IO.FS.readFile result)
      let out ← IO.getStdout
      out.putStr (solutionText p.out d.info values)
      return 0
  | _ => IO.eprintln "usage: frontier_frontend (--stats | --tnf | --dump) FILE.fzn | --solution FILE.fzn RESULT.txt"; return 2
