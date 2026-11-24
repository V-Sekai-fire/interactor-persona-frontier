import Turbo.Coop

def main (args : List String) : IO Unit :=
  match args with
  | ["solve"] => IO.println (LeanSlang.emit (Turbo.solveModule false))
  | ["solve-coop"] => IO.println (LeanSlang.emit Turbo.solveCoopModule)
  | ["solve-cuda"] => IO.println (LeanSlang.emit (Turbo.solveModule true))
  | _ => IO.println (LeanSlang.emit Turbo.fixpointModule)
