# node-overload-health — standing, low-noise, READ-ONLY monitor of sustained per-node
# CPU/memory saturation, folded into the single fleet signal.
#
# Motivated by fleet/projects/node-overload-health.md: fleet-health-rollup now folds host
# root-DISK pressure into fleet/health-summary (disk-pressure-health), and the dashboard
# resources panel (dashboard-resources-engine) shows per-node CPU/mem/disk + overload
# flags — but the SINGLE signal still has no CPU/mem component. A node pinned at 100% CPU
# / out of RAM is invisible to fleet/health-summary today; only its disk is. This is the
# exact blind spot dashboard-resources-engine.md calls out: "oraclebox1 is chronically
# saturated (CPU ~100%, RAM ~85%)".
#
# This is the natural complement to disk-pressure-health: same proven pattern, different
# resource. Read-only, no host SSH/creds, dynamic roster via the Nomad API —
#   GET /v1/nodes                       -> ready node ids+names
#   GET /v1/client/stats?node_id=<uuid> -> CPU[] (avg TotalPercent) + Memory (Used/Total)
# and writes a compact per-node verdict to fleet/overload-health/<node>. The rollup globs
# fleet/overload-health/ so each node appears as an overload:<node> component (the monitor
# sets `detail`, so synth_detail needs no change); individually ack-able via fleet/health-ack.
#
# SUSTAINED, not spiky: a single 15m sample cannot tell a CPU spike from saturation, so we
# persist a consecutive-over-threshold `over_streak` in the var:
#   - warn     : CPU >= WARN_CPU OR mem >= WARN_MEM right now (one over-threshold sample)
#   - critical : over_streak >= CRIT_STREAK runs (>= ~1h at the 15m cadence) — proven sustained
#   - healthy  : under threshold
#
# Quiet by design: each var is overwritten per run (no log/commit spam); a status
# transition is captured in the var (prev_status + changed_at), mirroring
# jobs/disk-pressure-health.hcl / jobs/keystone-service-liveness.hcl.
#
# NOTE: script body avoids ${...} brace expansions because Nomad HCL2 would interpret
# them as interpolation inside the heredoc; use $VAR throughout.
job "node-overload-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to oraclebox1: the stable voter that hosts the rollup + the other fleet monitors
  # and can reach the Nomad API over the tailnet. Same placement as fleet-health-rollup /
  # disk-pressure-health. The job is a tiny read-only curl+python.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "node-overload-health" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "probe" {
      driver = "raw_exec"

      env {
        NOMAD_ADDR    = "http://100.125.210.126:4646"
        PROBE_TIMEOUT = "8"
        WARN_CPU      = "90"
        WARN_MEM      = "90"
        CRIT_STREAK   = "4"
      }

      config {
        command = "/bin/bash"
        args    = ["local/probe.sh"]
      }

      template {
        destination = "local/probe.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only per-node CPU/mem saturation probe -> Nomad vars fleet/overload-health/<node>
set -uo pipefail

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
API="$NOMAD_ADDR"
TMO="$PROBE_TIMEOUT"

# put_node <node> <status> <cpu_pct> <mem_pct> <over_streak> <detail>
# overwrites fleet/overload-health/<node>, stamping changed_at on a status transition.
put_node() {
  local node="$1" st="$2" cpu="$3" mem="$4" streak="$5" det="$6"
  local hvar="fleet/overload-health/$node"
  local prev prevlabel ca trans
  prev="$(nomad var get -item=status "$hvar" 2>/dev/null || echo '')"
  prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
  ca="$(nomad var get -item=changed_at "$hvar" 2>/dev/null || echo '')"
  trans="(none)"
  if [ "$prev" != "$st" ]; then ca="$now"; trans="$prevlabel->$st"; fi
  [ -n "$ca" ] || ca="$now"
  nomad var put -force "$hvar" \
    status="$st" cpu_pct="$cpu" mem_pct="$mem" over_streak="$streak" \
    warn_cpu="$WARN_CPU" warn_mem="$WARN_MEM" crit_streak="$CRIT_STREAK" \
    detail="$det" prev_status="$prevlabel" changed_at="$ca" ts="$now" >/dev/null 2>&1 \
    || { echo "[overload-health] WARN: nomad var put failed for $node"; return 0; }
  echo "[overload-health] $node status=$st cpu=$cpu pct mem=$mem pct streak=$streak transition=$trans"
}

# fetch ready nodes (name<TAB>id) from the API
nodes_json="$(curl -s --max-time "$TMO" "$API/v1/nodes" 2>/dev/null)"
if [ -z "$nodes_json" ]; then
  echo "[overload-health] ERROR: could not list nodes from $API/v1/nodes"
  exit 0
fi

echo "$nodes_json" | python3 -c '
import sys, json
nodes = json.load(sys.stdin)
for n in nodes:
    if n.get("Status") == "ready":
        print(n.get("Name",""), n.get("ID",""))
' | while read -r name id; do
  [ -n "$id" ] || continue
  stats="$(curl -s --max-time "$TMO" "$API/v1/client/stats?node_id=$id" 2>/dev/null)"
  # parse live util; emit: cpu_pct|mem_pct  (or empty on miss/unreachable)
  parsed="$(printf '%s' "$stats" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cpus = d.get("CPU") or []
mem = d.get("Memory") or {}
if not cpus and not mem.get("Total"):
    sys.exit(0)
cpu_pct = (sum((c.get("TotalPercent") or 0) for c in cpus) / len(cpus)) if cpus else 0.0
mem_pct = (100.0 * (mem.get("Used") or 0) / mem["Total"]) if mem.get("Total") else 0.0
print("%.1f|%.1f" % (cpu_pct, mem_pct))
' 2>/dev/null)"

  if [ -z "$parsed" ]; then
    echo "[overload-health] skip $name: no live stats (unreachable/flaky client)"
    continue
  fi

  IFS='|' read -r cpu mem <<EOF
$parsed
EOF

  # prior streak of consecutive over-threshold runs (persisted in the var)
  hvar="fleet/overload-health/$name"
  prev_streak="$(nomad var get -item=over_streak "$hvar" 2>/dev/null || echo '')"
  case "$prev_streak" in ''|*[!0-9]*) prev_streak=0 ;; esac

  # over threshold now?  (CPU >= WARN_CPU OR mem >= WARN_MEM)
  if awk -v c="$cpu" -v m="$mem" -v wc="$WARN_CPU" -v wm="$WARN_MEM" \
       'BEGIN{exit !(c>=wc || m>=wm)}'; then
    over=1
    streak=$((prev_streak + 1))
  else
    over=0
    streak=0
  fi

  # classify: critical (sustained: streak >= CRIT_STREAK) > warn (over now) > healthy
  if [ "$over" = "1" ] && [ "$streak" -ge "$CRIT_STREAK" ]; then
    st="critical"
    det="sustained: cpu $cpu pct / mem $mem pct over thr ($WARN_CPU/$WARN_MEM) for $streak runs"
  elif [ "$over" = "1" ]; then
    st="warn"
    det="high: cpu $cpu pct / mem $mem pct (thr $WARN_CPU/$WARN_MEM), run $streak/$CRIT_STREAK"
  else
    st="healthy"
    det="cpu $cpu pct / mem $mem pct (thr $WARN_CPU/$WARN_MEM)"
  fi

  put_node "$name" "$st" "$cpu" "$mem" "$streak" "$det"
done

exit 0
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 128
      }

      kill_timeout = "20s"
    }
  }
}
