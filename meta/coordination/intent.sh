#!/usr/bin/env bash
# intent.sh — the front door for the user's messages to the cluster.
#
# monad-operator (the textual interface) records each user directive VERBATIM as a durable,
# git-backed intent, then decomposes it into small chained tasks (../task.sh) that recursively
# ensure the intent is met. This is the "record my messages, then kick off a recursive job
# composed of little steps" layer. It is the durable record even while Nomad is down.
# See ../PROTOCOL.md.
#
# Usage:
#   intent.sh record "<verbatim user message>"        # create an intent, print its id
#   intent.sh interpret <id> "<one-line reading>"      # attach operator's interpretation
#   intent.sh accept    <id> "<acceptance condition>"  # add a measurable done-condition (repeatable)
#   intent.sh link      <id> <task-id>                 # link a spawned child task to this intent
#   intent.sh status    <id> <open|active|met|blocked> # update status
#   intent.sh show      <id>                            # print one intent
#   intent.sh list      [status]                        # list intents (default: all)
#
# An intent is "met" only when every acceptance condition holds and every linked task is done.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTENTS="$DIR/intents"
mkdir -p "$INTENTS"

gen_id() {
  local seq; seq=$(( $(cat "$INTENTS/.seq" 2>/dev/null || echo 0) + 1 ))
  echo "$seq" > "$INTENTS/.seq"
  printf 'i-%04d' "$seq"
}

py() { python3 - "$@"; }

cmd="${1:-list}"; shift || true
case "$cmd" in
  record)
    msg="${1:?verbatim message required}"
    id="$(gen_id)"
    INTENT_ID="$id" VERBATIM="$msg" WHO="$(hostname)" py "$INTENTS/$id.json" <<'PY'
import json, os, sys
f = sys.argv[1]
json.dump({
    "id": os.environ["INTENT_ID"],
    "from": "eliott",
    "recorded_by": os.environ["WHO"],
    "verbatim": os.environ["VERBATIM"],
    "interpretation": None,
    "acceptance": [],
    "tasks": [],
    "status": "open",
}, open(f, "w"), indent=2)
PY
    echo "$id"
    ;;
  interpret)
    id="${1:?id}"; text="${2:?interpretation}"; f="$INTENTS/$id.json"
    [ -f "$f" ] || { echo "no such intent: $id" >&2; exit 1; }
    TEXT="$text" py "$f" <<'PY'
import json, os, sys
f = sys.argv[1]; d = json.load(open(f)); d["interpretation"] = os.environ["TEXT"]
json.dump(d, open(f, "w"), indent=2)
PY
    echo "interpreted $id"
    ;;
  accept)
    id="${1:?id}"; text="${2:?acceptance condition}"; f="$INTENTS/$id.json"
    [ -f "$f" ] || { echo "no such intent: $id" >&2; exit 1; }
    TEXT="$text" py "$f" <<'PY'
import json, os, sys
f = sys.argv[1]; d = json.load(open(f)); d["acceptance"].append(os.environ["TEXT"])
json.dump(d, open(f, "w"), indent=2)
PY
    echo "added acceptance to $id"
    ;;
  link)
    id="${1:?id}"; tid="${2:?task-id}"; f="$INTENTS/$id.json"
    [ -f "$f" ] || { echo "no such intent: $id" >&2; exit 1; }
    TID="$tid" py "$f" <<'PY'
import json, os, sys
f = sys.argv[1]; d = json.load(open(f)); t = os.environ["TID"]
if t not in d["tasks"]: d["tasks"].append(t)
json.dump(d, open(f, "w"), indent=2)
PY
    echo "linked $tid -> $id"
    ;;
  status)
    id="${1:?id}"; st="${2:?status}"; f="$INTENTS/$id.json"
    [ -f "$f" ] || { echo "no such intent: $id" >&2; exit 1; }
    ST="$st" py "$f" <<'PY'
import json, os, sys
f = sys.argv[1]; d = json.load(open(f)); d["status"] = os.environ["ST"]
json.dump(d, open(f, "w"), indent=2)
PY
    echo "status $id = $st"
    ;;
  show)
    id="${1:?id}"; f="$INTENTS/$id.json"
    [ -f "$f" ] || { echo "no such intent: $id" >&2; exit 1; }
    python3 -m json.tool "$f"
    ;;
  list)
    want="${1:-all}"
    shopt -s nullglob
    for f in "$INTENTS"/i-*.json; do
      WANT="$want" py "$f" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); want = os.environ["WANT"]
if want == "all" or d.get("status") == want:
    print(f"{d['id']:<8} {d['status']:<8} tasks={len(d['tasks'])}  {d['verbatim'][:70]}")
PY
    done
    ;;
  *) echo "usage: intent.sh record|interpret|accept|link|status|show|list  (see header)"; exit 2 ;;
esac
