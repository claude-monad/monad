#!/bin/bash
# dispatch.sh — dispatch a Claude task to a cluster node
#
# Usage:
#   dispatch.sh <prompt> [--node <name>] [--account <acct>] [--timeout <secs>] [--wait]
#
# Examples:
#   dispatch.sh "check disk space and report" --node bigo-server
#   dispatch.sh "run the latest computation" --account max-2 --wait
#   dispatch.sh "explore the math frontier" --wait --timeout 3600
#
# Dispatches a parameterized claude-task Nomad job. With --wait, polls until
# the task completes and prints the result.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

PROMPT=""
TARGET_NODE=""
TARGET_ACCOUNT=""
TIMEOUT="1800"
WAIT=false

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --node)       TARGET_NODE="$2"; shift 2 ;;
    --account)    TARGET_ACCOUNT="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --wait)       WAIT=true; shift ;;
    *)
      if [ -z "$PROMPT" ]; then
        PROMPT="$1"
      else
        PROMPT="$PROMPT $1"
      fi
      shift ;;
  esac
done

if [ -z "$PROMPT" ]; then
  echo "Usage: dispatch.sh <prompt> [--node <name>] [--account <acct>] [--timeout <secs>] [--wait]"
  exit 1
fi

TASK_ID="task-$(date +%s)-$RANDOM"

echo "[dispatch] task=$TASK_ID"
echo "[dispatch] prompt: ${PROMPT:0:80}..."
[ -n "$TARGET_NODE" ] && echo "[dispatch] target node: $TARGET_NODE"
[ -n "$TARGET_ACCOUNT" ] && echo "[dispatch] target account: $TARGET_ACCOUNT"

# Build dispatch command
DISPATCH_ARGS=(-meta "prompt=$PROMPT" -meta "timeout=$TIMEOUT" -meta "task_id=$TASK_ID")
[ -n "$TARGET_NODE" ] && DISPATCH_ARGS+=(-meta "target_node=$TARGET_NODE")
[ -n "$TARGET_ACCOUNT" ] && DISPATCH_ARGS+=(-meta "target_account=$TARGET_ACCOUNT")

# Dispatch
OUTPUT=$(nomad job dispatch "${DISPATCH_ARGS[@]}" claude-task 2>&1)
echo "$OUTPUT"

DISPATCH_ID=$(echo "$OUTPUT" | grep -oP 'Dispatched Job ID\s*=\s*\K\S+' || true)
ALLOC_ID=$(echo "$OUTPUT" | grep -oP 'Allocation ID\s*=\s*\K\S+' || true)

if [ -z "$DISPATCH_ID" ]; then
  echo "[dispatch] ERROR: dispatch failed"
  exit 1
fi

echo "[dispatch] dispatched: job=$DISPATCH_ID alloc=$ALLOC_ID"

if [ "$WAIT" = true ]; then
  echo "[dispatch] waiting for completion..."
  while true; do
    RESULT=$(nomad var get -json "monad/task-results/$TASK_ID" 2>/dev/null || true)
    if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Items']['status'])" 2>/dev/null | grep -q "done"; then
      echo ""
      echo "=== Task $TASK_ID completed ==="
      echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)['Items']
print(f\"Node: {d.get('node','?')}\")
print(f\"Exit code: {d.get('exit_code','?')}\")
print(f\"Finished: {d.get('finished','?')}\")
print(f\"--- Output ---\")
print(d.get('summary','(no output)'))
" 2>/dev/null
      break
    fi
    sleep 5
  done
fi
