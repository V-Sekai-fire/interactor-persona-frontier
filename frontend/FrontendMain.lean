-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Fzn
/-! `frontier_frontend --stats FILE.fzn`: parse a FlatZinc file and print the statistics Turbo prints after `parse_cn`. -/
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
      return 0
  | _ => IO.eprintln "usage: frontier_frontend --stats FILE.fzn"; return 2
