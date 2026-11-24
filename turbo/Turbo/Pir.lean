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

def eq (l r : E) : E := bin "==" l r
def ne (l r : E) : E := bin "!=" l r
def lt (l r : E) : E := bin "<" l r
def gt (l r : E) : E := bin ">" l r
def le (l r : E) : E := bin "<=" l r
def ge (l r : E) : E := bin ">=" l r
def add (l r : E) : E := bin "+" l r
def sub (l r : E) : E := bin "-" l r
def mul (l r : E) : E := bin "*" l r
def mn (l r : E) : E := call "min" [l, r]
def mx (l r : E) : E := call "max" [l, r]
def pick (cond a b : E) : E := .ternary cond a b
def mk (l u : E) : E := call "itv_make" [l, u]
def itvTop : E := call "itv_top" []
def itvBot : E := call "itv_bot" []
def fjoinE (a b : E) : E := call "itv_fjoin" [a, b]
def ret (e : E) : S := .ret (some e)
def when (c : E) (body : List S) : S := .ifThen c body []
def retWhen (c e : E) : S := when c [ret e]
def copy (name : String) (src : E) : List S := [.decl itv name, .assign (v name) src]

-- Operator codes, in the order of the source's `Sig` values used here.
def opAdd := n 0
def opMul := n 1
def opMin := n 2
def opMax := n 3
def opEq := n 4
def opLeq := n 5
def opTdiv := n 6
def opCdiv := n 7
def opFdiv := n 8
def opEdiv := n 9
def opEmod := n 10

def itvParameters : List SlangBinding := [param "r1" itv, param "r2" itv, param "r3" itv]
def itvInOut : List SlangBinding := [param "r1" itv .qInOut, param "r2" itv .qInOut, param "r3" itv .qInOut]
def op : E := v "op"

def itvTopFn : SlangFunctionDecl := { retType := itv, name := "itv_top", body := [ret (mk minusInfinity infinity)] }
def itvBotFn : SlangFunctionDecl := { retType := itv, name := "itv_bot", body := [ret (mk infinity minusInfinity)] }
def isTopE (a : E) : E := land (eq (lower a) minusInfinity) (eq (upper a) infinity)
def itvIsTop : SlangFunctionDecl := { retType := bool, name := "itv_is_top", params := [param "a" itv], body := [ret (isTopE (v "a"))] }
def itvIsBot : SlangFunctionDecl :=
  { retType := bool, name := "itv_is_bot", params := [param "a" itv],
    body := [ret (lor (lor (eq (lower (v "a")) infinity) (eq (upper (v "a")) minusInfinity))
      (land (.un "!" (call "itv_is_top" [v "a"])) (gt (lower (v "a")) (upper (v "a")))))] }
/-- Lattice meet: the lower bound takes the maximum, the upper the minimum; true when `a` changed. -/
def itvMeet : SlangFunctionDecl :=
  { retType := bool, name := "itv_meet", params := [param "a" itv .qInOut, param "o" itv],
    body := [.declInit int "l" (mx (lower (v "a")) (lower (v "o"))), .declInit int "u" (mn (upper (v "a")) (upper (v "o"))),
      .declInit bool "changed" (lor (ne (v "l") (lower (v "a"))) (ne (v "u") (upper (v "a")))),
      .assign (lower (v "a")) (v "l"), .assign (upper (v "a")) (v "u"), ret (v "changed")] }
def itvJoin : SlangFunctionDecl :=
  { name := "itv_join", params := [param "a" itv .qInOut, param "o" itv],
    body := [.assign (lower (v "a")) (mn (lower (v "a")) (lower (v "o"))), .assign (upper (v "a")) (mx (upper (v "a")) (upper (v "o")))] }
def itvFjoin : SlangFunctionDecl :=
  { retType := itv, name := "itv_fjoin", params := [param "a" itv, param "b" itv],
    body := [retWhen (call "itv_is_bot" [v "a"]) (v "b"), retWhen (call "itv_is_bot" [v "b"]) (v "a"),
      ret (mk (mn (lower (v "a")) (lower (v "b"))) (mx (upper (v "a")) (upper (v "b"))))] }
def meetInto (name : String) (e : E) : S := .expr (call "itv_meet" [v name, e])
def joinInto (name : String) (e : E) : S := .expr (call "itv_join" [v name, e])

/-- `div(a, op, b)` of the source. -/
def divFn : SlangFunctionDecl :=
  { retType := int, name := "div_op", params := [param "a" int, param "op" int, param "b" int],
    body := [retWhen (eq op opTdiv) (call "tdiv" [v "a", v "b"]), retWhen (eq op opCdiv) (call "cdiv" [v "a", v "b"]),
      retWhen (eq op opFdiv) (call "fdiv" [v "a", v "b"]), retWhen (eq op opEdiv) (call "ediv" [v "a", v "b"]), ret (v "a")] }

def isDivision : E := land (ge op opTdiv) (le op opEdiv)

def askFn : SlangFunctionDecl :=
  { retType := bool, name := "ask", params := param "op" int :: itvParameters,
    body := [
      retWhen (eq op opEq) (lor (land (eq xl (n 1)) (land (eq yu zl) (eq yl zu))) (land (eq xu (n 0)) (lor (lt yu zl) (gt yl zu)))),
      retWhen (eq op opLeq) (lor (land (eq xl (n 1)) (le yu zl)) (land (eq xu (n 0)) (gt yl zu))),
      retWhen (eq op opAdd) (land (land (land (eq xl xu) (eq yl yu)) (eq zl zu)) (eq xl (add yl zl))),
      retWhen (eq op opMul) (land (eq xl xu)
        (lor (land (land (eq yl yu) (eq zl zu)) (eq xl (mul yl zl)))
             (land (eq xl (n 0)) (lor (land (eq yl (n 0)) (eq yu (n 0))) (land (eq zl (n 0)) (eq zu (n 0))))))),
      retWhen isDivision (lor
        (land (land (land (land (eq xl xu) (eq yl yu)) (eq zl zu)) (ne zl (n 0))) (eq xl (call "div_op" [yl, op, zl])))
        (land (land (land (eq xl yu) (eq xu yl)) (eq xl (n 0))) (lor (gt zl (n 0)) (lt zu (n 0))))),
      retWhen (eq op opEmod) (land (land (land (land (eq xl xu) (eq yl yu)) (eq zl zu)) (ne zl (n 0))) (eq xl (call "emod" [yl, zl]))),
      retWhen (eq op opMin) (lor (land (land (eq xl yu) (eq xu yl)) (le yu zl)) (land (land (eq xl zu) (eq xu zl)) (le zu yl))),
      retWhen (eq op opMax) (lor (land (land (eq xl yu) (eq xu yl)) (ge yl zu)) (land (land (eq xl zu) (eq xu zl)) (ge zl yu))),
      ret (.litBool false)] }

/-- r1 = r2 / r3 -/
def itvDiv : SlangFunctionDecl :=
  { name := "itv_div", params := param "op" int :: itvInOut,
    body := [.ifThen (land (lt zl (n 0)) (gt zu (n 0)))
      [.assign (lower (v "r1")) (mx xl (mn yl (pick (eq yu minusInfinity) infinity (neg yu)))),
       .assign (upper (v "r1")) (mn xu (mx (pick (eq yl infinity) minusInfinity (neg yl)) yu))]
      [when (eq zl (n 0)) [.assign (lower (v "r3")) (n 1)],
       when (eq zu (n 0)) [.assign (upper (v "r3")) (neg (n 1))],
       when (lor (lor (eq yl minusInfinity) (eq yu infinity)) (lor (eq zl minusInfinity) (eq zu infinity))) [.retVoid],
       when (call "itv_is_bot" [v "r3"]) [.retVoid],
       .declInit int "t1" (call "div_op" [yl, op, zl]), .declInit int "t2" (call "div_op" [yl, op, zu]),
       .declInit int "t3" (call "div_op" [yu, op, zl]), .declInit int "t4" (call "div_op" [yu, op, zu]),
       .assign (lower (v "r1")) (mx xl (mn (mn (v "t1") (v "t2")) (mn (v "t3") (v "t4")))),
       .assign (upper (v "r1")) (mn xu (mx (mx (v "t1") (v "t2")) (mx (v "t3") (v "t4"))))]] }

def numFdiv : SlangFunctionDecl :=
  { retType := itv, name := "num_fdiv", params := [param "r1" itv, param "r3" itv],
    body := [
      .ifThen (land (lt zl (n 0)) (gt zu (n 0)))
        [ret (mk (mn (mn xl (neg xu)) (mn (mul xl zu) (add (mul (add xu (n 1)) zl) (n 1))))
                 (mx (mx (neg xl) xu) (mx (mul xl zl) (sub (mul (add xu (n 1)) zu) (n 1)))))]
        [when (lor (gt zl (n 0)) (lt zu (n 0)))
          [ret (mk (mn (mn (mul xl zl) (mul xl zu)) (mn (add (mul (add xu (n 1)) zl) (n 1)) (add (mul (add xu (n 1)) zu) (n 1))))
                   (mx (mx (mul xl zl) (mul xl zu)) (mx (sub (mul (add xu (n 1)) zl) (n 1)) (sub (mul (add xu (n 1)) zu) (n 1)))))]],
      ret itvTop] }

def numCdiv : SlangFunctionDecl :=
  { retType := itv, name := "num_cdiv", params := [param "r1" itv, param "r3" itv],
    body := [
      .ifThen (land (lt zl (n 0)) (gt zu (n 0)))
        [ret (mk (mn (mn xl (neg xu)) (mn (mul xu zl) (add (mul (sub xl (n 1)) zu) (n 1))))
                 (mx (mx (neg xl) xu) (mx (mul xu zu) (sub (mul (sub xl (n 1)) zl) (n 1)))))]
        [when (lor (gt zl (n 0)) (lt zu (n 0)))
          [ret (mk (mn (mn (mul xu zl) (mul xu zu)) (mn (add (mul (sub xl (n 1)) zl) (n 1)) (add (mul (sub xl (n 1)) zu) (n 1))))
                   (mx (mx (mul xu zl) (mul xu zu)) (mx (sub (mul (sub xl (n 1)) zl) (n 1)) (sub (mul (sub xl (n 1)) zu) (n 1)))))]],
      ret itvTop] }

def numTdiv : SlangFunctionDecl :=
  { retType := itv, name := "num_tdiv", params := [param "r1" itv, param "r3" itv],
    body := [
      retWhen (gt xl (n 0)) (call "num_fdiv" [v "r1", v "r3"]),
      retWhen (lt xu (n 0)) (call "num_cdiv" [v "r1", v "r3"]),
      when (land (le xl (n 0)) (le (n 0) xu))
        (copy "r" (mk (add (mn zl (neg zu)) (n 1)) (sub (mx (neg zl) zu) (n 1))) ++
         [when (ne xl (n 0)) [joinInto "r" (call "num_cdiv" [mk xl (neg (n 1)), v "r3"])],
          when (ne xu (n 0)) [joinInto "r" (call "num_fdiv" [mk (n 1) xu, v "r3"])],
          ret (v "r")]),
      ret itvTop] }

def numEdiv : SlangFunctionDecl :=
  { retType := itv, name := "num_ediv", params := [param "r1" itv, param "r3" itv],
    body := [
      retWhen (gt zl (n 0)) (call "num_fdiv" [v "r1", v "r3"]),
      retWhen (lt zu (n 0)) (call "num_cdiv" [v "r1", v "r3"]),
      retWhen (land (lt zl (n 0)) (gt zu (n 0)))
        (fjoinE (call "num_cdiv" [v "r1", mk zl (neg (n 1))]) (call "num_fdiv" [v "r1", mk (n 1) zu])),
      ret itvTop] }

def m1 : E := neg (n 1)
def m2 : E := neg (n 2)
/-- Lemma A.11. The source recurses; `self` and `next` name this level and the one below it. -/
def denFdiv (self next : String) : SlangFunctionDecl :=
  let nx (a b : E) : E := call next [a, b]
  { retType := itv, name := self, params := [param "r1" itv, param "r2" itv],
    body := [
      .ifThen (lor (gt xl (n 0)) (lt (add xu (n 1)) (n 0)))
        [retWhen (gt yl (n 0)) (mk (add (mn (call "fdiv" [yl, add xu (n 1)]) (call "fdiv" [yu, add xu (n 1)])) (n 1))
                                    (mx (call "fdiv" [yl, xl]) (call "fdiv" [yu, xl]))),
         retWhen (lt yu (n 0)) (mk (mn (call "cdiv" [yl, xl]) (call "cdiv" [yu, xl]))
                                    (sub (mx (call "cdiv" [yl, add xu (n 1)]) (call "cdiv" [yu, add xu (n 1)])) (n 1))),
         retWhen (land (eq (n 0) yl) (lt yl yu)) (nx (v "r1") (mk (n 1) yu)),
         retWhen (land (lt yl yu) (eq yu (n 0))) (nx (v "r1") (mk yl m1)),
         retWhen (land (lt yl (n 0)) (lt (n 0) yu)) (fjoinE (nx (v "r1") (mk yl m1)) (nx (v "r1") (mk (n 1) yu))),
         retWhen (land (eq yl (n 0)) (eq yu (n 0))) itvBot]
        [.ifThen (land (eq xl (n 0)) (eq xu (n 0)))
          [retWhen (gt yl (n 0)) (mk (add yl (n 1)) infinity), retWhen (lt yu (n 0)) (mk minusInfinity (sub yu (n 1)))]
          [.ifThen (land (eq xl m1) (eq xu m1))
            [retWhen (gt yl (n 0)) (mk minusInfinity (neg yl)), retWhen (lt yu (n 0)) (mk (neg yu) infinity),
             retWhen (land (eq (n 0) yl) (lt yl yu)) (mk minusInfinity m1), retWhen (land (lt yl yu) (eq yu (n 0))) (mk (n 1) infinity),
             retWhen (land (eq yl (n 0)) (eq yu (n 0))) itvBot]
            [.ifThen (land (eq xl (n 0)) (lt (n 0) xu))
              [ret (fjoinE (nx (mk (n 0) (n 0)) (v "r2")) (nx (mk (n 1) xu) (v "r2")))]
              [.ifThen (land (lt xl m1) (eq xu m1))
                [ret (fjoinE (nx (mk xl m2) (v "r2")) (nx (mk m1 m1) (v "r2")))]
                [when (land (le xl m1) (ge xu (n 0)))
                  (copy "r" (nx (mk m1 m1) (v "r2")) ++
                   [joinInto "r" (nx (mk (n 0) (n 0)) (v "r2")),
                    when (ne xl m1) [joinInto "r" (nx (mk xl m2) (v "r2"))],
                    when (ne xu (n 0)) [joinInto "r" (nx (mk (n 1) xu) (v "r2"))],
                    ret (v "r")])]]]]],
      ret itvTop] }

/-- Lemma C.12. -/
def denCdiv (self next : String) : SlangFunctionDecl :=
  let nx (a b : E) : E := call next [a, b]
  { retType := itv, name := self, params := [param "r1" itv, param "r2" itv],
    body := [
      .ifThen (lor (gt (sub xl (n 1)) (n 0)) (lt xu (n 0)))
        [retWhen (gt yl (n 0)) (mk (mn (call "cdiv" [yl, xu]) (call "cdiv" [yu, xu]))
                                    (sub (mx (call "cdiv" [yl, sub xl (n 1)]) (call "cdiv" [yu, sub xl (n 1)])) (n 1))),
         retWhen (lt yu (n 0)) (mk (add (mn (call "fdiv" [yl, sub xl (n 1)]) (call "fdiv" [yu, sub xl (n 1)])) (n 1))
                                    (mx (call "fdiv" [yl, xu]) (call "fdiv" [yu, xu]))),
         retWhen (land (eq (n 0) yl) (lt yl yu)) (nx (v "r1") (mk (n 1) yu)),
         retWhen (land (lt yl yu) (eq yu (n 0))) (nx (v "r1") (mk yl m1)),
         retWhen (land (lt yl (n 0)) (lt (n 0) yu)) (fjoinE (nx (v "r1") (mk yl m1)) (nx (v "r1") (mk (n 1) yu))),
         retWhen (land (eq yl (n 0)) (eq yu (n 0))) itvBot]
        [.ifThen (land (eq xl (n 0)) (eq xu (n 0)))
          [retWhen (gt yl (n 0)) (mk minusInfinity (sub (neg yl) (n 1))), retWhen (lt yu (n 0)) (mk (add (neg yu) (n 1)) infinity)]
          [.ifThen (land (eq xl (n 1)) (eq xu (n 1)))
            [retWhen (gt yl (n 0)) (mk yl infinity), retWhen (lt yu (n 0)) (mk minusInfinity yu),
             retWhen (land (eq (n 0) yl) (lt yl yu)) (mk (n 1) infinity), retWhen (land (lt yl yu) (eq yu (n 0))) (mk minusInfinity m1),
             retWhen (land (eq yl (n 0)) (eq yu (n 0))) itvBot]
            [.ifThen (land (lt xl (n 0)) (eq xu (n 0)))
              [ret (fjoinE (nx (mk xl m1) (v "r2")) (nx (mk (n 0) (n 0)) (v "r2")))]
              [.ifThen (land (eq xl (n 1)) (lt (n 1) xu))
                [ret (fjoinE (nx (mk (n 1) (n 1)) (v "r2")) (nx (mk (n 2) xu) (v "r2")))]
                [when (land (le xl (n 0)) (ge xu (n 1)))
                  (copy "r" (nx (mk (n 1) (n 1)) (v "r2")) ++
                   [joinInto "r" (nx (mk (n 0) (n 0)) (v "r2")),
                    when (ne xl (n 0)) [joinInto "r" (nx (mk xl m1) (v "r2"))],
                    when (ne xu (n 1)) [joinInto "r" (nx (mk (n 2) xu) (v "r2"))],
                    ret (v "r")])]]]]],
      ret itvTop] }

def denFdivBelow : SlangFunctionDecl := { retType := itv, name := "den_fdiv_below", params := [param "r1" itv, param "r2" itv], body := [ret itvTop] }
def denCdivBelow : SlangFunctionDecl := { retType := itv, name := "den_cdiv_below", params := [param "r1" itv, param "r2" itv], body := [ret itvTop] }

/-- Lemma C.13 for x = [0, 0]; the source calls `den_tdiv` on it. -/
def denTdivZero : SlangFunctionDecl :=
  { retType := itv, name := "den_tdiv_zero", params := itvParameters,
    body := [retWhen (land (gt yl (n 0)) (gt zl (n 0))) (mk (add yl (n 1)) infinity),
      retWhen (land (gt yl (n 0)) (lt zu (n 0))) (mk minusInfinity (sub (neg yl) (n 1))),
      retWhen (land (lt yu (n 0)) (gt zl (n 0))) (mk (add (neg yu) (n 1)) infinity),
      retWhen (land (lt yu (n 0)) (lt zu (n 0))) (mk minusInfinity (sub yu (n 1))), ret itvTop] }

def denTdiv : SlangFunctionDecl :=
  { retType := itv, name := "den_tdiv", params := itvParameters,
    body := [
      retWhen (gt xl (n 0)) (call "den_fdiv" [v "r1", v "r2"]),
      retWhen (lt xu (n 0)) (call "den_cdiv" [v "r1", v "r2"]),
      retWhen (land (eq xl (n 0)) (eq xu (n 0))) (call "den_tdiv_zero" [v "r1", v "r2", v "r3"]),
      when (land (le xl (n 0)) (le (n 0) xu))
        (copy "r" (call "den_tdiv_zero" [mk (n 0) (n 0), v "r2", v "r3"]) ++
         [when (ne xl (n 0)) [joinInto "r" (call "den_cdiv" [mk xl m1, v "r2"])],
          when (ne xu (n 0)) [joinInto "r" (call "den_fdiv" [mk (n 1) xu, v "r2"])],
          ret (v "r")]),
      ret itvTop] }

def denEdiv : SlangFunctionDecl :=
  { retType := itv, name := "den_ediv", params := itvParameters,
    body := [
      retWhen (gt zl (n 0)) (call "den_fdiv" [v "r1", v "r2"]),
      retWhen (lt zu (n 0)) (call "den_cdiv" [v "r1", v "r2"]),
      retWhen (land (lt zl (n 0)) (lt (n 0) zu)) (fjoinE (call "den_fdiv" [v "r1", v "r2"]) (call "den_cdiv" [v "r1", v "r2"])),
      ret itvTop] }

def itvDivNum : SlangFunctionDecl :=
  { name := "itv_div_num", params := [param "op" int, param "r1" itv, param "r2" itv .qInOut, param "r3" itv],
    body := [
      when (eq op opFdiv) [meetInto "r2" (call "num_fdiv" [v "r1", v "r3"])],
      when (eq op opCdiv) [meetInto "r2" (call "num_cdiv" [v "r1", v "r3"])],
      when (eq op opTdiv) [meetInto "r2" (call "num_tdiv" [v "r1", v "r3"])],
      when (eq op opEdiv) [meetInto "r2" (call "num_ediv" [v "r1", v "r3"])]] }

def itvDivDen : SlangFunctionDecl :=
  { name := "itv_div_den", params := [param "op" int, param "r1" itv, param "r2" itv, param "r3" itv .qInOut],
    body := [
      when (eq op opFdiv) [meetInto "r3" (call "den_fdiv" [v "r1", v "r2"])],
      when (eq op opCdiv) [meetInto "r3" (call "den_cdiv" [v "r1", v "r2"])],
      when (eq op opTdiv) [meetInto "r3" (call "den_tdiv" [v "r1", v "r2", v "r3"])],
      when (eq op opEdiv) [meetInto "r3" (call "den_ediv" [v "r1", v "r2", v "r3"])]] }

def mulInv : SlangFunctionDecl :=
  { name := "mul_inv", params := [param "r1" itv, param "r2" itv .qInOut, param "r3" itv .qInOut],
    body := [
      when (lor (gt xl (n 0)) (lt xu (n 0)))
        [when (eq zl (n 0)) [.assign (lower (v "r3")) (n 1)], when (eq zu (n 0)) [.assign (upper (v "r3")) m1]],
      .ifThen (land (lor (gt xl (n 0)) (lt xu (n 0))) (land (lt zl (n 0)) (gt zu (n 0))))
        [.assign (lower (v "r2")) (mx yl (mn xl (pick (eq xu minusInfinity) infinity (neg xu)))),
         .assign (upper (v "r2")) (mn yu (mx (pick (eq xl infinity) minusInfinity (neg xl)) xu))]
        [when (lor (lor (gt xl (n 0)) (lt xu (n 0))) (lor (gt zl (n 0)) (lt zu (n 0))))
          [when (lor (lor (eq xl minusInfinity) (eq xu infinity)) (lor (eq zl minusInfinity) (eq zu infinity))) [.retVoid],
           when (call "itv_is_bot" [v "r3"]) [.retVoid],
           .assign (lower (v "r2")) (mx yl (mn (mn (call "cdiv" [xl, zl]) (call "cdiv" [xl, zu])) (mn (call "cdiv" [xu, zl]) (call "cdiv" [xu, zu])))),
           .assign (upper (v "r2")) (mn yu (mx (mx (call "fdiv" [xl, zl]) (call "fdiv" [xl, zu])) (mx (call "fdiv" [xu, zl]) (call "fdiv" [xu, zu]))))]]] }

def isOne (r : String) : E := land (eq (lower (v r)) (n 1)) (eq (upper (v r)) (n 1))
def isZero (r : String) : E := land (eq (lower (v r)) (n 0)) (eq (upper (v r)) (n 0))

/-- `deduce`: the source embeds each result into the store; here `r1`, `r2`, `r3` are changed in place, as the source changes its copies, and are the new store values. -/
def deduceFn : SlangFunctionDecl :=
  { name := "deduce", params := param "op" int :: itvInOut,
    body := [
      when (eq op opEq)
        [.ifThen (isOne "r1") [.decl itv "o2", .assign (v "o2") (v "r2"), meetInto "r2" (v "r3"), meetInto "r3" (v "o2")]
          [.ifThen (land (isZero "r1") (lor (eq yl yu) (eq zl zu)))
            [.decl itv "hole", .assign (v "hole") (mk (pick (eq yl zl) (add yl (n 1)) minusInfinity) (pick (eq yu zu) (sub yu (n 1)) infinity)),
             .ifThen (eq zl zu) [meetInto "r2" (v "hole")] [meetInto "r3" (v "hole")]]
            [.ifThen (land (eq yu zl) (eq yl zu)) [meetInto "r1" (mk (n 1) (n 1))]
              [when (lor (gt yl zu) (lt yu zl)) [meetInto "r1" (mk (n 0) (n 0))]]]],
         .retVoid],
      when (eq op opLeq)
        [.ifThen (isOne "r1") [.decl itv "m", .assign (v "m") (mk yl zu), meetInto "r2" (v "m"), meetInto "r3" (v "m")]
          [.ifThen (isZero "r1")
            [.decl itv "a", .assign (v "a") (mk (add zl (n 1)) yu), .decl itv "b", .assign (v "b") (mk zl (sub yu (n 1))),
             meetInto "r2" (v "a"), meetInto "r3" (v "b")]
            [.ifThen (le yu zl) [meetInto "r1" (mk (n 1) (n 1))] [when (gt yl zu) [meetInto "r1" (mk (n 0) (n 0))]]]],
         .retVoid],
      when (eq op opAdd) ([
        .assign (lower (v "r1")) (pick (lor (eq yl minusInfinity) (eq zl minusInfinity)) xl (mx xl (add yl zl))),
        .assign (upper (v "r1")) (pick (lor (eq yu infinity) (eq zu infinity)) xu (mn xu (add yu zu))),
        .assign (lower (v "r2")) (pick (lor (eq xl minusInfinity) (eq zu infinity)) yl (mx yl (sub xl zu))),
        .assign (upper (v "r2")) (pick (lor (eq xu infinity) (eq zl minusInfinity)) yu (mn yu (sub xu zl))),
        .assign (lower (v "r3")) (pick (lor (eq xl minusInfinity) (eq yu infinity)) zl (mx zl (sub xl yu))),
        .assign (upper (v "r3")) (pick (lor (eq xu infinity) (eq yl minusInfinity)) zu (mn zu (sub xu yl))), .retVoid]),
      when (eq op opMul) ([
        when (land (land (ne yl minusInfinity) (ne yu infinity)) (land (ne zl minusInfinity) (ne zu infinity)))
          [.declInit int "t1" (mul yl zl), .declInit int "t2" (mul yl zu), .declInit int "t3" (mul yu zl), .declInit int "t4" (mul yu zu),
           .assign (lower (v "r1")) (mx xl (mn (mn (v "t1") (v "t2")) (mn (v "t3") (v "t4")))),
           .assign (upper (v "r1")) (mn xu (mx (mx (v "t1") (v "t2")) (mx (v "t3") (v "t4"))))],
        .expr (call "mul_inv" [v "r1", v "r2", v "r3"]), .expr (call "mul_inv" [v "r1", v "r3", v "r2"]), .retVoid]),
      when isDivision ([
        .expr (call "itv_div" [op, v "r1", v "r2", v "r3"]),
        when (land (.un "!" (call "itv_is_bot" [v "r1"])) (.un "!" (call "itv_is_bot" [v "r3"])))
          [.expr (call "itv_div_num" [op, v "r1", v "r2", v "r3"]),
           when (.un "!" (call "itv_is_bot" [v "r2"])) [.expr (call "itv_div_den" [op, v "r1", v "r2", v "r3"])]], .retVoid]),
      when (eq op opEmod) ([
        when (eq zl (n 0)) [.assign (lower (v "r3")) (n 1)], when (eq zu (n 0)) [.assign (upper (v "r3")) m1],
        when (land (eq yl yu) (eq zl zu)) [.assign (lower (v "r1")) (call "emod" [yl, zl]), .assign (upper (v "r1")) xl], .retVoid]),
      when (eq op opMin) ([
        .assign (lower (v "r1")) (mx xl (mn yl zl)), .assign (upper (v "r1")) (mn xu (mn yu zu)),
        .assign (lower (v "r2")) (mx yl xl), when (lt xu zl) [.assign (upper (v "r2")) (mn yu xu)],
        .assign (lower (v "r3")) (mx zl xl), when (lt xu yl) [.assign (upper (v "r3")) (mn zu xu)], .retVoid]),
      when (eq op opMax) ([
        .assign (lower (v "r1")) (mx xl (mx yl zl)), .assign (upper (v "r1")) (mn xu (mx yu zu)),
        .assign (upper (v "r2")) (mn yu xu), when (gt xl zu) [.assign (lower (v "r2")) (mx yl xl)],
        .assign (upper (v "r3")) (mn zu xu), when (gt xl yu) [.assign (lower (v "r3")) (mx zl xl)], .retVoid])] }

def shaderModule : SlangShaderModule :=
  { structs := [itvStruct],
    functions := [signum, tdiv, fdiv, cdiv, ediv, emod, itvMake, itvTopFn, itvBotFn, itvIsTop, itvIsBot, itvMeet, itvJoin, itvFjoin, divFn,
      askFn, itvDiv, numFdiv, numCdiv, numTdiv, numEdiv,
      denFdivBelow, denCdivBelow,
      denFdiv "den_fdiv0" "den_fdiv_below", denCdiv "den_cdiv0" "den_cdiv_below",
      denFdiv "den_fdiv1" "den_fdiv0", denCdiv "den_cdiv1" "den_cdiv0",
      denFdiv "den_fdiv" "den_fdiv1", denCdiv "den_cdiv" "den_cdiv1",
      denTdivZero, denTdiv, denEdiv, itvDivNum, itvDivDen, mulInv, deduceFn] }

end Turbo
