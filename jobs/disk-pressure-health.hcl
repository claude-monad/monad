# disk-pressure-health — standing, low-noise, READ-ONLY monitor of host root-disk
# pressure across the cluster, folded into the single fleet signal.
#
# Motivated by fleet/projects/disk-pressure-health.md: fleet-health-rollup aggregates
# raft/registry/backup/checkout/maintenance/service health, but HOST ROOT-DISK pressure
# is not a component — a current, cluster-threatening blind spot:
#   - oraclebox1 / : ~84.8% used, ~7.2 GB free (47 GB). It is a RAFT VOTER and runs the
#     conductor/foreman/fleet-builder/concierge agents; a full root => Nomad server data
#     dir + Raft logs + agent allocs break => quorum risk.
#   - bigo-server / : ~84.7% used, ~17 GB free (117 GB). Keystone stateful host: registry
#     + 3x registry backups + postgres + vars backups, all growing on one disk.
# registry-health measures bigo-server's disk but keeps status=healthy, so the pressure
# is invisible. node-doctors log disk to CSV but not into the single signal.
#
# How: query the Nomad API (no host SSH, no creds, dynamic roster) —
#   GET /v1/nodes                       -> ready node ids+names
#   GET /v1/client/stats?node_id=<uuid> -> DiskStats[] (find the root "/" mount)
# and write a compact per-node verdict to fleet/disk-health/<node>. The rollup globs
# fleet/disk-health/ so each node appears as a disk:<node> component (the rollup already
# normalizes "critical" and synth_detail already reads disk_used_pct); individually
# ack-able via fleet/health-ack.
#
# Thresholds: warn at used% >= 85 OR free < 10 GB; critical at used% >= 93 OR free < 4 GB.
#
# Quiet by design: each var is overwritten per run (no log/commit spam); a status
# transition is captured in the var (prev_status + changed_at), mirroring
# jobs/keystone-service-liveness.hcl / jobs/registry-health.hcl.
#
# NOTE: script body avoids ${...} brace expansions because Nomad HCL2 would interpret
# them as interpolation inside the heredoc; use $VAR throughout.
job "disk-pressure-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to oraclebox1: the stable voter that hosts the rollup + the other fleet monitors
  # and can reach the Nomad API over the tailnet. Same placement as fleet-health-rollup /
  # raft-quorum-health / keystone-service-liveness. The job is a tiny read-only curl+python.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "disk-pressure-health" {
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
        WARN_PCT      = "85"
        CRIT_PCT      = "93"
        WARN_FREE_GB  = "10"
        CRIT_FREE_GB  = "4"
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
# read-only host root-disk pressure probe -> Nomad vars fleet/disk-health/<node>
set -uo pipefail

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
API="$NOMAD_ADDR"
TMO="$PROBE_TIMEOUT"

# put_node <node> <status> <used_pct> <avail_gb> <size_gb> <mount> <device> <detail>
# overwrites fleet/disk-health/<node>, stamping changed_at on a status transition.
put_node() {
  local node="$1" st="$2" upct="$3" avail="$4" size="$5" mnt="$6" dev="$7" det="$8"
  local hvar="fleet/disk-health/$node"
  local prev prevlabel ca trans
  prev="$(nomad var get -item=status "$hvar" 2>/dev/null || echo '')"
  prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
  ca="$(nomad var get -item=changed_at "$hvar" 2>/dev/null || echo '')"
  trans="(none)"
  if [ "$prev" != "$st" ]; then ca="$now"; trans="$prevlabel->$st"; fi
  [ -n "$ca" ] || ca="$now"
  nomad var put -force "$hvar" \
    status="$st" used_pct="$upct" avail_gb="$avail" size_gb="$size" \
    mount="$mnt" device="$dev" detail="$det" \
    prev_status="$prevlabel" changed_at="$ca" ts="$now" >/dev/null 2>&1 \
    || { echo "[disk-health] WARN: nomad var put failed for $node"; return 0; }
  echo "[disk-health] $node status=$st used=$upct pct free=$avail GB transition=$trans"
}

# fetch ready nodes (name<TAB>id) from the API
nodes_json="$(curl -s --max-time "$TMO" "$API/v1/nodes" 2>/dev/null)"
if [ -z "$nodes_json" ]; then
  echo "[disk-health] ERROR: could not list nodes from $API/v1/nodes"
  exit 0
fi

# iterate ready nodes; for each, read DiskStats for the root mount via client/stats
echo "$nodes_json" | python3 -c '
import sys, json
nodes = json.load(sys.stdin)
for n in nodes:
    if n.get("Status") == "ready":
        print(n.get("Name",""), n.get("ID",""))
' | while read -r name id; do
  [ -n "$id" ] || continue
  stats="$(curl -s --max-time "$TMO" "$API/v1/client/stats?node_id=$id" 2>/dev/null)"
  # parse the root "/" mount; emit: used_pct|avail_gb|size_gb|device  (or empty on miss)
  parsed="$(printf '%s' "$stats" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ds = d.get("DiskStats") or []
root = None
for x in ds:
    if x.get("Mountpoint") == "/":
        root = x; break
if root is None:
    sys.exit(0)
upct = root.get("UsedPercent") or 0.0
avail = (root.get("Available") or 0) / 1e9
size = (root.get("Size") or 0) / 1e9
dev = root.get("Device") or "?"
print("%.1f|%.1f|%.1f|%s" % (upct, avail, size, dev))
' 2>/dev/null)"

  if [ -z "$parsed" ]; then
    echo "[disk-health] skip $name: no root-mount stats (unreachable/flaky client)"
    continue
  fi

  IFS='|' read -r upct avail size dev <<EOF
$parsed
EOF

  # classify: critical (>= CRIT_PCT or < CRIT_FREE_GB) > warn (>= WARN_PCT or < WARN_FREE_GB) > healthy
  st="healthy"
  if awk -v u="$upct" -v a="$avail" -v cp="$CRIT_PCT" -v cf="$CRIT_FREE_GB" \
       'BEGIN{exit !(u>=cp || a<cf)}'; then
    st="critical"
  elif awk -v u="$upct" -v a="$avail" -v wp="$WARN_PCT" -v wf="$WARN_FREE_GB" \
       'BEGIN{exit !(u>=wp || a<wf)}'; then
    st="warn"
  fi

  det="root $dev $upct pct used, $avail GB free of $size GB"
  put_node "$name" "$st" "$upct" "$avail" "$size" "/" "$dev" "$det"
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
