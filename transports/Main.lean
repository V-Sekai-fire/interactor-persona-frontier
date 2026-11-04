import Std.Http
import Frontier.Loop
import Frontier.Dist
/-!
# frontier: the $12-server build.

One process, one box, no dependencies beyond SQLite: the planner is a library, the store is
SQLite (pages in FoundationDB when datasource-store's VFS is loaded), the HTTP/1.1 A2A server
is `Std.Http`, and the Erlang node is `Frontier.Dist`. The challenge (Arjay McCandless, "How Many
Users Can a $12 Server Handle?"): 1 vCPU, 2 GB, everything on the machine, k6 virtual users until
p95 passes 500 ms, p99 passes 1 s or more than 1 % of requests fail.

    elixir build.exs                                              one command: deps, lake build, witness, PropCheck
    frontier --port 9920 --dist-port 9930 --cookie <cookie>      (or --cookie-file <path>; --host 0.0.0.0 in a container, --node-host <addr peers dial>)

The box is DigitalOcean's `s-1vcpu-2gb` Basic Droplet ($12.00/mo, $0.01786/hr), and one box is one cell:
FoundationDB, epmd and this node colocated in one pod with constant shares (`deploy/pod.exs up|smoke|down`).
More capacity is more cells. `deploy/cloud-init.yaml` builds the box.

| Route | Answer |
| --- | --- |
| `GET /.well-known/agent-card.json` | the Agent Card |
| `POST /` A2A `message/send` | the plan to the goal in the text part, or a refusal by name |
| `GET /frontier` | the levels, the next level to practise, the revision |
| `POST /practice` | one frontier cycle |
| `POST /experience` | an experience report from a real stage run |
| `POST /learn` | fold experience into knowledge through the gate |

The same six answers over the Erlang node, as message text: a goal, `frontier`, `practice`,
`learn`, or `experience {json}`.
-/
open Lean Std Http Async Frontier

def card (url : String) : Json :=
  Json.mkObj [("name", "persona-frontier"), ("version", "0.2.0"), ("url", url), ("protocolVersion", "1.0"),
    ("description", "Which stage of your character, prop or world comes next, and what does it need first? An exact plan from a planning domain that learns from experience."),
    ("capabilities", Json.mkObj [("streaming", false), ("pushNotifications", false)]),
    ("defaultInputModes", Json.arr #["text/plain"]), ("defaultOutputModes", Json.arr #["application/json"]),
    ("skills", Json.arr #[Json.mkObj [("id", "plan"), ("name", "Plan to a stage"), ("tags", Json.arr #["planning", "taskweft", "frontier"]),
      ("description", "Send a goal as text: reach-<subject>-N (character, prop, world), a subject alone, a stage name alone, or empty."),
      ("examples", Json.arr #["reach-character-10", "world", "prop 7", "garments"])]])]

/-- Every command, one function, so HTTP and the Erlang node answer alike. -/
def command (text : String) : IO Json := do
  let k ← Db.knowledge
  let t := text.trimAscii.toString
  if t == "frontier" then
    return Json.mkObj [("levels", Json.arr ((← Loop.levels k).map (·.toJson)).toArray), ("next", ((← Loop.nextLevel k).map (·.toJson)).getD .null), ("revision", field k "revision")]
  else if t == "practice" then Loop.practice k
  else if t == "learn" then Loop.learn k
  else if t.startsWith "experience " then
    match Json.parse (Loop.dropN t 11) with
    | .ok r => Loop.experience r
    | .error _ => return Json.mkObj [("refused", "bad_experience")]
  else
    let a := Loop.answer k t
    Loop.record (Json.mkObj [("kind", "request"), ("text", t), ("reached", Loop.reached a), ("refused", field a "refused")])
    return a

def rpc (body : String) : IO Json := do
  let err (id : Json) (code : Int) (msg : String) : Json := Json.mkObj [("jsonrpc", "2.0"), ("id", id), ("error", Json.mkObj [("code", code), ("message", msg)])]
  match Json.parse body with
  | .error _ => return err .null (-32700) "parse error"
  | .ok j =>
    let id := field j "id"
    let m := str (field j "method")
    if m == "message/send" || m == "SendMessage" then
      let parts := ((field (field (field j "params") "message") "parts").getArr?.toOption.getD #[]).toList
      match parts.findSome? fun p => (field p "text").getStr?.toOption with
      | none => return err id (-32602) "message has no text part"
      | some text =>
        let a ← command text
        return Json.mkObj [("jsonrpc", "2.0"), ("id", id), ("result", Json.mkObj [("message", Json.mkObj [("messageId", Json.str s!"a2a-{id.compress}"), ("role", "ROLE_AGENT"), ("parts", Json.arr #[Json.mkObj [("text", a.compress)]])])])]
    else if ["GetTask", "CancelTask", "tasks/get", "tasks/cancel"].contains m then return err id (-32001) "the persona keeps no task"
    else if ["SendStreamingMessage", "SubscribeToTask", "message/stream"].contains m then return err id (-32004) "nothing to stream"
    else return err id (-32601) "method not found"

def route (method path body url : String) : IO (Nat × Json) := do
  match method, path with
  | "GET", "/.well-known/agent-card.json" => pure (200, card url)
  | "POST", "/" => pure (200, ← rpc body)
  | "GET", "/frontier" => pure (200, ← command "frontier")
  | "POST", "/practice" => pure (200, ← command "practice")
  | "POST", "/experience" => pure (200, ← command s!"experience {body}")
  | "POST", "/learn" => pure (200, ← command "learn")
  | _, _ => pure (404, Json.mkObj [("error", "not found")])

def handler (url : String) : Server.StatelessHandler where
  onRequest req := do
    let body ← if req.line.method == .post then req.body.readAll (maximumSize := some 1048576) else pure ""
    let method := match req.line.method with | .get => "GET" | .post => "POST" | _ => "OTHER"
    let path := match req.line.uri with | .originForm p _ => toString p | _ => ""
    let (code, json) ← try route method path body url catch e => pure (500, Json.mkObj [("error", toString e)])
    let status : Status := if code == 200 then .ok else if code == 404 then .notFound else .internalServerError
    (Response.withStatus status).json json.compress

def parseIPv4 (s : String) : Option Std.Net.IPv4Addr :=
  match (s.splitOn ".").map String.toNat? with
  | [some a, some b, some c, some d] => if a < 256 && b < 256 && c < 256 && d < 256 then some (Std.Net.IPv4Addr.ofParts a.toUInt8 b.toUInt8 c.toUInt8 d.toUInt8) else none
  | _ => none

def option (args : List String) (flag : String) : Option String :=
  match args.dropWhile (· != flag) with | _ :: v :: _ => some v | _ => none

def main (args : List String) : IO UInt32 := do
  let host := (option args "--host").getD "127.0.0.1"
  let some ip := parseIPv4 host | IO.eprintln s!"frontier: --host must be an IPv4 address, got '{host}'"; return 2
  let port := ((option args "--port").bind String.toNat?).getD 9920
  let distPort := ((option args "--dist-port").bind String.toNat?).getD 9930
  let cookie ← match option args "--cookie", option args "--cookie-file" with
    | some c, _ => pure c
    | none, some f => pure (← IO.FS.readFile f).trimAscii.toString
    | none, none => do
      let home := (← IO.getEnv "HOME").getD "."
      let p : System.FilePath := home / ".erlang.cookie"
      if ← p.pathExists then pure (← IO.FS.readFile p).trimAscii.toString else pure "frontier"
  Db.init
  let _ ← Db.knowledge
  let url := s!"http://{host}:{port}/"
  IO.println s!"frontier on {url} (HTTP/1.1), db {← Db.url}"
  (← IO.getStdout).flush
  let answer (t : String) : IO String := do return (← command t).compress
  -- the node's name carries the address a peer dials, which is not the bind address in a container
  let nodeHost := (option args "--node-host").getD (if host == "0.0.0.0" then "127.0.0.1" else host)
  let _ ← IO.asTask (Async.block (Dist.run answer { host := nodeHost, ip, port := distPort.toUInt16, cookie }))
  Async.block do
    let server ← Server.serve (.v4 ⟨ip, port.toUInt16⟩) (handler url) { maxBodySize := 1048576 }
    server.waitShutdown
  return 0
