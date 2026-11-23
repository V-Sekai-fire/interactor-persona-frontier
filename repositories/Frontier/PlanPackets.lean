import Lean.Data.Json
import EntityPacket.Codec
import EntityPacket.Classes
import EntityPacket.Hlc
/-!
# A Party Saga plan as entity packets.
Commands are `command` class packets (a call that fits in one packet); each move also gives `persona` state packets
at the keyframes of its speed profile, so a receiver can dead-reckon between them. Everything is integral. The tick
rate is 64 Hz: one model second is 64 ticks, and one map length unit is one metre (1 000 000 um).
-/
namespace Frontier.PlanPackets
open Lean EntityPacket

def TICKS_PER_SECOND : Nat := 64
def UM_PER_UNIT : Nat := 1000000
def tickMs (k : Nat) : Nat := k * 1000 / TICKS_PER_SECOND

def RUN_A_OFF : Nat := OFF_POS
def RUN_A_LEN : Nat := OFF_HLC - OFF_POS
def RUN_B_OFF : Nat := OFF_ROT
def RUN_B_LEN : Nat := OFF_RESERVED - OFF_ROT
def RUN_LEN : Nat := RUN_A_LEN + RUN_B_LEN

inductive Cmd where
  | move | scout | duty | equip
  deriving DecidableEq, Repr

def Cmd.toType : Cmd → UInt32
  | .move => 1 | .scout => 2 | .duty => 3 | .equip => 4

def Cmd.ofType? : UInt32 → Option Cmd
  | 1 => some .move | 2 => some .scout | 3 => some .duty | 4 => some .equip | _ => none

structure Command where
  seq : UInt32
  owner : UInt32
  ms : Nat
  counter : Nat
  cmd : Cmd
  args : List UInt32
  deriving Repr, BEq

def runOffset (i : Nat) : Nat := if i < RUN_A_LEN then RUN_A_OFF + i else RUN_B_OFF + (i - RUN_A_LEN)

def wordBytes (a : UInt32) : List UInt8 :=
  [a.toUInt8, (a >>> 8).toUInt8, (a >>> 16).toUInt8, (a >>> 24).toUInt8]

def encodeCommand (c : Command) : Option Bytes := do
  let used := 4 * c.args.length
  if RUN_LEN < used then none
  let co ← classOwner .command c.owner
  let run := (c.args.flatMap wordBytes).toArray
  let mut b : Bytes := Array.replicate SIZE 0
  b := putU32 b OFF_GID c.seq
  b := putU64 b OFF_HLC (Hlc.pack ⟨c.ms, c.counter⟩)
  b := putU32 b OFF_CLASS_OWNER co
  b := putU32 b OFF_SUB_INDEX ((UInt32.ofNat used <<< 16) ||| c.cmd.toType)
  for i in [0:used] do
    b := b.set! (runOffset i) run[i]!
  return b

def decodeCommand (b : Bytes) : Option Command := do
  let (cls, owner) ← splitClassOwner (getU32 b OFF_CLASS_OWNER)
  if cls != .command then none
  let sub := getU32 b OFF_SUB_INDEX
  let used := (sub >>> 16).toNat
  let cmd ← Cmd.ofType? (sub &&& 0xFFFF)
  if RUN_LEN < used || used % 4 != 0 then none
  let byteAt (i : Nat) : UInt32 := (b[runOffset i]!).toUInt32
  let word (k : Nat) : UInt32 :=
    byteAt (4 * k) ||| (byteAt (4 * k + 1) <<< 8) ||| (byteAt (4 * k + 2) <<< 16) ||| (byteAt (4 * k + 3) <<< 24)
  let h := Hlc.unpack (getU64 b OFF_HLC)
  some { seq := getU32 b OFF_GID, owner, ms := h.l, counter := h.c, cmd, args := (List.range (used / 4)).map word }

/-- The Int16 velocity code, to nearest: the scale is `V_MAX_UM_PER_TICK` at 32767. -/
def velCode (v : Int) : Int16 :=
  let m := min 32767 ((v.natAbs * 32767 + V_MAX_UM_PER_TICK / 2) / V_MAX_UM_PER_TICK)
  Int16.ofInt (if v < 0 then -(Int.ofNat m) else Int.ofNat m)

def velOfCode (c : Int16) : Int := c.toInt * Int.ofNat V_MAX_UM_PER_TICK / 32767

/-- One leg between two nodes: `ticks` long, speeding up and slowing down over at most `rampTicks` each, `lengthUm` long,
starting at arc coordinate `arcUm`. -/
structure Hop where
  actor : UInt32
  departMs : Nat
  ticks : Nat
  rampTicks : Nat
  lengthUm : Nat
  arcUm : Nat
  deriving Repr

structure Key where
  tick : Nat
  posUm : Nat
  velUm : Nat
  accUm : Int
  deriving Repr

def rampOf (h : Hop) : Nat := min h.rampTicks (h.ticks / 2)

/-- The keyframes of the speed profile, in whole numbers. With `a` the ramp and `N` the ticks, the distance covered
by tick `k` is `D * G k / (2a(N-a))`, the speed `D * min(k, a, N-k) / (a(N-a))`, the acceleration `+-D / (a(N-a))`. -/
def keyframes (h : Hop) : List Key :=
  let n := h.ticks
  let a := rampOf h
  if a == 0 then [⟨0, h.arcUm, 0, 0⟩, ⟨n, h.arcUm + h.lengthUm, 0, 0⟩]
  else
    let den := a * (n - a)
    let g (k : Nat) : Nat :=
      if k ≤ a then k * k else if k ≤ n - a then a * (2 * k - a) else 2 * a * (n - a) - (n - k) * (n - k)
    let acc : Int := Int.ofNat ((h.lengthUm + den - 1) / den)
    let frame (k : Nat) : Key :=
      { tick := k, posUm := h.arcUm + h.lengthUm * g k / (2 * den), velUm := h.lengthUm * (min k (min a (n - k))) / den,
        accUm := if k < a then acc else if k < n - a then 0 else if k < n then -acc else 0 }
    ([0, a, n - a, n].eraseDups).map frame

def statePacket (seq : UInt32) (actor : UInt32) (counter : Nat) (h : Hop) (k : Key) : Option Bytes := do
  let co ← classOwner .persona actor
  let p : Packet :=
    { gid := seq, posUm := (Int64.ofInt (Int.ofNat k.posUm), 0, 0), vel := (velCode k.velUm, 0, 0),
      accel := (accelCodeUp k.accUm, 0, 0), hlc := Hlc.pack ⟨h.departMs + tickMs k.tick, counter⟩, classOwner := co,
      subIndex := 0, rot := (0, 0, 0), payload := Array.replicate PAYLOAD_LEN 0 }
  return encode p

/-- A state packet agrees with its keyframe: position exactly, velocity and acceleration up to their codes. -/
def stateMatches (b : Bytes) (k : Key) : Bool :=
  let p := decode b
  p.posUm.1.toInt == Int.ofNat k.posUm && p.vel.1 == velCode k.velUm && p.accel.1 == accelCodeUp k.accUm

/-- Between two keyframes the speed is linear, so the distance is the mean speed times the ticks, up to the rounding of the codes. -/
def segmentConsistent (a b : Bytes) (dk : Nat) : Bool :=
  let pa := decode a
  let pb := decode b
  let dpos := pb.posUm.1.toInt - pa.posUm.1.toInt
  let mean := (velOfCode pa.vel.1 + velOfCode pb.vel.1) * Int.ofNat dk / 2
  (dpos - mean).natAbs ≤ dk * 16 + 4

end Frontier.PlanPackets
