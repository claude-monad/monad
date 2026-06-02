# raft-quorum-health — standing, low-noise monitor of the Nomad Raft control
# plane's quorum margin. READ-ONLY: it only HTTP-GETs each server's
# /v1/agent/self and /v1/status/leader, then records a compact verdict to the
# Nomad var fleet/raft-health.
#
# Motivated by fleet/projects/raft-quorum-health.md and the 2026-06-02 leaderless
# outage: the Raft config had only 2 voters (v1410-1 + oraclebox1) => quorum 2/2,
# zero fault tolerance, so one flaky voter took the whole control plane down and
# blocked every deploy. Nothing watched this (cluster-watchdog has no raft/voter
# logic). This turns "are we one flap from an outage?" into a queryable signal:
# warn when voter_count < 3 (fragile) BEFORE it tips into critical (no leader).
#
# Quiet by design: the single var fleet/raft-health is overwritten each run (no
# log/commit spam); a status transition is captured in the var (prev_status +
# changed_at), mirroring jobs/registry-health.hcl and jobs/agent-checkout-health.hcl.
#
# NOTE: the embedded probe is Python (parsing raft latest_configuration is far
# cleaner than sed). It contains no ${...} sequences, so Nomad HCL2 does not try
# to interpolate it.
job "raft-quorum-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]
    prohibit_overlap = true
  }

  # Pin to oraclebox1: the stable voter that already hosts the conductor + fleet
  # jobs and can reach both server RPC endpoints on the tailnet. (If oraclebox1
  # itself is down the whole control plane is down anyway.)
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "raft-quorum-health" {
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
        # space-separated server RPC/HTTP IPs to probe (the Raft voter set hosts)
        SERVERS    = "100.75.75.39 100.125.210.126"
        # local server for the var write
        NOMAD_ADDR = "http://100.125.210.126:4646"
        # warn if term climbs by at least this much between runs (election churn)
        CHURN_WARN = "5"
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
# read-only Raft quorum health probe -> Nomad var fleet/raft-health
import json, os, re, subprocess, datetime, urllib.request

HVAR = "fleet/raft-health"
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
servers = os.environ.get("SERVERS", "").split()
churn_warn = int(os.environ.get("CHURN_WARN", "5") or "5")

def nvget(item):
    try:
        r = subprocess.run(["nomad", "var", "get", "-item=" + item, HVAR],
                           capture_output=True, text=True, timeout=15)
        return r.stdout.strip()
    except Exception:
        return ""

def http_get(url, timeout=8):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", "replace")

prev_status = nvget("status") or "none"
changed_at = nvget("changed_at")
prev_term = nvget("term")

reachable = []
states = {}
voters = []
max_term = 0
leader_present = False

for ip in servers:
    try:
        d = json.loads(http_get("http://%s:4646/v1/agent/self" % ip))
    except Exception:
        continue
    reachable.append(ip)
    raft = d.get("stats", {}).get("raft", {})
    st = raft.get("state", "?")
    states[ip] = st
    if st == "Leader":
        leader_present = True
    try:
        max_term = max(max_term, int(raft.get("term", "0") or 0))
    except Exception:
        pass
    cfg = raft.get("latest_configuration", "")
    if "Suffrage:Voter" in cfg and not voters:
        for m in re.finditer(r"Suffrage:Voter ID:[0-9a-fA-F-]+ Address:([0-9.]+:[0-9]+)", cfg):
            voters.append(m.group(1))

# cross-check the leader via /v1/status/leader in case no probed node self-reports Leader
if not leader_present:
    for ip in reachable:
        try:
            lead = http_get("http://%s:4646/v1/status/leader" % ip, timeout=6).strip().strip('"')
        except Exception:
            lead = ""
        if lead and "error" not in lead.lower() and "no cluster leader" not in lead.lower():
            leader_present = True
            break

voter_count = len(voters)
quorum = (voter_count // 2 + 1) if voter_count else 0
tolerance = (voter_count - quorum) if voter_count else 0

term_delta = "?"
if prev_term.isdigit():
    term_delta = str(max_term - int(prev_term))

# verdict
if not reachable:
    status, detail = "unknown", "no nomad server reachable on the tailnet"
elif not leader_present:
    status = "critical"
    detail = "NO raft leader (cluster cannot commit writes); voters=%d term=%d" % (voter_count, max_term)
elif voter_count and voter_count < 3:
    status = "warn"
    detail = "fragile quorum: %d voters, fault_tolerance=%d (target is 3 voters for 1-node tolerance)" % (voter_count, tolerance)
elif term_delta.lstrip("-").isdigit() and int(term_delta) >= churn_warn:
    status = "warn"
    detail = "leadership churn: term rose by %s since last run (elections flapping)" % term_delta
else:
    status = "healthy"
    detail = "leader present, %d voters, fault_tolerance=%d" % (voter_count, tolerance)

ca = changed_at if (changed_at and prev_status == status) else now

args = ["nomad", "var", "put", "-force", HVAR,
        "status=" + status,
        "detail=" + detail,
        "leader_present=" + ("yes" if leader_present else "no"),
        "voter_count=" + str(voter_count),
        "fault_tolerance=" + str(tolerance),
        "voters=" + (",".join(voters) if voters else "?"),
        "term=" + str(max_term),
        "prev_term=" + (prev_term if prev_term else "?"),
        "term_delta=" + term_delta,
        "servers_reachable=" + (",".join(reachable) if reachable else "none"),
        "server_states=" + (";".join("%s=%s" % (k, v) for k, v in states.items()) if states else "none"),
        "prev_status=" + prev_status,
        "changed_at=" + ca,
        "ts=" + now]
try:
    r = subprocess.run(args, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        print("[raft-health] WARN: nomad var put failed (likely no leader): %s" % r.stderr.strip())
except Exception as e:
    print("[raft-health] WARN: nomad var put errored: %s" % e)

print("[raft-health] status=%s leader=%s voters=%d tol=%d term=%d delta=%s reachable=%s" % (
    status, leader_present, voter_count, tolerance, max_term, term_delta, ",".join(reachable) or "none"))
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
