#!/usr/bin/env bash
# fleet-foreman.sh — keep the fleet building. Ensures up to N builder agents are running,
# working the backlog (fleet/projects/*.md). Run once to top up, or loop it.
#
#   fleet-foreman.sh [N]          # ensure N builders running (default 2), then exit
#   fleet-foreman.sh [N] --loop   # keep ensuring every INTERVAL (default 600s)
#
# Builders are dispatched via the fleet-builder job; they self-coordinate over the mesh and
# claim projects via git, so it's safe to run a few. Engine alternates claude/codex to spread
# load across rate-limit pools.
#
# Each cycle it: (1) git-pulls so the backlog is fresh, (2) reads fleet/projects/*.md and
# counts statuses, (3) tops up builders up to N (Nomad reaps finished batch allocs, so dead
# ones simply stop counting and get replaced), (4) records a summary to the Nomad var
# fleet/status and an event line to logs/events.jsonl (source "fleet").
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
N="${1:-2}"; LOOP=""; [ "${2:-}" = "--loop" ] && LOOP=1
INTERVAL="${INTERVAL:-600}"
PROJECTS_DIR="$REPO_DIR/fleet/projects"
EVENTS="$REPO_DIR/logs/events.jsonl"
NODE="$(uname -n)"

log() { echo "[foreman $(date '+%H:%M:%S')] $*"; }

event() { # action result detail
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","node":"%s","source":"fleet","action":"%s","result":"%s","detail":"%s"}\n' \
    "$ts" "$NODE" "$1" "$2" "${3//\"/\'}" >> "$EVENTS" 2>/dev/null || true
}

# Count "active" builders = dispatched children that are Pending OR Running. fleet-builder is
# a parameterized job, so its `job status` shows a Parameterized Job Summary (Pending Running
# Dead), not a unified Allocations table. We count Pending+Running so builders that are queued
# waiting for capacity still count toward N — otherwise the foreman piles up pending children
# that all place at once when capacity frees (over-shooting N).
active_builders() {
  nomad job status fleet-builder 2>/dev/null | awk '
    /Parameterized Job Summary/ { getline; getline; print $1 + $2; found=1; exit }
    END { if (!found) print 0 }'
}

# Count project statuses across fleet/projects/*.md -> sets globals B_TODO B_BUILDING ...
backlog_counts() {
  B_TODO=0; B_CLAIMED=0; B_BUILDING=0; B_REVIEW=0; B_DONE=0; B_BLOCKED=0
  local f s
  for f in "$PROJECTS_DIR"/*.md; do
    [ -e "$f" ] || continue
    s="$(awk -F': *' '/^status:/{print $2; exit}' "$f" | tr -d '[:space:]')"
    case "$s" in
      todo)     B_TODO=$((B_TODO+1)) ;;
      claimed)  B_CLAIMED=$((B_CLAIMED+1)) ;;
      building) B_BUILDING=$((B_BUILDING+1)) ;;
      review)   B_REVIEW=$((B_REVIEW+1)) ;;
      done)     B_DONE=$((B_DONE+1)) ;;
      blocked)  B_BLOCKED=$((B_BLOCKED+1)) ;;
    esac
  done
}

ensure() {
  # Refresh the backlog from git so counts/claims reflect what builders have pushed.
  git -C "$REPO_DIR" pull --ff-only --quiet >/dev/null 2>&1 || true

  # make sure the parameterized job is registered
  nomad job status fleet-builder >/dev/null 2>&1 || nomad job run "$REPO_DIR/jobs/fleet-builder.hcl" >/dev/null 2>&1

  backlog_counts
  local backlog="todo=$B_TODO building=$B_BUILDING blocked=$B_BLOCKED done=$B_DONE"

  local have; have="$(active_builders)"
  log "builders running: ${have}/${N} | backlog: $backlog"

  # Only top up if there is open work (todo/building/blocked); don't burn quota when the
  # backlog is fully done. Always keep at least 1 builder alive to pick up new todos.
  local want="$N" open=$((B_TODO + B_BUILDING + B_BLOCKED))
  [ "$open" -eq 0 ] && want=1

  local dispatched=0 i engine name
  for i in $(seq $((have+1)) "$want"); do
    engine=$([ $((i % 2)) -eq 0 ] && echo codex || echo claude)
    name="agent-builder-$i-$(date +%H%M%S)"
    # -detach: register the child and return immediately (don't block monitoring placement;
    # a capacity-blocked child just stays Pending and is counted by active_builders next cycle).
    if nomad job dispatch -detach -meta "agent_name=$name" -meta "engine=$engine" fleet-builder >/dev/null 2>&1; then
      log "dispatched builder $name (engine=$engine)"; dispatched=$((dispatched+1))
    else
      log "dispatch failed for $name"
    fi
    sleep 3
  done

  local now; now="$(active_builders)"
  # record fleet status (machine-readable, one place to look)
  nomad var put -force fleet/status \
    running="$now" target="$want" dispatched_this_cycle="$dispatched" \
    backlog_todo="$B_TODO" backlog_building="$B_BUILDING" \
    backlog_blocked="$B_BLOCKED" backlog_done="$B_DONE" \
    updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

  event "foreman-cycle" "ok" "builders=$now/$want dispatched=$dispatched | $backlog"
}

ensure
while [ -n "$LOOP" ]; do sleep "$INTERVAL"; ensure; done
