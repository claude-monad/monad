#!/usr/bin/env bash
# mesh-convo — manage persistent reactive LLM agents on the mesh (jobs/mesh-conversation.hcl).
#
#   mesh-convo.sh launch <name> "<role>" [--engine codex|claude] [--greet "<msg>"] [--node N]
#   mesh-convo.sh list
#   mesh-convo.sh remove <name>
#
# Placement is governor-driven (least-loaded engine-ready node) unless --node is given.
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
die() { echo "mesh-convo: $*" >&2; exit 1; }

cmd="${1:-}"; shift || true
case "$cmd" in
  launch)
    name="${1:-}"; shift || true; [ -n "$name" ] || die "usage: launch <name> \"<role>\" [opts]"
    role=""; engine="codex"; greet=""; node=""
    while [ $# -gt 0 ]; do case "$1" in
      --engine) engine="$2"; shift 2;; --greet) greet="$2"; shift 2;; --node) node="$2"; shift 2;;
      *) role="${role:+$role }$1"; shift;;
    esac; done
    [ -n "$role" ] || die "a role is required"
    if [ -z "$node" ]; then
      node="$(python3 "$REPO_DIR/scripts/llm-scheduler.py" place --engine "$engine" --mem 300 --quiet 2>/dev/null)"
      { [ -z "$node" ] || [ "$node" = "QUEUE" ]; } && die "no capacity for a $engine agent right now (governor said QUEUE)"
    fi
    out="$(nomad job dispatch -detach -meta "name=$name" -meta "role=$role" -meta "engine=$engine" \
      -meta "node=$node" -meta "greet=$greet" mesh-conversation 2>&1)"
    echo "$out" | grep -qi 'Dispatched' && echo "launched agent-$name ($engine) on $node" || die "dispatch failed: $out"
    ;;
  list)
    echo "live mesh agents (relay /peers):"
    curl -s -m8 "http://100.75.75.39:8477/peers" 2>/dev/null | python3 -c 'import json,sys;[print("  %s  online=%s  age=%ss"%(p["name"],p["online"],p["age_s"])) for p in json.load(sys.stdin)]' 2>/dev/null || echo "  (relay unreachable)"
    ;;
  remove)
    name="${1:-}"; [ -n "$name" ] || die "usage: remove <name>"
    # stop the dispatched child job(s) for this persona
    nomad job status mesh-conversation 2>/dev/null | awk '/^mesh-conversation\/dispatch-/{print $1}' | while read -r j; do
      nomad job status "$j" 2>/dev/null | grep -q "name.*=.*$name" 2>/dev/null
    done
    # simplest robust: stop all dispatches whose meta name matches
    for j in $(nomad job status mesh-conversation 2>/dev/null | awk '/^mesh-conversation\/dispatch-/{print $1}'); do
      if nomad job inspect "$j" 2>/dev/null | grep -q "\"name\": \"$name\""; then
        nomad job stop -purge "$j" >/dev/null 2>&1 && echo "removed agent-$name ($j)"
      fi
    done
    ;;
  *) echo "usage: mesh-convo.sh {launch <name> \"<role>\"|list|remove <name>}" >&2; exit 2 ;;
esac
