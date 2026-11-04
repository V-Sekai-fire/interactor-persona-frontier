import Std.Async.TCP
import Frontier.Md5
import Frontier.Etf
/-!
# An Erlang distribution node (a hidden C node), in Lean.

Registers with EPMD on 4369 as a hidden node, accepts one peer at a time on `--dist-port`, runs
the version-6 handshake (`N` name, `s` ok, `N` challenge, `r` reply, `a` ack; the digest is
`md5(cookie ++ decimal challenge)`), then answers REG_SEND messages to the registered name
`frontier`: a `{from_pid, text}` tuple comes in, the answer goes back to `from_pid` as a binary
with a SEND control message. Ticks (empty frames) are answered with ticks. Distribution header
atom caches are not negotiated, so every term arrives as plain pass-through (`112`).

    iex --name a@127.0.0.1 --cookie <cookie>
    Node.connect(:"frontier@127.0.0.1")
    send({:frontier, :"frontier@127.0.0.1"}, {self(), "world"}); flush()
-/
namespace Frontier.Dist

open Std Async TCP Etf

structure Config where
  name : String := "frontier"
  host : String := "127.0.0.1"
  ip : Net.IPv4Addr := Net.IPv4Addr.ofParts 127 0 0 1
  port : UInt16 := 9930
  cookie : String

def fullName (c : Config) : String := s!"{c.name}@{c.host}"

-- DFLAG_EXTENDED_REFERENCES 4 · FUN_TAGS 0x10 · NEW_FUN_TAGS 0x80 · EXTENDED_PIDS_PORTS 0x100 ·
-- EXPORT_PTR_TAG 0x200 · BIT_BINARIES 0x400 · NEW_FLOATS 0x800 · UTF8_ATOMS 0x10000 · MAP_TAG 0x20000 ·
-- BIG_CREATION 0x40000 · HANDSHAKE_23 0x1000000 · UNLINK_ID 0x2000000 · V4_NC 1<<34 · MANDATORY_25_DIGEST 1<<36
def flags : UInt64 :=
  [4, 0x10, 0x80, 0x100, 0x200, 0x400, 0x800, 0x10000, 0x20000, 0x40000, 0x1000000, 0x2000000, 2^34, 2^36].foldl (fun (a : UInt64) (n : Nat) => a ||| n.toUInt64) 0

def push64 (b : ByteArray) (n : UInt64) : ByteArray :=
  (List.range 8).foldl (fun a i => a.push ((n >>> (8 * (7 - i)).toUInt64) &&& 0xff).toUInt8) b

def loopback : Net.IPv4Addr := Net.IPv4Addr.ofParts 127 0 0 1

/-- Read exactly `n` bytes. -/
partial def recvExact (s : Socket.Client) (n : Nat) (acc : ByteArray := .empty) : Async ByteArray := do
  if acc.size >= n then return acc
  match ← s.recv? (n - acc.size).toUInt64 with
  | some d => if d.size == 0 then throw (IO.userError "peer closed") else recvExact s n (acc ++ d)
  | none => throw (IO.userError "peer closed")

def recvFrame (s : Socket.Client) (lenBytes : Nat) : Async ByteArray := do
  let hdr ← recvExact s lenBytes
  let n := if lenBytes == 2 then be16 hdr 0 else be32 hdr 0
  if n == 0 then return .empty
  recvExact s n

def sendFrame (s : Socket.Client) (lenBytes : Nat) (body : ByteArray) : Async Unit :=
  s.send ((if lenBytes == 2 then push16 .empty body.size else push32 .empty body.size) ++ body)

/-- ALIVE2_REQ to EPMD; the socket stays open for as long as the node is registered. -/
def registerEpmd (c : Config) : Async (Socket.Client × Nat) := do
  let s ← Socket.Client.mk
  s.connect (.v4 ⟨loopback, 4369⟩)
  let name := c.name.toUTF8
  let req := (push16 (ByteArray.empty.push 120) c.port.toNat).push 72 |>.push 0 |> (push16 · 6) |> (push16 · 6) |> (push16 · name.size)
  sendFrame s 2 (req ++ name ++ push16 .empty 0)
  let resp ← recvExact s 2
  if resp.get! 0 != 118 then throw (IO.userError s!"epmd: tag {resp.get! 0}")
  if resp.get! 1 != 0 then throw (IO.userError s!"epmd: result {resp.get! 1}")
  let creation ← recvExact s 4
  return (s, be32 creation 0)

def digest (cookie : String) (challenge : Nat) : ByteArray := Md5.digest (cookie ++ toString challenge).toUTF8

/-- The accepting side of the version-6 handshake. Returns the peer's node name. -/
def handshake (c : Config) (creation : Nat) (s : Socket.Client) : Async String := do
  let m ← recvFrame s 2
  if m.get! 0 != (78 : UInt8) then throw (IO.userError s!"handshake: expected N, got {m.get! 0}")
  let nlen := be16 m 13
  let peer := String.fromUTF8! (slice m 15 nlen)
  sendFrame s 2 ("sok".toUTF8)
  let ours := (← IO.rand 1 0xfffffffe)
  let name := (fullName c).toUTF8
  sendFrame s 2 ((push32 (push32 (push64 (ByteArray.empty.push 78) flags) ours) creation |> (push16 · name.size)) ++ name)
  let r ← recvFrame s 2
  if r.get! 0 != (114 : UInt8) then throw (IO.userError "handshake: expected r")
  let theirs := be32 r 1
  if slice r 5 16 != digest c.cookie ours then throw (IO.userError "handshake: bad cookie digest")
  sendFrame s 2 (ByteArray.empty.push 97 ++ digest c.cookie theirs)
  return peer

/-- Serve one connected peer: ticks, and REG_SEND to our name answered with SEND. -/
partial def serve (answer : String → IO String) (c : Config) (s : Socket.Client) : Async Unit := do
  let frame ← recvFrame s 4
  if frame.size == 0 then
    s.send (push32 .empty 0)
    return ← serve answer c s
  if frame.get! 0 != 112 then return ← serve answer c s
  match unpack frame 1 with
  | .error e => IO.eprintln s!"dist: {e}"
  | .ok (ctrl, j) =>
    match ctrl with
    | .tuple #[.int 6, _sender, _, .atom to] =>
      if to == c.name then
        match unpack frame j with
        | .ok (.tuple #[reply, msg], _) =>
          let text := (msg.text?).getD ""
          let out ← answer text
          let ctrl := pack (.tuple #[.int 2, .atom "", reply])
          let payload := pack (.bin out.toUTF8)
          s.send (push32 .empty (1 + ctrl.size + payload.size) ++ ByteArray.empty.push 112 ++ ctrl ++ payload)
        | .ok (msg, _) => IO.eprintln s!"dist: message to {to} is not a sender-text tuple: {msg}"
        | .error e => IO.eprintln s!"dist: {e}"
      else IO.eprintln s!"dist: no process named {to}"
    | _ => pure ()
  serve answer c s

/-- The EPMD connection must stay open for as long as the node is registered: EPMD drops the
name when the socket closes, so the handle lives here, never in a local that is freed. -/
initialize epmdSocket : IO.Ref (Option Socket.Client) ← IO.mkRef none

/-- Register with EPMD, then accept peers until the process is stopped. -/
partial def run (answer : String → IO String) (c : Config) : Async Unit := do
  let (epmd, creation) ← registerEpmd c
  epmdSocket.set (some epmd)
  let srv ← Socket.Server.mk
  srv.bind (.v4 ⟨c.ip, c.port⟩)
  srv.listen 8
  IO.println s!"dist: {fullName c} on {c.host}:{c.port}, creation {creation}, registered with epmd"
  (← IO.getStdout).flush
  let rec accept : Async Unit := do
    let peer ← srv.accept
    try
      let who ← handshake c creation peer
      IO.println s!"dist: {who} connected"
      serve answer c peer
    catch e => IO.eprintln s!"dist: {e}"
    accept
  accept

end Frontier.Dist
