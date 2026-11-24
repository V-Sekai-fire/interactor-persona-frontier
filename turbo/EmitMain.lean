import Turbo.Pir

def main : IO Unit := IO.println (LeanSlang.emit Turbo.shaderModule)
