#!/bin/bash
# run-claude-task.sh — execute a dispatched agent task with EITHER engine (claude|codex).
# Called by the claude-task Nomad job. Uses NOMAD_META_* env vars. Routes through the
# engine abstraction (meta/agent/run-agent.sh) so the brain can dispatch either type.
# Drops to a non-root user if running as root (claude refuses full-access mode as root).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_AGENT="$REPO_DIR/meta/agent/run-agent.sh"

TASK_ID="${NOMAD_META_task_id:-${NOMAD_ALLOC_ID:0:8}}"
TIMEOUT="${NOMAD_META_timeout:-1800}"
PROMPT="${NOMAD_META_prompt:?PROMPT required}"
ENGINE="${NOMAD_META_engine:-auto}"          # claude|codex|auto
RESULT_DIR="/tmp/claude-task-results"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

mkdir -p "$RESULT_DIR"; chmod 777 "$RESULT_DIR" 2>/dev/null || true
OUT="$RESULT_DIR/$TASK_ID.out"
# Pass the prompt as a file (@file) to avoid shell-quoting issues across su.
PF="$RESULT_DIR/$TASK_ID.prompt"; printf '%s' "$PROMPT" > "$PF"; chmod 644 "$PF" 2>/dev/null || true

echo "[agent-task] $(date -Is) task=$TASK_ID engine=$ENGINE on $(hostname)"
echo "[agent-task] prompt: ${PROMPT:0:120}..."

AGENT_CMD="MONAD_ENGINE=$ENGINE NOMAD_ADDR=$NOMAD_ADDR \"$RUN_AGENT\" --engine $ENGINE --quiet --timeout $TIMEOUT --cwd \"$REPO_DIR\" \"@$PF\""

if [ "$(id -u)" = "0" ]; then
  # Find a non-root user with a ready engine and drop privileges.
  RUN_USER=""
  for u in bigo ubuntu e eliott; do
    if id "$u" &>/dev/null && su - "$u" -c "command -v claude >/dev/null 2>&1 || command -v codex >/dev/null 2>&1"; then
      RUN_USER="$u"; break
    fi
  done
  if [ -z "$RUN_USER" ]; then
    echo "[agent-task] ERROR: no non-root user with an agent engine found" >&2
    nomad var put -force "monad/task-results/$TASK_ID" status="done" exit_code="1" \
      node="$(hostname)" engine="$ENGINE" finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      summary="ERROR: no non-root user with claude or codex found" 2>/dev/null || true
    exit 1
  fi
  echo "[agent-task] dropping privileges to user: $RUN_USER"
  su - "$RUN_USER" -c "$AGENT_CMD" > "$OUT" 2>&1; RC=$?
else
  eval "$AGENT_CMD" > "$OUT" 2>&1; RC=$?
fi

echo "[agent-task] $(date -Is) task=$TASK_ID finished rc=$RC"

SUMMARY=$(tail -50 "$OUT" | head -50)
nomad var put -force "monad/task-results/$TASK_ID" \
  status="done" exit_code="$RC" node="$(hostname)" engine="$ENGINE" \
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" summary="$SUMMARY" 2>/dev/null || true

exit $RC
