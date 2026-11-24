-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Formula
import Std.Data.HashMap
import Std.Data.HashSet
/-! The FlatZinc parser of lala-parsing (`flatzinc_parser.hpp`), written as a recursive descent over the bytes.
    The grammar, the semantic actions, `predicate_call` and the annotation handling follow the C++ source;
    table constraints (`turbo_fzn_*`) are not used by the three levels and are refused. -/
namespace Frontend
open F

/-- A semantic value of the PEG (`std::any`). -/
inductive Val where
  | f (x : F)
  | arr (xs : Array F)
  | str (s : String)
  | srt (s : Srt)

structure Ann where
  name : String
  params : Array Val

/-- What `SolverOutput` records: the `output_var` variables and the `output_array` arrays with their dimensions. -/
structure Output where
  vars : Array String := #[]
  arrays : Array (String × Array F × Array String) := #[]

structure S where
  pos : Nat := 0
  params : Std.HashMap String F := {}
  arrays : Std.HashMap String Nat := {}
  out : Output := {}
  arrayIdx : Std.HashMap String Nat := {}
  ignored : Std.HashSet String := {}
  warnings : Array String := #[]

abbrev P := ReaderT ByteArray (StateT S (Except String))

namespace Fzn

def byteAt (i : Nat) : P (Option UInt8) := do
  let inp ← read
  return if h : i < inp.size then some inp[i] else none

def peek : P (Option UInt8) := do byteAt (← get).pos

def isWs (c : UInt8) : Bool := c == 32 || c == 10 || c == 13 || c == 9
def isDigit (c : UInt8) : Bool := c ≥ 48 && c ≤ 57
def isIdStart (c : UInt8) : Bool := (c ≥ 65 && c ≤ 90) || (c ≥ 97 && c ≤ 122) || c == 95
def isIdChar (c : UInt8) : Bool := isIdStart c || isDigit c

partial def skipWs : P Unit := do
  match ← peek with
  | some c =>
    if isWs c then modify (fun s => { s with pos := s.pos + 1 }); skipWs
    else if c == 37 then
      -- a `%` comment runs to the end of the line
      let rec go : P Unit := do
        match ← peek with
        | some d => if d == 10 || d == 13 then pure () else modify (fun s => { s with pos := s.pos + 1 }); go
        | none => pure ()
      go; skipWs
    else pure ()
  | none => pure ()

def startsWithAt (s : String) (i : Nat) : P Bool := do
  let inp ← read
  let bs := s.toUTF8
  if i + bs.size > inp.size then return false
  let mut k := 0
  while k < bs.size do
    if inp[i + k]! != bs[k]! then return false
    k := k + 1
  return true

def peekLit (s : String) : P Bool := do startsWithAt s (← get).pos

/-- Match a literal token, then skip the whitespace. -/
def matchLit (s : String) : P Bool := do
  if ← peekLit s then
    modify fun st => { st with pos := st.pos + s.utf8ByteSize }
    skipWs
    return true
  else return false

def expect (s : String) : P Unit := do
  unless ← matchLit s do
    throw s!"{(← get).pos}: expected `{s}`"

def substr (a b : Nat) : P String := do
  let inp ← read
  return String.fromUTF8! (inp.extract a b)

/-- `Identifier <- < [a-zA-Z_][a-zA-Z0-9_]* >`. -/
def identOpt : P (Option String) := do
  let st ← get
  match ← byteAt st.pos with
  | some c =>
    if isIdStart c then
      let mut j := st.pos + 1
      while (← byteAt j).any isIdChar do j := j + 1
      let name ← substr st.pos j
      set { st with pos := j }
      skipWs
      return some name
    else return none
  | none => return none

def ident : P String := do
  match ← identOpt with
  | some n => pure n
  | none => throw s!"{(← get).pos}: expected an identifier"

/-- `Integer <- < [+-]? [0-9]+ >` as a number, or `none` and nothing consumed. -/
def integerOpt : P (Option Int) := do
  let st ← get
  let mut j := st.pos
  let mut neg := false
  match ← byteAt j with
  | some 45 => neg := true; j := j + 1
  | some 43 => j := j + 1
  | _ => pure ()
  let d0 := j
  let mut n : Nat := 0
  while (← byteAt j).any isDigit do
    n := n * 10 + ((← byteAt j).get! - 48).toNat
    j := j + 1
  if j == d0 then return none
  set { st with pos := j }
  skipWs
  return some (if neg then -(n : Int) else (n : Int))

/-- `Real`: `inf`, `-inf`, or a number with a fraction or an exponent (not the `..` of a range). -/
def realOpt : P (Option F) := do
  let st ← get
  let i := st.pos
  if ← startsWithAt "inf" i then
    set { st with pos := i + 3 }; skipWs
    return some (r untyped (1.0 / 0.0) (1.0 / 0.0))
  if ← startsWithAt "-inf" i then
    set { st with pos := i + 4 }; skipWs
    return some (r untyped (-1.0 / 0.0) (-1.0 / 0.0))
  let mut j := i
  let mut neg := false
  match ← byteAt j with
  | some 45 => neg := true; j := j + 1
  | some 43 => j := j + 1
  | _ => pure ()
  let d0 := j
  let mut mant : Nat := 0
  while (← byteAt j).any isDigit do
    mant := mant * 10 + ((← byteAt j).get! - 48).toNat
    j := j + 1
  if j == d0 then return none
  let mut scale : Int := 0
  let mut ok := false
  let mut k := j
  if (← byteAt k) == some 46 then
    let k1 := k + 1
    if (← startsWithAt ".." k1) || (← byteAt k1) != some 46 then
      k := k1
      while (← byteAt k).any isDigit do
        mant := mant * 10 + ((← byteAt k).get! - 48).toNat
        scale := scale - 1
        k := k + 1
      ok := true
  if !ok then
    k := j
    if (← byteAt k).any (fun c => c == 69 || c == 101) then
      let mut m := k + 1
      let mut eneg := false
      match ← byteAt m with
      | some 45 => eneg := true; m := m + 1
      | some 43 => m := m + 1
      | _ => pure ()
      let e0 := m
      let mut ex : Nat := 0
      while (← byteAt m).any isDigit do
        ex := ex * 10 + ((← byteAt m).get! - 48).toNat
        m := m + 1
      if m > e0 then
        scale := scale + (if eneg then -(ex : Int) else (ex : Int))
        k := m
        ok := true
  if !ok then return none
  let v : Float :=
    let base := Float.ofNat mant
    if scale ≥ 0 then base * (10.0 ^ Float.ofNat scale.toNat) else base / (10.0 ^ Float.ofNat (-scale).toNat)
  let v := if neg then -v else v
  set { st with pos := k }
  skipWs
  return some (r untyped v v)

def arrayAccessName (name : String) (i : Int) : String := name ++ "[" ++ toString (i + 1) ++ "]"

def err {α} (msg : String) : P α := do throw s!"{(← get).pos}: {msg}"

mutual
/-- `Literal <- Boolean / Real / Integer / ArrayAccess / VariableLit / Set`. -/
partial def literal : P F := do
  if ← matchLit "true" then return mkTrue
  if ← matchLit "false" then return mkFalse
  if let some x ← realOpt then return x
  if let some n ← integerOpt then return mkZ n
  match ← peek with
  | some 123 => setLiteral
  | _ =>
    let name ← ident
    if ← matchLit "[" then
      let idx ← match ← identOpt with
        | some n => pure (mkLvar n)
        | none => match ← integerOpt with
          | some n => pure (mkZ n)
          | none => err "bad array index"
      expect "]"
      accessLiteral name idx
    else return mkLvar name

partial def accessLiteral (name : String) (index : F) : P F := do
  let st ← get
  let idx ← match index with
    | z _ n => pure n
    | lv _ p => match st.params[p]? with
      | some (z _ n) => pure n
      | _ => err "Given `a[b]`, `b` must be an integer or an integer parameter."
    | _ => err "Given `a[b]`, `b` must be an integer or an integer parameter."
  let access := arrayAccessName name (idx - 1)
  match st.params[access]? with
  | some p => return p
  | none => return mkLvar access

/-- `RangeLiteral <- SetRange / Literal`. -/
partial def rangeLiteral : P F := do
  let lo ← literal
  if ← matchLit ".." then
    let hi ← literal
    return mkSet #[(lo, hi)]
  else return lo

/-- `InnerRangeLiteral <- InnerSetRange / Literal`, as a set element or an interval. -/
partial def innerRange : P (Sum (F × F) F) := do
  let lo ← literal
  if ← matchLit ".." then
    let hi ← literal
    return .inl (lo, hi)
  else return .inr lo

/-- `Set` and `make_set_literal`. -/
partial def setLiteral : P F := do
  expect "{"
  let mut set : Array (F × F) := #[]
  if ← matchLit "}" then return mkSet set
  repeat
    match ← innerRange with
    | .inl rg => set := set.push rg
    | .inr element =>
      let mut added := false
      match element with
      | z _ n =>
        if set.size > 0 then
          let (lo, ub) := set.back!
          match ub with
          | z t u =>
            if u == n - 1 then
              set := set.pop.push (lo, z t n)
              added := true
          | _ => err "Elements in a set are expected to be all of the same type."
      | lv _ name =>
        match (← get).params[name]? with
        | some p => set := set.push (p, p); added := true
        | none => err s!"Undeclared parameter `{name}`."
      | _ => pure ()
      if !added then set := set.push (element, element)
    if ← matchLit "," then continue else break
  expect "}"
  return mkSet set
end

/-- `Type <- IntType / RealType / BoolType / SetType`; nothing is consumed on failure. -/
partial def typeOpt : P (Option Srt) := do
  let save := (← get).pos
  if ← matchLit "int" then return some .int
  if ← matchLit "float" then return some .real
  if ← matchLit "real" then return some .real
  if ← matchLit "bool" then return some .bool
  if ← matchLit "set" then
    if ← matchLit "of" then
      if let some sub ← typeOpt then return some (.set sub)
  modify fun st => { st with pos := save }
  return none

/-- `ValueType <- Type / SetValue / SetRange / Set`. -/
def valueType : P Val := do
  if let some t ← typeOpt then return .srt t
  if ← matchLit "set" then
    expect "of"
    let inner ← match ← peek with
      | some 123 => setLiteral
      | _ => do
        let lo ← literal
        expect ".."
        let hi ← literal
        pure (mkSet #[(lo, hi)])
    return .f (mkSet #[(mkSet #[], inner)])
  match ← peek with
  | some 123 => return .f (← setLiteral)
  | _ =>
    let lo ← literal
    expect ".."
    let hi ← literal
    return .f (mkSet #[(lo, hi)])

/-- `LiteralArray <- '[]' / '[' RangeLiteral (',' RangeLiteral)* ']'`. -/
partial def literalArray : P (Array F) := do
  if ← matchLit "[]" then return #[]
  expect "["
  let mut xs : Array F := #[]
  repeat
    xs := xs.push (← rangeLiteral)
    if ← matchLit "," then continue else break
  expect "]"
  return xs

-- `Parameter <- LiteralInExpression / FunctionCall / LiteralArray` and the predicate table.
mutual
partial def parameter : P Val := do
  match ← peek with
  | some 91 => return .arr (← literalArray)
  | some c =>
    if isIdStart c then
      let save := (← get).pos
      let isKeywordLit := (← peekLit "true") || (← peekLit "false") || (← peekLit "inf")
      if !isKeywordLit then
        let name ← ident
        if ← matchLit "(" then
          let args ← parameters
          expect ")"
          let sv := #[Val.str name] ++ args
          return .f (← functionCall sv)
        modify fun st => { st with pos := save }
    return .f (← rangeLiteral)
  | none => err "unexpected end of input"

partial def parameters : P (Array Val) := do
  let mut ps : Array Val := #[]
  repeat
    ps := ps.push (← parameter)
    if ← matchLit "," then continue else break
  return ps

partial def functionCall (sv : Array Val) : P F := do
  let st ← get
  match ← tryP (predicateCall sv) with
  | some x => return x
  | none =>
    set st
    functionFallback sv

partial def tryP {α} (p : P α) : P (Option α) := do
  let s ← get
  let r ← read
  match (p.run r |>.run s) with
  | .ok (a, s') => set s'; return some a
  | .error _ => return none

partial def functionFallback (sv : Array Val) : P F := do
  let name := match sv[0]? with | some (Val.str n) => n | _ => ""
  let un (sg : Sig) := makeUnaryFun sg sv
  let bi (sg : Sig) := makeBinaryFun sg sv
  match name with
  | "int_abs" => un .ABS | "int_neg" => un .NEG
  | "int_div" => bi .TDIV | "int_ediv" => bi .EDIV | "int_fdiv" => bi .FDIV | "int_cdiv" => bi .CDIV | "int_tdiv" => bi .TDIV
  | "int_mod" => bi .EMOD | "int_plus" => bi .ADD | "int_minus" => bi .SUB | "int_pow" => bi .POW
  | "int_times" => bi .MUL | "int_max" => bi .MAX | "int_min" => bi .MIN
  | "bool_and" => bi .AND | "bool_not" => un .NOT | "bool_or" => bi .OR | "bool_xor" => bi .XOR
  | "set_card" => un .CARD | "set_diff" => bi .DIFFERENCE | "set_intersect" => bi .INTERSECTION
  | "set_union" => bi .UNION | "set_symdiff" => bi .SYMMETRIC_DIFFERENCE
  | "float_abs" => bi .ABS | "float_neg" => bi .NEG | "float_plus" => bi .ADD | "float_minus" => bi .SUB
  | "float_times" => bi .MUL
  | "float_acos" => un .ACOS | "float_acosh" => un .ACOSH | "float_asin" => un .ASIN | "float_asinh" => un .ASINH
  | "float_atan" => un .ATAN | "float_atanh" => un .ATANH | "float_cos" => un .COS | "float_cosh" => un .COSH
  | "float_sin" => un .SIN | "float_sinh" => un .SINH | "float_tan" => un .TAN | "float_tanh" => un .TANH
  | "float_div" => bi .DIV | "float_log10" => makeLog 10 sv | "float_log2" => makeLog 2 sv
  | "float_min" => bi .MIN | "float_max" => bi .MAX | "float_exp" => un .EXP | "float_ln" => un .LN
  | "float_pow" => bi .POW | "float_sqrt" => un .SQRT
  | _ => err s!"Unknown function or predicate symbol `{name}`"

partial def fv (sv : Array Val) (i : Nat) : P F :=
  match sv[i]? with
  | some (Val.f x) => pure x
  | _ => err "bad_any_cast"

partial def arityError (sg : Sig) (expected obtained : Nat) : P F :=
  err s!"The symbol `{repr sg}` expects `{expected}` parameters, but we got `{obtained}` parameters."

partial def makeBinary (sg : Sig) (sv : Array Val) : P F := do
  if sv.size != 3 then arityError sg 2 (sv.size - 1)
  else return mkBinary (← fv sv 1) sg (← fv sv 2)

partial def makeUnaryFunEq (sg : Sig) (sv : Array Val) (eqKind : Sig := .EQ) : P F := do
  if sv.size != 3 then arityError sg 1 (sv.size - 2)
  else return mkBinary (mkUnary sg (← fv sv 1)) eqKind (← fv sv 2)

partial def makeUnaryFun (sg : Sig) (sv : Array Val) : P F := do
  if sv.size != 2 then arityError sg 1 (sv.size - 1)
  else return mkUnary sg (← fv sv 1)

partial def makeBinaryFunEq (sg : Sig) (sv : Array Val) (eqKind : Sig := .EQ) : P F := do
  if sv.size != 4 then arityError sg 2 (sv.size - 2)
  else
    let left := mkBinary (← fv sv 1) sg (← fv sv 2)
    let right ← fv sv 3
    if eqKind == .EQUIV && right.isTrue then return left
    else return mkBinary left eqKind right

partial def makeBinaryFun (sg : Sig) (sv : Array Val) : P F := do
  if sv.size != 3 then arityError sg 2 (sv.size - 1)
  else return mkBinary (← fv sv 1) sg (← fv sv 2)

partial def makeNaryFun (sg : Sig) (sv : Array Val) : P F := do
  let mut seq : Array F := #[]
  for i in [1:sv.size] do seq := seq.push (← fv sv i)
  return mkNary sg seq

partial def makeFloatIn (sv : Array Val) : P F := do
  let x ← fv sv 1
  return mkBinary (mkBinary x .GEQ (← fv sv 2)) .AND (mkBinary x .LEQ (← fv sv 3))

partial def makeLog (base : Int) (sv : Array Val) : P F := do
  return mkBinary (← fv sv 1) .LOG (mkZ base)

partial def makeLogEq (base : Int) (sv : Array Val) : P F := do
  return mkBinary (← makeLog base sv) .EQ (← fv sv 2)

/-- `resolve_array`: the elements of a literal array or of a named array. -/
partial def resolveArray (sv : Array Val) (i : Nat) : P (Array F) := do
  match sv[i]? with
  | some (Val.arr xs) => return (mkNary .AND xs).seqChildren
  | some (Val.f (lv _ name)) =>
    let st ← get
    match st.arrays[name]? with
    | none => err s!"Unknown array parameter `{name}`"
    | some size =>
      let mut seq : Array F := #[]
      for k in [0:size] do
        let vn := arrayAccessName name k
        match st.params[vn]? with
        | some p => seq := seq.push p
        | none => seq := seq.push (mkLvar vn)
      return (mkNary .AND seq).seqChildren
  | some (Val.f _) => err "Expects an array or the name of an array."
  | _ => err "Expects an array of valid elements."

partial def makeElement (name : String) (sv : Array Val) : P F := do
  if sv.size < 4 then err s!"`{name}` expects 3 parameters, but we got `{sv.size - 1}` parameters"
  let index ← fv sv 1
  let array ← resolveArray sv 2
  let value ← fv sv 3
  let mut seq : Array F := #[]
  for i in [0:array.size] do
    seq := seq.push (mkBinary (mkBinary index .EQ (mkZ (i + 1))) .IMPLY (mkBinary array[i]! .EQ value))
  return mkNary .AND seq

partial def makeLinear (name : String) (sg : Sig) (sv : Array Val) : P F := do
  if sv.size != 4 && sv.size != 5 then
    err s!"`{name}` expects 3 (or 4 if reified) parameters, but we got `{sv.size - 1}` parameters"
  let as ← resolveArray sv 1
  let bs ← resolveArray sv 2
  let c ← fv sv 3
  if as.size != bs.size then err s!"`{name}` expects arrays of the same size."
  let mut sum : Array F := #[]
  for i in [0:as.size] do sum := sum.push (mkBinary as[i]! .MUL bs[i]!)
  let lin :=
    if sum.size == 1 then mkBinary sum[0]! sg c else mkBinary (mkNary .ADD sum) sg c
  if sv.size == 5 then return mkBinary (← fv sv 4) .EQUIV lin else return lin

partial def makeBooleanConstraint (name : String) (sg : Sig) (sv : Array Val) : P F := do
  if sv.size != 2 && sv.size != 3 then
    err s!"`{name}` expects 1 (or 2 if reified) parameters, but we got `{sv.size - 1}` parameters"
  let array ← resolveArray sv 1
  if sv.size == 3 then return mkBinary (← fv sv 2) .EQUIV (mkNary sg array)
  else return mkNary sg array

partial def makeBooleanClause (name : String) (sv : Array Val) : P F := do
  if sv.size != 3 && sv.size != 4 then
    err s!"`{name}` expects 2 (or 3 if reified) parameters, but we got `{sv.size - 1}` parameters"
  let as ← resolveArray sv 1
  let bs ← resolveArray sv 2
  let negs := bs.map fun b => mkUnary .NOT b
  let clause := mkBinary (mkNary .OR as) .OR (mkNary .OR negs)
  if sv.size == 4 then return mkBinary (← fv sv 3) .EQUIV clause else return clause

/-- `predicate_call`. -/
partial def predicateCall (sv : Array Val) : P F := do
  let name := match sv[0]? with | some (Val.str n) => n | _ => ""
  let bin (sg : Sig) := makeBinary sg sv
  let bfe (sg : Sig) := makeBinaryFunEq sg sv
  let bfr (sg : Sig) := makeBinaryFunEq sg sv .EQUIV
  let ufe (sg : Sig) := makeUnaryFunEq sg sv
  match name with
  | "int_le" => bin .LEQ | "int_lt" => bin .LT | "int_ge" => bin .GEQ | "int_gt" => bin .GT
  | "int_eq" => bin .EQ | "int_ne" => bin .NEQ
  | "int_abs" => ufe .ABS | "int_neg" => ufe .NEG
  | "int_div" => bfe .TDIV | "int_ediv" => bfe .EDIV | "int_tdiv" => bfe .TDIV | "int_cdiv" => bfe .CDIV
  | "int_fdiv" => bfe .FDIV | "int_mod" => bfe .EMOD | "int_plus" => bfe .ADD | "int_minus" => bfe .SUB
  | "int_pow" => bfe .POW | "int_times" => bfe .MUL | "int_max" => bfe .MAX | "int_min" => bfe .MIN
  | "int_eq_reif" => bfr .EQ | "int_le_reif" => bfr .LEQ | "int_lt_reif" => bfr .LT | "int_ne_reif" => bfr .NEQ
  | "bool2int" => bin .EQ | "bool_eq" => bin .EQ | "bool_le" => bin .LEQ | "bool_lt" => bin .LT
  | "bool_imply" => bin .IMPLY
  | "bool_eq_reif" => bfr .EQ | "bool_le_reif" => bfr .LEQ | "bool_lt_reif" => bfr .LT
  | "bool_and" => bfr .AND
  | "bool_not" => if sv.size == 3 then bin .XOR else makeUnaryFun .NOT sv
  | "bool_or" => bfr .OR
  | "nbool_and" => makeNaryFun .AND sv | "nbool_or" => makeNaryFun .OR sv | "nbool_equiv" => makeNaryFun .EQUIV sv
  | "bool_xor" => if sv.size == 3 then bin .XOR else bfr .XOR
  | "set_card" => ufe .CARD | "set_diff" => bfe .DIFFERENCE | "set_eq" => bin .EQ | "set_eq_reif" => bfr .EQ
  | "set_in" => bin .IN | "set_in_reif" => bfr .IN | "set_intersect" => bfr .INTERSECTION
  | "set_union" => bfr .UNION | "set_ne" => bin .NEQ | "set_ne_reif" => bfr .NEQ
  | "set_subset" => bin .SUBSETEQ | "set_subset_reif" => bfr .SUBSETEQ | "set_superset" => bin .SUPSETEQ
  | "set_symdiff" => bfr .SYMMETRIC_DIFFERENCE | "set_le" => bin .LEQ | "set_le_reif" => bfr .LEQ
  | "set_lt" => bin .LT | "set_lt_reif" => bfr .LT
  | "float_abs" => bfe .ABS | "float_neg" => bfe .NEG | "float_plus" => bfe .ADD | "float_minus" => bfe .SUB
  | "float_times" => bfe .MUL
  | "float_acos" => ufe .ACOS | "float_acosh" => ufe .ACOSH | "float_asin" => ufe .ASIN | "float_asinh" => ufe .ASINH
  | "float_atan" => ufe .ATAN | "float_atanh" => ufe .ATANH | "float_cos" => ufe .COS | "float_cosh" => ufe .COSH
  | "float_sin" => ufe .SIN | "float_sinh" => ufe .SINH | "float_tan" => ufe .TAN | "float_tanh" => ufe .TANH
  | "float_div" => bin .DIV | "float_eq" => bin .EQ | "float_eq_reif" => bfr .EQ | "float_le" => bin .LEQ
  | "float_le_reif" => bfr .LEQ | "float_ne" => bin .NEQ | "float_ne_reif" => bfr .NEQ | "float_lt" => bin .LT
  | "float_lt_reif" => bfr .LT
  | "float_in" => makeFloatIn sv
  | "float_in_reif" => return mkBinary (← makeFloatIn sv) .EQUIV (← fv sv 4)
  | "float_log10" => makeLogEq 10 sv | "float_log2" => makeLogEq 2 sv
  | "float_min" => bfe .MIN | "float_max" => bfe .MAX | "float_exp" => ufe .EXP | "float_ln" => ufe .LN
  | "float_pow" => bfe .POW | "float_sqrt" => ufe .SQRT
  | "int2float" => bin .EQ
  | "array_int_element" | "array_var_int_element" | "array_bool_element" | "array_var_bool_element"
  | "array_set_element" | "array_var_set_element" | "array_float_element" | "array_var_float_element" =>
    makeElement name sv
  | "int_lin_eq" | "bool_lin_eq" | "float_lin_eq" | "int_lin_eq_reif" | "bool_lin_eq_reif" | "float_lin_eq_reif" =>
    makeLinear name .EQ sv
  | "int_lin_le" | "bool_lin_le" | "float_lin_le" | "int_lin_le_reif" | "bool_lin_le_reif" | "float_lin_le_reif" =>
    makeLinear name .LEQ sv
  | "int_lin_ne" | "bool_lin_ne" | "float_lin_ne" | "int_lin_ne_reif" | "bool_lin_ne_reif" | "float_lin_ne_reif" =>
    makeLinear name .NEQ sv
  | "array_bool_and" => makeBooleanConstraint name .AND sv
  | "array_bool_or" => makeBooleanConstraint name .OR sv
  | "array_bool_xor" => makeBooleanConstraint name .XOR sv
  | "bool_clause" | "bool_clause_reif" => makeBooleanClause name sv
  | _ => err s!"Unknown predicate `{name}`"
end

/-- `Annotation <- Identifier ('(' Parameter (',' Parameter)* ')')?`. -/
def annotation : P Ann := do
  let name ← ident
  if ← matchLit "(" then
    let ps ← parameters
    expect ")"
    return { name, params := ps }
  return { name, params := #[] }

/-- `Annotations <- ('::' Annotation)*`. -/
def annotations : P (Array Ann) := do
  let mut xs : Array Ann := #[]
  while ← matchLit "::" do xs := xs.push (← annotation)
  return xs

def warnOnce (name : String) : P Unit :=
  modify fun st =>
    if st.ignored.contains name then st
    else { st with ignored := st.ignored.insert name, warnings := st.warnings.push s!"% WARNING: Annotation {name} is unknown and was ignored." }

/-- `update_with_annotations`; `arrayName` is the name of the enclosing array declaration, if any. -/
def updateWithAnnotations (arrayName : Option String) (formula : F) (annots : Array Ann) : P F := do
  let mut fm := formula
  for a in annots do
    match a.name with
    | "abstract" =>
      match a.params[0]? with
      | some (Val.f (z _ n)) => fm := fm.setTy n
      | _ => err "bad_any_cast"
    | "is_defined_var" | "defines_var" | "var_is_introduced" => pure ()
    | "output_var" =>
      match fm with
      | e _ name _ => modify fun st => { st with out := { st.out with vars := st.out.vars.push name } }
      | _ => warnOnce a.name
    | "output_array" =>
      match fm, arrayName with
      | e _ name _, some an =>
        let dims := match a.params[0]? with | some (Val.arr xs) => xs | _ => #[]
        modify fun st =>
          match st.arrayIdx[an]? with
          | some k =>
            let (n0, d0, els) := st.out.arrays[k]!
            { st with out := { st.out with arrays := st.out.arrays.set! k (n0, d0, els.push name) } }
          | none =>
            { st with arrayIdx := st.arrayIdx.insert an st.out.arrays.size,
                      out := { st.out with arrays := st.out.arrays.push (an, dims, #[name]) } }
      | _, _ => warnOnce a.name
    | other => warnOnce other
  return fm

def makeExistential (arrayName : Option String) (so : Srt) (name : String) (annots : Array Ann) : P F :=
  updateWithAnnotations arrayName (e untyped name so) annots

def makeVariableDecl (arrayName : Option String) (name : String) (typeVar : Val) (annots : Array Ann) : P F := do
  match typeVar with
  | .srt so => makeExistential arrayName so name annots
  | .f typeValue =>
    let inConstraint := mkBinary (mkLvar name) .IN typeValue
    match typeValue.srt? with
    | some (.set sub) =>
      let ex ← makeExistential arrayName sub name annots
      return mkBinary ex .AND inConstraint
    | _ => err "We only allow type-value of variables to be of type Set."
  | _ => err "bad_any_cast"

/-- `IndexSet <- '1' '..' Integer`. -/
def indexSet : P Int := do
  expect "1"
  expect ".."
  match ← integerOpt with
  | some n => pure n
  | none => err "bad index set"

def variableDecl : P F := do
  expect "var"
  let ty ← valueType
  expect ":"
  let name ← ident
  let annots ← annotations
  let decl ← makeVariableDecl none name ty annots
  if ← matchLit "=" then
    let value ← literal
    expect ";"
    return mkBinary decl .AND (mkBinary (mkLvar name) .EQ value)
  expect ";"
  return decl

def varArrayDecl (size : Int) : P F := do
  let ty ← valueType
  expect ":"
  let name ← ident
  let annots ← annotations
  modify fun st => { st with arrays := st.arrays.insert name size.toNat }
  let mut decl : Array F := #[]
  for i in [0:size.toNat] do
    decl := decl.push (← makeVariableDecl (some name) (arrayAccessName name i) ty annots)
  if ← matchLit "=" then
    let xs ← literalArray
    for i in [0:xs.size] do
      decl := decl.push (mkBinary (mkLvar (arrayAccessName name i)) .EQ xs[i]!)
  expect ";"
  return mkNary .AND decl

/-- `ParameterDecl <- ParameterType ':' Identifier '=' ParameterExpr ';'`, after the type. -/
def parameterDecl : P F := do
  expect ":"
  let name ← ident
  expect "="
  match ← peek with
  | some 91 =>
    let xs ← literalArray
    modify fun st =>
      let ps := (List.range xs.size).foldl (fun m i => m.insert (arrayAccessName name i) xs[i]!) st.params
      { st with arrays := st.arrays.insert name xs.size, params := ps }
  | _ =>
    let x ← rangeLiteral
    if (← get).params.contains name then err s!"Parameter `{name}` already declared."
    modify fun st => { st with params := st.params.insert name x }
  expect ";"
  return mkTrue

def predicateDecl : P F := do
  expect "predicate"
  let inp ← read
  let mut j := (← get).pos
  while j < inp.size && inp[j]! != 41 do j := j + 1
  modify fun st => { st with pos := j + 1 }
  skipWs
  expect ";"
  return mkTrue

def constraintDecl : P F := do
  expect "constraint"
  let save := (← get).pos
  let formula ← do
    match ← identOpt with
    | some name =>
      if ← matchLit "(" then
        let args ← parameters
        expect ")"
        predicateCall (#[Val.str name] ++ args)
      else
        modify fun st => { st with pos := save }
        if ← matchLit "true" then pure mkTrue
        else if ← matchLit "false" then pure mkFalse
        else err "expected a predicate call"
    | none => err "expected a predicate call"
  let annots ← annotations
  expect ";"
  updateWithAnnotations none formula annots

/-- `SearchAnnotation <- SeqSearch / BaseSearch`. -/
partial def searchAnnotation : P F := do
  if ← matchLit "seq_search" then
    expect "("; expect "["
    let mut subs : Array F := #[]
    repeat
      subs := subs.push (← searchAnnotation)
      if ← matchLit "," then continue else break
    expect "]"; expect ")"
    let mut seqv : Array F := #[]
    for sub in subs do
      match sub with
      | seq _ .AND cs => seqv := seqv ++ cs
      | _ => seqv := seqv.push sub
    return mkNary .AND seqv
  else
    unless (← matchLit "int_search") || (← matchLit "bool_search") || (← matchLit "set_search") do
      err "expected a search annotation"
    expect "("
    let first ← do
      match ← peek with
      | some 91 => pure (Val.arr (← literalArray))
      | _ => pure (Val.f (mkLvar (← ident)))
    expect ","
    let a ← ident
    expect ","
    let b ← ident
    expect ","
    let _ ← ident
    expect ")"
    let array ← resolveArray #[first] 0
    let mut seqv : Array F := #[eseq untyped a #[], eseq untyped b #[]]
    for x in array do
      if x.isVariable then seqv := seqv.push x
    return eseq untyped "search" seqv

def solveItem : P F := do
  expect "solve"
  let mut subs : Array F := #[]
  while ← matchLit "::" do subs := subs.push (← searchAnnotation)
  let sa :=
    if subs.size == 1 then subs[0]!
    else mkNary .AND (subs.foldl (init := #[]) fun acc sub =>
      match sub with
      | seq _ .AND cs => acc ++ cs
      | _ => acc.push sub)
  let item ← do
    if ← matchLit "minimize" then pure (mkUnary .MINIMIZE (← rangeLiteral))
    else if ← matchLit "maximize" then pure (mkUnary .MAXIMIZE (← rangeLiteral))
    else if ← matchLit "satisfy" then pure mkTrue
    else err "expected minimize, maximize or satisfy"
  expect ";"
  if item.isTrue then return sa else return mkBinary sa .AND item

/-- One `Statement`. -/
def statement : P F := do
  if ← peekLit "predicate" then predicateDecl
  else if ← peekLit "var" then variableDecl
  else if ← peekLit "array" then
    expect "array"; expect "["
    let n ← indexSet
    expect "]"; expect "of"
    if ← matchLit "var" then varArrayDecl n
    else
      let _ ← typeOpt
      parameterDecl
  else if ← peekLit "constraint" then constraintDecl
  else if ← peekLit "solve" then solveItem
  else
    let some _ ← typeOpt | err "unexpected statement"
    parameterDecl

/-- `Statements` and `make_statements`. -/
def statements : P F := do
  skipWs
  let inp ← read
  let mut children : Array F := #[]
  let mut count := 0
  let mut single : F := mkTrue
  while (← get).pos < inp.size do
    let x ← statement
    count := count + 1
    single := x
    if !x.isTrue then children := children.push x
  if count == 1 then return single
  return mkNary .AND children

end Fzn

/-- The parsed formula before `eval` (`parsed`: the statistics of `parse_cn` are taken on it), the formula after `eval`
    (`formula`, what `parse_cn` returns) and the recorded outputs. -/
structure Parsed where
  parsed : F
  formula : F
  out : Output
  warnings : Array String

def parseFlatzinc (input : ByteArray) : Except String Parsed :=
  match (Fzn.statements.run input |>.run {}) with
  | .ok (f, st) => .ok { parsed := f, formula := F.eval f, out := st.out, warnings := st.warnings }
  | .error msg => .error msg

end Frontend
