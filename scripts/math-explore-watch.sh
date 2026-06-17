#!/usr/bin/env bash
# math-explore-watch.sh — turn every new math-repo commit into autonomous Codex discovery.
#
# Watches eliottcassidy2000/math HEAD (like formalize-watch). When new commits land, it spins up
# a bounded number of Codex `math-explore` sessions (jobs/math-explore.hcl) seeded with the
# recent-commit context + distinct exploration angles, so the cluster keeps building on its own
# latest results — discovering new theorems/proofs/connections. The formalizer already covers
# formalization on the same commits; this covers FORWARD research.
#
# Cost-safe on the Codex pool: governor admission (skip if Codex nodes are at capacity)
# + a hard cap on concurrent explorers + don't re-dispatch while explorers are already running.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"; export NOMAD_ADDR

MATH_REPO_URL="${MATH_REPO_URL:-https://github.com/eliottcassidy2000/math.git}"
MATH_BRANCH="${MATH_BRANCH:-main}"
EXPLORE_JOB="${EXPLORE_JOB:-math-explore}"
STATE_VAR="monad/explore/cursor"
INBOX_VAR="monad/explore/inbox"
MAX_CONCURRENT="${MAX_CONCURRENT:-2}"   # never more than this many explorers at once
PER_BATCH="${PER_BATCH:-2}"             # how many to spawn per new-commit batch
EVENTS_FILE="$REPO_DIR/logs/events.jsonl"; mkdir -p "$REPO_DIR/logs"

log() { echo "[explore-watch $(date '+%H:%M:%S')] $*"; }
emit() { printf '{"ts":"%s","node":"%s","source":"explore-watch","action":"%s","result":"%s","detail":"%s"}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" "$1" "$2" "${3//\"/\'}" >> "$EVENTS_FILE" 2>/dev/null || true; }

# Distinct angles so parallel explorers don't duplicate each other.
ANGLES=(
  " Angle: build directly on the newest result — push it further or find its sharpest consequence."
  " Angle: hunt a cross-domain connection (TANGENTS.md / CONCEPT-MAP.md) the recent work suggests."
  " Angle: stress-test the recent claims — try to refute, find a counterexample, or strengthen hypotheses."
)

REMOTE_SHA="$(git ls-remote "$MATH_REPO_URL" "refs/heads/$MATH_BRANCH" 2>/dev/null | awk '{print $1}')"
[ -n "$REMOTE_SHA" ] || { log "cannot reach math repo — skip"; emit poll fail "ls-remote failed"; exit 0; }
LAST_SHA="$(nomad var get -item=last_sha "$STATE_VAR" 2>/dev/null || true)"

if [ "$REMOTE_SHA" = "$LAST_SHA" ]; then log "no new commits (HEAD=$REMOTE_SHA)"; exit 0; fi
if [ -z "$LAST_SHA" ]; then
  log "baseline: recording HEAD=$REMOTE_SHA (no trigger on first sight)"
  nomad var put -force "$STATE_VAR" last_sha="$REMOTE_SHA" updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true
  emit baseline ok "$REMOTE_SHA"; exit 0
fi

# Summarize the new commits as the seed.
WORK="$(mktemp -d /tmp/explore-watch.XXXXXX)"; trap 'rm -rf "$WORK"' EXIT
SUMMARY=""; COUNT="?"
if git clone --quiet --filter=blob:none --no-checkout "$MATH_REPO_URL" "$WORK/math" 2>/dev/null; then
  SUMMARY="$(git -C "$WORK/math" log --no-merges --oneline "${LAST_SHA}..${REMOTE_SHA}" 2>/dev/null | head -25)"
  COUNT="$(git -C "$WORK/math" rev-list --no-merges --count "${LAST_SHA}..${REMOTE_SHA}" 2>/dev/null || echo '?')"
fi
[ -n "$SUMMARY" ] || SUMMARY="(HEAD moved ${LAST_SHA:0:8} -> ${REMOTE_SHA:0:8})"
log "math repo moved: $COUNT new commit(s)"
nomad var put -force "$INBOX_VAR" since="$LAST_SHA" head="$REMOTE_SHA" count="$COUNT" \
  arrived="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" commits="$SUMMARY" >/dev/null 2>&1 || true

# Don't pile up: count running explorers.
RUNNING="$(nomad job status "$EXPLORE_JOB" 2>/dev/null | grep -cE '\brunning\b' || echo 0)"
if [ "${RUNNING:-0}" -ge "$MAX_CONCURRENT" ]; then
  log "$RUNNING explorer(s) already running (cap $MAX_CONCURRENT) — left commits in inbox, no new spawn"
  emit notify-active ok "$COUNT commit(s); $RUNNING running"
  nomad var put -force "$STATE_VAR" last_sha="$REMOTE_SHA" updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true
  exit 0
fi

SEED="Recent math-repo commits ($COUNT) you should build on:
$SUMMARY"
want=$(( MAX_CONCURRENT - RUNNING )); [ "$want" -gt "$PER_BATCH" ] && want="$PER_BATCH"
spawned=0
for i in $(seq 0 $((want-1))); do
  # Governor admission: only spawn if a Codex node has capacity (else don't overload).
  node="$(python3 "$REPO_DIR/scripts/llm-scheduler.py" place --engine codex --mem 1024 --quiet 2>/dev/null)"
  if [ -z "$node" ] || [ "$node" = "QUEUE" ]; then
    log "governor: no Codex capacity right now — holding ($spawned spawned this batch)"; break
  fi
  angle="${ANGLES[$(( i % ${#ANGLES[@]} ))]}"
  if nomad job dispatch -detach -meta "seed=$SEED" -meta "angle=$angle" "$EXPLORE_JOB" >/dev/null 2>&1; then
    log "dispatched explorer #$((i+1)) (governor node hint: $node)"; spawned=$((spawned+1))
  else
    log "WARN: dispatch failed for explorer #$((i+1))"
  fi
  sleep 2
done
emit spawn ok "$spawned explorer(s) for $COUNT commit(s)"
nomad var put -force "$STATE_VAR" last_sha="$REMOTE_SHA" updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true
log "watermark advanced to $REMOTE_SHA ($spawned explorer(s) spawned)"
