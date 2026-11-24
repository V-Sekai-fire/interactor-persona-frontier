import LeanSlang.AST
import LeanSlang.Emit

/-! The Turbo propagator (lala_pc `pir.hpp`) as a Lean shader module, printed with contract-lean-slang.
    First slice: the integer division helpers, the interval type, and `ADD` (`ask` and `deduce`). -/
namespace Turbo
open LeanSlang

abbrev E := SlangExpr
abbrev S := SlangStmt

def int : SlangType := .scalar .int
def bool : SlangType := .scalar .bool
def itv : SlangType := .named "Itv"

def v (name : String) : E := .var name
def n (k : Nat) : E := .call "int" [.litUint k]
def neg (e : E) : E := .un "-" e
def bin (op : String) (l r : E) : E := .bin op l r
def lower (e : E) : E := .member e "lower"
def upper (e : E) : E := .member e "upper"
def call (fn : String) (args : List E) : E := .call fn args
def param (name : String) (type : SlangType) (qualifier : ParamQualifier := .qIn) : SlangBinding :=
  { name, type, qualifier }

def infinity : E := call "int" [.litUint 2147483647]
def minusInfinity : E := bin "-" (neg infinity) (n 1)

def signum : SlangFunctionDecl :=
  { retType := int, name := "signum", params := [param "x" int],
    body := [.ret (some (bin "-" (.ternary (bin ">" (v "x") (n 0)) (n 1) (n 0)) (.ternary (bin "<" (v "x") (n 0)) (n 1) (n 0))))] }

def divisionHelper (name : String) (body : E) : SlangFunctionDecl :=
  { retType := int, name, params := [param "x" int, param "y" int], body := [.ret (some body)] }

def quotient : E := bin "/" (v "x") (v "y")
def remainder : E := bin "%" (v "x") (v "y")
def sign (e : E) : E := call "signum" [e]

def tdiv : SlangFunctionDecl := divisionHelper "tdiv" quotient
def fdiv : SlangFunctionDecl :=
  divisionHelper "fdiv" (bin "-" quotient (.ternary (bin "==" (sign remainder) (neg (sign (v "y")))) (n 1) (n 0)))
def cdiv : SlangFunctionDecl :=
  divisionHelper "cdiv" (bin "+" quotient (.ternary (bin "==" (sign remainder) (sign (v "y"))) (n 1) (n 0)))
def ediv : SlangFunctionDecl :=
  divisionHelper "ediv" (bin "-" quotient (.ternary (bin ">=" remainder (n 0)) (n 0) (sign (v "y"))))
def emod : SlangFunctionDecl :=
  divisionHelper "emod" (bin "+" remainder (bin "*" (v "y") (.ternary (bin ">=" remainder (n 0)) (n 0) (sign (v "y")))))

def itvStruct : SlangStructDecl :=
  { name := "Itv", fields := [param "lower" int, param "upper" int] }

def itvMake : SlangFunctionDecl :=
  { retType := itv, name := "itv_make", params := [param "l" int, param "u" int],
    body := [.decl itv "r", .assign (lower (v "r")) (v "l"), .assign (upper (v "r")) (v "u"), .ret (some (v "r"))] }

def xl := lower (v "r1")
def xu := upper (v "r1")
def yl := lower (v "r2")
def yu := upper (v "r2")
def zl := lower (v "r3")
def zu := upper (v "r3")
def land (l r : E) : E := bin "&&" l r
def lor (l r : E) : E := bin "||" l r

/-- `ask` for `ADD`: `xl == xu && yl == yu && zl == zu && xl == yl + zl`. -/
def askAdd : SlangFunctionDecl :=
  { retType := bool, name := "ask_add", params := [param "r1" itv, param "r2" itv, param "r3" itv],
    body := [.ret (some (land (land (land (bin "==" xl xu) (bin "==" yl yu)) (bin "==" zl zu)) (bin "==" xl (bin "+" yl zl))))] }

/-- `deduce` for `ADD`; the three results are met into the store by the caller. -/
def deduceAdd : SlangFunctionDecl :=
  let pick (cond a b : E) : E := .ternary cond a b
  { name := "deduce_add", params := [param "r1" itv .qInOut, param "r2" itv .qInOut, param "r3" itv .qInOut],
    body := [
      .decl itv "n1", .assign (v "n1") (v "r1"), .decl itv "n2", .assign (v "n2") (v "r2"), .decl itv "n3", .assign (v "n3") (v "r3"),
      .assign (lower (v "n1")) (pick (lor (bin "==" yl minusInfinity) (bin "==" zl minusInfinity)) xl (call "max" [xl, bin "+" yl zl])),
      .assign (upper (v "n1")) (pick (lor (bin "==" yu infinity) (bin "==" zu infinity)) xu (call "min" [xu, bin "+" yu zu])),
      .assign (lower (v "n2")) (pick (lor (bin "==" xl minusInfinity) (bin "==" zu infinity)) yl (call "max" [yl, bin "-" xl zu])),
      .assign (upper (v "n2")) (pick (lor (bin "==" xu infinity) (bin "==" zl minusInfinity)) yu (call "min" [yu, bin "-" xu zl])),
      .assign (lower (v "n3")) (pick (lor (bin "==" xl minusInfinity) (bin "==" yu infinity)) zl (call "max" [zl, bin "-" xl yu])),
      .assign (upper (v "n3")) (pick (lor (bin "==" xu infinity) (bin "==" yl minusInfinity)) zu (call "min" [zu, bin "-" xu yl])),
      .assign (v "r1") (v "n1"), .assign (v "r2") (v "n2"), .assign (v "r3") (v "n3")] }

def shaderModule : SlangShaderModule :=
  { structs := [itvStruct],
    functions := [signum, tdiv, fdiv, cdiv, ediv, emod, itvMake, askAdd, deduceAdd] }

end Turbo
