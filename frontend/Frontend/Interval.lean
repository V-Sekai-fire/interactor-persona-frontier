-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Frontend.Formula
/-! The interval store and the propagators of lala-pc `pir.hpp` as executable Lean on `Int32` (Turbo's `bound_value_type` is `int`, arithmetic wraps).
    The same rules are emitted for the GPU by `turbo/Turbo/Pir.lean`; this copy runs inside the front end, where Turbo runs them on the CPU
    during `preprocess_tcn`. The store is `VStore<Interval<ZLB, ZUB>>`: `embed` meets, and meeting to an empty interval marks the store as bottom. -/
namespace Frontend
abbrev I := Int32
def INF : I := 2147483647
def MINF : I := -2147483648
@[inline] def mx (a b : I) : I := if a < b then b else a
@[inline] def mn (a b : I) : I := if b < a then b else a

structure Itv where
  lo : I
  hi : I
  deriving BEq, Inhabited

namespace Itv
def top : Itv := ⟨MINF, INF⟩
def bot : Itv := ⟨INF, MINF⟩
def zero : Itv := ⟨0, 0⟩
def one : Itv := ⟨1, 1⟩
def isBot (a : Itv) : Bool := a.lo == INF || a.hi == MINF || a.lo > a.hi
def join (a b : Itv) : Itv := ⟨mn a.lo b.lo, mx a.hi b.hi⟩
/-- `meet`: the result and whether `a` changed. -/
def meet (a b : Itv) : Itv × Bool := (⟨mx a.lo b.lo, mn a.hi b.hi⟩, b.lo > a.lo || b.hi < a.hi)
end Itv

structure Store where
  lo : Array I
  hi : Array I
  atBot : Bool

namespace Store
def empty : Store := ⟨#[], #[], false⟩
@[inline] def get (s : Store) (x : Nat) : Itv := ⟨s.lo[x]!, s.hi[x]!⟩
def push (s : Store) (d : Itv) : Store := { s with lo := s.lo.push d.lo, hi := s.hi.push d.hi }
/-- `VStore::embed`: meet with the stored domain; reaching bottom marks the store. -/
def embed (s : Store) (x : Nat) (d : Itv) : Store × Bool :=
  let cur : Itv := ⟨s.lo[x]!, s.hi[x]!⟩
  let (r, ch) := cur.meet d
  if ch then
    let s := { s with lo := s.lo.set! x r.lo, hi := s.hi.set! x r.hi }
    ({ s with atBot := s.atBot || r.isBot }, true)
  else (s, false)
end Store

/-- One propagator `x = y op z`. -/
structure Con where
  op : Sig
  x : Nat
  y : Nat
  z : Nat
  deriving Inhabited

@[inline] def sgn (x : I) : I := if x > 0 then 1 else if x < 0 then -1 else 0
def tdivI (x y : I) : I := x / y
def fdivI (x y : I) : I := x / y - (if sgn (x % y) == -(sgn y) then 1 else 0)
def cdivI (x y : I) : I := x / y + (if sgn (x % y) == sgn y then 1 else 0)
def ediv (x y : I) : I := x / y - (if x % y >= 0 then 0 else sgn y)
def emodI (x y : I) : I := x % y + y * (if x % y >= 0 then 0 else sgn y)
def divOp (a : I) (op : Sig) (b : I) : I :=
  match op with
  | .TDIV => tdivI a b | .CDIV => cdivI a b | .FDIV => fdivI a b | .EDIV => ediv a b | _ => a

def numFdiv (r1 r3 : Itv) : Itv :=
  let xl := r1.lo; let xu := r1.hi; let zl := r3.lo; let zu := r3.hi
  if zl < 0 && zu > 0 then
    ⟨mn (mn xl (-xu)) (mn (xl * zu) ((xu + 1) * zl + 1)), mx (mx (-xl) xu) (mx (xl * zl) ((xu + 1) * zu - 1))⟩
  else if zl > 0 || zu < 0 then
    ⟨mn (mn (xl * zl) (xl * zu)) (mn ((xu + 1) * zl + 1) ((xu + 1) * zu + 1)),
     mx (mx (xl * zl) (xl * zu)) (mx ((xu + 1) * zl - 1) ((xu + 1) * zu - 1))⟩
  else Itv.top

def numCdiv (r1 r3 : Itv) : Itv :=
  let xl := r1.lo; let xu := r1.hi; let zl := r3.lo; let zu := r3.hi
  if zl < 0 && zu > 0 then
    ⟨mn (mn xl (-xu)) (mn (xu * zl) ((xl - 1) * zu + 1)), mx (mx (-xl) xu) (mx (xu * zu) ((xl - 1) * zl - 1))⟩
  else if zl > 0 || zu < 0 then
    ⟨mn (mn (xu * zl) (xu * zu)) (mn ((xl - 1) * zl + 1) ((xl - 1) * zu + 1)),
     mx (mx (xu * zl) (xu * zu)) (mx ((xl - 1) * zl - 1) ((xl - 1) * zu - 1))⟩
  else Itv.top

def numTdiv (r1 r3 : Itv) : Itv :=
  let xl := r1.lo; let xu := r1.hi; let zl := r3.lo; let zu := r3.hi
  if xl > 0 then numFdiv r1 r3
  else if xu < 0 then numCdiv r1 r3
  else if xl <= 0 && 0 <= xu then
    let r : Itv := ⟨mn zl (-zu) + 1, mx (-zl) zu - 1⟩
    let r := if xl != 0 then r.join (numCdiv ⟨xl, -1⟩ r3) else r
    if xu != 0 then r.join (numFdiv ⟨1, xu⟩ r3) else r
  else Itv.top

def numEdiv (r1 r3 : Itv) : Itv :=
  let zl := r3.lo; let zu := r3.hi
  if zl > 0 then numFdiv r1 r3
  else if zu < 0 then numCdiv r1 r3
  else if zl < 0 && zu > 0 then (numCdiv r1 ⟨zl, -1⟩).join (numFdiv r1 ⟨1, zu⟩)
  else Itv.top

partial def denFdiv (r1 r2 : Itv) : Itv :=
  let xl := r1.lo; let xu := r1.hi; let yl := r2.lo; let yu := r2.hi
  if xl > 0 || xu + 1 < 0 then
    if yl > 0 then ⟨mn (fdivI yl (xu + 1)) (fdivI yu (xu + 1)) + 1, mx (fdivI yl xl) (fdivI yu xl)⟩
    else if yu < 0 then ⟨mn (cdivI yl xl) (cdivI yu xl), mx (cdivI yl (xu + 1)) (cdivI yu (xu + 1)) - 1⟩
    else if 0 == yl && yl < yu then denFdiv r1 ⟨1, yu⟩
    else if yl < yu && yu == 0 then denFdiv r1 ⟨yl, -1⟩
    else if yl < 0 && 0 < yu then (denFdiv r1 ⟨yl, -1⟩).join (denFdiv r1 ⟨1, yu⟩)
    else if yl == 0 && yu == 0 then Itv.bot
    else Itv.top
  else if xl == 0 && xu == 0 then
    if yl > 0 then ⟨yl + 1, INF⟩ else if yu < 0 then ⟨MINF, yu - 1⟩ else Itv.top
  else if xl == -1 && xu == -1 then
    if yl > 0 then ⟨MINF, -yl⟩
    else if yu < 0 then ⟨-yu, INF⟩
    else if 0 == yl && yl < yu then ⟨MINF, -1⟩
    else if yl < yu && yu == 0 then ⟨1, INF⟩
    else if yl == 0 && yu == 0 then Itv.bot
    else Itv.top
  else if xl == 0 && 0 < xu then (denFdiv ⟨0, 0⟩ r2).join (denFdiv ⟨1, xu⟩ r2)
  else if xl < -1 && xu == -1 then (denFdiv ⟨xl, -2⟩ r2).join (denFdiv ⟨-1, -1⟩ r2)
  else if xl <= -1 && xu >= 0 then
    let r := (denFdiv ⟨-1, -1⟩ r2).join (denFdiv ⟨0, 0⟩ r2)
    let r := if xl != -1 then r.join (denFdiv ⟨xl, -2⟩ r2) else r
    if xu != 0 then r.join (denFdiv ⟨1, xu⟩ r2) else r
  else Itv.top

partial def denCdiv (r1 r2 : Itv) : Itv :=
  let xl := r1.lo; let xu := r1.hi; let yl := r2.lo; let yu := r2.hi
  if xl - 1 > 0 || xu < 0 then
    if yl > 0 then ⟨mn (cdivI yl xu) (cdivI yu xu), mx (cdivI yl (xl - 1)) (cdivI yu (xl - 1)) - 1⟩
    else if yu < 0 then ⟨mn (fdivI yl (xl - 1)) (fdivI yu (xl - 1)) + 1, mx (fdivI yl xu) (fdivI yu xu)⟩
    else if 0 == yl && yl < yu then denCdiv r1 ⟨1, yu⟩
    else if yl < yu && yu == 0 then denCdiv r1 ⟨yl, -1⟩
    else if yl < 0 && 0 < yu then (denCdiv r1 ⟨yl, -1⟩).join (denCdiv r1 ⟨1, yu⟩)
    else if yl == 0 && yu == 0 then Itv.bot
    else Itv.top
  else if xl == 0 && xu == 0 then
    if yl > 0 then ⟨MINF, -yl - 1⟩ else if yu < 0 then ⟨-yu + 1, INF⟩ else Itv.top
  else if xl == 1 && xu == 1 then
    if yl > 0 then ⟨yl, INF⟩
    else if yu < 0 then ⟨MINF, yu⟩
    else if 0 == yl && yl < yu then ⟨1, INF⟩
    else if yl < yu && yu == 0 then ⟨MINF, -1⟩
    else if yl == 0 && yu == 0 then Itv.bot
    else Itv.top
  else if xl < 0 && xu == 0 then (denCdiv ⟨xl, -1⟩ r2).join (denCdiv ⟨0, 0⟩ r2)
  else if xl == 1 && 1 < xu then (denCdiv ⟨1, 1⟩ r2).join (denCdiv ⟨2, xu⟩ r2)
  else if xl <= 0 && xu >= 1 then
    let r := (denCdiv ⟨1, 1⟩ r2).join (denCdiv ⟨0, 0⟩ r2)
    let r := if xl != 0 then r.join (denCdiv ⟨xl, -1⟩ r2) else r
    if xu != 1 then r.join (denCdiv ⟨2, xu⟩ r2) else r
  else Itv.top

partial def denTdiv (r1 r2 r3 : Itv) : Itv :=
  let xl := r1.lo; let xu := r1.hi; let yl := r2.lo; let yu := r2.hi; let zl := r3.lo; let zu := r3.hi
  if xl > 0 then denFdiv r1 r2
  else if xu < 0 then denCdiv r1 r2
  else if xl == 0 && xu == 0 then
    if yl > 0 && zl > 0 then ⟨yl + 1, INF⟩
    else if yl > 0 && zu < 0 then ⟨MINF, -yl - 1⟩
    else if yu < 0 && zl > 0 then ⟨-yu + 1, INF⟩
    else if yu < 0 && zu < 0 then ⟨MINF, yu - 1⟩
    else Itv.top
  else if xl <= 0 && 0 <= xu then
    let r := denTdiv ⟨0, 0⟩ r2 r3
    let r := if xl != 0 then r.join (denCdiv ⟨xl, -1⟩ r2) else r
    if xu != 0 then r.join (denFdiv ⟨1, xu⟩ r2) else r
  else Itv.top

def denEdiv (r1 r2 r3 : Itv) : Itv :=
  let zl := r3.lo; let zu := r3.hi
  if zl > 0 then denFdiv r1 r2
  else if zu < 0 then denCdiv r1 r2
  else if zl < 0 && 0 < zu then (denFdiv r1 r2).join (denCdiv r1 r2)
  else Itv.top

/-- `itv_div`: narrows `r1` and `r3`. -/
def itvDiv (op : Sig) (r1 r2 r3 : Itv) : Itv × Itv :=
  let xl := r1.lo; let xu := r1.hi; let yl := r2.lo; let yu := r2.hi
  if r3.lo < 0 && r3.hi > 0 then
    (⟨mx xl (mn yl (if yu == MINF then INF else -yu)), mn xu (mx (if yl == INF then MINF else -yl) yu)⟩, r3)
  else
    let r3 : Itv := if r3.lo == 0 then ⟨1, r3.hi⟩ else r3
    let r3 : Itv := if r3.hi == 0 then ⟨r3.lo, -1⟩ else r3
    let zl := r3.lo; let zu := r3.hi
    if yl == MINF || yu == INF || zl == MINF || zu == INF then (r1, r3)
    else if r3.isBot then (r1, r3)
    else
      let t1 := divOp yl op zl; let t2 := divOp yl op zu; let t3 := divOp yu op zl; let t4 := divOp yu op zu
      (⟨mx xl (mn (mn t1 t2) (mn t3 t4)), mn xu (mx (mx t1 t2) (mx t3 t4))⟩, r3)

def itvDivNum (op : Sig) (r1 r2 r3 : Itv) : Itv :=
  let n : Itv := match op with
    | .FDIV => numFdiv r1 r3 | .CDIV => numCdiv r1 r3 | .TDIV => numTdiv r1 r3 | .EDIV => numEdiv r1 r3 | _ => Itv.top
  match op with
  | .FDIV | .CDIV | .TDIV | .EDIV => (r2.meet n).1
  | _ => r2

def itvDivDen (op : Sig) (r1 r2 r3 : Itv) : Itv :=
  match op with
  | .FDIV => (r3.meet (denFdiv r1 r2)).1
  | .CDIV => (r3.meet (denCdiv r1 r2)).1
  | .TDIV => (r3.meet (denTdiv r1 r2 r3)).1
  | .EDIV => (r3.meet (denEdiv r1 r2 r3)).1
  | _ => r3

/-- `mul_inv(r1, r2, r3)`: narrows `r2` and `r3`. -/
def mulInv (r1 r2 r3 : Itv) : Itv × Itv :=
  let xl := r1.lo; let xu := r1.hi
  let r3 : Itv := if (xl > 0 || xu < 0) && r3.lo == 0 then ⟨1, r3.hi⟩ else r3
  let r3 : Itv := if (xl > 0 || xu < 0) && r3.hi == 0 then ⟨r3.lo, -1⟩ else r3
  let yl := r2.lo; let yu := r2.hi; let zl := r3.lo; let zu := r3.hi
  if (xl > 0 || xu < 0) && zl < 0 && zu > 0 then
    (⟨mx yl (mn xl (if xu == MINF then INF else -xu)), mn yu (mx (if xl == INF then MINF else -xl) xu)⟩, r3)
  else if xl > 0 || xu < 0 || zl > 0 || zu < 0 then
    if xl == MINF || xu == INF || zl == MINF || zu == INF then (r2, r3)
    else if r3.isBot then (r2, r3)
    else
      (⟨mx yl (mn (mn (cdivI xl zl) (cdivI xl zu)) (mn (cdivI xu zl) (cdivI xu zu))),
        mn yu (mx (mx (fdivI xl zl) (fdivI xl zu)) (mx (fdivI xu zl) (fdivI xu zu)))⟩, r3)
  else (r2, r3)

/-- `PIR::ask(bytecode)`: is the propagator entailed. -/
def askBc (st : Store) (b : Con) : Bool :=
  let r1 := st.get b.x; let r2 := st.get b.y; let r3 := st.get b.z
  let xl := r1.lo; let xu := r1.hi; let yl := r2.lo; let yu := r2.hi; let zl := r3.lo; let zu := r3.hi
  match b.op with
  | .EQ => (xl == 1 && yu == zl && yl == zu) || (xu == 0 && (yu < zl || yl > zu))
  | .LEQ => (xl == 1 && yu <= zl) || (xu == 0 && yl > zu)
  | .ADD => xl == xu && yl == yu && zl == zu && xl == yl + zl
  | .MUL => xl == xu && ((yl == yu && zl == zu && xl == yl * zl) || (xl == 0 && (r2 == Itv.zero || r3 == Itv.zero)))
  | .TDIV | .CDIV | .FDIV | .EDIV =>
    (xl == xu && yl == yu && zl == zu && zl != 0 && xl == divOp yl b.op zl)
    || (xl == yu && xu == yl && xl == 0 && (zl > 0 || zu < 0))
  | .EMOD => xl == xu && yl == yu && zl == zu && zl != 0 && xl == emodI yl zl
  | .MIN => (xl == yu && xu == yl && yu <= zl) || (xl == zu && xu == zl && zu <= yl)
  | .MAX => (xl == yu && xu == yl && yl >= zu) || (xl == zu && xu == zl && zl >= yu)
  | _ => false

/-- `PIR::deduce(bytecode)`: one propagation step; returns the store and whether it changed. -/
def deduceBc (st : Store) (b : Con) : Store × Bool :=
  let r1 := st.get b.x; let r2 := st.get b.y; let r3 := st.get b.z
  let xl := r1.lo; let xu := r1.hi; let yl := r2.lo; let yu := r2.hi; let zl := r3.lo; let zu := r3.hi
  match b.op with
  | .EQ =>
    if r1 == Itv.one then
      let (st, c1) := st.embed b.y r3
      let (st, c2) := st.embed b.z r2
      (st, c1 || c2)
    else if r1 == Itv.zero && (yl == yu || zl == zu) then
      st.embed (if zl == zu then b.y else b.z) ⟨if yl == zl then yl + 1 else MINF, if yu == zu then yu - 1 else INF⟩
    else if yu == zl && yl == zu then st.embed b.x Itv.one
    else if yl > zu || yu < zl then st.embed b.x Itv.zero
    else (st, false)
  | .LEQ =>
    if r1 == Itv.one then
      let (st, c1) := st.embed b.y ⟨yl, zu⟩
      let (st, c2) := st.embed b.z ⟨yl, zu⟩
      (st, c1 || c2)
    else if r1 == Itv.zero then
      let (st, c1) := st.embed b.y ⟨zl + 1, yu⟩
      let (st, c2) := st.embed b.z ⟨zl, yu - 1⟩
      (st, c1 || c2)
    else if yu <= zl then st.embed b.x Itv.one
    else if yl > zu then st.embed b.x Itv.zero
    else (st, false)
  | op =>
    let (r1, r2, r3) : Itv × Itv × Itv :=
      match op with
      | .ADD =>
        -- the C++ macros read the live intervals, so each bound sees the previous assignments
        let r1 : Itv := ⟨if yl == MINF || zl == MINF then xl else mx xl (yl + zl), if yu == INF || zu == INF then xu else mn xu (yu + zu)⟩
        let r2 : Itv := ⟨if r1.lo == MINF || zu == INF then yl else mx yl (r1.lo - zu), if r1.hi == INF || zl == MINF then yu else mn yu (r1.hi - zl)⟩
        let r3 : Itv := ⟨if r1.lo == MINF || r2.hi == INF then zl else mx zl (r1.lo - r2.hi), if r1.hi == INF || r2.lo == MINF then zu else mn zu (r1.hi - r2.lo)⟩
        (r1, r2, r3)
      | .MUL =>
        let r1 : Itv :=
          if yl != MINF && yu != INF && zl != MINF && zu != INF then
            let t1 := yl * zl; let t2 := yl * zu; let t3 := yu * zl; let t4 := yu * zu
            ⟨mx xl (mn (mn t1 t2) (mn t3 t4)), mn xu (mx (mx t1 t2) (mx t3 t4))⟩
          else r1
        let (r2, r3) := mulInv r1 r2 r3
        let (r3, r2) := mulInv r1 r3 r2
        (r1, r2, r3)
      | .TDIV | .CDIV | .FDIV | .EDIV =>
        let (r1, r3) := itvDiv op r1 r2 r3
        if !r1.isBot && !r3.isBot then
          let r2 := itvDivNum op r1 r2 r3
          if !r2.isBot then (r1, r2, itvDivDen op r1 r2 r3) else (r1, r2, r3)
        else (r1, r2, r3)
      | .EMOD =>
        let r3 : Itv := if zl == 0 then ⟨1, r3.hi⟩ else r3
        let r3 : Itv := if r3.hi == 0 then ⟨r3.lo, -1⟩ else r3
        if yl == yu && r3.lo == r3.hi then
          let l := emodI yl r3.lo
          (⟨l, l⟩, r2, r3)
        else (r1, r2, r3)
      | .MIN =>
        let r1 : Itv := ⟨mx xl (mn yl zl), mn xu (mn yu zu)⟩
        let r2 : Itv := ⟨mx yl r1.lo, if r1.hi < zl then mn yu r1.hi else r2.hi⟩
        let r3 : Itv := ⟨mx zl r1.lo, if r1.hi < r2.lo then mn zu r1.hi else r3.hi⟩
        (r1, r2, r3)
      | .MAX =>
        let r1 : Itv := ⟨mx xl (mx yl zl), mn xu (mx yu zu)⟩
        let r2 : Itv := ⟨if r1.lo > zu then mx yl r1.lo else r2.lo, mn yu r1.hi⟩
        let r3 : Itv := ⟨if r1.lo > r2.hi then mx zl r1.lo else r3.lo, mn zu r1.hi⟩
        (r1, r2, r3)
      | _ => (r1, r2, r3)
    let (st, c1) := st.embed b.x r1
    let (st, c2) := st.embed b.y r2
    let (st, c3) := st.embed b.z r3
    (st, c1 || c2 || c3)
end Frontend
