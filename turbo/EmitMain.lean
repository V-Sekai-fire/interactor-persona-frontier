-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Turbo.Coop

def main (args : List String) : IO Unit :=
  match args with
  | ["solve"] => IO.println (LeanSlang.emit (Turbo.solveModule false))
  | ["solve-coop"] => IO.println (LeanSlang.emit Turbo.solveCoopModule)
  | ["solve-cuda"] => IO.println (LeanSlang.emit (Turbo.solveModule true))
  | _ => IO.println (LeanSlang.emit Turbo.fixpointModule)
