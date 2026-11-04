/-!
# MD5, for the distribution handshake digest only.
RFC 1321, over a `ByteArray`. The challenge digest is `md5(cookie ++ decimal challenge)`.
-/
namespace Frontier.Md5

private def S : Array UInt32 := #[7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
  5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20, 4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
  6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21]

private def K : Array UInt32 := Id.run do
  let mut k : Array UInt32 := #[]
  for i in [0:64] do
    -- floor(abs(sin(i+1)) * 2^32); Float.sin is exact enough for the table
    let v := Float.floor (Float.abs (Float.sin (Float.ofNat (i + 1))) * 4294967296.0)
    k := k.push (UInt32.ofNat v.toUInt64.toNat)
  return k

private def rotl (x : UInt32) (c : UInt32) : UInt32 := (x <<< c) ||| (x >>> (32 - c))

private def le32 (b : ByteArray) (i : Nat) : UInt32 :=
  (b.get! i).toUInt32 ||| ((b.get! (i+1)).toUInt32 <<< 8) ||| ((b.get! (i+2)).toUInt32 <<< 16) ||| ((b.get! (i+3)).toUInt32 <<< 24)

private def pushLe32 (b : ByteArray) (w : UInt32) : ByteArray :=
  b.push (w &&& 0xff).toUInt8 |>.push ((w >>> 8) &&& 0xff).toUInt8 |>.push ((w >>> 16) &&& 0xff).toUInt8 |>.push ((w >>> 24) &&& 0xff).toUInt8

def digest (msg : ByteArray) : ByteArray := Id.run do
  let bitLen : UInt64 := (msg.size * 8).toUInt64
  let mut m := msg.push 0x80
  while m.size % 64 != 56 do m := m.push 0
  for i in [0:8] do m := m.push ((bitLen >>> (8 * i).toUInt64) &&& 0xff).toUInt8
  let mut a0 : UInt32 := 0x67452301
  let mut b0 : UInt32 := 0xefcdab89
  let mut c0 : UInt32 := 0x98badcfe
  let mut d0 : UInt32 := 0x10325476
  for blk in [0:m.size / 64] do
    let base := blk * 64
    let mut a := a0; let mut b := b0; let mut c := c0; let mut d := d0
    for i in [0:64] do
      let (f, g) :=
        if i < 16 then ((b &&& c) ||| ((~~~b) &&& d), i)
        else if i < 32 then ((d &&& b) ||| ((~~~d) &&& c), (5*i + 1) % 16)
        else if i < 48 then (b ^^^ c ^^^ d, (3*i + 5) % 16)
        else (c ^^^ (b ||| (~~~d)), (7*i) % 16)
      let f2 := f + a + K[i]! + le32 m (base + 4*g)
      a := d; d := c; c := b
      b := b + rotl f2 S[i]!
    a0 := a0 + a; b0 := b0 + b; c0 := c0 + c; d0 := d0 + d
  return pushLe32 (pushLe32 (pushLe32 (pushLe32 ByteArray.empty a0) b0) c0) d0

def hex (b : ByteArray) : String :=
  String.join (b.toList.map fun x => let s := (Nat.toDigits 16 x.toNat); String.mk (if s.length == 1 then '0' :: s else s))

end Frontier.Md5
