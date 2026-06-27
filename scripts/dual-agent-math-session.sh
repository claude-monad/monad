#!/usr/bin/env bash
# dual-agent-math-session.sh — run one autonomous math session with Claude and one
# with Codex, then report back to the cluster how both went.
#
# Designed for git-bash on the Windows node `windesk`. Safe to run unattended from
# a Windows Scheduled Task. Each agent works in its own fresh shallow clone of the
# math repo (isolation, throwaway). We do NOT push the agents' math work — this job
# only *measures and reports* how each agent performed.
#
# Reporting channels (all cluster-visible):
#   1. cluster-memory.sh  — node.windesk.dual-agent.* keys (git-backed blackboard)
#   2. cluster-msg.sh     — broadcast a summary to all nodes (Nomad variables)
#   3. logs/events.jsonl  — append structured events
#   4. monad git          — commit + push the memory/event updates
#
# Usage: dual-agent-math-session.sh
set -uo pipefail

# ── Paths & environment ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MATH_REPO="https://github.com/eliottcassidy2000/math.git"

# Harden PATH so this works under Windows Task Scheduler (non-interactive shell),
# where ~/.local/bin (claude) and the git toolchain may not be on PATH by default.
export PATH="$HOME/.local/bin:/usr/bin:/usr/local/bin:/mingw64/bin:$PATH"
export GIT_TERMINAL_PROMPT=0
# Resolve claude explicitly (falls back to the known install location).
CLAUDE_BIN="$(command -v claude || true)"
[ -z "$CLAUDE_BIN" ] && [ -x "$HOME/.local/bin/claude.exe" ] && CLAUDE_BIN="$HOME/.local/bin/claude.exe"
[ -z "$CLAUDE_BIN" ] && CLAUDE_BIN="claude"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export HOSTNAME="${HOSTNAME:-$(hostname)}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_ID="dual-${TIMESTAMP}"
LOG_DIR="$MONAD_DIR/logs"
mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/${RUN_ID}.log"

# Per-agent task time budget (seconds). Keep sessions focused & bounded.
AGENT_TIMEOUT="${AGENT_TIMEOUT:-2400}"

# ── Single-instance guard ──────────────────────────────────────────────────────
LOCKFILE="/tmp/monad-dual-agent.lock"
if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "[dual-agent] $(date -Is): already running (PID $LOCK_PID) — skipping."
    exit 0
  fi
  rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"

WORK_ROOT="/tmp/dual-agent-${TIMESTAMP}"
trap 'rm -f "$LOCKFILE"; rm -rf "$WORK_ROOT"' EXIT
mkdir -p "$WORK_ROOT"

# IMPORTANT: log to stderr (+ run log), never stdout — run_agent's stdout is captured
# by command substitution and must contain ONLY the final status line.
log() { echo "[dual-agent] $(date -Is): $*" | tee -a "$RUN_LOG" >&2; }

log "starting run $RUN_ID on $HOSTNAME (timeout ${AGENT_TIMEOUT}s/agent)"

# ── Resolve the codex binary (latest versioned bin dir) ─────────────────────────
CODEX_BIN=""
CODEX_ROOT="$HOME/AppData/Local/OpenAI/Codex/bin"
if [ -d "$CODEX_ROOT" ]; then
  CODEX_BIN=$(ls -1dt "$CODEX_ROOT"/*/codex.exe 2>/dev/null | head -1 || true)
fi

# Optional bounded runner: use `timeout` if available, else run directly.
run_bounded() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM "$secs" "$@"
  else
    "$@"
  fi
}

# The shared, deliberately-small autonomous task. Each agent gets a fresh clone.
read -r -d '' TASK_PROMPT <<'EOF'
You are an autonomous pure-mathematics research agent working in this tournament-theory
repository (Hamiltonian path counts H(T), the formal group F(x,y)=(x+y)/(1+xy), OEIS
sequences). Work AUTONOMOUSLY and be focused and quick — you have a short time budget.

Steps:
1. Skim 00-navigation/ to orient (README/INDEX, OPEN-QUESTIONS if present).
2. Pick exactly ONE small, concrete, verifiable task: e.g. re-verify a short computation,
   extend a known small sequence by a couple of terms by hand or with a quick script,
   or sanity-check one stated claim.
3. Do it. Keep scope tiny so you finish in time.
4. Write your outcome to a NEW file SESSION_RESULT.md in the repo root with:
   - what you chose, what you did, the concrete result, and a confidence note.
Finally, print a 3-5 sentence summary of what you accomplished. Do not start anything
you cannot finish in the time budget.
EOF

# ── Run one agent in an isolated clone; echo a status line we can parse ──────────
# Captures: <agent>|<exit_code>|<duration_s>|<out_words>|<result_file_present>
run_agent() {
  local name="$1"          # "claude" | "codex"
  local clone="$WORK_ROOT/$name"
  local out="$LOG_DIR/${RUN_ID}-${name}.out"
  local start end rc=0 words=0 hasresult="no"

  log "[$name] cloning math repo (depth 1) -> $clone"
  if ! git clone --depth=1 "$MATH_REPO" "$clone" >/dev/null 2>&1; then
    log "[$name] ERROR: clone failed"
    echo "$name|clone_failed|0|0|no"
    return
  fi
  echo "monad-dual-${name}-windesk" > "$clone/.machine-id"

  start=$(date +%s)
  log "[$name] launching autonomous session"
  (
    cd "$clone" || exit 99
    case "$name" in
      claude)
        run_bounded "$AGENT_TIMEOUT" "$CLAUDE_BIN" --print --dangerously-skip-permissions "$TASK_PROMPT"
        ;;
      codex)
        if [ -z "$CODEX_BIN" ]; then
          echo "CODEX BINARY NOT FOUND under $CODEX_ROOT"; exit 127
        fi
        run_bounded "$AGENT_TIMEOUT" "$CODEX_BIN" exec --skip-git-repo-check "$TASK_PROMPT"
        ;;
    esac
  ) >"$out" 2>&1
  rc=$?
  end=$(date +%s)

  [ -f "$clone/SESSION_RESULT.md" ] && hasresult="yes"
  words=$(wc -w < "$out" 2>/dev/null | tr -d ' ' || echo 0)
  log "[$name] done rc=$rc duration=$((end-start))s words=$words result=$hasresult"
  echo "$name|$rc|$((end-start))|$words|$hasresult"
}

# ── Run both agents sequentially (rate-limit / resource friendliness) ───────────
# tail -1: defensive — capture only the final status line even if anything leaks to stdout
CLAUDE_STATUS=$(run_agent claude | tail -1)
CODEX_STATUS=$(run_agent codex | tail -1)

# ── Build human summary ─────────────────────────────────────────────────────────
summarize() {  # name|rc|dur|words|hasresult -> readable verdict
  local s="$1"
  IFS='|' read -r n rc dur words res <<< "$s"
  local verdict="ok"
  [ "$rc" = "0" ] || verdict="nonzero-exit($rc)"
  [ "$rc" = "clone_failed" ] && verdict="clone-failed"
  echo "$n: $verdict, ${dur}s, ${words} words out, SESSION_RESULT.md=$res"
}
CLAUDE_LINE=$(summarize "$CLAUDE_STATUS")
CODEX_LINE=$(summarize "$CODEX_STATUS")

SUMMARY="dual-agent math test ($RUN_ID) on windesk
  $CLAUDE_LINE
  $CODEX_LINE"

log "SUMMARY:"
echo "$SUMMARY" | tee -a "$RUN_LOG"

# Last lines of each transcript (for the broadcast body)
tail_of() { tail -n 8 "$LOG_DIR/${RUN_ID}-$1.out" 2>/dev/null | tr '\n' ' ' | cut -c1-500; }
CLAUDE_TAIL=$(tail_of claude)
CODEX_TAIL=$(tail_of codex)

# ── Report back to the cluster ──────────────────────────────────────────────────
log "reporting to cluster..."

# 1) git-backed blackboard (cluster-memory) — pull first to avoid conflicts
( cd "$MONAD_DIR" && git pull --ff-only >/dev/null 2>&1 || true )

# NOTE: cluster-memory.sh passes an MSYS path (/c/...) to python3, but the python3 on
# this Windows node is the native Windows build which only accepts C:\ paths. So we
# write the blackboard directly here with a cygpath-converted native path (TTL 7d).
MEM_WIN=$(cygpath -w "$MONAD_DIR/cluster-memory.json" 2>/dev/null || echo "$MONAD_DIR/cluster-memory.json")
mem_set() {  # key value
  python3 - "$MEM_WIN" "$1" "$2" "$HOSTNAME" <<'PY' 2>>"$RUN_LOG" || true
import json, sys, time
path, key, value, host = sys.argv[1:5]
try:
    with open(path) as f: data = json.load(f)
except Exception:
    data = {}
data[key] = {"value": value, "updated": time.time(),
             "updated_by": host, "expires": time.time() + 7*86400}
with open(path, "w") as f: json.dump(data, f, indent=2, sort_keys=True)
PY
}
mem_set "node.windesk.dual-agent.last_run" "$RUN_ID"
mem_set "node.windesk.dual-agent.claude"   "$CLAUDE_LINE"
mem_set "node.windesk.dual-agent.codex"    "$CODEX_LINE"

# 2) broadcast to all nodes (real-time Nomad-variable mailbox)
"$SCRIPT_DIR/cluster-msg.sh" broadcast \
  "dual-agent math test ($RUN_ID)" \
  "windesk ran Claude + Codex autonomous math sessions.
$CLAUDE_LINE
  claude tail: $CLAUDE_TAIL
$CODEX_LINE
  codex tail: $CODEX_TAIL" 2>&1 | tee -a "$RUN_LOG" || true

# 3) structured event log
EVENT=$(python3 - "$RUN_ID" "$HOSTNAME" "$CLAUDE_STATUS" "$CODEX_STATUS" <<'PY'
import json, sys, time
run_id, node, claude_s, codex_s = sys.argv[1:5]
def parse(s):
    p = s.split('|')
    return {"agent":p[0],"rc":p[1],"duration_s":p[2],"out_words":p[3],"result_file":p[4]} if len(p)==5 else {"raw":s}
print(json.dumps({
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "node": node, "source": "dual-agent-test", "action": run_id, "result": "ok",
    "detail": {"claude": parse(claude_s), "codex": parse(codex_s)},
}))
PY
)
echo "$EVENT" >> "$LOG_DIR/events.jsonl"

# 4) commit + push so the whole cluster sees it.
# Scope the commit to OUR artifacts only (cluster-memory + event log) — never `add -A`,
# so an unattended run can't sweep in unrelated work-in-progress.
(
  cd "$MONAD_DIR" || exit 0
  git add cluster-memory.json logs/events.jsonl >/dev/null 2>&1 || true
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "dual-agent math test $RUN_ID: report claude+codex session results

Co-Authored-By: Claude <noreply@anthropic.com>" >/dev/null 2>&1 || true
    GIT_TERMINAL_PROMPT=0 git push origin main >/dev/null 2>&1 || true
  fi
) || true

log "run $RUN_ID complete — reported to cluster-memory, broadcast, events.jsonl, git."
exit 0
