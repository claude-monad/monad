#!/usr/bin/env bash
# math-session-windows.sh — Windows-native math session launcher
#
# Runs a Claude research session in a fresh clone (isolation without Docker).
# Designed for git bash on Windows. Safe to run from cron / scheduled task.
#
# Usage: math-session-windows.sh [mode]
#   mode: explorer (default) | compute | targeted "<question>"
#
# The script:
#   1. Clones the math repo to a temp dir (isolation)
#   2. Loads the appropriate prompt
#   3. Runs claude --print --dangerously-skip-permissions
#   4. Cleans up the temp dir
set -uo pipefail

MODE="${1:-explorer}"
QUESTION="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="$SCRIPT_DIR/prompts"
MATH_REPO="https://github.com/eliottcassidy2000/math.git"
MONAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="$TMPDIR/math-session-${MODE}-${TIMESTAMP}"
if [ -z "${TMPDIR:-}" ]; then
  WORK_DIR="/tmp/math-session-${MODE}-${TIMESTAMP}"
fi

LOGFILE="$MONAD_DIR/logs/session-${MODE}-${TIMESTAMP}.log"

# guard: one session at a time per account
LOCKFILE="/tmp/monad-session-pro.lock"
if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "[math-session] $(date -Is): session already running (PID $LOCK_PID) — skipping."
    exit 0
  fi
  rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; rm -rf "$WORK_DIR"' EXIT

echo "[math-session] $(date -Is): starting ${MODE} session"
echo "[math-session] work dir: $WORK_DIR"

# clone
mkdir -p "$WORK_DIR"
git clone --depth=100 "$MATH_REPO" "$WORK_DIR/math" 2>&1 | tail -1
cd "$WORK_DIR/math"

# machine id
MACHINE_ID="monad-${MODE}-windesk"
echo "$MACHINE_ID" > .machine-id

# register agent if possible
if [ -f agents/processor.py ]; then
  python3 agents/processor.py --register 2>/dev/null || true
fi

# load prompt
case "$MODE" in
  explorer)
    PROMPT=$(cat "$PROMPT_DIR/explorer.md")
    ;;
  compute)
    PROMPT=$(cat "$PROMPT_DIR/compute.md")
    ;;
  targeted)
    PROMPT=$(cat "$PROMPT_DIR/targeted.md")
    if [ -n "$QUESTION" ]; then
      PROMPT="$PROMPT"$'\n\n'"## Target question"$'\n'"$QUESTION"
    fi
    ;;
  researcher)
    PROMPT=$(cat "$PROMPT_DIR/researcher.md")
    DAY=$(date +%u)
    case $DAY in
      1) FOCUS="Pick the highest-priority red open question from 00-navigation/OPEN-QUESTIONS.md and attempt a proof or significant partial result" ;;
      2) FOCUS="Run computation scripts from 04-computation/ — extend known OEIS sequences, verify conjectures with new data" ;;
      3) FOCUS="Review hypotheses in 05-knowledge/hypotheses/INDEX.md — pick one and try to prove or definitively refute it" ;;
      4) FOCUS="Read 00-navigation/TANGENTS.md and CONCEPT-MAP.md — develop the most promising cross-domain connection into a concrete result" ;;
      5) FOCUS="Engineering: build or improve a tool — check OPEN-QUESTIONS.md for engineering tasks, improve scripts in 04-computation/" ;;
      6) FOCUS="Write-up day: take a result from 05-knowledge/results/ that lacks a clean proof and write a proper theorem file for 01-canon/theorems/" ;;
      7) FOCUS="Free exploration: read CONCEPT-MAP.md and INVESTIGATION-BACKLOG.md, investigate whatever seems most promising" ;;
    esac
    PROMPT="${PROMPT//\{\{FOCUS\}\}/$FOCUS}"
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 1
    ;;
esac

# run the session
echo "[math-session] $(date -Is): launching claude (${MODE})"
claude --print --dangerously-skip-permissions "$PROMPT" 2>&1 | tee "$LOGFILE"

echo "[math-session] $(date -Is): session complete"
