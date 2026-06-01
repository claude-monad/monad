#!/usr/bin/env bash
# task.sh — git-backed task queue for self-chaining cluster sessions.
# Emitting a task is a commit, so the queue is durable and survives Nomad being down.
# See meta/coordination/PROTOCOL.md ("The task queue").
#
# Usage:
#   task.sh emit  <type> <repo> "<scope>" [parent-id]   # create a task, print its id
#   task.sh claim <id> <machine>                         # mark claimed by you
#   task.sh done  <id>                                   # mark done
#   task.sh list  [status]                               # list tasks (default: open)
#
#   type: math | merge | push | formalize | review | compute
#
# Each session does ONE small task, then EMITS the next instead of doing it inline.
# Example chain:
#   id=$(task.sh emit math eliottcassidy2000/math "prove HYP-1981 n=8 case")
#   ... do the math locally ...
#   task.sh emit push eliottcassidy2000/math "open PR for S514 result" "$id"
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS="$DIR/tasks"
mkdir -p "$TASKS"

# short id without Date.now(): hash of args + a counter file (deterministic, collision-safe)
gen_id() {
  local seq; seq=$(( $(cat "$TASKS/.seq" 2>/dev/null || echo 0) + 1 ))
  echo "$seq" > "$TASKS/.seq"
  printf 't-%04d' "$seq"
}

esc() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

cmd="${1:-list}"; shift || true
case "$cmd" in
  emit)
    type="${1:?type}"; repo="${2:?repo}"; scope="${3:?scope}"; parent="${4:-null}"
    id="$(gen_id)"
    pjson="null"; [ "$parent" != "null" ] && pjson="$(esc "$parent")"
    cat > "$TASKS/$id.json" <<EOF
{
  "id": "$id",
  "type": $(esc "$type"),
  "scope": $(esc "$scope"),
  "repo": $(esc "$repo"),
  "payload": {},
  "status": "open",
  "owner": null,
  "parent": $pjson
}
EOF
    echo "$id"
    ;;
  claim)
    id="${1:?id}"; who="${2:?machine}"; f="$TASKS/$id.json"
    [ -f "$f" ] || { echo "no such task: $id" >&2; exit 1; }
    python3 - "$f" "$who" <<'PY'
import json,sys
f,who=sys.argv[1],sys.argv[2]
d=json.load(open(f)); d["status"]="claimed"; d["owner"]=who
json.dump(d,open(f,"w"),indent=2)
PY
    echo "claimed $id by $who"
    ;;
  done)
    id="${1:?id}"; f="$TASKS/$id.json"
    [ -f "$f" ] || { echo "no such task: $id" >&2; exit 1; }
    python3 - "$f" <<'PY'
import json,sys
f=sys.argv[1]; d=json.load(open(f)); d["status"]="done"; json.dump(d,open(f,"w"),indent=2)
PY
    echo "done $id"
    ;;
  list)
    want="${1:-open}"
    shopt -s nullglob
    for f in "$TASKS"/t-*.json; do
      python3 - "$f" "$want" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); want=sys.argv[2]
if want=="all" or d.get("status")==want:
    print(f"{d['id']:<8} {d['status']:<8} {d['type']:<10} {d['repo']:<28} {d['scope']}")
PY
    done
    ;;
  *) echo "usage: task.sh emit|claim|done|list  (see header)"; exit 2 ;;
esac
