#!/bin/bash
# run-claude-task.sh — execute a dispatched Claude task
# Called by the claude-task Nomad job. Uses NOMAD_META_* env vars.
set -uo pipefail

TASK_ID="${NOMAD_META_task_id:-${NOMAD_ALLOC_ID:0:8}}"
TIMEOUT="${NOMAD_META_timeout:-1800}"
PROMPT="${NOMAD_META_prompt:?PROMPT required}"
RESULT_DIR="/tmp/claude-task-results"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

mkdir -p "$RESULT_DIR"

echo "[claude-task] $(date -Is) task=$TASK_ID starting on $(hostname)"
echo "[claude-task] prompt: ${PROMPT:0:120}..."

if [ "$TIMEOUT" = "0" ]; then
  claude --print --dangerously-skip-permissions "$PROMPT" \
    > "$RESULT_DIR/$TASK_ID.out" 2>&1
else
  timeout --signal=TERM "$TIMEOUT" \
    claude --print --dangerously-skip-permissions "$PROMPT" \
    > "$RESULT_DIR/$TASK_ID.out" 2>&1
fi
RC=$?

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
