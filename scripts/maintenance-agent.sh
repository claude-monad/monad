#!/usr/bin/env bash
# maintenance-agent.sh — a STANDING per-node maintenance agent (claude or codex).
#
# Cluster maintenance is delegated from the cluster brain (conductor) to a maintenance
# agent on each machine. This is that agent. It runs as a Nomad SYSTEM job (one alloc
# per node), so every machine has one. It:
#   1. drains brain-delegated tasks from this node's queue   (monad/maintenance/<node>/queue/*)
#   2. between tasks, runs a light periodic self-maintenance pass
#   3. reports results to Nomad vars + the cluster event log
# Engine is chosen via the abstraction (run-agent --engine auto), so it uses whatever
# engine the node has ready (claude or codex). In the tsnet phase it also gets a tailnet
# IP + mailbox so these agents can message each other to sort out problems.
#
# Env: MAINT_INTERVAL (self-maint seconds, default 1800), POLL (queue seconds, default 60),
#      MONAD_ENGINE (default auto), NOMAD_ADDR.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_AGENT="$REPO_DIR/meta/agent/run-agent.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/meta/agent/engines.sh" 2>/dev/null || true

NODE="$(hostname)"
INTERVAL="${MAINT_INTERVAL:-1800}"
POLL="${POLL:-60}"
ENGINE="${MONAD_ENGINE:-auto}"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"

QUEUE="monad/maintenance/${NODE}/queue"
RESULTS="monad/maintenance/${NODE}/results"
LAST="monad/maintenance/${NODE}/last"
EVENTS="$REPO_DIR/logs/events.jsonl"

log()   { echo "[maint $NODE $(date '+%H:%M:%S')] $*"; }
event() { # type action status detail
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","node":"%s","source":"maintenance-agent","type":"%s","action":"%s","status":"%s","detail":"%s"}\n' \
    "$ts" "$NODE" "$1" "$2" "$3" "${4//\"/\'}" >> "$EVENTS" 2>/dev/null || true
}

ready_engines() { engines_ready 2>/dev/null; }

run_task() { # $1=prompt-file  $2=task-id  -> echoes exit code
  local pf="$1" id="$2" out rc
  out="$("$RUN_AGENT" --engine "$ENGINE" --quiet --timeout "${TASK_TIMEOUT:-1200}" --cwd "$REPO_DIR" "@$pf" 2>&1)"; rc=$?
  nomad var put -force "$RESULTS/$id" \
    node="$NODE" engine="$ENGINE" exit_code="$rc" \
    finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    summary="$(printf '%s' "$out" | tail -40)" >/dev/null 2>&1 || true
  echo "$rc"
}

drain_queue() { # returns 0 if it ran at least one task
  local listed ran=1 path id pf
  # -out=terse prints one path per line (plus a trailing UI hint) — keep only real paths.
  listed="$(nomad var list -out=terse "$QUEUE/" 2>/dev/null | grep "^$QUEUE/")" || return 1
  [ -z "$listed" ] && return 1
  while read -r path; do
    [ -z "$path" ] && continue
    id="${path##*/}"
    pf="$(mktemp)"
    if nomad var get -item=prompt "$path" >"$pf" 2>/dev/null && [ -s "$pf" ]; then
      log "delegated task $id starting (engine=$ENGINE)"
      event "maintenance" "delegated-task" "start" "$id"
      local rc; rc="$(run_task "$pf" "$id")"
      event "maintenance" "delegated-task" "$([ "$rc" = 0 ] && echo ok || echo fail)" "$id rc=$rc"
      nomad var purge "$path" >/dev/null 2>&1 || true
      ran=0
    fi
    rm -f "$pf"
  done <<< "$listed"
  return $ran
}

self_maintenance() {
  local pf rc
  pf="$(mktemp)"
  cat > "$pf" <<EOF
You are the maintenance agent for node "$NODE" in the Monad Nomad cluster.
Your repo (GitOps source of truth) is at: $REPO_DIR  (use the 'monad' CLI; NOMAD_ADDR is set).
Do a LIGHT, SAFE maintenance pass on THIS node only and report concisely:
  - disk: clean obviously-safe junk (old logs in logs/, /tmp, 'docker system prune -f' if docker is idle) ONLY if disk pressure is real.
  - git: if the repo is behind origin/main and clean, fast-forward; never force or discard local work.
  - nomad: confirm the local agent is healthy; if not, note it (do not restart blindly).
  - engines: confirm at least one agent engine (claude/codex) is ready; if a CLI is missing, note it.
Do NOT take destructive or cluster-wide actions. If something looks wrong but risky to fix,
report it for the conductor instead of acting. Keep your final reply to <12 lines: what you
checked, what you changed, and anything the conductor should know.
EOF
  log "self-maintenance pass (engine=$ENGINE)"
  event "maintenance" "self-pass" "start" ""
  local out; out="$("$RUN_AGENT" --engine "$ENGINE" --quiet --timeout "${SELF_TIMEOUT:-600}" --cwd "$REPO_DIR" "@$pf" 2>&1)"; rc=$?
  nomad var put -force "$LAST" node="$NODE" engine="$ENGINE" exit_code="$rc" \
    finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" summary="$(printf '%s' "$out" | tail -40)" >/dev/null 2>&1 || true
  event "maintenance" "self-pass" "$([ "$rc" = 0 ] && echo ok || echo fail)" "rc=$rc"
  rm -f "$pf"
}

log "maintenance-agent starting (interval=${INTERVAL}s poll=${POLL}s engine=$ENGINE)"
event "maintenance" "boot" "ok" "engines=$(ready_engines)"
# Wait one interval before the first self-pass so (re)starts don't burst LLM calls;
# brain-delegated queue tasks still run immediately.
last_self="$(date +%s)"
while true; do
  if [ -z "$(ready_engines)" ]; then
    log "no engine ready — running ensure-engines and idling"
    "$REPO_DIR/meta/agent/ensure-engines.sh" >/dev/null 2>&1 || true
    sleep "$POLL"; continue
  fi
  drain_queue || true
  now="$(date +%s)"
  if [ $(( now - last_self )) -ge "$INTERVAL" ]; then
    self_maintenance
    last_self="$(date +%s)"
  fi
  sleep "$POLL"
done
