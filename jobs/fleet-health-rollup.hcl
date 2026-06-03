# fleet-health-rollup — standing, low-noise aggregator of the fleet's scattered
# health monitors. READ-ONLY: it only reads existing Nomad vars (the per-monitor
# verdicts) and writes a single rollup var fleet/health-summary.
#
# Motivated by fleet/projects/fleet-health-rollup.md: the fleet built several
# standing monitors, each writing to its OWN var with nothing tying them together:
#   - fleet/raft-health            (raft-quorum-health, every 15m)
#   - fleet/registry-health        (registry-health, every 6h)
#   - fleet/checkout-health/<node> (agent-checkout-health, every 6h, per node)
# To answer "is the cluster healthy?" you had to read 5+ vars, and a monitor that
# silently dies still reads "healthy" (its var freezes). This rolls them into one
# fleet/health-summary: overall status (worst component), per-component breakdown,
# and STALENESS detection (a component whose ts is older than its threshold is
# reported as degraded instead of a frozen "healthy").
#
# Quiet by design: overwrites the single var each run; a status transition is
# captured via prev_status + changed_at, mirroring jobs/raft-quorum-health.hcl.
#
# The embedded probe is Python (clean JSON/var parsing). It contains no ${...}
# sequences, so Nomad HCL2 does not try to interpolate it.
job "fleet-health-rollup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]
    prohibit_overlap = true
  }

  # Pin to oraclebox1: the stable voter that hosts the conductor + the other fleet
  # monitors and can reach the Nomad API on the tailnet. Same placement as
  # raft-quorum-health.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "fleet-health-rollup" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "rollup" {
      driver = "raw_exec"

      env {
        NOMAD_ADDR = "http://100.125.210.126:4646"
        # per-component staleness thresholds in seconds (generous: ~4x the
        # monitor's own interval). A component older than this is "stale".
        STALE_RAFT     = "3600"
        STALE_REGISTRY = "28800"
        STALE_CHECKOUT = "28800"
      }

      config {
        command = "/usr/bin/env"
        args    = ["python3", "local/rollup.py"]
      }

      template {
        destination = "local/rollup.py"
        perms       = "755"
        data        = <<-SCRIPT
#!/usr/bin/env python3
# read-only fleet health rollup -> Nomad var fleet/health-summary
import json, os, subprocess, datetime

HVAR = "fleet/health-summary"
now = datetime.datetime.now(datetime.timezone.utc)
now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")

def run(args, timeout=20):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        class R: pass
        r = R(); r.returncode = 1; r.stdout = ""; r.stderr = str(e)
        return r

def var_items(path):
    # returns dict of items for a var path, or None if it doesn't exist
    r = run(["nomad", "var", "get", "-out=json", path])
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout).get("Items", {})
    except Exception:
        return None

def list_paths(prefix):
    r = run(["nomad", "var", "list", "-out=json", prefix])
    if r.returncode != 0:
        return []
    try:
        return [v["Path"] for v in json.loads(r.stdout)]
    except Exception:
        return []

def age_secs(ts):
    if not ts:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
        try:
            t = datetime.datetime.strptime(ts, fmt).replace(tzinfo=datetime.timezone.utc)
            return int((now - t).total_seconds())
        except Exception:
            continue
    return None

# component spec: name -> (var path, staleness threshold secs)
stale_raft = int(os.environ.get("STALE_RAFT", "3600") or "3600")
stale_reg  = int(os.environ.get("STALE_REGISTRY", "28800") or "28800")
stale_co   = int(os.environ.get("STALE_CHECKOUT", "28800") or "28800")

comps = [("raft", "fleet/raft-health", stale_raft),
         ("registry", "fleet/registry-health", stale_reg)]
for p in sorted(list_paths("fleet/checkout-health/")):
    node = p.rsplit("/", 1)[-1]
    comps.append(("checkout:" + node, p, stale_co))

# rank for "worst wins"
RANK = {"healthy": 0, "ok": 0, "unknown": 1, "stale": 2, "warn": 2, "critical": 3}
def rank(s):
    return RANK.get(s, 1)

results = {}   # name -> effective status
details = {}   # name -> short detail
stale_list = []
overall = "healthy"

for name, path, thresh in comps:
    items = var_items(path)
    if items is None:
        eff = "unknown"
        det = "missing var " + path
    else:
        raw = (items.get("status") or "unknown").lower()
        a = age_secs(items.get("ts"))
        if a is not None and a > thresh:
            eff = "stale"
            det = "monitor stale: last ts %s (%dm old > %dm)" % (
                items.get("ts", "?"), a // 60, thresh // 60)
            stale_list.append(name)
        else:
            eff = raw
            det = items.get("detail", "")[:120]
    results[name] = eff
    details[name] = det
    if rank(eff) > rank(overall):
        overall = eff

# normalize overall label
if overall == "ok":
    overall = "healthy"

# foreman context (informational, not part of the verdict)
fs = var_items("fleet/status") or {}
foreman = "running=%s/%s todo=%s building=%s blocked=%s" % (
    fs.get("running", "?"), fs.get("target", "?"), fs.get("backlog_todo", "?"),
    fs.get("backlog_building", "?"), fs.get("backlog_blocked", "?"))

# human summary line
bad = [n for n in results if rank(results[n]) >= 2]
if overall in ("healthy",):
    detail = "all %d components healthy" % len(comps)
elif overall == "unknown":
    detail = "some components unreadable: " + ", ".join(n for n in results if results[n] == "unknown")
else:
    detail = "degraded: " + ", ".join("%s=%s" % (n, results[n]) for n in bad)

components_str = ";".join("%s=%s" % (n, results[n]) for n, _, _ in comps)

prev = var_items(HVAR) or {}
prev_status = prev.get("status", "none")
changed_at = prev.get("changed_at")
ca = changed_at if (changed_at and prev_status == overall) else now_s

args = ["nomad", "var", "put", "-force", HVAR,
        "status=" + overall,
        "detail=" + detail,
        "components=" + components_str,
        "component_count=" + str(len(comps)),
        "stale=" + (",".join(stale_list) if stale_list else "none"),
        "foreman=" + foreman,
        "prev_status=" + prev_status,
        "changed_at=" + ca,
        "ts=" + now_s]
# attach each component's short detail for the dashboard/debugging
for n, _, _ in comps:
    key = "d_" + n.replace(":", "_")
    args.append(key + "=" + (details.get(n, "") or ""))

r = run(args)
if r.returncode != 0:
    print("[health-rollup] WARN: nomad var put failed: %s" % r.stderr.strip())
print("[health-rollup] overall=%s components=[%s] stale=%s" % (
    overall, components_str, ",".join(stale_list) or "none"))
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "20s"
    }
  }
}
