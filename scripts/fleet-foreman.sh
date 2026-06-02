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
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
N="${1:-2}"; LOOP=""; [ "${2:-}" = "--loop" ] && LOOP=1
INTERVAL="${INTERVAL:-600}"

log() { echo "[foreman $(date '+%H:%M:%S')] $*"; }

running_builders() {
  nomad job status fleet-builder 2>/dev/null \
    | sed -n '/Allocations/,$p' | awk '$6=="running"{c++} END{print c+0}'
}

ensure() {
  # make sure the parameterized job is registered
  nomad job status fleet-builder >/dev/null 2>&1 || nomad job run "$REPO_DIR/jobs/fleet-builder.hcl" >/dev/null 2>&1
  local have; have="$(running_builders)"
  log "builders running: ${have}/${N}"
  local i engine
  for i in $(seq $((have+1)) "$N"); do
    engine=$([ $((i % 2)) -eq 0 ] && echo codex || echo claude)
    local name="agent-builder-$i-$(date +%H%M%S)"
    nomad job dispatch -meta "agent_name=$name" -meta "engine=$engine" fleet-builder >/dev/null 2>&1 \
      && log "dispatched builder $name (engine=$engine)" \
      || log "dispatch failed for $name"
    sleep 3
  done
  # record fleet status
  nomad var put -force fleet/status running="$(running_builders)" target="$N" \
    updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
}

ensure
while [ -n "$LOOP" ]; do sleep "$INTERVAL"; ensure; done
