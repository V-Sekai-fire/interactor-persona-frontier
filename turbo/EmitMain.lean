import Turbo.Fixpoint

def main : IO Unit := IO.println (LeanSlang.emit Turbo.fixpointModule)
