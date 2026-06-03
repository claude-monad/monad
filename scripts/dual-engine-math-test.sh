#!/usr/bin/env bash
# dual-engine-math-test.sh — a self-contained CLUSTER CAPABILITY TEST.
#
# Runs ONE bounded autonomous math-research session with EACH engine (claude, then
# codex) on a fresh clone of the research repo, captures how each went, and REPORTS
# BACK TO THE CLUSTER: an event in logs/events.jsonl, a committed report under
# logs/dual-engine-math-test/, and a broadcast to the math fleet.
#
# Designed to run as the `dual-engine-math-test` Nomad periodic job (raw_exec, user
# ubuntu) on a node that advertises BOTH engines. Safe to run by hand too.
set -uo pipefail

MONAD_DIR="${MONAD_REPO_DIR:-$HOME/monad}"
MATH_REPO_URL="${MATH_REPO_URL:-https://github.com/eliottcassidy2000/math.git}"
RUN_AGENT="$MONAD_DIR/meta/agent/run-agent.sh"
PER_ENGINE_TIMEOUT="${PER_ENGINE_TIMEOUT:-720}"   # 12 min hard cap per engine
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$(mktemp -d /tmp/dual-engine-math-XXXX)"
REPORT_DIR="$MONAD_DIR/logs/dual-engine-math-test"
REPORT="$REPORT_DIR/report-$STAMP.md"
EVENTS="$MONAD_DIR/logs/events.jsonl"
NODE="$(hostname)"
mkdir -p "$REPORT_DIR"

log() { echo "[dual-engine-test $(date -u +%H:%M:%S)] $*"; }

# The autonomous research task both engines get (bounded, verifiable, no push).
read -r -d '' PROMPT <<'EOP'
You are running ONE bounded (~8 minute) autonomous research pass on this tournament /
Lonely-Runner-Conjecture mathematics repo. You are in a FRESH, throwaway clone — do NOT
git push and do NOT run agents/finish_session.py.

1. Read 00-navigation/SESSION-LOG.md (top few entries) for recent context.
2. Pick ONE small, concrete, verifiable computation that checks or extends a recent
   finding (e.g. the loneliness spectral gap, the antipodal-transversal reduction, or a
   doubled-prime fact).
3. Write a short Python script under 04-computation/ and RUN it.
4. Report in 5-8 lines: exactly what you tested, the numeric result, and whether it
   CONFIRMED or REFUTED the idea. Produce a real verified number, not a plan.
EOP

# ── run one engine, capture outcome ───────────────────────────────────────────
declare -A RC DUR OUT DIFF
run_engine() {
  local eng="$1"                       # bind eng first (set -u: same-line self-ref fails)
  local dir="$WORK/$eng" out="$WORK/$eng.out" t0 t1
  log "cloning math repo for $eng ..."
  git clone --depth 30 "$MATH_REPO_URL" "$dir" >/dev/null 2>&1 || { RC[$eng]=200; OUT[$eng]="(clone failed)"; DUR[$eng]=0; DIFF[$eng]=0; return; }
  log "running $eng session (timeout ${PER_ENGINE_TIMEOUT}s) ..."
  t0=$(date +%s)
  ( cd "$dir" && "$RUN_AGENT" --engine "$eng" --cwd "$dir" --timeout "$PER_ENGINE_TIMEOUT" --quiet "$PROMPT" ) >"$out" 2>&1
  RC[$eng]=$?
  t1=$(date +%s); DUR[$eng]=$((t1-t0))
  OUT[$eng]="$(tail -c 1400 "$out" 2>/dev/null)"
  DIFF[$eng]="$(cd "$dir" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  log "$eng done: rc=${RC[$eng]} dur=${DUR[$eng]}s files_changed=${DIFF[$eng]}"
}

verdict() {  # rc -> human verdict
  case "$1" in
    0) echo "completed" ;;
    124) echo "TIMED OUT (${PER_ENGINE_TIMEOUT}s cap)" ;;
    200) echo "setup failed (clone)" ;;
    3) echo "engine not ready (not installed/logged in)" ;;
    *) echo "failed (exit $1)" ;;
  esac
}

log "=== dual-engine math capability test on $NODE @ $STAMP ==="
run_engine claude
run_engine codex

# ── assemble the report ───────────────────────────────────────────────────────
{
  echo "# Dual-engine math capability test — $STAMP"
  echo
  echo "**Node:** \`$NODE\`  •  **Per-engine cap:** ${PER_ENGINE_TIMEOUT}s  •  task: one bounded autonomous research pass each."
  echo
  for eng in claude codex; do
    echo "## $eng — $(verdict "${RC[$eng]}")"
    echo "- exit=\`${RC[$eng]}\`  duration=\`${DUR[$eng]}s\`  files_changed_in_clone=\`${DIFF[$eng]}\`"
    echo
    echo '```'
    echo "${OUT[$eng]:-(no output)}"
    echo '```'
    echo
  done
  echo "_Reported automatically by the \`dual-engine-math-test\` Nomad job._"
} > "$REPORT"
log "report written: $REPORT"

# ── report back to the cluster: events.jsonl + git commit + math broadcast ────
EVENT="$(python3 -c "
import json,sys
print(json.dumps({
  'timestamp':'$STAMP','event':'dual-engine-math-test','node':'$NODE',
  'claude':{'rc':${RC[claude]},'dur_s':${DUR[claude]},'files':${DIFF[claude]}},
  'codex':{'rc':${RC[codex]},'dur_s':${DUR[codex]},'files':${DIFF[codex]}},
  'report':'logs/dual-engine-math-test/report-$STAMP.md'}))
")"
echo "$EVENT" >> "$EVENTS"

# commit + push the report (token from host gh, if available)
if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
  git config --global credential.helper '!f() { echo username=x-access-token; echo "password=$(gh auth token)"; }; f' 2>/dev/null || true
fi
( cd "$MONAD_DIR" \
  && git add logs/dual-engine-math-test/ logs/events.jsonl 2>/dev/null \
  && git -c user.name="$NODE" -c user.email="$NODE@monad" commit -q \
       -m "dual-engine-math-test: claude=$(verdict "${RC[claude]}" | cut -d' ' -f1) codex=$(verdict "${RC[codex]}" | cut -d' ' -f1) @ $STAMP" 2>/dev/null \
  && (git pull --rebase -q origin main 2>/dev/null; git push -q origin main 2>/dev/null) \
  && log "report committed + pushed to monad" ) || log "git report step skipped/failed (non-fatal)"

# broadcast to the math fleet (best-effort)
if [ -f "$WORK/claude/agents/processor.py" ]; then
  ( cd "$WORK/claude" && python3 agents/processor.py --send --to all \
      --subject "dual-engine capability test @ $STAMP: claude=$(verdict "${RC[claude]}"|cut -d' ' -f1) codex=$(verdict "${RC[codex]}"|cut -d' ' -f1)" \
      --body "Cluster ran one autonomous math session per engine on $NODE. claude: $(verdict "${RC[claude]}") in ${DUR[claude]}s. codex: $(verdict "${RC[codex]}") in ${DUR[codex]}s. Full report: monad logs/dual-engine-math-test/report-$STAMP.md" >/dev/null 2>&1 \
      && log "broadcast sent to math fleet" ) || log "math broadcast skipped (non-fatal)"
fi

log "=== test complete: claude=$(verdict "${RC[claude]}") | codex=$(verdict "${RC[codex]}") ==="
rm -rf "$WORK" 2>/dev/null || true
exit 0
