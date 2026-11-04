# Token inventory

The ledger's rule: a token is a substrate, the thing a failure takes down with it, not a feature. The org spends two innovation tokens: guest ELFs on the pinned double engine (Token 1) and one store, SQLite with its pages in FoundationDB (Token 2). Boring technology is `Stock` or `Already paid`; a capability is what the server lets a caller do and what guards it. One row per substrate or capability in this repository.

## Innovation tokens

| Row | Substrate | Status | Why, and what fails with it |
| --- | --- | --- | --- |
| Store | SQLite through `c/sql.c`; pages in FoundationDB when `FRONTIER_VFS_EXT` loads datasource-store's `libweftfdb` | Token 2 | The one store. Traces and knowledge live there; the knowledge seed is the only thing that survives it. |
| Planner | `interactor-taskweft-persona` (RECTGTN over JSON-LD) as a Lean library | Already paid | The same Lean toolchain and planner Token 1's guests pay for; here as a host library, no guest ELF. |
| Erlang node in Lean | `Frontier/Dist.lean`: EPMD ALIVE2, the v6 handshake, pass-through ETF, REG_SEND in, SEND out | **Not spent, and the ledger has no third token** | A hand-rolled distribution peer. Its failure takes down every Elixir caller of the node. The boring substitute is a BEAM-side port or `erl_interface` C node; this row is the one to retire or to claim against a token before a rung pins it. |
| MD5 in Lean | `Frontier/Md5.lean`, for the handshake digest only | Not spent (part of the row above) | Dies with the Erlang-node row. A shim over libcrypto is the stock route if the row stays. |
| HTTP server | `Std.Http` from the Lean toolchain | Already paid | The A2A library already serves on it. |

## Boring technology

| Row | What | Status | Notes |
| --- | --- | --- | --- |
| BEAM | Elixir for `build.exs`, PropCheck/PropEr in `test/node` | Stock | Tools and gates only; nothing ships into the product. |
| epmd | Erlang's port mapper, from the Erlang install | Stock | The node registers with it; the container starts it. |
| SQLite | libsqlite3 from Homebrew or the distro | Stock | Linked by the shim. |
| C | one 60-line shim (`c/sql.c`) | Stock | Where a C ABI is unavoidable. |
| elan, lake | Lean toolchain management, pinned by `lean-toolchain` | Already paid | |
| k6 | `deploy/k6.js`, the challenge's thresholds | Stock | The measurement tool, not shipped. |
| cloud-init, systemd | `deploy/cloud-init.yaml` | Stock | |
| AlmaLinux 10 container | `Containerfile`, two stages | Stock | |
| DigitalOcean `s-1vcpu-2gb` | the box, $12.00/mo | Stock | A supplier, not a substrate. |
| GitHub Actions | `.github/workflows/node.yml` | Stock | Blocked by billing on this private repo. |
| JSON-LD | the domain, problem and plan documents | Already paid | The persona's own interchange. |

## Capabilities

| Capability | Surface | Guard | Who holds it |
| --- | --- | --- | --- |
| Plan a goal | `POST /` A2A `message/send`; node text | Loopback bind by default; `--host 0.0.0.0` only in the container; no bearer token yet | Anyone who reaches the socket |
| Read the frontier | `GET /frontier`; node text `frontier` | Same as above | Same |
| Practise a level | `POST /practice`; node text `practice` | Same; writes a trace | Same |
| Report experience | `POST /experience`; node text `experience {json}` | Same; writes a trace; the only path truth enters by | Same, and it should be the owning repository's CI |
| Learn | `POST /learn`; node text `learn` | The gate: positive and negative control; writes knowledge, domain and gold plan | Same |
| Erlang peer | `Node.connect`, `send({:frontier, node}, {pid, text})` | The distribution cookie (`--cookie`, `--cookie-file`, `~/.erlang.cookie`) | Any node holding the cookie |
| Store access | `FRONTIER_DB`, `FRONTIER_VFS_EXT`, `WEFT_FDB_CLUSTER_FILE` | Process environment; the FDB cluster file | The process |

Three capability gaps: HTTP has no bearer token (the A2A library had one; this server dropped it), every HTTP caller can write traces and trigger learning, and the Erlang cookie is the only credential on the node side.
