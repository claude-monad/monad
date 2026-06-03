# engine-coverage-health — standing, low-noise monitor of agent-ENGINE coverage
# across the cluster. READ-ONLY: it only HTTP-GETs the Nomad node API and reads the
# cluster/engine default var, then records a compact verdict to fleet/engine-coverage.
#
# Motivated by fleet/projects/engine-coverage-health.md. The cluster gained a default
# agent-engine toggle (cluster/engine var, default codex as of 2026-06-03 dc308de;
# meta/agent/engines.sh reads it). Nothing watched COVERAGE: only oraclebox1 + V1410-1
# advertise has_codex; claudebox is claude-only; death-star/windesk/eliotts-mac-mini
# advertise no engine meta at all. engine_pick falls back to claude, so an unsatisfiable
# default is not an outage — it's a SILENT no-op (the toggle stops meaning anything).
# This turns "is the configured default engine runnable anywhere?" into a queryable signal.
#
# Verdict is tight to avoid perpetual-warn (uneven coverage is reported as DATA, not warned):
#   critical : zero ready nodes advertise ANY ready engine (no agent can run anywhere)
#   warn     : zero ready nodes advertise the cluster DEFAULT engine (toggle is a no-op)
#   healthy  : otherwise
#
# Quiet by design: the single var fleet/engine-coverage is overwritten each run; a status
# transition is captured (prev_status + changed_at), mirroring jobs/raft-quorum-health.hcl
# and jobs/registry-health.hcl. The embedded probe is Python and contains no ${...}/%{...}
# sequences, so Nomad HCL2 does not interpolate it.
job "engine-coverage-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/30 * * * *"]
    prohibit_overlap = true
  }

  # Pin to oraclebox1 to match the monitor family (raft/registry/maintenance rollup live
  # here; it can reach the node API + write Nomad vars on the tailnet).
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "engine-coverage-health" {
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
# read-only agent-engine coverage probe -> Nomad var fleet/engine-coverage
import json, os, subprocess, datetime, urllib.request

HVAR = "fleet/engine-coverage"
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
addr = os.environ.get("NOMAD_ADDR", "http://100.125.210.126:4646").rstrip("/")
ENGINES = ["claude", "codex"]

def http_get(path, timeout=8):
    with urllib.request.urlopen(addr + path, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")

def nvget(item):
    try:
        r = subprocess.run(["nomad", "var", "get", "-item=" + item, HVAR],
                           capture_output=True, text=True, timeout=15)
        return r.stdout.strip()
    except Exception:
        return ""

# cluster default engine (documented fallback: codex). "auto" => target is "any engine".
default_engine = ""
try:
    r = subprocess.run(["nomad", "var", "get", "-item=engine", "cluster/engine"],
                       capture_output=True, text=True, timeout=15)
    default_engine = (r.stdout or "").strip()
except Exception:
    pass
if default_engine not in ("claude", "codex", "auto"):
    default_engine = "codex"

prev_status = nvget("status") or "none"
changed_at = nvget("changed_at")

try:
    node_list = json.loads(http_get("/v1/nodes"))
    api_ok = True
except Exception as e:
    node_list, api_ok = [], False

ready_nodes = []
node_engines = {}            # name -> set of ready engines
per_engine = {e: [] for e in ENGINES}
no_meta = []

for stub in node_list:
    if stub.get("Status") != "ready":
        continue
    nid = stub.get("ID")
    name = stub.get("Name") or (nid[:8] if nid else "?")
    meta = {}
    try:
        nd = json.loads(http_get("/v1/node/" + nid))
        meta = nd.get("Meta") or {}
    except Exception:
        meta = {}
    adv = [x.strip() for x in (meta.get("agent_engines") or "").split(",") if x.strip()]
    es = set()
    for e in ENGINES:
        if meta.get("has_" + e) == "true" or e in adv:
            es.add(e)
            per_engine[e].append(name)
    node_engines[name] = es
    ready_nodes.append(name)
    if not es:
        no_meta.append(name)

ready_count = len(ready_nodes)
engine_capable = [n for n in ready_nodes if node_engines[n]]

if default_engine == "auto":
    default_label = "auto(any)"
    default_nodes = list(engine_capable)
else:
    default_label = default_engine
    default_nodes = list(per_engine.get(default_engine, []))

if not api_ok:
    status, detail = "unknown", "nomad node API unreachable at " + addr
elif ready_count == 0:
    status, detail = "unknown", "no ready nodes reported by the scheduler"
elif len(engine_capable) == 0:
    status = "critical"
    detail = "zero ready nodes advertise any engine -- no agent can run anywhere"
elif len(default_nodes) == 0:
    status = "warn"
    detail = ("cluster default engine '%s' runnable on 0 ready nodes "
              "(agents silently fall back; the toggle is a no-op)") % default_label
else:
    status = "healthy"
    detail = ("default '%s' runnable on %d node(s); %d/%d ready nodes engine-capable"
              % (default_label, len(default_nodes), len(engine_capable), ready_count))

ca = changed_at if (changed_at and prev_status == status) else now

def lst(v):
    return ",".join(sorted(v)) if v else "none"

args = ["nomad", "var", "put", "-force", HVAR,
        "status=" + status,
        "detail=" + detail,
        "default_engine=" + default_label,
        "default_engine_nodes=" + lst(default_nodes),
        "claude_nodes=" + lst(per_engine["claude"]),
        "codex_nodes=" + lst(per_engine["codex"]),
        "ready_nodes=" + lst(ready_nodes),
        "nodes_no_engine_meta=" + lst(no_meta),
        "ready_count=" + str(ready_count),
        "engine_capable_count=" + str(len(engine_capable)),
        "prev_status=" + prev_status,
        "changed_at=" + ca,
        "ts=" + now]
try:
    r = subprocess.run(args, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        print("[engine-coverage] WARN: nomad var put failed: %s" % r.stderr.strip())
except Exception as e:
    print("[engine-coverage] WARN: nomad var put errored: %s" % e)

print("[engine-coverage] status=%s default=%s default_nodes=%s capable=%d/%d no_meta=%s" % (
    status, default_label, lst(default_nodes), len(engine_capable), ready_count, lst(no_meta)))
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
