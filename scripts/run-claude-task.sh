#!/bin/bash
# run-claude-task.sh — execute a dispatched Claude task
# Called by the claude-task Nomad job. Uses NOMAD_META_* env vars.
# Drops to a non-root user if running as root (Claude refuses --dangerously-skip-permissions as root).
set -uo pipefail

TASK_ID="${NOMAD_META_task_id:-${NOMAD_ALLOC_ID:0:8}}"
TIMEOUT="${NOMAD_META_timeout:-1800}"
PROMPT="${NOMAD_META_prompt:?PROMPT required}"
RESULT_DIR="/tmp/claude-task-results"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

mkdir -p "$RESULT_DIR"
chmod 777 "$RESULT_DIR" 2>/dev/null || true

echo "[claude-task] $(date -Is) task=$TASK_ID starting on $(hostname)"
echo "[claude-task] prompt: ${PROMPT:0:120}..."

# If running as root, find a non-root user with Claude and drop privileges
RUN_CMD="claude --print --dangerously-skip-permissions"
if [ "$(id -u)" = "0" ]; then
  # Find a user with claude installed
  RUN_USER=""
  for u in bigo ubuntu e eliott; do
    if id "$u" &>/dev/null && su - "$u" -c "which claude" &>/dev/null; then
      RUN_USER="$u"
      break
    fi
  done
  if [ -z "$RUN_USER" ]; then
    echo "[claude-task] ERROR: no non-root user with claude found" >&2
    nomad var put -force "monad/task-results/$TASK_ID" \
      status="done" exit_code="1" node="$(hostname)" \
      finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      summary="ERROR: no non-root user with claude found" 2>/dev/null || true
    exit 1
  fi
  echo "[claude-task] dropping privileges to user: $RUN_USER"

  if [ "$TIMEOUT" = "0" ]; then
    su - "$RUN_USER" -c "NOMAD_ADDR=$NOMAD_ADDR claude --print --dangerously-skip-permissions '$PROMPT'" \
      > "$RESULT_DIR/$TASK_ID.out" 2>&1
  else
    su - "$RUN_USER" -c "NOMAD_ADDR=$NOMAD_ADDR timeout --signal=TERM $TIMEOUT claude --print --dangerously-skip-permissions '$PROMPT'" \
      > "$RESULT_DIR/$TASK_ID.out" 2>&1
  fi
  RC=$?
else
  # Already non-root
  if [ "$TIMEOUT" = "0" ]; then
    claude --print --dangerously-skip-permissions "$PROMPT" \
      > "$RESULT_DIR/$TASK_ID.out" 2>&1
  else
    timeout --signal=TERM "$TIMEOUT" \
      claude --print --dangerously-skip-permissions "$PROMPT" \
      > "$RESULT_DIR/$TASK_ID.out" 2>&1
  fi
  RC=$?
fi

echo "[claude-task] $(date -Is) task=$TASK_ID finished rc=$RC"

# Post result summary via Nomad variable
SUMMARY=$(tail -50 "$RESULT_DIR/$TASK_ID.out" | head -50)
nomad var put -force \
  "monad/task-results/$TASK_ID" \
  status="done" \
  exit_code="$RC" \
  node="$(hostname)" \
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  summary="$SUMMARY" 2>/dev/null || true

exit $RC
