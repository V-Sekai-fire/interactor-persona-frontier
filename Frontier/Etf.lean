/-!
# External Term Format, the few terms a `{from, text}` message needs.
Decoded: small/large tuple, list, nil, atoms (UTF-8, old, small), binaries, small and 32-bit
integers, pids (NEW_PID and PID_EXT, kept as raw bytes so a reply can address them). Encoded:
tuple, atom, binary, small integer, nil, and a raw pid. Everything else decodes as `other` with
its bytes, which is enough to skip it.
-/
namespace Frontier.Etf


inductive Term where
  | atom (name : String)
  | int (n : Int)
  | bin (bytes : ByteArray)
  | tuple (xs : Array Term)
  | list (xs : Array Term)
  | nil
  | pid (raw : ByteArray)
  | other (tag : UInt8) (raw : ByteArray)
  deriving Inhabited

partial def Term.show : Term → String
  | .atom s => s!"'{s}'"
  | .int n => toString n
  | .bin b => s!"<<{b.size} bytes>>"
  | .tuple xs => "{" ++ ", ".intercalate (xs.toList.map Term.show) ++ "}"
  | .list xs => "[" ++ ", ".intercalate (xs.toList.map Term.show) ++ "]"
  | .nil => "[]"
  | .pid r => s!"#PID<{r.size}>"
  | .other t r => s!"#other<{t},{r.size}>"

instance : ToString Term := ⟨Term.show⟩
instance : Repr Term := ⟨fun t _ => Term.show t⟩

def be16 (b : ByteArray) (i : Nat) : Nat := (b.get! i).toNat * 256 + (b.get! (i+1)).toNat
def be32 (b : ByteArray) (i : Nat) : Nat := be16 b i * 65536 + be16 b (i+2)
def push16 (b : ByteArray) (n : Nat) : ByteArray := b.push (n / 256).toUInt8 |>.push (n % 256).toUInt8
def push32 (b : ByteArray) (n : Nat) : ByteArray := push16 (push16 b (n / 65536)) (n % 65536)
def slice (b : ByteArray) (i n : Nat) : ByteArray := b.extract i (i + n)

/-- Decode one term at `i`; returns the term and the offset after it. -/
partial def decode (b : ByteArray) (i : Nat) : Except String (Term × Nat) := do
  if i >= b.size then throw "etf: truncated"
  let tag := b.get! i
  match tag with
  | 97 => pure (.int (b.get! (i+1)).toNat, i + 2)
  | 98 =>
    let u := be32 b (i+1)
    pure (.int (if u >= 2^31 then (u : Int) - 2^32 else u), i + 5)
  | 106 => pure (.nil, i + 1)
  | 100 => let n := be16 b (i+1); pure (.atom (String.fromUTF8! (slice b (i+3) n)), i + 3 + n)
  | 118 => let n := be16 b (i+1); pure (.atom (String.fromUTF8! (slice b (i+3) n)), i + 3 + n)
  | 119 => let n := (b.get! (i+1)).toNat; pure (.atom (String.fromUTF8! (slice b (i+2) n)), i + 2 + n)
  | 109 => let n := be32 b (i+1); pure (.bin (slice b (i+5) n), i + 5 + n)
  | 104 | 105 =>
    let (n, j) := if tag == 104 then ((b.get! (i+1)).toNat, i + 2) else (be32 b (i+1), i + 5)
    let mut xs : Array Term := #[]
    let mut k := j
    for _ in [0:n] do
      let (t, k') ← decode b k
      xs := xs.push t; k := k'
    pure (.tuple xs, k)
  | 108 =>
    let n := be32 b (i+1)
    let mut xs : Array Term := #[]
    let mut k := i + 5
    for _ in [0:n] do
      let (t, k') ← decode b k
      xs := xs.push t; k := k'
    let (_, k'') ← decode b k  -- the tail
    pure (.list xs, k'')
  | 88 | 103 =>
    let (_, j) ← decode b (i+1)  -- node atom
    let k := j + 8 + (if tag == 88 then 4 else 1)
    pure (.pid (slice b i (k - i)), k)
  | 107 => let n := be16 b (i+1); pure (.other tag (slice b i (3 + n)), i + 3 + n)
  | _ => throw s!"etf: tag {tag} not handled"

partial def encode (t : Term) (acc : ByteArray := .empty) : ByteArray :=
  match t with
  | .atom s => let u := s.toUTF8; (acc.push 119 |>.push u.size.toUInt8) ++ u
  | .int n => if 0 ≤ n && n < 256 then acc.push 97 |>.push n.toNat.toUInt8 else push32 (acc.push 98) ((n % 2^32).toNat)
  | .bin b => push32 (acc.push 109) b.size ++ b
  | .nil => acc.push 106
  | .tuple xs => xs.foldl (fun a x => encode x a) (acc.push 104 |>.push xs.size.toUInt8)
  | .list xs => (xs.foldl (fun a x => encode x a) (push32 (acc.push 108) xs.size)).push 106
  | .pid raw => acc ++ raw
  | .other _ raw => acc ++ raw

/-- A whole term with the 131 version byte. -/
def pack (t : Term) : ByteArray := encode t (ByteArray.empty.push 131)

def unpack (b : ByteArray) (i : Nat) : Except String (Term × Nat) :=
  if b.get! i == 131 then decode b (i+1) else throw "etf: no version byte"

def Term.text? : Term → Option String
  | .bin b => String.fromUTF8? b
  | .atom s => some s
  | .list xs => some (String.mk (xs.toList.filterMap fun | .int n => Char.ofNat n.toNat | _ => none))
  | .nil => some ""
  | _ => none

end Frontier.Etf
