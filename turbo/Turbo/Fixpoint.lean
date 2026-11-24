import Turbo.Pir

/-! The store and bytecode format, and the sequential Gauss-Seidel fixpoint of Turbo's `GaussSeidelIteration` over `PIR`.
    Store: `lower[v]`, `upper[v]`. Bytecode `i`: `code[i] = (op, x, y, z)` meaning `x = y op z`, with the operator codes of `Turbo.Pir`.
    `control[0]` is the number of bytecodes; the kernel writes the number of rounds to `control[1]` and 1 to `control[2]` when the store became bot. -/
namespace Turbo
open LeanSlang

def global (name : String) (type : SlangType) (binding : Nat) : SlangBinding :=
  { name, type, binding := some binding, space := some 0 }

def codeAt (i : E) : E := .index (v "code") i
def storeLower (e : E) : E := .index (v "lower") e
def storeUpper (e : E) : E := .index (v "upper") e

/-- `embed(x, r)` of the store: meet `r` into variable `x`; true when the store changed. -/
def embedFn : SlangFunctionDecl :=
  { retType := bool, name := "embed", params := [param "x" int, param "r" itv],
    body := [
      .decl itv "s", .assign (lower (v "s")) (storeLower (v "x")), .assign (upper (v "s")) (storeUpper (v "x")),
      .declInit bool "changed" (call "itv_meet" [v "s", v "r"]),
      .assign (storeLower (v "x")) (lower (v "s")), .assign (storeUpper (v "x")) (upper (v "s")),
      ret (v "changed")] }

def loadFn : SlangFunctionDecl :=
  { retType := itv, name := "load", params := [param "x" int],
    body := [ret (mk (storeLower (v "x")) (storeUpper (v "x")))] }

/-- `deduce(bytecode)` of `PIR`: load the three variables, deduce, embed the three results in order. -/
def deduceBytecodeFn : SlangFunctionDecl :=
  { retType := bool, name := "deduce_bytecode", params := [param "i" (.scalar .uint)],
    body := [
      .declInit (.vec .int 4) "c" (codeAt (v "i")),
      .declInit int "x" (.member (v "c") "y"), .declInit int "y" (.member (v "c") "z"), .declInit int "z" (.member (v "c") "w"),
      .declInit itv "r1" (call "load" [v "x"]), .declInit itv "r2" (call "load" [v "y"]), .declInit itv "r3" (call "load" [v "z"]),
      .expr (call "deduce" [.member (v "c") "x", v "r1", v "r2", v "r3"]),
      .declInit bool "changed" (call "embed" [v "x", v "r1"]),
      .assign (v "changed") (lor (call "embed" [v "y", v "r2"]) (v "changed")),
      .assign (v "changed") (lor (call "embed" [v "z", v "r3"]) (v "changed")),
      .ifThen (lor (lor (call "itv_is_bot" [call "load" [v "x"]]) (call "itv_is_bot" [call "load" [v "y"]])) (call "itv_is_bot" [call "load" [v "z"]]))
        [.assign (.index (v "control") (.litUint 2)) (n 1)] [],
      ret (v "changed")] }

/-- Gauss-Seidel: sweep the bytecodes in order until a sweep changes nothing or a variable is bot. -/
def fixpointFn : SlangFunctionDecl :=
  { attrs := [.shaderCompute, .numthreads 1 1 1], name := "fixpoint", params := [⟨"tid", .vec .uint 3, .svDispatchThreadId, none, none, .qIn⟩],
    body := [
      .declInit int "count" (.index (v "control") (.litUint 0)),
      .declInit bool "changed" (.litBool true), .declInit int "rounds" (n 0),
      .whileLoop (land (v "changed") (eq (.index (v "control") (.litUint 2)) (n 0)))
        [.assign (v "changed") (.litBool false), .assign (v "rounds") (add (v "rounds") (n 1)),
         .forCount "i" (.litUint 0) (call "uint" [v "count"])
           [.ifThen (call "deduce_bytecode" [v "i"]) [.assign (v "changed") (.litBool true)] []]],
      .assign (.index (v "control") (.litUint 1)) (v "rounds")] }

def fixpointModule : SlangShaderModule :=
  { shaderModule with
    globals := [global "lower" (.rwBuf int) 0, global "upper" (.rwBuf int) 1, global "code" (.roBuf (.vec .int 4)) 2, global "control" (.rwBuf int) 3],
    functions := shaderModule.functions ++ [embedFn, loadFn, deduceBytecodeFn, fixpointFn] }

end Turbo
