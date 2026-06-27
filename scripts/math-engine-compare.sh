#!/usr/bin/env bash
# math-engine-compare.sh — Run an identical math task with Claude and Codex,
# then report back to the cluster comparing both results.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_AGENT="$REPO_DIR/meta/agent/run-agent.sh"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

WORK_DIR="/tmp/math-engine-compare-$$"
mkdir -p "$WORK_DIR"
trap "rm -rf $WORK_DIR" EXIT

MATH_REPO="${MATH_REPO_URL:-https://github.com/eliottcassidy2000/math.git}"

# If running as root (Nomad raw_exec), find a non-root user and re-exec as them.
if [ "$(id -u)" = "0" ]; then
    for u in e bigo ubuntu eliott; do
        if id "$u" &>/dev/null && su - "$u" -c "command -v claude >/dev/null 2>&1 || command -v codex >/dev/null 2>&1"; then
            echo "[math-engine-compare] re-executing as $u (claude/codex refuse root)"
            exec su - "$u" -c "MATH_REPO_URL='$MATH_REPO' NOMAD_ADDR='$NOMAD_ADDR' bash '$0'"
        fi
    done
    echo "ERROR: no non-root user with claude or codex found" >&2
    exit 1
fi

echo "=== Math Engine Comparison Test ==="
echo "Started: $(date -Is)"
echo "Node: $(hostname)"
echo ""

# ── Clone math repo (shared copy for both engines) ───────────────────────────
echo "[setup] Cloning math repo (depth 5 for speed)..."
git clone --depth=5 "$MATH_REPO" "$WORK_DIR/math" 2>&1 | tail -1
echo "[setup] Clone complete."
echo ""

# ── The prompt — identical for both engines ──────────────────────────────────
PROMPT_FILE="$WORK_DIR/prompt.md"
cat > "$PROMPT_FILE" << 'PROMPT'
You are running a quick math computation test. Do these steps:

1. Read 00-navigation/OPEN-QUESTIONS.md to find a computation task
2. Find a Python script in 04-computation/ that computes tournament-related sequences
3. Pick a SMALL, quick computation (something that runs in under 60 seconds)
4. Run it and capture the output
5. Summarize what you computed and the result in 3-5 sentences

Keep it bounded — you have up to 40 minutes max. Focus on producing a concrete numeric result.
PROMPT

TIMEOUT=2400  # 40 minutes per engine

# ── Run Claude ───────────────────────────────────────────────────────────────
echo "=== ENGINE 1: Claude ==="
CLAUDE_START=$(date +%s)
CLAUDE_OUT="$WORK_DIR/claude.out"

if "$RUN_AGENT" --engine claude --quiet --timeout "$TIMEOUT" --cwd "$WORK_DIR/math" "@$PROMPT_FILE" > "$CLAUDE_OUT" 2>&1; then
  CLAUDE_RC=0
else
  CLAUDE_RC=$?
fi
CLAUDE_END=$(date +%s)
CLAUDE_DURATION=$(( CLAUDE_END - CLAUDE_START ))

echo "Claude finished in ${CLAUDE_DURATION}s (exit=$CLAUDE_RC)"
echo ""

# ── Reset repo state for Codex ───────────────────────────────────────────────
cd "$WORK_DIR/math" && git checkout . && git clean -fd 2>/dev/null

# ── Run Codex ────────────────────────────────────────────────────────────────
echo "=== ENGINE 2: Codex ==="
CODEX_START=$(date +%s)
CODEX_OUT="$WORK_DIR/codex.out"

if "$RUN_AGENT" --engine codex --quiet --timeout "$TIMEOUT" --cwd "$WORK_DIR/math" "@$PROMPT_FILE" > "$CODEX_OUT" 2>&1; then
  CODEX_RC=0
else
  CODEX_RC=$?
fi
CODEX_END=$(date +%s)
CODEX_DURATION=$(( CODEX_END - CODEX_START ))

echo "Codex finished in ${CODEX_DURATION}s (exit=$CODEX_RC)"
echo ""

# ── Build report ─────────────────────────────────────────────────────────────
REPORT="$WORK_DIR/report.md"
cat > "$REPORT" << EOF
# Math Engine Comparison Report
**Date**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Node**: $(hostname)

## Claude (engine 1)
- **Duration**: ${CLAUDE_DURATION}s
- **Exit code**: ${CLAUDE_RC}
- **Output** (last 40 lines):
\`\`\`
$(tail -40 "$CLAUDE_OUT" 2>/dev/null || echo "(no output)")
\`\`\`

## Codex (engine 2)
- **Duration**: ${CODEX_DURATION}s
- **Exit code**: ${CODEX_RC}
- **Output** (last 40 lines):
\`\`\`
$(tail -40 "$CODEX_OUT" 2>/dev/null || echo "(no output)")
\`\`\`

## Comparison
- Claude took ${CLAUDE_DURATION}s, Codex took ${CODEX_DURATION}s
- Claude exit: ${CLAUDE_RC}, Codex exit: ${CODEX_RC}
EOF

echo "=== REPORT ==="
cat "$REPORT"

# ── Report to cluster via Nomad variable ─────────────────────────────────────
TASK_ID="engine-compare-$(date +%s)"
SUMMARY="Claude: ${CLAUDE_DURATION}s/rc${CLAUDE_RC}, Codex: ${CODEX_DURATION}s/rc${CODEX_RC}"

nomad var put -force "monad/task-results/$TASK_ID" \
  status="done" \
  node="$(hostname)" \
  type="engine-comparison" \
  claude_duration="${CLAUDE_DURATION}" \
  claude_exit="${CLAUDE_RC}" \
  codex_duration="${CODEX_DURATION}" \
  codex_exit="${CODEX_RC}" \
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  summary="$SUMMARY" 2>/dev/null && echo "[report] Results stored in Nomad variable: monad/task-results/$TASK_ID" || echo "[report] WARNING: could not store results in Nomad (non-fatal)"

# ── Log event ────────────────────────────────────────────────────────────────
EVENT_LOG="$REPO_DIR/logs/events.jsonl"
printf '{"ts":"%s","event":"engine-comparison","node":"%s","claude_duration":%d,"claude_rc":%d,"codex_duration":%d,"codex_rc":%d}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname)" "$CLAUDE_DURATION" "$CLAUDE_RC" "$CODEX_DURATION" "$CODEX_RC" \
  >> "$EVENT_LOG" 2>/dev/null || true

echo ""
echo "=== Comparison complete ==="
echo "Summary: $SUMMARY"
