# fleet-health-rollup — standing, low-noise aggregator of the fleet's scattered
# health monitors. READ-ONLY: it only reads existing Nomad vars (the per-monitor
# verdicts) and writes a single rollup var fleet/health-summary.
#
# Motivated by fleet/projects/fleet-health-rollup.md: the fleet built several
# standing monitors, each writing to its OWN var with nothing tying them together:
#   - fleet/raft-health            (raft-quorum-health, every 15m)
#   - fleet/registry-health        (registry-health, every 6h)
#   - fleet/backup-health          (backup-health, every 30m)
#   - fleet/checkout-health/<node> (agent-checkout-health, every 6h, per node)
#   - fleet/job-hygiene            (nomad-job-hygiene, every 30m)
# To answer "is the cluster healthy?" you had to read 5+ vars, and a monitor that
# silently dies still reads "healthy" (its var freezes). This rolls them into one
# fleet/health-summary: overall status (worst component), per-component breakdown,
# and STALENESS detection (a component whose ts is older than its threshold is
# reported as degraded instead of a frozen "healthy").
#
# Quiet by design: overwrites the single var each run; a status transition is
# captured via prev_status + changed_at, mirroring jobs/raft-quorum-health.hcl.
#
# ACKNOWLEDGEMENT LAYER (fleet/projects/health-summary-acknowledge.md, #23): the
# top-line `status` is the worst of components NOT acknowledged in the optional
# var fleet/health-ack (item `acks` = ';'-list of `component|acked_status|reason`).
# A component is covered only while its current status is no worse than its acked
# level -- so an accepted, owner-gated condition (e.g. the #11 wrong-origin
# checkouts) doesn't pin the signal to warn, but a NEW degradation beyond the
# acked level still trips it. Acks never hide a component: `raw_status` (worst of
# ALL components) and the full `components`/`d_*` breakdown are unchanged, and
# covered components are listed under `acknowledged`. No ack var => old behavior.
#
# PERIPHERAL SEVERITY CAP (fleet/projects/health-summary-node-severity.md, #40): a
# PERIPHERAL node's local resource pressure must not force the whole-cluster headline to
# `critical`. Nodes listed in env KEYSTONE_NODES (Raft voters + the keystone-service host)
# escalate at full severity; for `disk:<node>` / `overload:<node>` components on any other
# node, the value used for the top-line `status` is capped at `warn`. Nothing is hidden:
# `raw_status`, `components`, and every `d_*` keep TRUE severity, and any reduction is
# listed in the `peripheral_capped` item (e.g. disk:eliotts-mac-mini=critical->warn).
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
        STALE_BACKUP   = "7200"
        STALE_CHECKOUT = "28800"
        STALE_MAINT    = "7200"
        STALE_SERVICE  = "3600"
        STALE_ENGINE   = "7200"
        STALE_JOBS     = "7200"
        STALE_ESCALATION = "3600"
        # health-summary-node-severity (#40): nodes whose local resource pressure is
        # cluster-critical (Raft voters + the keystone-service host). A disk:/overload:
        # component on a node NOT in this list is capped at `warn` for the HEADLINE
        # `status` only -- its true severity still shows in raw_status/components/d_*.
        KEYSTONE_NODES = "v1410-1,oraclebox1,claudebox,bigo-server"
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
stale_bak  = int(os.environ.get("STALE_BACKUP", "7200") or "7200")
# backup-restore-verify (#29) runs once daily (test-restores are heavy), so it needs a
# generous staleness window — ~36h covers a fully-missed run without false "stale" trips.
stale_brv  = int(os.environ.get("STALE_BACKUP_RESTORE", "129600") or "129600")
stale_co   = int(os.environ.get("STALE_CHECKOUT", "28800") or "28800")
stale_mt   = int(os.environ.get("STALE_MAINT", "7200") or "7200")
# keystone-service-liveness (#31) probes the dashboard + postgres every 10m, one var
# per service; ~6x the interval gives a generous staleness window.
stale_svc  = int(os.environ.get("STALE_SERVICE", "3600") or "3600")
# disk-pressure-health (disk-pressure-health.md) probes host root-disk every 15m, one
# var per node; ~4x the interval gives a generous staleness window.
stale_disk = int(os.environ.get("STALE_DISK", "3600") or "3600")
# engine-coverage-health (engine-coverage-health.md) probes agent-engine coverage every
# 30m into one var; ~4x the interval gives a generous staleness window.
stale_engine = int(os.environ.get("STALE_ENGINE", "7200") or "7200")
# node-overload-health (node-overload-health.md) probes per-node CPU/mem saturation every
# 15m, one var per node; ~4x the interval gives a generous staleness window.
stale_overload = int(os.environ.get("STALE_OVERLOAD", "3600") or "3600")
# nomad-job-hygiene (nomad-job-hygiene.md) probes committed long-running job drift every
# 30m into one var; ~4x the interval gives a generous staleness window.
stale_jobs = int(os.environ.get("STALE_JOBS", "7200") or "7200")
# escalation-capture-health probes captured gh-less GitHub escalations every 10m.
stale_escalation = int(os.environ.get("STALE_ESCALATION", "3600") or "3600")
# health-history-trends (every 15m) publishes fleet/health-trend; its `status` folds in
# WRITER liveness (now vs the latest health_snapshots row), so this component catches a
# stalled health-history time-series. The var `ts` staleness separately catches the
# trends job itself dying; ~4x the 15m interval is a generous window.
stale_trend = int(os.environ.get("STALE_TREND", "3600") or "3600")

comps = [("raft", "fleet/raft-health", stale_raft),
         ("registry", "fleet/registry-health", stale_reg),
         ("backup", "fleet/backup-health", stale_bak),
         ("backup-restore", "fleet/backup-restore-verify", stale_brv),
         ("engine", "fleet/engine-coverage", stale_engine),
         ("jobs", "fleet/job-hygiene", stale_jobs),
         ("escalation", "fleet/escalation-health", stale_escalation),
         ("health-history", "fleet/health-trend", stale_trend)]
for p in sorted(list_paths("fleet/checkout-health/")):
    node = p.rsplit("/", 1)[-1]
    comps.append(("checkout:" + node, p, stale_co))
# maintenance-agent-health (#25) publishes one var per node, like checkout-health;
# surface each as a maintenance:<node> component so the cluster's immune system is
# part of the single signal (and individually ack-able via fleet/health-ack).
for p in sorted(list_paths("fleet/maintenance-health/")):
    node = p.rsplit("/", 1)[-1]
    comps.append(("maintenance:" + node, p, stale_mt))
# keystone-service-liveness (#31) publishes one var per keystone service
# (dashboard, postgres), like checkout-health/maintenance-health; surface each as a
# service:<svc> component so the fleet's OWN services are part of the single signal
# (and individually ack-able via fleet/health-ack).
for p in sorted(list_paths("fleet/service-health/")):
    svc = p.rsplit("/", 1)[-1]
    comps.append(("service:" + svc, p, stale_svc))
# disk-pressure-health publishes one var per node (root-disk used%/free GB), like
# checkout-health/maintenance-health; surface each as a disk:<node> component so host
# disk pressure on keystone/voter nodes is part of the single signal (and individually
# ack-able via fleet/health-ack). synth_detail already renders disk_used_pct.
for p in sorted(list_paths("fleet/disk-health/")):
    node = p.rsplit("/", 1)[-1]
    comps.append(("disk:" + node, p, stale_disk))
# node-overload-health publishes one var per node (sustained CPU/mem saturation), like
# disk-health; surface each as an overload:<node> component so a node pinned at 100% CPU /
# out of RAM is part of the single signal (and individually ack-able via fleet/health-ack).
# The monitor sets `detail`, so synth_detail renders it directly.
for p in sorted(list_paths("fleet/overload-health/")):
    node = p.rsplit("/", 1)[-1]
    comps.append(("overload:" + node, p, stale_overload))

# The monitors use inconsistent status words; normalize to one 4-state scale so
# the rollup (and the dashboard) speak a single vocabulary.
NORM = {"healthy": "healthy", "ok": "healthy",
        "warn": "warn", "unhealthy": "warn", "stale": "warn",
        "critical": "critical",
        "unknown": "unknown", "none": "unknown", "": "unknown"}
RANK = {"healthy": 0, "unknown": 1, "warn": 2, "critical": 3}
def norm(s):
    return NORM.get((s or "").lower(), "unknown")
def rank(s):
    return RANK.get(s, 1)

def synth_detail(items):
    # prefer an explicit detail; else compose one from common monitor fields
    d = (items.get("detail") or "").strip()
    if d:
        return d[:140]
    bits = []
    for k in ("origin_ok", "key_files_ok", "behind", "dirty", "disk_used_pct",
              "leader_present", "voter_count"):
        if k in items:
            bits.append("%s=%s" % (k, items[k]))
    return " ".join(bits)[:140]

# Acknowledged conditions: fleet/health-ack carries a single item `acks`, a
# ';'-separated list of `component|acked_status|reason` (component names contain
# ':' but never '|' or ';'). A component is "covered" while its current effective
# status is no WORSE than its acked status (rank <= acked rank) -- so an accepted,
# owner-gated condition (e.g. the #11 wrong-origin checkouts) does not pin the
# top-line, but if it degrades BEYOND what was accepted it counts again. Absent
# var => no acks => behaves exactly as before. Acks never hide a component: it
# still appears in `components`/`d_*` and is listed under `acknowledged`.
ack_items = var_items("fleet/health-ack") or {}
acks = {}  # component -> (acked_status, reason)
for entry in (ack_items.get("acks", "") or "").split(";"):
    entry = entry.strip()
    if not entry:
        continue
    parts = entry.split("|")
    comp = parts[0].strip()
    if not comp:
        continue
    ast = norm(parts[1].strip()) if len(parts) > 1 and parts[1].strip() else "warn"
    reason = parts[2].strip() if len(parts) > 2 else ""
    acks[comp] = (ast, reason)

results = {}   # name -> normalized status
details = {}   # name -> short detail
stale_list = []
overall = "healthy"

for name, path, thresh in comps:
    items = var_items(path)
    if items is None:
        eff = "unknown"
        det = "missing var " + path
    else:
        a = age_secs(items.get("ts"))
        if a is not None and a > thresh:
            eff = "warn"   # stale monitor = degraded coverage
            det = "STALE monitor: last ts %s (%dm old > %dm threshold)" % (
                items.get("ts", "?"), a // 60, thresh // 60)
            stale_list.append(name)
        else:
            eff = norm(items.get("status"))
            det = synth_detail(items)
    results[name] = eff
    details[name] = det
    if rank(eff) > rank(overall):
        overall = eff

# raw_status = worst of ALL components (the pre-ack behavior, full transparency).
raw_status = overall

# health-summary-node-severity (#40): a PERIPHERAL node's local resource pressure must
# not force the whole-cluster headline to `critical`. Nodes in KEYSTONE_NODES (the Raft
# voters + the keystone-service host) escalate at full severity; for `disk:<node>` /
# `overload:<node>` components on any OTHER node, the value used for the HEADLINE `status`
# is capped at `warn`. True severity is untouched in results[] (raw_status/components/d_*);
# any reduction is recorded in `peripheral_capped` so it is explicit and auditable.
keystone = set(n.strip() for n in (os.environ.get("KEYSTONE_NODES", "") or "").split(",") if n.strip())
WARN = "warn"
capped_notes = []  # "disk:eliotts-mac-mini=critical->warn(peripheral)"
def headline_status(n):
    eff = results[n]
    if ":" in n:
        kind, node = n.split(":", 1)
        # empty KEYSTONE_NODES disables the cap entirely (== prior behavior), so dropping
        # the env can never accidentally suppress every node's disk/overload cluster-wide.
        if keystone and kind in ("disk", "overload") and node not in keystone and rank(eff) > rank(WARN):
            capped_notes.append("%s=%s->%s(peripheral)" % (n, eff, WARN))
            return WARN
    return eff

# Top-line `status` = worst of components NOT covered by an ack. A component is
# covered only while its current status is no worse than its acked level; if it
# degrades beyond what was accepted (or it's un-acked), it counts toward the
# top-line so a NEW problem still surfaces. The peripheral cap (#40) is applied to
# each component's headline contribution before this worst-of fold.
def covered(n):
    a = acks.get(n)
    return a is not None and rank(results[n]) <= rank(a[0])

status = "healthy"
for n, _, _ in comps:
    if covered(n):
        continue
    hs = headline_status(n)
    if rank(hs) > rank(status):
        status = hs
peripheral_capped_str = ",".join(capped_notes) if capped_notes else "none"

# acknowledged: components currently covered by an ack, with their reason.
ack_listed = []
for n, _, _ in comps:
    if covered(n):
        a = acks[n]
        ack_listed.append("%s=%s(%s)" % (n, results[n], a[1] or "acked"))
acknowledged_str = ",".join(ack_listed) if ack_listed else "none"

# foreman context (informational, not part of the verdict)
fs = var_items("fleet/status") or {}
foreman = "running=%s/%s todo=%s building=%s blocked=%s" % (
    fs.get("running", "?"), fs.get("target", "?"), fs.get("backlog_todo", "?"),
    fs.get("backlog_building", "?"), fs.get("backlog_blocked", "?"))

# human summary line, based on the actionable top-line status
actionable_bad = [n for n, _, _ in comps if results[n] != "healthy" and not covered(n)]
if status == "healthy":
    if ack_listed:
        detail = "all actionable components healthy (%d acknowledged: %s)" % (
            len(ack_listed), acknowledged_str)
    else:
        detail = "all %d components healthy" % len(comps)
else:
    detail = "%s: " % status + ", ".join("%s=%s" % (n, results[n]) for n in actionable_bad)
    if stale_list:
        detail += " | stale: " + ",".join(stale_list)
    if ack_listed:
        detail += " | ack: " + acknowledged_str
detail = detail[:200]

components_str = ";".join("%s=%s" % (n, results[n]) for n, _, _ in comps)

prev = var_items(HVAR) or {}
prev_status = prev.get("status", "none")
changed_at = prev.get("changed_at")
ca = changed_at if (changed_at and prev_status == status) else now_s

args = ["nomad", "var", "put", "-force", HVAR,
        "status=" + status,
        "raw_status=" + raw_status,
        "acknowledged=" + acknowledged_str,
        "peripheral_capped=" + peripheral_capped_str,
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
print("[health-rollup] status=%s raw=%s components=[%s] stale=%s ack=%s capped=%s" % (
    status, raw_status, components_str, ",".join(stale_list) or "none", acknowledged_str,
    peripheral_capped_str))
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
