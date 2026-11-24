-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
/-! The logic formula of lala-core (`logic/ast.hpp`, `logic/algorithm.hpp`): the AST, the smart constructors and `eval`.
    Every construct follows the C++ source; `ty` is the abstract type tag (`-1` is UNTYPED). -/
namespace Frontend

inductive Sig where
  | NEG | ABS | ADD | SUB | MUL | POW | MIN | MAX | SQRT | EXP | LN | NROOT | LOG
  | SIN | COS | TAN | ASIN | ACOS | ATAN | SINH | COSH | TANH | ASINH | ACOSH | ATANH
  | DIV | MOD | TDIV | TMOD | FDIV | FMOD | CDIV | CMOD | EDIV | EMOD
  | UNION | INTERSECTION | DIFFERENCE | SYMMETRIC_DIFFERENCE | COMPLEMENT
  | SUBSET | SUBSETEQ | SUPSET | SUPSETEQ | IN | CARD | HULL | CONVEX
  | EQ | NEQ | LEQ | GEQ | LT | GT
  | AND | OR | IMPLY | EQUIV | NOT | XOR | ITE | MAXIMIZE | MINIMIZE
  deriving BEq, DecidableEq, Repr, Inhabited

inductive Srt where
  | bool | int | real | set (sub : Srt)
  deriving BEq, Repr, Inhabited

def untyped : Int := -1

/-- `TFormula`: the constructors are the variants of the C++ `std::variant` (B, Z, R, S, V, LV, E, Seq, ESeq). -/
inductive F where
  | b (ty : Int) (v : Bool)
  | z (ty : Int) (v : Int)
  | r (ty : Int) (lo hi : Float)
  | s (ty : Int) (set : Array (F × F))
  | v (ty : Int) (vid : Nat)
  | lv (ty : Int) (name : String)
  | e (ty : Int) (name : String) (sort : Srt)
  | seq (ty : Int) (sig : Sig) (children : Array F)
  | eseq (ty : Int) (esig : String) (children : Array F)
  deriving Inhabited

namespace F

def ty : F → Int
  | b t _ | z t _ | r t _ _ | s t _ | v t _ | lv t _ | e t _ _ | seq t _ _ | eseq t _ _ => t

def mkTrue : F := b untyped true
def mkFalse : F := b untyped false
def mkZ (n : Int) : F := z untyped n
def mkLvar (name : String) : F := lv untyped name
def mkSet (set : Array (F × F)) : F := s untyped set

def setTy (n : Int) : F → F
  | b _ x => b n x | z _ x => z n x | r _ l h => r n l h | s _ x => s n x | v _ i => v n i
  | lv _ x => lv n x | e _ x so => e n x so | seq _ sg cs => seq n sg cs | eseq _ sg cs => eseq n sg cs

def isAssociative : Sig → Bool
  | .ADD | .MUL | .AND | .OR | .EQUIV | .XOR | .UNION | .INTERSECTION | .MAX | .MIN => true
  | _ => false

/-- `make_nary(sig, children, atype, flatten)`: associative operators absorb same-sig same-type children. -/
def mkNary (sig : Sig) (children : Array F) (atype : Int := untyped) (flatten : Bool := true) : F :=
  if isAssociative sig && flatten then
    let out := children.foldl (init := (Array.mkEmpty children.size : Array F)) fun acc c =>
      match c with
      | seq t sg cs => if sg == sig && t == atype then acc ++ cs else acc.push c
      | _ => acc.push c
    seq atype sig out
  else seq atype sig children

def mkUnary (sig : Sig) (c : F) (atype : Int := untyped) : F := mkNary sig #[c] atype
def mkBinary (l : F) (sig : Sig) (r : F) (atype : Int := untyped) (flatten : Bool := true) : F :=
  mkNary sig #[l, r] atype flatten

def isTrue : F → Bool
  | b _ x => x
  | z _ n => n != 0
  | _ => false
def isFalse : F → Bool
  | b _ x => !x
  | z _ n => n == 0
  | _ => false
def isBZ : F → Bool
  | b .. | z .. => true
  | _ => false
def toZ : F → Int
  | b _ x => if x then 1 else 0
  | z _ n => n
  | _ => 0
def isConstant : F → Bool
  | b .. | z .. | r .. | s .. => true
  | _ => false
def isVariable : F → Bool
  | lv .. | v .. => true
  | _ => false
def isUnary : F → Bool
  | seq _ _ cs => cs.size == 1
  | _ => false
def isBinary : F → Bool
  | seq _ _ cs => cs.size == 2
  | _ => false
def isE : F → Bool
  | e .. => true
  | _ => false
def isSeq : F → Bool
  | seq .. => true
  | _ => false
def sigOf? : F → Option Sig
  | seq _ sg _ => some sg
  | _ => none
def seqChildren : F → Array F
  | seq _ _ cs => cs
  | eseq _ _ cs => cs
  | _ => #[]

partial def beq : F → F → Bool
  | b t x, b u y => t == u && x == y
  | z t x, z u y => t == u && x == y
  | r t a c, r u x y => t == u && a == x && c == y
  | s t xs, s u ys => t == u && xs.size == ys.size && (xs.zip ys).all fun ((a, c), (x, y)) => beq a x && beq c y
  | v t x, v u y => t == u && x == y
  | lv t x, lv u y => t == u && x == y
  | e t x sx, e u y sy => t == u && x == y && sx == sy
  | seq t sg xs, seq u sg' ys => t == u && sg == sg' && xs.size == ys.size && (xs.zip ys).all fun (a, c) => beq a c
  | eseq t sg xs, eseq u sg' ys => t == u && sg == sg' && xs.size == ys.size && (xs.zip ys).all fun (a, c) => beq a c
  | _, _ => false

/-- `TFormula::sort()`. -/
partial def srt? : F → Option Srt
  | b .. => some .bool
  | z .. => some .int
  | r .. => some .real
  | s _ set =>
    set.findSome? fun (lo, hi) => (lo.srt?.orElse fun _ => hi.srt?).map Srt.set
  | e _ _ so => some so
  | _ => none

/-- `num_quantified_vars`: the existential quantifiers anywhere in the formula. -/
partial def numQuantifiedVars : F → Nat
  | e .. => 1
  | seq _ _ cs | eseq _ _ cs => cs.foldl (fun n c => n + numQuantifiedVars c) 0
  | _ => 0

/-- `find_maximize_var`: the name of the variable that `maximize` names, anywhere in a conjunction. -/
partial def maximizeVar? : F → Option String
  | seq _ .MAXIMIZE cs => match cs[0]? with | some (lv _ name) => some name | _ => none
  | seq _ .AND cs => cs.findSome? maximizeVar?
  | _ => none

/-- `find_existential_of`: the type and sort of the existential quantifier of a variable. -/
partial def existentialOf? (name : String) : F → Option (Int × Srt)
  | e t n sort => if n == name then some (t, sort) else none
  | seq _ _ cs | eseq _ _ cs => cs.findSome? (existentialOf? name)
  | _ => none

/-- `add_minimize_objective_var`: `maximize(x)` becomes `maximize(x) /\ exists(__MINIMIZE_OBJ) /\ __MINIMIZE_OBJ = -x` in place, so that the search can only minimize. -/
partial def addMinimizeObjective (sort : Srt) : F → F
  | f@(seq _ .MAXIMIZE cs) =>
    match cs[0]? with
    | some x@(lv xt _) | some x@(v xt _) =>
      mkBinary f .AND (mkBinary (e xt "__MINIMIZE_OBJ" sort) .AND (mkBinary (lv xt "__MINIMIZE_OBJ") .EQ (mkUnary .NEG x)))
    | _ => f
  | seq t .AND cs => seq t .AND (cs.map (addMinimizeObjective sort))
  | f => f

/-- Turbo's `preprocess` on the barebones architecture, before ternarizing. A problem without `maximize` is returned as it is. -/
def withMinimizeObjective (f : F) : F :=
  match maximizeVar? f with
  | some name => match existentialOf? name f with
    | some (_, sort) => addMinimizeObjective sort f
    | none => f
  | none => f

/-- `num_constraints`: an existential is not a constraint, a conjunction is the sum of its conjuncts. -/
partial def numConstraints : F → Nat
  | e .. => 0
  | seq _ .AND cs => cs.foldl (fun n c => n + numConstraints c) 0
  | _ => 1

/-- `negate`: `none` when the formula cannot be negated syntactically. -/
partial def negate (f : F) : Option F :=
  if f.isTrue then some mkFalse
  else if f.isFalse then some mkTrue
  else if f.isVariable then some (mkUnary .NOT f f.ty)
  else match f with
    | seq t sig cs =>
      match sig with
      | .NOT => cs[0]?
      | .EQ =>
        match cs[0]?, cs[1]? with
        | some (b u x), some c => some (mkBinary (b u !x) .EQ c t)
        | some a, some (b u x) => some (mkBinary a .EQ (b u !x) t)
        | _, _ => some (mkNary .NEQ cs t)
      | .LEQ => some (mkNary .GT cs t)
      | .GEQ => some (mkNary .LT cs t)
      | .NEQ => some (mkNary .EQ cs t)
      | .LT => some (mkNary .GEQ cs t)
      | .GT => some (mkNary .LEQ cs t)
      | .SUBSET | .SUBSETEQ | .SUPSET | .SUPSETEQ | .IN => some (mkUnary .NOT f t)
      | .AND => deMorgan .OR cs t
      | .OR => deMorgan .AND cs t
      | _ => none
    | _ => none
where
  deMorgan (sigNeg : Sig) (cs : Array F) (t : Int) : Option F :=
    (cs.mapM negate).map fun ns => mkNary sigNeg ns t

def cdiv (a b : Int) : Int := -((-a).fdiv b)

def ipow (a : Int) (n : Int) : Int := if n < 0 then 0 else a ^ n.toNat

/-- `impl::eval_seq`: the constant folding and the small syntactic rewrites over an already evaluated sequence. -/
partial def evalSeq (sig : Sig) (sq : Array F) (atype : Int) : F :=
  let dflt := mkNary sig sq atype
  let two := sq.size == 2
  let bz2 := two && sq[0]!.isBZ && sq[1]!.isBZ
  let z2 := two && (match sq[0]!, sq[1]! with | z .., z .. => true | _, _ => false)
  let zv (i : Nat) : Int := sq[i]!.toZ
  match sig with
  | .AND =>
    if sq.any isFalse then mkFalse
    else
      let residual := sq.filter fun c => !c.isTrue
      if residual.size == 0 then mkTrue
      else if residual.size == 1 then residual[0]!
      else mkNary .AND residual atype
  | .OR =>
    if sq.any isTrue then mkTrue
    else
      let residual := sq.filter fun c => !c.isFalse
      if residual.size == 0 then mkFalse
      else if residual.size == 1 then residual[0]!
      else mkNary .OR residual atype
  | .IMPLY =>
    if bz2 then (if sq[0]!.isFalse || sq[1]!.isTrue then mkTrue else mkFalse)
    else if two then
      if sq[0]!.isTrue then sq[1]!
      else if sq[0]!.isFalse then mkTrue
      else if sq[1]!.isTrue then mkTrue
      else if sq[1]!.isFalse then (match negate sq[0]! with | some rr => rr | none => dflt)
      else dflt
    else dflt
  | .EQUIV =>
    if bz2 then (if sq[0]!.isTrue == sq[1]!.isTrue then mkTrue else mkFalse)
    else if two then
      if sq[0]!.isTrue then sq[1]!
      else if sq[0]!.isFalse then mkUnary .NOT sq[1]! atype
      else if sq[1]!.isTrue then sq[0]!
      else if sq[1]!.isFalse then mkUnary .NOT sq[0]! atype
      else dflt
    else dflt
  | .NOT =>
    if sq.size == 1 && sq[0]!.isBZ then (if sq[0]!.isTrue then mkFalse else mkTrue)
    else if sq.size == 1 && sq[0]!.isUnary && sq[0]!.sigOf? == some .NOT then sq[0]!.seqChildren[0]!
    else dflt
  | .XOR =>
    if bz2 then (if sq[0]!.isTrue != sq[1]!.isTrue then mkTrue else mkFalse) else dflt
  | .ITE =>
    if sq.size == 3 && sq[0]!.isBZ then (if sq[0]!.isTrue then sq[1]! else sq[2]!) else dflt
  | .EQ =>
    if two && sq[0]!.isConstant && sq[1]!.isConstant then (if beq sq[0]! sq[1]! then mkTrue else mkFalse)
    else if two && sq[0]!.isBinary && (match sq[1]! with | z _ 0 => true | _ => false) && sq[0]!.sigOf? == some .ADD
        && sq[0]!.seqChildren[1]!.isUnary && sq[0]!.seqChildren[1]!.sigOf? == some .NEG
        && sq[0]!.seqChildren[1]!.seqChildren[0]!.isVariable && sq[0]!.seqChildren[0]!.isVariable then
      mkBinary sq[0]!.seqChildren[0]! .EQ sq[0]!.seqChildren[1]!.seqChildren[0]! atype
    else dflt
  | .NEQ =>
    if two && sq[0]!.isConstant && sq[1]!.isConstant then (if beq sq[0]! sq[1]! then mkFalse else mkTrue)
    else if two && sq[0]!.isBinary && (match sq[1]! with | z _ 0 => true | _ => false) && sq[0]!.sigOf? == some .ADD
        && sq[0]!.seqChildren[1]!.isUnary && sq[0]!.seqChildren[1]!.sigOf? == some .NEG
        && sq[0]!.seqChildren[1]!.seqChildren[0]!.isVariable && sq[0]!.seqChildren[0]!.isVariable then
      mkBinary sq[0]!.seqChildren[0]! .NEQ sq[0]!.seqChildren[1]!.seqChildren[0]! atype
    else if two && sq[0]!.isBinary && sq[1]!.isBZ && sq[0]!.sigOf? == some .ADD && sq[0]!.seqChildren[1]!.isBZ then
      mkBinary sq[0]!.seqChildren[0]! .NEQ (mkZ (sq[1]!.toZ - sq[0]!.seqChildren[1]!.toZ)) atype
    else if two && sq[0]!.isBZ && sq[1]!.isUnary && sq[1]!.sigOf? == some .NEG && sq[1]!.seqChildren[0]!.isVariable then
      mkBinary (mkZ (-sq[0]!.toZ)) .NEQ sq[1]!.seqChildren[0]! atype
    else if two && sq[1]!.isBZ && sq[0]!.isUnary && sq[0]!.sigOf? == some .NEG && sq[0]!.seqChildren[0]!.isVariable then
      mkBinary sq[0]!.seqChildren[0]! .NEQ (mkZ (-sq[1]!.toZ)) atype
    else dflt
  | .LT => if z2 then (if zv 0 < zv 1 then mkTrue else mkFalse) else dflt
  | .LEQ => if z2 then (if zv 0 ≤ zv 1 then mkTrue else mkFalse) else dflt
  | .GT => if z2 then (if zv 0 > zv 1 then mkTrue else mkFalse) else dflt
  | .GEQ => if z2 then (if zv 0 ≥ zv 1 then mkTrue else mkFalse) else dflt
  | .MIN => if z2 then mkZ (min (zv 0) (zv 1)) else dflt
  | .MAX => if z2 then mkZ (max (zv 0) (zv 1)) else dflt
  | .NEG =>
    if sq.size == 1 && sq[0]!.isBZ then mkZ (-sq[0]!.toZ)
    else if sq.size == 1 && sq[0]!.isUnary && sq[0]!.sigOf? == some .NEG then sq[0]!.seqChildren[0]!
    else dflt
  | .ABS => if sq.size == 1 && sq[0]!.isBZ then mkZ (sq[0]!.toZ.natAbs : Int) else dflt
  | .ADD =>
    let (residual, sum) := sq.foldl (init := ((#[] : Array F), (0 : Int))) fun (res, sm) c =>
      if c.isBZ then (res, sm + c.toZ) else (res.push c, sm)
    if residual.size == 0 then mkZ sum
    else
      let residual := if sum != 0 then residual.push (mkZ sum) else residual
      if residual.size == 1 then residual[0]! else mkNary .ADD residual atype
  | .MUL =>
    let (residual, prod) := sq.foldl (init := ((#[] : Array F), (1 : Int))) fun (res, p) c =>
      if c.isBZ then (res, p * c.toZ) else (res.push c, p)
    if residual.size == 0 then mkZ prod
    else if prod == 0 then mkZ 0
    else
      let residual :=
        if prod == -1 then residual.set! 0 (mkUnary .NEG residual[0]! atype)
        else if prod != 1 then residual.push (mkZ prod)
        else residual
      if residual.size == 1 then residual[0]! else mkNary .MUL residual atype
  | .SUB =>
    if bz2 then mkZ (zv 0 - zv 1)
    else if two && sq[1]!.isBZ && sq[1]!.toZ == 0 then sq[0]!
    else if two && sq[0]!.isBZ && sq[0]!.toZ == 0 then mkUnary .NEG sq[1]! atype
    else dflt
  | .TDIV | .FDIV | .CDIV | .EDIV =>
    if z2 then
      match sig with
      | .TDIV => mkZ (Int.tdiv (zv 0) (zv 1))
      | .FDIV => mkZ (Int.fdiv (zv 0) (zv 1))
      | .CDIV => mkZ (cdiv (zv 0) (zv 1))
      | _ => mkZ (Int.ediv (zv 0) (zv 1))
    else if two && sq[0]!.isBZ && sq[0]!.toZ == 0 then mkZ 0
    else if two && sq[1]!.isBZ && sq[1]!.toZ == 1 then sq[0]!
    else dflt
  | .TMOD => if z2 then mkZ (Int.tmod (zv 0) (zv 1)) else dflt
  | .FMOD => if z2 then mkZ (Int.fmod (zv 0) (zv 1)) else dflt
  | .CMOD => if z2 then mkZ (zv 0 - zv 1 * cdiv (zv 0) (zv 1)) else dflt
  | .EMOD => if z2 then mkZ (Int.emod (zv 0) (zv 1)) else dflt
  | .POW =>
    if bz2 then mkZ (ipow (zv 0) (zv 1))
    else if two && sq[1]!.isBZ && sq[1]!.toZ == 0 then mkZ 1
    else dflt
  | .IN =>
    if two && sq[0]!.isBZ && (match sq[1]! with | s .. => true | _ => false) then
      match sq[1]! with
      | s _ set =>
        let x := sq[0]!.toZ
        if set.any fun (lo, hi) => lo.isBZ && hi.isBZ && x ≥ lo.toZ && x ≤ hi.toZ then mkTrue else mkFalse
      | _ => dflt
    else if two && (match sq[1]! with | s _ set => set.size == 0 | _ => false) then mkFalse
    else dflt
  | _ => dflt

/-- lala-core `eval`: bottom-up syntactic simplification. -/
partial def eval : F → F
  | seq t sig cs => evalSeq sig (cs.map eval) t
  | eseq t es cs => mkEseq es (cs.map eval) t
  | f => f
where
  mkEseq (es : String) (cs : Array F) (t : Int) : F := eseq t es cs

end F
end Frontend
