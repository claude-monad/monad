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
# fleet/status and an event line (source "fleet"). FOREMAN_EVENTS_FILE can redirect that
# event stream outside the Git checkout so a standing service does not dirty the source tree.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
N="${1:-2}"; LOOP=""; [ "${2:-}" = "--loop" ] && LOOP=1
INTERVAL="${INTERVAL:-600}"
PROJECTS_DIR="$REPO_DIR/fleet/projects"
EVENTS="${FOREMAN_EVENTS_FILE:-$REPO_DIR/logs/events.jsonl}"
NODE="$(uname -n)"

log() { echo "[foreman $(date '+%H:%M:%S')] $*"; }

event() { # action result detail
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$EVENTS")" 2>/dev/null || true
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

pending_builder_children() {
  nomad job status fleet-builder 2>/dev/null | awk '
    $1 ~ /^fleet-builder\/dispatch-/ && $2 == "pending" { print $1 }'
}

REAPED_PENDING=0
reap_excess_pending_builders() {
  local have="$1" want="$2" excess child
  REAPED_PENDING=0
  excess=$((have - want))
  [ "$excess" -gt 0 ] || return 0

  while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ "$REAPED_PENDING" -lt "$excess" ] || break
    if nomad job stop -detach -purge -yes "$child" >/dev/null 2>&1; then
      log "reaped excess pending builder $child"
      REAPED_PENDING=$((REAPED_PENDING + 1))
    else
      log "WARN: failed to reap pending builder $child"
    fi
  done <<EOF
$(pending_builder_children)
EOF

  [ "$REAPED_PENDING" -eq 0 ] || sleep 2
}

# Count project statuses across fleet/projects/*.md -> sets globals B_TODO B_BUILDING ...
front_value() {
  local key="$1" f="$2"
  sed -n "s/^${key}:[[:space:]]*//p" "$f" | head -n 1 | sed 's/^"//; s/"$//' | tr -d '\r'
}

append_csv() {
  local var="$1" value="$2" cur
  cur="${!var:-}"
  if [ -z "$cur" ]; then
    printf -v "$var" '%s' "$value"
  else
    printf -v "$var" '%s,%s' "$cur" "$value"
  fi
}

backlog_counts() {
  B_TODO=0; B_CLAIMED=0; B_BUILDING=0; B_REVIEW=0; B_DONE=0; B_BLOCKED=0
  B_ACTIVE_PROJECTS=""; B_BLOCKED_PROJECTS=""
  local f slug s owner updated entry
  for f in "$PROJECTS_DIR"/*.md; do
    [ -e "$f" ] || continue
    slug="$(basename "$f" .md)"
    s="$(front_value status "$f" | tr -d '[:space:]')"
    owner="$(front_value owner "$f")"
    updated="$(front_value updated "$f")"
    [ -n "$owner" ] || owner="none"
    [ -n "$updated" ] || updated="unknown"
    entry="${slug}:${s}:${owner}:${updated}"
    case "$s" in
      todo)     B_TODO=$((B_TODO+1)) ;;
      claimed)  B_CLAIMED=$((B_CLAIMED+1)); append_csv B_ACTIVE_PROJECTS "$entry" ;;
      building) B_BUILDING=$((B_BUILDING+1)); append_csv B_ACTIVE_PROJECTS "$entry" ;;
      review)   B_REVIEW=$((B_REVIEW+1)); append_csv B_ACTIVE_PROJECTS "$entry" ;;
      done)     B_DONE=$((B_DONE+1)) ;;
      blocked)  B_BLOCKED=$((B_BLOCKED+1)); append_csv B_BLOCKED_PROJECTS "$entry" ;;
    esac
  done
}

ensure() {
  # Refresh the backlog from git so counts/claims reflect what builders have pushed.
  if ! git -C "$REPO_DIR" pull --ff-only --quiet >/dev/null 2>&1; then
    log "WARN: git pull failed for $REPO_DIR; using existing checkout"
  fi

  # make sure the parameterized job is registered
  nomad job status fleet-builder >/dev/null 2>&1 || nomad job run "$REPO_DIR/jobs/fleet-builder.hcl" >/dev/null 2>&1

  backlog_counts
  local backlog="todo=$B_TODO claimed=$B_CLAIMED building=$B_BUILDING review=$B_REVIEW blocked=$B_BLOCKED done=$B_DONE"

  local have; have="$(active_builders)"
  log "builders running: ${have}/${N} | backlog: $backlog"

  # Only top up to full strength for actionable work. Blocked projects stay visible in
  # fleet/status, but they should not burn builder quota while waiting on an owner.
  # Always keep at least 1 builder alive to pick up new todos.
  local want="$N" actionable=$((B_TODO + B_CLAIMED + B_BUILDING + B_REVIEW))
  [ "$actionable" -eq 0 ] && want=1
  reap_excess_pending_builders "$have" "$want"
  [ "$REAPED_PENDING" -eq 0 ] || have="$(active_builders)"

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
    reaped_pending="$REAPED_PENDING" \
    backlog_todo="$B_TODO" backlog_building="$B_BUILDING" \
    backlog_claimed="$B_CLAIMED" backlog_review="$B_REVIEW" \
    backlog_blocked="$B_BLOCKED" backlog_done="$B_DONE" \
    active_projects="${B_ACTIVE_PROJECTS:-none}" \
    blocked_projects="${B_BLOCKED_PROJECTS:-none}" \
    updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

  event "foreman-cycle" "ok" "builders=$now/$want dispatched=$dispatched reaped_pending=$REAPED_PENDING | $backlog"
}

ensure
while [ -n "$LOOP" ]; do sleep "$INTERVAL"; ensure; done
