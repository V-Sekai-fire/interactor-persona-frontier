#!/usr/bin/env nu
# One command, no arguments: a fresh clone builds the node and its gates and runs them.
#   nu build.nu
# Installs what is missing through brew (macOS) or apt (Debian/Ubuntu): elan (the Lean toolchain
# named in lean-toolchain), SQLite headers, Erlang and Elixir. Then: lake build, the Lean witness,
# the PropCheck suite against a node started on scratch ports with its own SQLite file.
# FoundationDB is not installed here; the FDB-backed run is deploy/cloud-init.yaml and
# .github/workflows/node.yml. Exit code is non-zero on the first failing step.

def need [cmd: string, brew_pkg: string, apt_pkg: string] {
  if (which $cmd | is-empty) {
    print $"installing ($cmd)"
    if $nu.os-info.name == "macos" { brew install $brew_pkg } else { sudo apt-get install -y $apt_pkg }
  }
}

def main [] {
  cd ($env.FILE_PWD? | default (pwd))

  # 1. dependencies
  if (which elan | is-empty) {
    print "installing elan"
    curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
    $env.PATH = ($env.PATH | prepend $"($env.HOME)/.elan/bin")
  }
  need sqlite3 sqlite libsqlite3-dev
  need erl erlang erlang-dev
  need epmd erlang erlang-epmd
  need elixir elixir elixir
  need cc gcc build-essential
  if $nu.os-info.name == "macos" and not ("/opt/homebrew/opt/sqlite/include/sqlite3.h" | path exists) { brew install sqlite }
  if $nu.os-info.name != "macos" and not ("/usr/include/sqlite3.h" | path exists) { sudo apt-get install -y libsqlite3-dev }

  # 2. the node and its unit gate (elan picks the toolchain from lean-toolchain)
  lake build
  ./.lake/build/bin/frontier_witness

  # 3. the node as an Erlang peer, under PropCheck, on scratch ports and a scratch database
  let db = ($env.TMPDIR? | default "/tmp" | path join $"frontier-build-(random int 1000..9999).sqlite")
  let cookie = (random chars --length 24)
  epmd -daemon
  let node = (job spawn { FRONTIER_DB=$db ./.lake/build/bin/frontier --port 9950 --dist-port 9951 --cookie $cookie })
  mut up = false
  for _ in 1..30 { if (do -i { epmd -names } | str contains "name frontier at port 9951") { $up = true; break }; sleep 1sec }
  if not $up { job kill $node; error make { msg: "the node did not register with epmd within 30 s" } }
  let result = (do -i { cd test/node; mix deps.get; elixir --name probe@127.0.0.1 --cookie $cookie -S mix test } | complete)
  job kill $node
  rm -f $db
  print $result.stdout
  if $result.exit_code != 0 { print $result.stderr; exit $result.exit_code }
  print "OK: build.nu"
}
