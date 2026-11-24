-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Std.Data.HashMap
import Frontend.Formula
/-! `ternarize` (lala-core `logic/ternarize.hpp`) and `normalize` (`logic/algorithm.hpp`): the first steps of `preprocess_tcn`.
    The order in which variables and constants are introduced follows the C++ source, because the numbering of the solver's variables follows it. -/
namespace Frontend
open F

def isLogical : Sig → Bool
  | .AND | .OR | .IMPLY | .EQUIV | .NOT | .XOR => true
  | _ => false
def isPredicate : Sig → Bool
  | .IN | .SUBSET | .SUBSETEQ | .SUPSET | .SUPSETEQ | .EQ | .NEQ | .LEQ | .GEQ | .LT | .GT => true
  | _ => false
def isTernaryOp (s : Sig) : Bool := s == .MAX || s == .MIN || s == .EQ || s == .LEQ || (!isLogical s && !isPredicate s)

def isConstantVar : F → Bool
  | lv _ n => n.startsWith "__CONSTANT_"
  | _ => false

/-- `value_of_constant`: `__CONSTANT_m5` is `-5`. -/
def valueOfConstant : F → Int
  | lv _ n =>
    let s := n.drop 11
    if s.startsWith "m" then -(Int.ofNat ((s.drop 1).toNat!)) else Int.ofNat s.toNat!
  | _ => 0

/-- `num_vars`: the occurrences of variables, existentials included. -/
partial def numVars : F → Nat
  | v .. | e .. | lv .. => 1
  | seq _ _ cs | eseq _ _ cs => cs.foldl (fun n c => n + numVars c) 0
  | _ => 0

/-- `is_extended_ternary_form`. -/
def isExtendedTernaryForm (f : F) : Bool :=
  let n := numVars f
  let unaryCase :=
    n == 1 && (f.isE || (match f with
      | seq _ sg #[x, y] => sg != .NEQ && sg != .IN && (x.isVariable || y.isVariable) && (x.isConstant || y.isConstant)
      | _ => false))
  let ternaryCase :=
    n == 3 && (match f with
      | seq _ .EQ #[x, y] =>
        (x.isVariable && (match y with
          | seq _ sg #[p, q] => isTernaryOp sg && p.isVariable && q.isVariable
          | _ => false))
        || (y.isVariable && (match x with
          | seq _ sg #[p, q] => isTernaryOp sg && p.isVariable && q.isVariable
          | _ => false))
      | _ => false)
  unaryCase || ternaryCase

/-- `is_tnf`: `x = (y op z)` with three variables. -/
def isTnf : F → Bool
  | seq _ sg #[x, seq _ _ #[p, q]] => x.isVariable && (sg == .EQ || sg == .EQUIV) && p.isVariable && q.isVariable
  | _ => false

/-- `num_tnf_constraints`. -/
partial def numTnfConstraints (f : F) : Nat :=
  if isTnf f then 1
  else match f with
    | seq _ .AND cs => cs.foldl (fun n c => n + numTnfConstraints c) 0
    | _ => 0

/-- `converse_comparison`. -/
def converseComparison : Sig → Sig
  | .LEQ => .GEQ | .GEQ => .LEQ | .GT => .LT | .LT => .GT
  | .SUBSET => .SUPSET | .SUBSETEQ => .SUPSETEQ | .SUPSET => .SUBSET | .SUPSETEQ => .SUBSETEQ
  | other => other

def isComparison : F → Bool
  | seq _ sg _ => match sg with
    | .LEQ | .GEQ | .LT | .GT | .EQ | .NEQ | .SUBSET | .SUBSETEQ | .SUPSET | .SUPSETEQ => true
    | _ => false
  | _ => false

/-- `impl::itv_to_formula`. -/
def itvToFormula (f : F) (itv : F × F) : F :=
  let (l, u) := itv
  if F.beq l u then mkBinary f .EQ l f.ty
  else
    let (geq, leq) := match l with
      | s .. => (Sig.SUPSETEQ, Sig.SUBSETEQ)
      | _ => (Sig.GEQ, Sig.LEQ)
    mkBinary (mkBinary f geq l f.ty) .AND (mkBinary f leq u f.ty) f.ty

/-- `decompose_in_constraint`. -/
def decomposeIn (f : F) : F :=
  match f with
  | seq _ .IN #[x, s _ set] =>
    if set.size == 1 then itvToFormula x set[0]!
    else mkNary .OR (set.map (itvToFormula x)) f.ty
  | _ => f

structure TState where
  conj : Array F := #[]
  exs : Array F := #[]
  idx : Std.HashMap String Nat := {}
  ints : Nat := 0
  bools : Nat := 0
  consts : Nat := 0

abbrev T := StateM TState

def introduceExistingVar (name : String) : T Unit := do
  if name.startsWith "__VAR_Z_" then
    match (name.drop 8).toNat? with
    | some k => modify fun s => { s with ints := max (k + 1) s.ints }
    | none => pure ()
  else if name.startsWith "__VAR_B_" then
    match (name.drop 8).toNat? with
    | some k => modify fun s => { s with bools := max (k + 1) s.bools }
    | none => pure ()

def introduceVar (name : String) (sort : Srt) (constant : Bool) : T F := do
  modify fun s =>
    let n := s.exs.size
    let s := { s with idx := s.idx.insert name n }
    let s := { s with exs := s.exs.push (e untyped name sort) }
    if constant then { s with consts := s.consts + 1 }
    else match sort with
      | .int => { s with ints := s.ints + 1 }
      | .bool => { s with bools := s.bools + 1 }
      | _ => s
  return mkLvar name

def introduceIntVar : T F := do
  let s ← get
  introduceVar s!"__VAR_Z_{s.ints}" .int false

def introduceBoolVar : T F := do
  let s ← get
  introduceVar s!"__VAR_B_{s.bools}" .bool false

def pushConj (f : F) : T Unit := modify fun s => { s with conj := s.conj.push f }

def ternarizeConstant (f : F) : T F := do
  let index := f.toZ
  let name := "__CONSTANT_" ++ (if index < 0 then "m" else "") ++ toString index.natAbs
  if (← get).idx.contains name then return mkLvar name
  let sort := (f.srt?).getD .int
  let var ← introduceVar name sort true
  pushConj (mkBinary var .EQ f)
  return var

def simplifyToUnary (x y : F) (sg : Sig) (z : F) : T Bool := do
  if isConstantVar x && (isConstantVar y || isConstantVar z) && (sg == .LEQ || (sg == .EQ && valueOfConstant x == 1)) then
    let yv := if isConstantVar y then mkZ (valueOfConstant y) else y
    let zv := if isConstantVar z then mkZ (valueOfConstant z) else z
    if valueOfConstant x == 0 then pushConj (mkBinary yv .GT zv) else pushConj (mkBinary yv sg zv)
    return true
  return false

def pushTernary (x y : F) (sg : Sig) (z : F) : T F := do
  if ← simplifyToUnary x y sg z then return x
  if sg == .SUB then
    pushConj (mkBinary y .EQ (mkBinary x .ADD z))
    return x
  pushConj (mkBinary x .EQ (mkBinary y sg z))
  return x

def isBoolean (t : F) : T Bool := do
  match t with
  | lv _ n =>
    let s ← get
    match s.idx[n]? with
    | some i => return (match s.exs[i]! with | e _ _ so => so == .bool | _ => false)
    | none => return false
  | _ => return false

/-- Child accessor that tolerates a malformed formula (the C++ would be undefined there). -/
def kid (f : F) (i : Nat) : F := f.seqChildren[i]!

mutual
partial def booleanize (t : F) (sg : Sig) : T F := do
  if isLogical sg && !(← isBoolean t) then
    ternarize (mkBinary t .NEQ (mkZ 0))
  else return t

partial def ternarizeUnary (f : F) (toplevel : Bool) : T F := do
  let x ← ternarize (kid f 0)
  match f.sigOf?.getD .AND with
  | .NEG =>
    let tv ← introduceIntVar
    let zero ← ternarize (mkZ 0)
    let t ← pushTernary tv zero .SUB x
    if toplevel then ternarizeWith (mkBinary t .NEQ (mkZ 0)) true else return t
  | .ABS =>
    let t1 ← ternarize (mkUnary .NEG x)
    let t2 ← introduceIntVar
    compute (mkBinary t2 .EQ (mkBinary x .MAX t1))
    compute (mkBinary t2 .GEQ (mkZ 0))
    if toplevel then ternarizeWith (mkBinary t2 .NEQ (mkZ 0)) true else return t2
  | .NOT => ternarizeWith (mkBinary x .EQ (mkZ 0)) toplevel
  | sg =>
    if sg == .MINIMIZE || sg == .MAXIMIZE then
      pushConj (mkUnary sg x)
      return x
    else
      panic! s!"Unary operator {repr sg} not supported during ternarization"

partial def ternarizeBinary (f0 : F) (toplevel0 : Bool) : T F := do
  let sg0 := f0.sigOf?.getD .AND
  let a0 := kid f0 0
  let b0 := kid f0 1
  let isInSet := (match b0 with | s .. => true | _ => false)
  if sg0 == .IN && a0.isVariable && isInSet then
    if toplevel0 then
      compute (decomposeIn f0)
      match b0 with
      | s _ set => if set.size > 1 then pushConj f0
      | _ => pure ()
      return mkTrue
    else
      return ← ternarizeWith (decomposeIn f0) toplevel0
  let mut f := f0
  let mut toplevel := toplevel0
  let mut almost := false
  let mut t0 : F := mkTrue
  let almostCond :=
    (((a0.isVariable || a0.isConstant) && b0.isBinary) || ((b0.isVariable || b0.isConstant) && a0.isBinary))
      && (sg0 == .EQUIV || sg0 == .EQ)
  let mut early : Option F := none
  if almostCond then
    let left := if a0.isBinary then 1 else 0
    let right := if b0.isBinary then 1 else 0
    if (kid f0 right).sigOf? == some .IN then
      early := some (← ternarizeWith (mkBinary (kid f0 left) .EQ (decomposeIn (kid f0 right))) toplevel0)
    else
      t0 ← ternarize (kid f0 left)
      f := kid f0 right
      toplevel := false
      almost := true
  if let some res := early then return res
  let sg := f.sigOf?.getD .AND
  let mut t1 ← ternarize (kid f 0)
  t1 ← booleanize t1 sg
  let mut t2 ← ternarize (kid f 1)
  t2 ← booleanize t2 sg
  if !almost then
    if toplevel && (sg == .NEQ || sg == .XOR || sg == .IMPLY || sg == .GT || sg == .LT) then pure ()
    else
      let logical ← do
        if isLogical sg || isPredicate sg then pure true
        else if sg == .MIN || sg == .MAX then
          let b1 ← isBoolean t1
          if b1 then isBoolean t2 else pure false
        else pure false
      if logical then
        t0 ← (if toplevel then ternarizeConstant (mkZ 1) else introduceBoolVar)
      else
        t0 ← (if toplevel then ternarizeConstant (mkZ 1) else introduceIntVar)
  match sg with
  | .AND | .MIN => pushTernary t0 t1 .MIN t2
  | .OR | .MAX => pushTernary t0 t1 .MAX t2
  | .EQ | .EQUIV => pushTernary t0 t1 .EQ t2
  | .NEQ | .XOR =>
    if toplevel then
      let c0 ← ternarizeConstant (mkZ 0)
      pushTernary c0 t1 .EQ t2
    else
      let n ← ternarizeWith (mkUnary .NOT t0) false
      let _ ← pushTernary n t1 .EQ t2
      return t0
  | .IMPLY => ternarizeWith (mkBinary (mkUnary .NOT t1) .OR t2) toplevel
  | .LEQ => pushTernary t0 t1 .LEQ t2
  | .GEQ => pushTernary t0 t2 .LEQ t1
  | .GT =>
    if toplevel then
      let c0 ← ternarizeConstant (mkZ 0)
      pushTernary c0 t1 .LEQ t2
    else
      let n ← ternarizeWith (mkUnary .NOT t0) false
      let _ ← pushTernary n t1 .LEQ t2
      return t0
  | .LT =>
    if toplevel then
      let c0 ← ternarizeConstant (mkZ 0)
      pushTernary c0 t2 .LEQ t1
    else
      let n ← ternarizeWith (mkUnary .NOT t0) false
      let _ ← pushTernary n t2 .LEQ t1
      return t0
  | _ => pushTernary t0 t1 sg t2

partial def ternarizeNary (f : F) (toplevel : Bool) : T F := do
  let sg := f.sigOf?.getD .AND
  let cs := f.seqChildren
  if isAssociative sg then
    let half := cs.size / 2
    let left := cs.extract 0 half
    let right := cs.extract half cs.size
    let t1 ← ternarize (if left.size == 1 then left.back! else mkNary sg left)
    let t2 ← ternarize (if right.size == 1 then right.back! else mkNary sg right)
    ternarizeWith (mkBinary t1 sg t2) toplevel
  else
    let mut tmp ← ternarize (mkBinary cs[0]! sg cs[1]!)
    for i in [2:cs.size - 1] do
      tmp ← ternarize (mkBinary tmp sg cs[i]!)
    ternarizeWith (mkBinary tmp sg cs.back!) toplevel

partial def ternarizeWith (f : F) (toplevel : Bool) : T F := do
  if f.isVariable then
    if toplevel then ternarizeWith (mkBinary f .NEQ (mkZ 0)) true else return f
  else match f with
    | z .. | b .. =>
      if toplevel then return (if f.toZ != 0 then mkTrue else mkFalse)
      else ternarizeConstant f
    | s .. => return f
    | seq _ _ cs =>
      if cs.size == 1 then ternarizeUnary f toplevel
      else if cs.size == 2 then ternarizeBinary f toplevel
      else if cs.size > 2 then ternarizeNary f toplevel
      else panic! "unsupported formula during ternarization"
    | _ => panic! "unsupported formula during ternarization"

partial def ternarize (f : F) : T F := ternarizeWith f false

partial def compute (f : F) : T Unit := do
  match f with
  | seq _ .AND cs => for c in cs do compute c
  | e _ name _ =>
    modify fun s =>
      let n := s.exs.size
      let s := { s with idx := s.idx.insert name n }
      { s with exs := s.exs.push f }
    introduceExistingVar name
  | _ =>
    let isE : Bool := (match f with | eseq .. => true | _ => false)
    if !isE && !isExtendedTernaryForm f then
      let _ ← ternarizeWith f true
    else pushConj f
end

/-- `ternarize(f, VarEnv(), constants)`: the conjunction of the existentials and the constraints in extended ternary form. -/
def ternarizeFormula (f : F) (constants : Array Int) : F :=
  let act : T F := do
    for c in constants do let _ ← ternarizeConstant (mkZ c)
    compute f
    let s ← get
    let all := s.exs ++ s.conj
    if all.size == 1 then return all[0]! else return mkNary .AND all untyped false
  (act.run {}).1

/-- `normalize(f, extra)`. -/
partial def normalizeWith (f : F) (extra : Array F) : F × Array F :=
  match f with
  | eseq .. => (f, extra.push f)
  | seq t sg cs =>
    let extra := if sg == .MINIMIZE || sg == .MAXIMIZE then extra.push f else extra
    if sg == .NOT && cs.size == 1 then
      let c := cs[0]!
      if c.isVariable then (mkBinary c .EQ (mkZ 0) t, extra)
      else
        let fi := (normalizeWith c #[]).1
        match F.negate fi with
        | some nf => if !F.beq nf f then ((normalizeWith nf #[]).1, extra) else (mkUnary .NOT fi t, extra)
        | none => (mkUnary .NOT fi t, extra)
    else if cs.size == 2 && isComparison f && cs[0]!.isConstant then
      (mkBinary (normalizeWith cs[1]! #[]).1 (converseComparison sg) cs[0]! t, extra)
    else if cs.size == 2 && isComparison f && !cs[0]!.isVariable && cs[1]!.isVariable then
      (mkBinary cs[1]! (converseComparison sg) (normalizeWith cs[0]! #[]).1 t, extra)
    else if cs.size == 2 && sg == .IN && (match cs[1]! with | s _ set => set.size == 1 && F.beq set[0]!.1 set[0]!.2 | _ => false) then
      (match cs[1]! with
        | s _ set => (mkBinary cs[0]! .EQ set[0]!.1 t, extra)
        | _ => (f, extra))
    else
      let (out, extra) := cs.foldl (init := (Array.mkEmpty cs.size, extra)) fun (acc, ex) c =>
        if sg == .AND then
          let (n, ex') := normalizeWith c ex
          (acc.push n, ex')
        else (acc.push (normalizeWith c #[]).1, ex)
      (mkNary sg out t true, extra)
  | _ => (f, extra)


def sigName (sg : Sig) : String := ((reprStr sg).splitOn ".").getLast!

def srtName : Srt → String
  | .bool => "B" | .int => "Z" | .real => "R" | .set _ => "S"

/-- Canonical text of a formula, equal to the oracle's printer in `slang/turbo/oracle/cp_dump.cpp`. -/
partial def toText : F → String
  | z _ n => toString n
  | b _ x => if x then "true" else "false"
  | r .. => "R"
  | s _ set => "{" ++ ",".intercalate (set.toList.map fun (lo, hi) => toText lo ++ ".." ++ toText hi) ++ "}"
  | v _ i => s!"#{i}"
  | lv _ n => n
  | e _ n so => s!"(E {n} {srtName so})"
  | seq _ sg cs => "(" ++ " ".intercalate (sigName sg :: cs.toList.map toText) ++ ")"
  | eseq _ es cs => "(ESEQ " ++ " ".intercalate (es :: cs.toList.map toText) ++ ")"

/-- One line per conjunct of the top-level conjunction. -/
def toLines (f : F) : Array String :=
  match f with
  | seq _ .AND cs => cs.map toText
  | _ => #[toText f]

end Frontend
