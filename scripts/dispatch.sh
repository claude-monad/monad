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
# Two dispatch modes:
#   --node <name>: SSH to that node and run claude directly (targeted)
#   (no --node):   Nomad dispatch, any eligible node picks it up
#
# With --wait, polls until the task completes and prints the result.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

# Node SSH map — add new nodes here
declare -A NODE_SSH=(
  [bigo-server]="bigo@100.78.218.70"
  [v1410-1]="root@100.75.75.39"
  [oraclebox1]="ubuntu@100.125.210.126"
)

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

# ── Targeted dispatch via SSH ──────────────────────────────────────────────────
if [ -n "$TARGET_NODE" ]; then
  SSH_TARGET="${NODE_SSH[$TARGET_NODE]:-}"
  if [ -z "$SSH_TARGET" ]; then
    echo "[dispatch] ERROR: unknown node '$TARGET_NODE'. Known: ${!NODE_SSH[*]}"
    exit 1
  fi
  echo "[dispatch] SSH dispatch → $SSH_TARGET"
  RESULT_FILE="/tmp/claude-task-results/$TASK_ID.out"
  ssh -o ConnectTimeout=10 "$SSH_TARGET" "
    mkdir -p /tmp/claude-task-results
    echo '[claude-task] starting on \$(hostname)'
    # Find a non-root user with claude if needed
    if [ \"\$(id -u)\" = \"0\" ]; then
      for u in bigo ubuntu e eliott; do
        if id \"\$u\" &>/dev/null && su - \"\$u\" -c 'which claude' &>/dev/null; then
          su - \"\$u\" -c \"timeout $TIMEOUT claude --print --dangerously-skip-permissions '$PROMPT'\" > /tmp/claude-task-results/$TASK_ID.out 2>&1
          break
        fi
      done
    else
      timeout $TIMEOUT claude --print --dangerously-skip-permissions '$PROMPT' > /tmp/claude-task-results/$TASK_ID.out 2>&1
    fi
    echo '[claude-task] done'
    cat /tmp/claude-task-results/$TASK_ID.out
  " 2>&1
  exit $?
fi

# ── Untargeted dispatch via Nomad ──────────────────────────────────────────────
DISPATCH_ARGS=(-meta "prompt=$PROMPT" -meta "timeout=$TIMEOUT" -meta "task_id=$TASK_ID")
[ -n "$TARGET_ACCOUNT" ] && DISPATCH_ARGS+=(-meta "target_account=$TARGET_ACCOUNT")

OUTPUT=$(nomad job dispatch "${DISPATCH_ARGS[@]}" claude-task 2>&1)
echo "$OUTPUT"

DISPATCH_ID=$(echo "$OUTPUT" | grep -oP 'Dispatched Job ID\s*=\s*\K\S+' || true)
if [ -z "$DISPATCH_ID" ]; then
  echo "[dispatch] ERROR: dispatch failed"
  exit 1
fi

echo "[dispatch] dispatched: job=$DISPATCH_ID"

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
