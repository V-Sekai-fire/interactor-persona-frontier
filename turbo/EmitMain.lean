import Turbo.Solve

def main (args : List String) : IO Unit :=
  match args with
  | ["solve"] => IO.println (LeanSlang.emit Turbo.solveModule)
  | _ => IO.println (LeanSlang.emit Turbo.fixpointModule)
