#!/usr/bin/bash
set -u
cd "$(dirname "$0")/.."
stage() {
  name=$1; shift
  "$@"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "FAILED $name (exit $rc)"; exit 1; fi
  echo "DONE $name"
}
echo "start $(date -u +%FT%TZ) steps=${STEPS:-20} limit=${LIMIT:-15}"
stage frontier elixir tools/party_saga.exs frontier --steps "${STEPS:-20}" --limit "${LIMIT:-15}"
stage agree elixir tools/party_saga.exs agree --limit "${AGREE_LIMIT:-30}"
echo ALLDONE
