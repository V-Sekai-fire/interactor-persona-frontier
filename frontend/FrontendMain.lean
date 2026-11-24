-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Fzn
import Frontend.Ternarize
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
      let tnf := (normalizeWith (ternarizeFormula p.formula #[0, 1, 2]) #[]).1
      IO.println s!"tnf_variables={F.numQuantifiedVars tnf}"
      IO.println s!"tnf_constraints={numTnfConstraints tnf}"
      return 0
  | ["--tnf", path] =>
    let bytes ← IO.FS.readBinFile path
    match parseFlatzinc bytes with
    | .error e => IO.eprintln s!"Could not parse input file: {e}"; return 1
    | .ok p =>
      let tnf := (normalizeWith (ternarizeFormula p.formula #[0, 1, 2]) #[]).1
      let out ← IO.getStdout
      for l in toLines tnf do out.putStrLn l
      return 0
  | _ => IO.eprintln "usage: frontier_frontend (--stats | --tnf) FILE.fzn"; return 2
