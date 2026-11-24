-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: Apache-2.0 OR MIT
import Lean.Data.Json
import Frontier.PlanPackets
/-! `frontier_packets STEPS.json OUT.bin`: encode a plan's steps as 100-byte entity packets, decode them back and check. -/
open Lean Frontier.PlanPackets EntityPacket

def natOf (j : Json) (k : String) : Nat := ((j.getObjVal? k).toOption >>= (·.getNat?.toOption)).getD 0
def strOf (j : Json) (k : String) : String := ((j.getObjVal? k).toOption >>= (·.getStr?.toOption)).getD ""
def argsOf (j : Json) : List UInt32 :=
  match j.getObjVal? "args" with
  | .ok (.arr a) => a.toList.map fun x => UInt32.ofNat (x.getNat?.toOption.getD 0)
  | _ => []

def hex (b : Bytes) : String :=
  String.join (b.toList.map fun x => (if x.toNat < 16 then "0" else "") ++ String.ofList (Nat.toDigits 16 x.toNat))

structure Emitted where
  packets : Array (String × Bytes) := #[]
  failures : Array String := #[]

def Emitted.add (o : Emitted) (tag : String) (b : Bytes) : Emitted := { o with packets := o.packets.push (tag, b) }
def Emitted.fail (o : Emitted) (why : String) : Emitted := { o with failures := o.failures.push why }

def commandOf (seq : UInt32) (j : Json) (cmd : Cmd) (ms : Nat) (args : List UInt32) : Frontier.PlanPackets.Command :=
  { seq, owner := UInt32.ofNat (natOf j "actor"), ms, counter := seq.toNat % 65536, cmd, args }

def pushCommand (o : Emitted) (c : Frontier.PlanPackets.Command) : Emitted :=
  match encodeCommand c with
  | none => o.fail s!"command {c.seq} does not encode"
  | some b => if decodeCommand b == some c then o.add "C" b else o.fail s!"command {c.seq} does not roundtrip"

def pushKeys (o : Emitted) (hop : Hop) : Emitted := Id.run do
  let mut o := o
  let ks := keyframes hop
  let mut prev : Option (Key × Bytes) := none
  for k in ks do
    let seq := UInt32.ofNat o.packets.size
    match statePacket seq hop.actor (o.packets.size % 65536) hop k with
    | none => o := o.fail s!"state {seq} does not encode"
    | some b =>
      if !stateMatches b k then o := o.fail s!"state {seq} does not match its keyframe"
      match prev with
      | some (pk, pb) => if rampOf hop > 0 && !segmentConsistent pb b (k.tick - pk.tick) then o := o.fail s!"state {seq}: speed and distance disagree"
      | none => pure ()
      o := o.add "S" b
      prev := some (k, b)
  return o

def pushStep (o : Emitted) (j : Json) : Emitted :=
  let seq := UInt32.ofNat o.packets.size
  match strOf j "kind" with
  | "move" =>
    let hop : Hop := { actor := UInt32.ofNat (natOf j "actor"), departMs := natOf j "depart_ms", ticks := natOf j "ticks",
                       rampTicks := natOf j "ramp_ticks", lengthUm := natOf j "length_um", arcUm := natOf j "arc_um" }
    let args := [natOf j "from", natOf j "to", hop.ticks, rampOf hop, hop.lengthUm].map UInt32.ofNat
    pushKeys (pushCommand o (commandOf seq j .move hop.departMs args)) hop
  | "scout" => pushCommand o (commandOf seq j .scout (natOf j "ms") (argsOf j))
  | "duty" => pushCommand o (commandOf seq j .duty (natOf j "ms") (argsOf j))
  | "equip" => pushCommand o (commandOf seq j .equip (natOf j "ms") (argsOf j))
  | other => o.fail s!"unknown step kind {other}"

def main (args : List String) : IO UInt32 := do
  match args with
  | [input, output] =>
    let text ← IO.FS.readFile input
    match Json.parse text with
    | .error e => IO.eprintln s!"FAILED input: {e}"; return 1
    | .ok j =>
      let steps := ((j.getObjVal? "steps").toOption.bind (·.getArr?.toOption)).getD #[]
      let o := steps.foldl pushStep {}
      IO.FS.writeBinFile output (ByteArray.mk (o.packets.foldl (fun acc (_, b) => acc ++ b) #[]))
      for (tag, b) in o.packets do IO.println s!"{tag} {hex b}"
      if o.failures.isEmpty then
        IO.println s!"OK packets={o.packets.size} commands={(o.packets.filter (·.1 == "C")).size} states={(o.packets.filter (·.1 == "S")).size}"
        return 0
      else
        for f in o.failures do IO.eprintln s!"FAILED {f}"
        return 1
  | _ => IO.eprintln "usage: frontier_packets STEPS.json OUT.bin"; return 2
