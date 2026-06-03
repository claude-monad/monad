# maintenance-agent-health — standing, low-noise monitor of the cluster's IMMUNE
# SYSTEM: the `maintenance-agent` system job that puts a standing agent on every
# linux node (meta/CLUSTER-HEALTH.md). Each self-pass writes its result to
# monad/maintenance/<node>/last (exit_code, finished, engine, summary), but nothing
# rolled those up — a node whose agent silently stops self-passing or starts exiting
# non-zero was invisible. This is the immune-system analogue of raft-quorum-health
# (#20) / registry-health (#17) / agent-checkout-health (#13).
#
# READ-ONLY: it only reads the maintenance-agent alloc set + node names + the
# monad/maintenance/<node>/last vars, and writes one var PER NODE:
#   fleet/maintenance-health/<node>  (status, exit_code, finished, engine, detail, ts)
# mirroring fleet/checkout-health/<node> so fleet-health-rollup (#22) auto-discovers
# them as `maintenance:<node>` components in the single fleet/health-summary signal.
# Per-node vars give per-node ACK granularity (health-summary-acknowledge, #23): an
# accepted gap (e.g. an engine-less node not reporting) can be acked without masking
# a NEW failure on another node.
#
# Quiet by design: overwrites each node's var every run; a status transition is
# captured via prev_status + changed_at, mirroring jobs/raft-quorum-health.hcl.
#
# The embedded probe is Python. It contains no ${...} sequences, so Nomad HCL2 does
# not try to interpolate it.
job "maintenance-agent-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/30 * * * *"]
    prohibit_overlap = true
  }

  # Pin to oraclebox1: the stable voter that hosts the conductor + the other fleet
  # monitors and can reach the Nomad API on the tailnet. Same placement as
  # raft-quorum-health / fleet-health-rollup.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "maintenance-agent-health" {
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
        NOMAD_ADDR = "http://100.125.210.126:4646"
        # a self-pass older than this (seconds) => the node's agent has stopped
        # self-passing. Generous (~12x the 30m monitor cadence) so normal cadence
        # never trips it, but a dead agent surfaces within a few hours.
        STALE_SELFPASS = "21600"
      }

      config {
        command = "/usr/bin/env"
        args    = ["python3", "local/probe.py"]
      }

      template {
        destination = "local/probe.py"
        perms       = "755"
        data        = <<-SCRIPT
#!/usr/bin/env python3
# read-only maintenance-agent health -> fleet/maintenance-health/<node>
import json, os, subprocess, datetime, urllib.request

now = datetime.datetime.now(datetime.timezone.utc)
now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")
STALE = int(os.environ.get("STALE_SELFPASS", "21600") or "21600")
NADDR = os.environ.get("NOMAD_ADDR", "http://127.0.0.1:4646").rstrip("/")

def api(path):
    # robust JSON read of the Nomad HTTP API (CLI -t templates vary by version)
    try:
        with urllib.request.urlopen(NADDR + path, timeout=20) as r:
            return json.load(r)
    except Exception:
        return None

def run(args, timeout=25):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        class R: pass
        r = R(); r.returncode = 1; r.stdout = ""; r.stderr = str(e)
        return r

def var_items(path):
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

# node id -> name (Nomad HTTP API)
id2name = {}
for n in (api("/v1/nodes") or []):
    if n.get("ID"):
        id2name[n["ID"]] = n.get("Name", n["ID"])

# maintenance-agent allocs that are currently running -> node names
running_nodes = set()
for a in (api("/v1/job/maintenance-agent/allocations") or []):
    if a.get("ClientStatus") == "running":
        nid = a.get("NodeID", "")
        running_nodes.add(id2name.get(nid, nid))

# nodes that have ever written a self-pass report
last_nodes = set()
for p in list_paths("monad/maintenance/"):
    parts = p.split("/")
    if len(parts) >= 4 and parts[-1] == "last":
        last_nodes.add(parts[2])

nodes = sorted(running_nodes | last_nodes)

def put_node(node, status, det, ec, fin, engine):
    prev = var_items("fleet/maintenance-health/" + node) or {}
    prev_status = prev.get("status", "none")
    ca = prev.get("changed_at")
    ca = ca if (ca and prev_status == status) else now_s
    args = ["nomad", "var", "put", "-force", "fleet/maintenance-health/" + node,
            "status=" + status,
            "node=" + node,
            "running=" + ("true" if node in running_nodes else "false"),
            "exit_code=" + (ec if ec else ""),
            "finished=" + (fin if fin else ""),
            "engine=" + (engine if engine else ""),
            "detail=" + det[:160],
            "prev_status=" + prev_status,
            "changed_at=" + ca,
            "ts=" + now_s]
    rr = run(args)
    if rr.returncode != 0:
        print("[maint-health] WARN: put %s failed: %s" % (node, rr.stderr.strip()))

summary = []
for node in nodes:
    items = var_items("monad/maintenance/%s/last" % node)
    running = node in running_nodes
    ec = ""; fin = ""; engine = ""
    if items is None:
        if running:
            status = "warn"
            det = "maintenance-agent running but no self-pass report (no monad/maintenance/%s/last)" % node
        else:
            status = "unknown"
            det = "no running maintenance-agent and no self-pass report"
    else:
        ec = (items.get("exit_code", "") or "").strip()
        fin = items.get("finished", "")
        engine = items.get("engine", "")
        a = age_secs(fin)
        if not running:
            status = "warn"
            det = "no running maintenance-agent alloc (last self-pass exit=%s @ %s)" % (ec or "?", fin or "?")
        elif a is not None and a > STALE:
            status = "warn"
            det = "STALE self-pass: last finished %s (%dm old > %dm threshold)" % (
                fin, a // 60, STALE // 60)
        elif ec not in ("0", ""):
            status = "warn"
            det = "self-pass exit_code=%s (finished %s)" % (ec, fin)
        else:
            status = "healthy"
            det = "exit=%s age=%s engine=%s" % (
                ec or "0", ("%dm" % (a // 60) if a is not None else "?"), engine or "?")
    put_node(node, status, det, ec, fin, engine)
    summary.append("%s=%s" % (node, status))

print("[maint-health] running=%d nodes=[%s]" % (len(running_nodes), ";".join(summary)))
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
