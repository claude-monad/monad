#!/usr/bin/env bash
# formalize-watch.sh — watch the informal math repo and keep math-lean in lockstep.
#
# Policy (see meta/FORMALIZATION-POLICY.md): formalization is delegated to automated
# codex work in the *separate* Lean repo (eliott-monad/math-lean). For EVERY new commit
# to the informal math repo (eliottcassidy2000/math) we make sure formalization work is
# spawned — or, if a formalizer is already running, we leave the new arrivals in a durable
# inbox so the active session picks them up. Net effect: math-lean is always converging on
# the latest informal results, with no manual nudging.
#
# This runs as a short periodic job on the server (jobs/formalize-watch.hcl). It does NOT
# do any math itself — it only detects "the math repo moved" and triggers the codex
# formalizer (jobs/math-formalizer.hcl), whose own startup re-syncs candidates and so is
# self-correcting even if a trigger is missed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

MATH_REPO_URL="${MATH_REPO_URL:-https://github.com/eliottcassidy2000/math.git}"
MATH_BRANCH="${MATH_BRANCH:-main}"
FORMALIZER_JOB="${FORMALIZER_JOB:-math-formalizer}"
# Cursor: the math-repo commit we've processed. Named per the fleet project spec
# (fleet/projects/math-commit-driven-formalization.md) so "is math-lean caught up to math?"
# is answerable from one var and can feed a formalizer-lag health signal.
STATE_VAR="fleet/formalizer-cursor"
INBOX_VAR="monad/formalize/inbox"

EVENTS_FILE="$REPO_DIR/logs/events.jsonl"
mkdir -p "$REPO_DIR/logs"

log() { echo "[formalize-watch $(date '+%H:%M:%S')] $*"; }

emit_event() { # action result detail
    printf '{"ts":"%s","node":"%s","source":"formalize-watch","action":"%s","result":"%s","detail":"%s"}\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" "$1" "$2" "${3//\"/\'}" \
        >> "$EVENTS_FILE" 2>/dev/null || true
}

# ── Where is the math repo now? ─────────────────────────────────────────────
REMOTE_SHA="$(git ls-remote "$MATH_REPO_URL" "refs/heads/$MATH_BRANCH" 2>/dev/null | awk '{print $1}')"
if [ -z "$REMOTE_SHA" ]; then
    log "cannot reach $MATH_REPO_URL ($MATH_BRANCH) — skipping this pass"
    emit_event "poll" "fail" "ls-remote failed for $MATH_REPO_URL"
    exit 0
fi

LAST_SHA="$(nomad var get -item=last_sha "$STATE_VAR" 2>/dev/null || true)"

if [ "$REMOTE_SHA" = "$LAST_SHA" ]; then
    log "no new math commits (HEAD=$REMOTE_SHA) — nothing to do"
    exit 0
fi

# First run on a fresh cluster: record the baseline, do not flood the formalizer with
# the entire backlog of history (sync-candidates.sh already manages the standing backlog).
if [ -z "$LAST_SHA" ]; then
    log "baseline: recording math HEAD=$REMOTE_SHA (no trigger on first sight)"
    nomad var put -force "$STATE_VAR" last_sha="$REMOTE_SHA" updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true
    emit_event "baseline" "ok" "recorded HEAD $REMOTE_SHA"
    exit 0
fi

# ── New commits arrived — summarize what changed ─────────────────────────────
WORK="$(mktemp -d /tmp/formalize-watch.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
SUMMARY=""
COUNT="?"
if git clone --quiet --filter=blob:none --no-checkout "$MATH_REPO_URL" "$WORK/math" 2>/dev/null; then
    SUMMARY="$(git -C "$WORK/math" log --no-merges --oneline "${LAST_SHA}..${REMOTE_SHA}" 2>/dev/null | head -40)"
    COUNT="$(git -C "$WORK/math" rev-list --no-merges --count "${LAST_SHA}..${REMOTE_SHA}" 2>/dev/null || echo '?')"
fi
[ -z "$SUMMARY" ] && SUMMARY="(commit log unavailable; HEAD moved ${LAST_SHA:0:8} -> ${REMOTE_SHA:0:8})"
log "math repo moved: $COUNT new commit(s) ${LAST_SHA:0:8}..${REMOTE_SHA:0:8}"

# Durable inbox — this is how we "communicate to the active job what has arrived".
# Whichever formalizer session runs next reads this for context and prioritization;
# sync-candidates.sh still pulls the authoritative target set.
nomad var put -force "$INBOX_VAR" \
    since="$LAST_SHA" head="$REMOTE_SHA" count="$COUNT" \
    arrived="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    commits="$SUMMARY" >/dev/null 2>&1 || true

# ── Make sure formalization work is spawned ──────────────────────────────────
# Is a formalizer already running? If so, the inbox above + its own candidate re-sync
# cover the new commits (the "communicate to the active job" path). If not, force an
# immediate run. The job's prohibit_overlap=true is the backstop against pile-ups.
RUNNING="$(nomad job status "$FORMALIZER_JOB" 2>/dev/null | grep -ciE '\brunning\b' || true)"
if [ "${RUNNING:-0}" -gt 0 ]; then
    log "formalizer already active — new commits left in inbox for the running session"
    emit_event "notify-active" "ok" "$COUNT commit(s) to running $FORMALIZER_JOB"
else
    if nomad job periodic force "$FORMALIZER_JOB" >/dev/null 2>&1; then
        log "forced an immediate $FORMALIZER_JOB run for $COUNT new commit(s)"
        emit_event "spawn" "ok" "forced $FORMALIZER_JOB for $COUNT commit(s)"
    else
        log "WARN: could not force $FORMALIZER_JOB (will retry next pass)"
        emit_event "spawn" "fail" "periodic force failed for $FORMALIZER_JOB"
    fi
fi

# Advance the watermark only after we've recorded/triggered, so a transient failure
# above re-triggers next pass rather than silently dropping commits.
nomad var put -force "$STATE_VAR" last_sha="$REMOTE_SHA" updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >/dev/null 2>&1 || true
log "watermark advanced to $REMOTE_SHA"
