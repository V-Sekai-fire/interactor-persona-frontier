-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Interval
import Frontend.Ternarize
import Std.Data.HashMap
/-! `preprocess_tcn` after `normalize` (common_solving.hpp): interpret the ternary normal form into the interval store and the propagators, run the
    simplifier of lala-core `simplifier.hpp` (equivalence classes, algebraic simplification, entailed-constraint elimination, I-CSE, useless-variable
    elimination) interleaved with the propagation fixpoint, then re-interpret the simplified formula. -/
open Std
namespace Frontend

structure Stats where
  icse : Nat := 0
  eqs : Nat := 0
  alg : Nat := 0
  entailed : Nat := 0
  icseIter : Nat := 0

structure Sim where
  st : Store
  names : Array String
  sorts : Array Srt
  idx : HashMap String Nat
  eqc : Array Nat
  elimV : Array Bool
  elimF : Array Bool
  cons : Array Con
  isCon : Array Bool
  bcs : Array Con
  c1 : Nat
  c2 : Nat
  stats : Stats

/-- A strategy: variable order, value order and the variables (by name until the final numbering). -/
structure Strat where
  varOrder : Nat
  valOrder : Nat
  vars : Array String

structure Pre where
  sim : Sim
  iterations : Nat
  perIter : Array Stats
  total : Stats
  eliminatedVars : Nat
  extra : Array F

/-- The position in lala's `enum Sig`, for the operators of the ternary normal form. -/
def sigIdx : Sig → Nat
  | .ADD => 2 | .MUL => 4 | .MIN => 6 | .MAX => 7 | .TDIV => 27 | .FDIV => 29 | .CDIV => 31 | .EDIV => 33 | .EMOD => 34
  | .EQ => 48 | .LEQ => 50 | _ => 99

@[inline] def Sim.eliminate (s : Sim) (i : Nat) : Sim × Bool :=
  if s.elimF[i]! then (s, false) else ({ s with elimF := s.elimF.set! i true }, true)

/-- `find`, with the path compression that embeds the child's domain in its parent. -/
def Sim.find (s : Sim) (x0 : Nat) : Nat × Sim := Id.run do
  let mut root := x0
  while s.eqc[root]! != root do root := s.eqc[root]!
  let mut s := s
  let mut x := x0
  while s.eqc[x]! != root do
    let parent := s.eqc[x]!
    let d := s.st.get x
    let st := s.st
    s := { s with st := Store.empty }
    let (st, _) := st.embed parent d
    s := { s with st := st, eqc := s.eqc.set! x root }
    x := parent
  return (root, s)

def Sim.embed (s : Sim) (x : Nat) (d : Itv) : Sim × Bool :=
  let st := s.st
  let s := { s with st := Store.empty }
  let (st, ch) := st.embed x d
  ({ s with st := st }, ch)

def Sim.merge (s : Sim) (x y : Nat) : Sim := Id.run do
  let (rx, s) := s.find x
  let (ry, s) := s.find y
  if rx != ry then
    let (rx, ry) := if rx < ry then (ry, rx) else (rx, ry)
    let d := s.st.get rx
    let s := { s with eqc := s.eqc.set! rx ry }
    let (s, _) := s.embed ry d
    return s
  return s

/-- `replace_by_equivalence(x, y, i, counter)`: merge and eliminate formula `i`; the counter is selected by `which`. -/
def Sim.replaceByEq (s : Sim) (x y i : Nat) (which : Nat) : Sim × Bool :=
  let s := s.merge x y
  let (s, ch) := s.eliminate i
  if ch then
    let t := s.stats
    let t := match which with
      | 0 => { t with icse := t.icse + 1 }
      | 1 => { t with eqs := t.eqs + 1 }
      | _ => { t with alg := t.alg + 1 }
    ({ s with stats := t }, true)
  else (s, false)

def Sim.elimCount (s : Sim) (i : Nat) (which : Nat) : Sim :=
  let (s, ch) := s.eliminate i
  if ch then
    let t := s.stats
    let t := match which with
      | 0 => { t with icse := t.icse + 1 }
      | 1 => { t with eqs := t.eqs + 1 }
      | _ => { t with alg := t.alg + 1 }
    { s with stats := t }
  else s

/-- `battery::iroots_up(x, 2)`: the estimate `pow(x, 1/2)` adjusted upwards with the cube test of the C++ source. -/
def iroot2Up (x : I) : I := Id.run do
  let mut u : I := Int32.ofInt (Float.sqrt x.toInt.toNat.toFloat).toUInt64.toNat
  while u * u * u < x do u := u + 1
  return u

def isCommutative (s : Sig) : Bool := F.isAssociative s || s == .EQ

/-- `meet_equivalence_classes`. -/
def Sim.meetClasses (s : Sim) : Sim := Id.run do
  let mut s := s
  let n := s.eqc.size
  for i in [0:n] do
    let (root, s') := s.find i
    s := s'
    let d := s.st.get i
    let (s', _) := s.embed root d
    s := s'
  for i in [0:n] do
    let (root, s') := s.find i
    s := s'
    let d := s.st.get root
    let (s', _) := s.embed i d
    s := s'
  return s

/-- `algebraic_simplify`; note `vstore[x]` is a copy in C++ (`PIR::operator[]` returns by value), so the meets below only report change. -/
def Sim.algebraic (s : Sim) : Sim × Bool := Id.run do
  let mut s := s
  let mut hasChanged := false
  let elimCons0 := s.stats.alg
  let elimEq0 := s.stats.eqs
  for i in [0:s.cons.size] do
    if !s.elimF[i]! then
      let c := s.cons[i]!
      let (x, s') := s.find c.x; s := s'
      let (y0, s') := s.find c.y; s := s'
      let (z0, s') := s.find c.z; s := s'
      let sig := c.op
      let xIsC := (s.st.get x).lo == (s.st.get x).hi
      let yIsC := (s.st.get y0).lo == (s.st.get y0).hi
      let zIsC0 := (s.st.get z0).lo == (s.st.get z0).hi
      let (y, z) := if isCommutative sig && yIsC then (z0, y0) else (y0, z0)
      let zIsC := zIsC0
      let vx := s.st.get x; let vy := s.st.get y; let vz := s.st.get z
      match sig with
      | .ADD =>
        if x == y || x == z then
          s := s.elimCount i 2
        else if vz == Itv.zero then
          let (s', _) := s.replaceByEq x y i 2; s := s'
        else if y == z then
          s := { s with cons := s.cons.set! i { c with op := .MUL, y := y, z := s.c2 } }
      | .MUL =>
        if x == y && zIsC then
          if vz != Itv.one then
            hasChanged := hasChanged || (vx.meet Itv.zero).2
          s := s.elimCount i 2
        else if xIsC && y == z then
          let n := iroot2Up vx.lo
          if n * n == vx.lo then
            hasChanged := hasChanged || ((s.st.get y).meet ⟨-n, n⟩).2
        else if vz == Itv.one then
          let (s', _) := s.replaceByEq x y i 2; s := s'
        else if x == y && y == z then
          s := s.elimCount i 2
      | .EDIV =>
        if vy == Itv.one && x == z then
          hasChanged := hasChanged || (vx.meet ⟨-1, 1⟩).2
        else if vy == Itv.zero && x == z then pure ()
        else if xIsC && y == z then pure ()
        else if vz == Itv.one then
          let (s', _) := s.replaceByEq x y i 2; s := s'
        else if x == y && y == z then
          s := s.elimCount i 2
      | .EMOD =>
        if x == y && y == z then s := s.elimCount i 2
        else if x == y && zIsC then s := s.elimCount i 2
        else if x == z && yIsC then pure ()
        else if y == z && vx == Itv.zero then s := s.elimCount i 2
      | .MIN | .MAX =>
        if y == z then
          let (s', _) := s.replaceByEq x y i 2; s := s'
        else if x == y || x == z then
          let y2 := if x == y then z else y
          let (x2, y2) := if sig == .MAX then (y2, x) else (x, y2)
          s := { s with cons := s.cons.set! i { op := .LEQ, x := s.c1, y := x2, z := y2 } }
      | .EQUIV | .EQ =>
        if vx == Itv.one then
          let (s', _) := s.replaceByEq y z i 1; s := s'
        else if x == y && zIsC then
          s := s.elimCount i 2
        else if y == z then
          s := s.elimCount i 2
      | .LEQ =>
        if x == y && zIsC then s := s.elimCount i 2
        else if x == z && yIsC then s := s.elimCount i 2
        else if y == z then s := s.elimCount i 2
      | _ => pure ()
  return (s, hasChanged || elimCons0 != s.stats.alg || elimEq0 != s.stats.eqs)

/-- `eliminate_entailed_constraints`. -/
def Sim.entailed (s : Sim) : Sim := Id.run do
  let mut s := s
  for i in [0:s.cons.size] do
    if s.isCon[i]! && !s.elimF[i]! then
      if askBc s.st s.cons[i]! then
        let (s', ch) := s.eliminate i
        s := s'
        if ch then s := { s with stats := { s.stats with entailed := s.stats.entailed + 1 } }
  return s

/-- `i_cse`. -/
def Sim.icse (s : Sim) : Sim × Bool := Id.run do
  let mut s := s
  let mut has := false
  let mut loc := true
  while loc do
    s := { s with stats := { s.stats with icseIter := s.stats.icseIter + 1 } }
    loc := false
    let mut cs : HashMap Nat Nat := HashMap.emptyWithCapacity s.cons.size
    for i in [0:s.cons.size] do
      if !s.elimF[i]! then
        let c := s.cons[i]!
        let (x, s') := s.find c.x; s := s'
        let (y, s') := s.find c.y; s := s'
        let (z, s') := s.find c.z; s := s'
        let (ya, za) := if isCommutative c.op && z < y then (z, y) else (y, z)
        let key := (sigIdx c.op * 2097152 + ya) * 2097152 + za
        match cs.get? key with
        | none => cs := cs.insert key x
        | some x' =>
          let (s', ch) := s.replaceByEq x x' i 0
          s := s'
          if ch then
            loc := true
            has := true
  return (s, has)

/-- `eliminate_useless_variables`: the variables that stay are the representatives that occur in a kept ternary constraint. Returns the count of eliminated variables
    and the constants (`constants[i] = store[find i]`). -/
def Sim.useless (s : Sim) : Sim × Nat × Array Itv := Id.run do
  let mut s := s
  let n := s.eqc.size
  let mut elim := Array.replicate n true
  for i in [0:s.cons.size] do
    if !s.elimF[i]! then
      let c := s.cons[i]!
      let (x, s') := s.find c.x; s := s'
      let (y, s') := s.find c.y; s := s'
      let (z, s') := s.find c.z; s := s'
      elim := elim.set! x false
      elim := elim.set! y false
      elim := elim.set! z false
  -- `dynamic_bitset::set()` also sets the padding bits of the last 64-bit word, and `count()` counts them
  let cnt := elim.foldl (fun a b => if b then a + 1 else a) 0 + (64 - n % 64) % 64
  let mut consts : Array Itv := Array.mkEmpty n
  for i in [0:n] do
    let (root, s') := s.find i; s := s'
    consts := consts.push (s.st.get root)
  return ({ s with elimV := elim }, cnt, consts)

/-- Interpret the normalized TNF (`f` is a top-level conjunction): variables in order, unary bounds, bytecodes sorted as `PIR::deduce` does. -/
def interpretTnf (children : Array F) : Sim := Id.run do
  let mut st := Store.empty
  let mut names : Array String := #[]
  let mut sorts : Array Srt := #[]
  let mut idx : HashMap String Nat := {}
  let mut cons : Array Con := Array.mkEmpty children.size
  let mut isCon : Array Bool := Array.mkEmpty children.size
  let mut unary : Array (Nat × Itv) := #[]
  for c in children do
    match c with
    | .e _ name so =>
      idx := idx.insert name names.size
      names := names.push name
      sorts := sorts.push so
      st := st.push (if so == .bool then ⟨0, 1⟩ else Itv.top)
      cons := cons.push default; isCon := isCon.push false
    | .seq _ sg #[.lv _ x, .seq _ op #[.lv _ y, .lv _ z]] =>
      if sg == .EQ || sg == .EQUIV then
        cons := cons.push { op := op, x := idx.getD x 0, y := idx.getD y 0, z := idx.getD z 0 }; isCon := isCon.push true
      else
        cons := cons.push default; isCon := isCon.push false
    | .seq _ sg #[.lv _ x, .z _ k] =>
      let v := idx.getD x 0
      let k32 : I := Int32.ofInt k
      unary := unary.push (v, if sg == .LEQ then ⟨MINF, k32⟩ else if sg == .GEQ then ⟨k32, INF⟩ else ⟨k32, k32⟩)
      cons := cons.push default; isCon := isCon.push false
    | _ => cons := cons.push default; isCon := isCon.push false
  for (v, d) in unary do
    let (st', _) := st.embed v d
    st := st'
  for i in [0:cons.size] do
    if isCon[i]! && (cons[i]!.op == .EQ || cons[i]!.op == .LEQ) then
      let (st', _) := st.embed cons[i]!.x ⟨0, 1⟩
      st := st'
  let bcs := (cons.zip isCon).foldl (fun acc (c, b) => if b then acc.push c else acc) #[]
  let bcs := bcs.qsort (fun a b =>
    if sigIdx a.op != sigIdx b.op then sigIdx a.op < sigIdx b.op
    else if a.y != b.y then a.y < b.y
    else if a.x != b.x then a.x < b.x
    else a.z < b.z)
  let n := names.size
  return { st := st, names := names, sorts := sorts, idx := idx, eqc := Array.ofFn (n := n) (fun i => i.val),
           elimV := Array.replicate n false, elimF := isCon.map (!·), cons := cons, isCon := isCon, bcs := bcs,
           c1 := idx.getD "__CONSTANT_1" 0, c2 := idx.getD "__CONSTANT_2" 0, stats := {} }

/-- One `fp_engine.fixpoint(iprop->num_deductions(), ...)`: returns whether anything changed in any round. -/
def Sim.propagate (s : Sim) : Sim × Bool := Id.run do
  let mut s := s
  let mut any := false
  let mut changed := true
  while changed && !s.st.atBot do
    changed := false
    for i in [0:s.bcs.size] do
      let st := s.st
      s := { s with st := Store.empty }
      let (st', ch) := deduceBc st s.bcs[i]!
      s := { s with st := st' }
      if ch then changed := true
    if changed then any := true
  return (s, any)

/-- The loop of `preprocess_tcn`: returns the simplifier state, the statistics of each iteration that printed (iteration number, stats) and the total. -/
def runLoop (s : Sim) (numVars : Nat) : Sim × Array (Nat × Stats) × Stats × Nat := Id.run do
  let mut s := s
  let mut per : Array (Nat × Stats) := #[]
  let mut total : Stats := {}
  let mut has := true
  let mut iters := 0
  while !s.st.atBot && has do
    has := false
    iters := iters + 1
    s := { s with stats := {} }
    let (s', ch) := s.propagate; s := s'
    has := ch
    if ch then s := s.meetClasses
    let (s', ch2) := s.algebraic; s := s'; has := has || ch2
    s := s.entailed
    if numVars < 1000000 then
      let (s', ch3) := s.icse; s := s'; has := has || ch3
    if has then
      s := s.meetClasses
      per := per.push (iters, s.stats)
    let t := s.stats
    total := { icse := total.icse + t.icse, eqs := total.eqs + t.eqs, alg := total.alg + t.alg, entailed := total.entailed + t.entailed, icseIter := total.icseIter + t.icseIter }
  return (s, per, total, iters)

/-- What `Simplifier::print_variable` needs to print the value of an original variable: its class representative, whether that survived into the
    final store (and under which index), and otherwise the constant of the class. -/
structure SolInfo where
  idx : HashMap String Nat := {}
  eqc : Array Nat := #[]
  elimV : Array Bool := #[]
  newIdx : Array Nat := #[]
  consts : Array Itv := #[]
  sorts : Array Srt := #[]

/-- The result of the whole front end after the simplifier: what `cp_dump` prints. -/
structure Dump where
  bot : Bool
  vars : Array Itv
  bcs : Array Con
  strats : Array (Nat × Nat × Array Nat)
  objective : Option Nat
  /-- the variable the search minimizes: the objective of `minimize`, `__MINIMIZE_OBJ` for `maximize` -/
  minimizeObjective : Option Nat
  isMin : Bool
  tnfVars : Nat
  tnfCons : Nat
  per : Array (Nat × Stats)
  total : Stats
  iters : Nat
  eliminatedVars : Nat
  varsAfter : Nat
  consAfter : Nat
  info : SolInfo := {}

def varOrderOf : String → Nat
  | "input_order" => 0 | "first_fail" => 1 | "anti_first_fail" => 2 | "smallest" => 3 | "largest" => 4 | "random" => 5 | _ => 0
def valOrderOf : String → Nat
  | "indomain_min" => 0 | "indomain_max" => 1 | "indomain_median" => 3 | "indomain_split" => 3 | "indomain_reverse_split" => 4 | _ => 0

/-- `preprocess_tcn` on the ternary normal form `tnf` (with the extra conjuncts `extra` of `normalize`). -/
def preprocessTcn (tnf : F) (extra : Array F) : Dump := Id.run do
  let children := match tnf with | .seq _ .AND cs => cs | _ => #[]
  let numVars := F.numQuantifiedVars tnf
  let tnfCons := numTnfConstraints tnf
  let s := interpretTnf children
  let (s, per, total, iters) := runLoop s numVars
  let (s, elimCount, consts) := s.useless
  if s.st.atBot then
    return { bot := true, vars := #[], bcs := #[], strats := #[], objective := none, minimizeObjective := none, isMin := false, tnfVars := numVars, tnfCons := tnfCons,
             per := per, total := total, iters := iters, eliminatedVars := elimCount, varsAfter := 0, consAfter := 0 }
  -- the surviving variables, numbered in order
  let n := s.eqc.size
  let mut newIdx : Array Nat := Array.replicate n 0
  let mut vars : Array Itv := #[]
  for i in [0:n] do
    if s.eqc[i]! == i && !s.elimV[i]! then
      newIdx := newIdx.set! i vars.size
      let d := consts[i]!
      let d := if s.sorts[i]! == .bool then (d.meet ⟨0, 1⟩).1 else d
      vars := vars.push d
  let mut st : Store := Store.empty
  for d in vars do st := st.push d
  let mut bcs : Array Con := #[]
  for i in [0:s.cons.size] do
    if s.isCon[i]! && !s.elimF[i]! then
      let c := s.cons[i]!
      bcs := bcs.push { op := c.op, x := newIdx[s.eqc[c.x]!]!, y := newIdx[s.eqc[c.y]!]!, z := newIdx[s.eqc[c.z]!]! }
  for c in bcs do
    if c.op == .EQ || c.op == .LEQ then
      let (st', _) := st.embed c.x ⟨0, 1⟩
      st := st'
  let consAfter := bcs.size
  bcs := bcs.qsort (fun a b =>
    if sigIdx a.op != sigIdx b.op then sigIdx a.op < sigIdx b.op
    else if a.y != b.y then a.y < b.y
    else if a.x != b.x then a.x < b.x
    else a.z < b.z)
  -- extra conjuncts: the objective and the search strategies, with variables replaced by their representative (constants are dropped)
  let keep (name : String) : Option Nat :=
    match s.idx.get? name with
    | none => none
    | some v => let r := s.eqc[v]!; if s.elimV[r]! then none else some newIdx[r]!
  let mut strats : Array (Nat × Nat × Array Nat) := #[]
  let mut objective : Option Nat := none
  let mut isMin := false
  for e in extra do
    match e with
    | .seq _ sg #[.lv _ name] =>
      if sg == .MINIMIZE || sg == .MAXIMIZE then
        objective := keep name
        isMin := sg == .MINIMIZE
    | .eseq _ "search" cs =>
      if cs.size >= 2 then
        let vo := match cs[0]! with | .eseq _ o _ => varOrderOf o | _ => 0
        let wo := match cs[1]! with | .eseq _ o _ => valOrderOf o | _ => 0
        let mut vs : Array Nat := #[]
        for c in cs[2:] do
          match c with
          | .lv _ name =>
            match keep name with
            | some v => vs := vs.push v
            | none => pure ()
          | _ => pure ()
        strats := strats.push (vo, wo, vs)
    | _ => pure ()
  strats := strats.push (1, 0, #[])
  return { bot := false, vars := vars, bcs := bcs, strats := strats, objective := objective, minimizeObjective := (if isMin then objective else (keep "__MINIMIZE_OBJ").orElse (fun _ => objective)), isMin := isMin, tnfVars := numVars, tnfCons := tnfCons,
           per := per, total := total, iters := iters, eliminatedVars := elimCount, varsAfter := vars.size, consAfter := consAfter,
           info := { idx := s.idx, eqc := s.eqc, elimV := s.elimV, newIdx := newIdx, consts := consts, sorts := s.sorts } }

def opText : Sig → String
  | .ADD => "+" | .MUL => "*" | .MIN => "min" | .MAX => "max" | .EQ => "=" | .LEQ => "≤"
  | .TDIV => "tdiv" | .FDIV => "fdiv" | .CDIV => "cdiv" | .EDIV => "ediv" | .EMOD => "emod" | _ => "?"

/-- The text `slang/turbo/oracle/cp_dump.cpp` prints in its default mode. -/
def Dump.text (d : Dump) : String := Id.run do
  let mut out : Array String := #[]
  out := out.push s!"bot {if d.bot then 1 else 0}"
  out := out.push s!"variables {d.vars.size}"
  for v in d.vars do out := out.push s!"{v.lo} {v.hi}"
  out := out.push s!"bytecodes {d.bcs.size}"
  for c in d.bcs do out := out.push s!"{opText c.op} {c.x} {c.y} {c.z}"
  out := out.push s!"strategies {d.strats.size}"
  for (a, b, vs) in d.strats do
    out := out.push (s!"{a} {b} {vs.size}" ++ String.join (vs.toList.map fun v => s!" {v}"))
  match d.minimizeObjective with
  | some v => out := out.push s!"objective 0 {v}"
  | none => out := out.push "objective 1 -1"
  out := out.push s!"optimization {if d.objective.isSome && d.isMin then 1 else 0} {if d.objective.isSome && !d.isMin then 1 else 0}"
  match d.objective with
  | some v => out := out.push s!"bab_objective {v}"
  | none => pure ()
  return String.intercalate "\n" out.toList ++ "\n"

end Frontend
