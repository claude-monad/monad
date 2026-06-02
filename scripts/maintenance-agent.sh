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
# Some delegators address this node by a different-case hostname (e.g. the roster lists
# "v1410-1" but `hostname` is "V1410-1"), so tasks queued at the other case would never be
# drained. Also watch a lowercased queue prefix when it differs from the exact one.
NODE_LC="$(printf '%s' "$NODE" | tr '[:upper:]' '[:lower:]')"
QUEUE_LC="monad/maintenance/${NODE_LC}/queue"

log()   { echo "[maint $NODE $(date '+%H:%M:%S')] $*"; }
event() { # type action status detail
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","node":"%s","source":"maintenance-agent","type":"%s","action":"%s","status":"%s","detail":"%s"}\n' \
    "$ts" "$NODE" "$1" "$2" "$3" "${4//\"/\'}" >> "$EVENTS" 2>/dev/null || true
}

ready_engines() { engines_ready 2>/dev/null; }

# --- engine-as-credentialed-user (amd64/root path) --------------------------------
# Set by detect_engine_user() below. When this agent runs as root with no host checkout
# (the alloc-clone fallback on V1410-1/bigo-server), claude refuses
# --dangerously-skip-permissions as root. If a non-root user on this host has their own
# engine creds, we run the ENGINE as them, in a clone they own, so self-passes + delegated
# tasks succeed. mesh-attach still runs as root → mesh membership is unchanged. On nodes
# already running as a non-root user (oraclebox1 su's to ubuntu via the HCL launcher's
# path 1), id -u != 0 so DROP_PRIV stays 0 and behavior is identical to before.
DROP_PRIV=0; ENGINE_USER=""; ENGINE_HOME=""; ENGINE_REPO="$REPO_DIR"; AGENT_REPO="$REPO_DIR"; DROP_ENGINES=""

# engine_run <prompt-file> <timeout> -> runs the agent, stdout=agent output, returns rc.
# Drops to the credentialed non-root user when DROP_PRIV=1; otherwise runs as-is.
engine_run() {
  local pf="$1" to="$2"
  if [ "$DROP_PRIV" = 1 ]; then
    chmod 0644 "$pf" 2>/dev/null || true
    su - "$ENGINE_USER" -c "cd '$ENGINE_REPO'; MONAD_ENGINE='$ENGINE' NOMAD_ADDR='$NOMAD_ADDR' LOCAL_PORT='${LOCAL_PORT:-}' ON_MESH='${ON_MESH:-0}' bash '$ENGINE_REPO/meta/agent/run-agent.sh' --engine '$ENGINE' --quiet --timeout '$to' --cwd '$ENGINE_REPO' '@$pf'"
  else
    "$RUN_AGENT" --engine "$ENGINE" --quiet --timeout "$to" --cwd "$REPO_DIR" "@$pf"
  fi
}

# engine_ready_now -> 0 if an engine is usable for the (possibly dropped-to) user.
engine_ready_now() {
  if [ "$DROP_PRIV" = 1 ]; then [ -n "$DROP_ENGINES" ]; return; fi
  [ -n "$(ready_engines)" ]
}

# detect_engine_user: when running as root, find a non-root user that owns its own engine
# creds and set up a clone they own. Idempotent (refreshes the clone). Best-effort.
detect_engine_user() {
  [ "$(id -u)" = 0 ] || return 0
  local u h eng
  for u in ubuntu bigo e eliott; do
    h="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$h" ] || continue
    eng=""
    [ -f "$h/.claude/.credentials.json" ] && [ "$(stat -c %U "$h/.claude/.credentials.json" 2>/dev/null)" = "$u" ] && eng="claude"
    [ -f "$h/.codex/auth.json" ] && [ "$(stat -c %U "$h/.codex/auth.json" 2>/dev/null)" = "$u" ] && eng="${eng:+$eng }codex"
    if [ -n "$eng" ]; then ENGINE_USER="$u"; ENGINE_HOME="$h"; DROP_ENGINES="$eng"; break; fi
  done
  [ -n "$ENGINE_USER" ] || return 0
  ENGINE_REPO="$ENGINE_HOME/.cache/monad-maint"
  if su - "$ENGINE_USER" -c "set -e; if [ -d '$ENGINE_REPO/.git' ]; then git -C '$ENGINE_REPO' fetch --depth 1 origin main -q && git -C '$ENGINE_REPO' reset --hard origin/main -q; else mkdir -p '$ENGINE_HOME/.cache'; git clone --depth 1 https://github.com/eliott-monad/monad '$ENGINE_REPO' -q; fi" 2>/dev/null && [ -f "$ENGINE_REPO/meta/agent/run-agent.sh" ]; then
    DROP_PRIV=1; AGENT_REPO="$ENGINE_REPO"
    log "engine runs as non-root user '$ENGINE_USER' (engines: $DROP_ENGINES) from $ENGINE_REPO"
    event "maintenance" "engine-user" "ok" "$ENGINE_USER engines=$DROP_ENGINES"
  else
    ENGINE_REPO="$REPO_DIR"
    log "engine-user '$ENGINE_USER' clone failed — engine will run as root (may fail on claude)"
    event "maintenance" "engine-user" "clone-fail" "$ENGINE_USER"
  fi
}

run_task() { # $1=prompt-file  $2=task-id  -> echoes exit code
  local pf="$1" id="$2" out rc
  out="$(engine_run "$pf" "${TASK_TIMEOUT:-1200}" 2>&1)"; rc=$?
  nomad var put -force "$RESULTS/$id" \
    node="$NODE" engine="$ENGINE" exit_code="$rc" \
    finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    summary="$(printf '%s' "$out" | tail -40)" >/dev/null 2>&1 || true
  echo "$rc"
}

drain_queue() { # returns 0 if it ran at least one task
  local listed ran=1 path id pf
  # -out=terse prints one path per line (plus a trailing UI hint) — keep only our queue
  # paths. Watch the lowercased queue too when it differs (case-mismatched delegations).
  listed="$(nomad var list -out=terse "$QUEUE/" 2>/dev/null | grep "^$QUEUE/")"
  if [ "$QUEUE_LC" != "$QUEUE" ]; then
    listed="$listed
$(nomad var list -out=terse "$QUEUE_LC/" 2>/dev/null | grep "^$QUEUE_LC/")"
  fi
  listed="$(printf '%s\n' "$listed" | grep -v '^$')"
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
Your repo (GitOps source of truth) is at: $AGENT_REPO  (use the 'monad' CLI; NOMAD_ADDR is set).

STANDING MANDATE — read $AGENT_REPO/meta/CLUSTER-HEALTH.md. You are responsible NOT just for
"$NODE" but for the constant health of the WHOLE roster (v1410-1, oraclebox1, claudebox,
eliotts-mac-mini, windesk). Do a cluster-health sweep and report concisely (<14 lines):

A. SELF (cheap, always safe):
   - disk: clean obviously-safe junk (old logs in logs/, /tmp, 'docker system prune -f' if docker is idle) ONLY if disk pressure is real.
   - git: if the repo is behind origin/main and clean, fast-forward; never force or discard local work.
   - nomad: confirm the local agent is healthy; engines: run meta/agent/ensure-engines.sh so this node stays installed + advertised.
B. PEERS (every other roster node): check 'nomad server members' (quorum: >=2 voters alive),
   'nomad node status' (each member ready+eligible), 'tailscale status' (who's offline), and
   'nomad job status maintenance-agent' (one running alloc per member).
C. ACT on any unhealthy peer, but COORDINATE so 5 nodes don't stampede the same fix:
   - CLAIM first: bash scripts/cluster-memory.sh set "health:<peer>" "$NODE"; proceed only if the value is "$NODE".
   - Then take the SMALLEST fix per CLUSTER-HEALTH.md: delegate a task to monad/maintenance/<peer>/queue/,
     restart a failed alloc, redeploy maintenance-agent, or bring a server back for quorum.
   - "Spawn programs as needed" is authorized (restart nomad, relaunch agents, ensure-engines,
     redeploy a job) — but pick the least-disruptive option and AVOID destructive/irreversible
     actions (no data wipes, force-pushes, or cluster-wide restarts). If a fix is risky or
     unclear, ESCALATE instead: log it and emit a task (meta/coordination/task.sh emit infra ...).
   - Release the claim when done: bash scripts/cluster-memory.sh set "health:<peer>" "DONE-\$(date -u +%FT%TZ)".
Quorum loss (fewer than 2 servers alive) is the top priority. Report: what you checked across
the roster, what you fixed/claimed, and anything escalated.
EOF
  if [ "${ON_MESH:-0}" = 1 ]; then
    local inbox; inbox="$(LOCAL_PORT="$LOCAL_PORT" "$AGENT_MSG" recv 2>/dev/null)"
    cat >> "$pf" <<EOF

You are on the Tailscale agent mesh as "$MESH_NAME". Coordinate with peers using:
  LOCAL_PORT=$LOCAL_PORT bash $AGENT_REPO/meta/agent/mesh/agent-msg.sh peers          # list peer agents
  LOCAL_PORT=$LOCAL_PORT bash $AGENT_REPO/meta/agent/mesh/agent-msg.sh send <peer> <text>
Messages addressed to you since last pass: ${inbox:-[none]}
If a peer asked you something or a cross-node issue needs coordinating, reply to them.
EOF
  fi
  log "self-maintenance pass (engine=$ENGINE user=${ENGINE_USER:-$(id -un)})"
  event "maintenance" "self-pass" "start" ""
  local out; out="$(engine_run "$pf" "${SELF_TIMEOUT:-600}" 2>&1)"; rc=$?
  nomad var put -force "$LAST" node="$NODE" engine="$ENGINE" exit_code="$rc" \
    finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)" summary="$(printf '%s' "$out" | tail -40)" >/dev/null 2>&1 || true
  event "maintenance" "self-pass" "$([ "$rc" = 0 ] && echo ok || echo fail)" "rc=$rc"
  rm -f "$pf"
}

log "maintenance-agent starting (interval=${INTERVAL}s poll=${POLL}s engine=$ENGINE)"

# Join the Tailscale agent mesh as agent-maint-<node> so this standing agent is a reachable
# peer and can coordinate with the rest of the fleet. Best-effort, non-fatal.
MESH_NAME="agent-maint-${NODE}"
if p="$("$REPO_DIR/meta/agent/mesh/mesh-attach.sh" "$MESH_NAME" 2>/dev/null)"; then
  export LOCAL_PORT="$p"
  AGENT_MSG="$REPO_DIR/meta/agent/mesh/agent-msg.sh"
  ON_MESH=1
  log "on mesh as $MESH_NAME (local api :$p)"
  event "mesh" "attach" "ok" "$MESH_NAME"
else
  ON_MESH=0
  log "not on mesh (sidecar unavailable) — continuing off-mesh"
fi

# If we're root (alloc-clone fallback, no host checkout), set up running the engine as a
# credentialed non-root user — claude refuses --dangerously-skip-permissions as root.
detect_engine_user

event "maintenance" "boot" "ok" "engines=$(ready_engines) drop_priv=$DROP_PRIV engine_user=${ENGINE_USER:-none} mesh=$ON_MESH"
# Wait one interval before the first self-pass so (re)starts don't burst LLM calls;
# brain-delegated queue tasks still run immediately.
last_self="$(date +%s)"
while true; do
  if ! engine_ready_now; then
    log "no engine ready — running ensure-engines and idling"
    "$REPO_DIR/meta/agent/ensure-engines.sh" >/dev/null 2>&1 || true
    # creds may have appeared (or a user's) — re-detect for the next cycle.
    detect_engine_user
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
