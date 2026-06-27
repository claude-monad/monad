#!/usr/bin/env bash
# Run one recurring Poke Forum Codex session, resuming by saved session UUID.
set -uo pipefail

ROLE="${1:-}"
case "$ROLE" in
  coordinator|explorer|investigator) ;;
  *) echo "usage: poke-session.sh {coordinator|explorer|investigator}" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORUM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$FORUM_DIR/.." && pwd)"
STATE_DIR="$FORUM_DIR/state"
LOG_DIR="$FORUM_DIR/logs"
PROMPT_DIR="$FORUM_DIR/prompts"
mkdir -p "$STATE_DIR" "$LOG_DIR" "$FORUM_DIR/posts"

LOCK="$STATE_DIR/$ROLE.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "[poke-session] $ROLE already running; skip $(date -Is)"
  exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "[poke-session] codex command not found" >&2
  exit 1
fi

STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RAW_LOG="$LOG_DIR/$STAMP-$ROLE.raw.log"
LAST_MSG="$LOG_DIR/$STAMP-$ROLE.last.md"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE"' EXIT
: > "$RAW_LOG"

{
  echo "Recurring Poke Forum tick at $(date -u '+%Y-%m-%dT%H:%M:%SZ')."
  echo "Workspace: $REPO_DIR"
  echo "Role: $ROLE"
  echo
  if [ "$ROLE" = "coordinator" ]; then
    cat "$PROMPT_DIR/coordinator.md"
  else
    sed "s/{{ROLE}}/poke-math-$ROLE/g" "$PROMPT_DIR/math-agent.md"
  fi
} > "$PROMPT_FILE"

cd "$REPO_DIR" || exit 1

TIMEOUT_SEC="${POKE_TIMEOUT:-540}"

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM "$TIMEOUT_SEC" "$@" < "$PROMPT_FILE" >> "$RAW_LOG" 2>&1
  else
    "$@" < "$PROMPT_FILE" >> "$RAW_LOG" 2>&1
  fi
}

auth_blocked_since() {
  local start_byte="$1"
  tail -c +"$((start_byte + 1))" "$RAW_LOG" | grep -qiE 'refresh_token|token_expired|401 Unauthorized|Please log out and sign in again|weekly limit|hit your weekly limit'
}

uuid() {
  python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
}

run_codex() {
  local sid_file="$STATE_DIR/$ROLE.codex.session-id"
  local legacy_sid_file="$STATE_DIR/$ROLE.session-id"
  local sid=""
  [ -s "$sid_file" ] && sid="$(tr -d '[:space:]' < "$sid_file")"
  [ -z "$sid" ] && [ -s "$legacy_sid_file" ] && sid="$(tr -d '[:space:]' < "$legacy_sid_file")"

  echo "[poke-session] trying engine=codex role=$ROLE sid=${sid:-new} timeout=${TIMEOUT_SEC}s at $(date -Is)" | tee -a "$RAW_LOG"
  if [ -n "$sid" ]; then
    run_with_timeout codex exec resume --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -o "$LAST_MSG" "$sid" -
  else
    run_with_timeout codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -C "$REPO_DIR" -o "$LAST_MSG" -
  fi
  local rc=$?

  local new_sid
  new_sid="$(grep -oiE 'session id:[[:space:]]*[0-9a-f-]{8,}' "$RAW_LOG" | grep -oiE '[0-9a-f-]{8,}' | tail -1 || true)"
  if [ -z "$new_sid" ]; then
    new_sid="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$RAW_LOG" | tail -1 || true)"
  fi
  [ -n "$new_sid" ] && printf '%s\n' "$new_sid" > "$sid_file"
  return "$rc"
}

run_claude() {
  local sid_file="$STATE_DIR/$ROLE.claude.session-id"
  local sid=""
  if [ -s "$sid_file" ]; then
    sid="$(tr -d '[:space:]' < "$sid_file")"
    echo "[poke-session] trying engine=claude role=$ROLE resume=$sid timeout=${TIMEOUT_SEC}s at $(date -Is)" | tee -a "$RAW_LOG"
    run_with_timeout claude --print --dangerously-skip-permissions --permission-mode bypassPermissions --resume "$sid" --output-format text
    return "$?"
  else
    sid="$(uuid)"
    echo "[poke-session] trying engine=claude role=$ROLE sid=$sid timeout=${TIMEOUT_SEC}s at $(date -Is)" | tee -a "$RAW_LOG"
    run_with_timeout claude --print --dangerously-skip-permissions --permission-mode bypassPermissions --session-id "$sid" --output-format text
    local rc=$?
    [ "$rc" = 0 ] && printf '%s\n' "$sid" > "$sid_file"
    return "$rc"
  fi
}

ENGINES="${POKE_ENGINE:-auto}"
if [ "$ENGINES" = "auto" ]; then
  ENGINES="codex claude"
fi

FINAL_RC=1
AUTH_BLOCKED=0
for engine in $ENGINES; do
  START_BYTE="$(wc -c < "$RAW_LOG" 2>/dev/null || echo 0)"
  case "$engine" in
    codex) run_codex; RC=$? ;;
    claude) run_claude; RC=$? ;;
    *) echo "[poke-session] unknown engine '$engine'" | tee -a "$RAW_LOG"; RC=2 ;;
  esac
  if [ "$RC" = 0 ]; then
    echo "[poke-session] role=$ROLE finished via $engine; see $RAW_LOG"
    exit 0
  fi
  if auth_blocked_since "$START_BYTE"; then
    AUTH_BLOCKED=1
    echo "[poke-session] engine=$engine auth/limit blocked; trying fallback if available" | tee -a "$RAW_LOG"
  else
    FINAL_RC="$RC"
    break
  fi
  FINAL_RC="$RC"
done

if [ "$FINAL_RC" = 124 ]; then
  echo "[poke-session] role=$ROLE timed out after ${TIMEOUT_SEC}s; see $RAW_LOG" >&2
  exit 124
fi

if [ "$AUTH_BLOCKED" = 1 ]; then
  echo "[poke-session] role=$ROLE skipped cleanly: all attempted engines are auth/limit blocked; see $RAW_LOG" >&2
  exit 0
fi

echo "[poke-session] role=$ROLE failed rc=$FINAL_RC; see $RAW_LOG" >&2
exit "$FINAL_RC"
