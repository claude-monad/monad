#!/usr/bin/env bash
# math-fanout.sh — launch one Claude math worker on EVERY capable node ("all the nodes that can
# handle it"). For each node that is ready + Linux + Claude-ready (meta.has_claude) + not currently
# overloaded + not already running a worker, it renders a node-PINNED worker job and runs it. The
# seed (the research brief) is read at runtime from the campaign Nomad var, so it stays central.
#
# Why pinned per node: dispatch meta can't drive a constraint and Nomad batch binpacks (everything
# lands on death-star otherwise). A per-node pinned job guarantees true spread across the cluster.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"; export NOMAD_ADDR
CAMPAIGN_VAR="${CAMPAIGN_VAR:-monad/campaign/signed-lrc}"
log() { echo "[fanout $(date '+%H:%M:%S')] $*"; }

# Capable nodes: ready + linux + has_claude + NOT flagged overloaded by the governor.
mapfile -t NODES < <(python3 - "$NOMAD_ADDR" <<'PY'
import json,sys,urllib.request
base=sys.argv[1].rstrip('/')
def api(p,timeout=10,retries=1):
    for a in range(retries+1):
        try:
            return json.load(urllib.request.urlopen(base+p,timeout=timeout))
        except Exception:
            if a==retries: raise
try:
    nodes=api('/v1/nodes')
except Exception as e:
    sys.stderr.write(f"cannot list nodes: {e}\n"); sys.exit(1)
for n in nodes:
    if n.get('Status')!='ready': continue
    # Tolerate a slow/unreachable node — skip it rather than crash the whole fanout.
    try:
        d=api('/v1/node/'+n['ID'])
        allocs=api('/v1/node/'+n['ID']+'/allocations')
    except Exception:
        sys.stderr.write(f"skip {n.get('Name')} (api slow)\n"); continue
    attrs=d.get('Attributes',{}) or {}; meta=d.get('Meta',{}) or {}
    if attrs.get('kernel.name')!='linux': continue
    if str(meta.get('has_claude','')).lower()!='true': continue
    nr=d.get('NodeResources',{}); tot=(nr.get('Memory',{}) or {}).get('MemoryMB',0) or 1
    amem=0
    for al in allocs:
        if al.get('ClientStatus')=='running':
            for t in (al.get('AllocatedResources',{}).get('Tasks') or {}).values():
                amem+=(t.get('Memory') or {}).get('MemoryMB',0)
    if amem/tot > 0.80:
        sys.stderr.write(f"skip {n['Name']} (mem {amem}/{tot})\n"); continue
    print(n['Name'])
PY
)

[ "${#NODES[@]}" -gt 0 ] || { log "no capable nodes found"; exit 0; }
log "capable nodes: ${NODES[*]}"

for NODE in "${NODES[@]}"; do
  JOB="math-worker-$(echo "$NODE" | tr '[:upper:].' '[:lower:]-')"
  # already a worker running on this node?
  if nomad job status "$JOB" >/dev/null 2>&1 && nomad job status "$JOB" 2>/dev/null | grep -qE '\brunning\b'; then
    log "$NODE: worker already running ($JOB) — skip"; continue
  fi
  TMP="$(mktemp /tmp/mathworker.XXXXXX.hcl)"
  cat > "$TMP" <<HCL
job "$JOB" {
  datacenters = ["dc1"]
  type        = "batch"
  priority    = 60
  constraint {
    attribute = "\${node.unique.name}"
    value     = "$NODE"
  }
  group "w" {
    count = 1
    reschedule {
      attempts  = 0
      unlimited = false
    }
    restart {
      attempts = 0
      mode     = "fail"
    }
    task "session" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args = ["-c", "W=/tmp/mw-monad; if [ -d \"\$W/.git\" ]; then git -C \"\$W\" fetch -q origin main && git -C \"\$W\" reset --hard -q origin/main || true; else rm -rf \"\$W\"; git clone -q --depth 1 https://github.com/eliott-monad/monad \"\$W\"; fi; export SEED=\"\$(nomad var get -item=seed $CAMPAIGN_VAR 2>/dev/null)\"; exec bash \"\$W/scripts/math-session.sh\" explorer 100"]
      }
      env {
        MATH_REPO_URL = "https://github.com/eliottcassidy2000/math.git"
        NOMAD_ADDR    = "$NOMAD_ADDR"
        MESH_RELAY    = "http://100.75.75.39:8477"
        AGENT_NAME    = "agent-mathworker-$NODE"
      }
      resources {
        cpu    = 500
        memory = 1024
      }
      kill_timeout = "15s"
    }
  }
}
HCL
  if nomad job run "$TMP" >/dev/null 2>&1; then log "$NODE: launched $JOB"; else log "$NODE: launch FAILED"; fi
  rm -f "$TMP"; sleep 1
done
log "fanout complete across ${#NODES[@]} node(s)"
