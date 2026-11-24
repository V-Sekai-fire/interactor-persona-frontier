#!/bin/bash
# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# One coordinator and three workers as separate Erlang nodes with separate addresses: a fast one, a throttled one (the stealing case) and one that dies on its first
# assignment (the node-death case). Scout, power 3, input from the fixture. Usage: tools/cluster_test.sh COORD_IP W1_IP W2_IP W3_IP HOST_BINARY GUEST_ELF
# The log is judged by tools/cluster_check.sh (the same judge the workflow uses on the coordinator container's log).
set -u
coord=$1; w1=$2; w2=$3; w3=$4; host=$5; guest=$6
here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
export ELIXIR_ERL_OPTIONS="+fnu"
cd "$here"
epmd -daemon || true
NODE_NAME=coord@$coord elixir tools/turbo_cluster.exs coordinator frontend/fixtures/scout.cp --power 3 --workers 3 --steal-after-ms 300 --problem frontend/fixtures/scout.power3.input.txt --cookie ci > "$out/coord.log" 2>&1 &
coord_pid=$!
sleep 4
NODE_NAME=w1@$w1 elixir tools/turbo_cluster.exs worker coord@$coord "$guest" "$host" --kind cpu --budget 50000000 --cookie ci > "$out/w1.log" 2>&1 &
NODE_NAME=w2@$w2 TURBO_SLEEP_US=20000 elixir tools/turbo_cluster.exs worker coord@$coord "$guest" "$host" --kind cpu --budget 1000000 --cookie ci > "$out/w2.log" 2>&1 &
NODE_NAME=w3@$w3 TURBO_DIE_AT_ASSIGN=1 elixir tools/turbo_cluster.exs worker coord@$coord "$guest" "$host" --kind cpu --budget 50000000 --cookie ci > "$out/w3.log" 2>&1 &
for _ in $(seq 1 120); do kill -0 $coord_pid 2>/dev/null || break; sleep 1; done
kill $coord_pid 2>/dev/null
cat "$out/coord.log"
exec "$here/tools/cluster_check.sh" "$out/coord.log"
