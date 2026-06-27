# formalizer-lag-health -- surface a stalled commit-driven formalization pipeline.
#
# READ-ONLY. The math-commit-driven-formalization pipeline keeps eliott-monad/math-lean
# converging on eliottcassidy2000/math: jobs/formalize-watch.hcl polls the math HEAD every
# 20m and, on a move, forces a math-formalizer (codex) run or defers the commits to an
# active session; the watermark lives in fleet/formalizer-cursor (last_sha = the math HEAD
# the watcher has processed). That project's Log named this follow-on: nothing folds a
# `formalizer-lag` signal into fleet/health-summary, so a stalled pipeline is invisible.
#
# This monitor reads the cursor + math HEAD + the pipeline job states and writes one compact
# verdict to fleet/formalizer-lag, which fleet-health-rollup folds in as the `formalizer`
# component. It never triggers formalization or touches math-lean.
job "formalizer-lag-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/20 * * * *"]  # every 20m (~2 watcher intervals)
    prohibit_overlap = true
  }

  # Placement: bigo-server hosts formalize-watch + math-formalizer and has headroom
  # (node-overload-health: ~62% cpu). The saturated oraclebox1 keystone is sustained-critical
  # on CPU, so we deliberately keep this monitor OFF it. Needs git + nomad CLI + network to
  # the math repo -- all present on bigo-server.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "formalizer-lag-health" {
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
        # Live Raft leader (v1410-1); older docs point at the dead orphan.
        NOMAD_ADDR    = "http://100.75.75.39:4646"
        MATH_REPO_URL = "https://github.com/eliottcassidy2000/math.git"
        MATH_BRANCH   = "main"
        # A commit is "behind" only transiently between watcher ticks; warn only once the
        # newest unprocessed commit is older than this grace (~2.5 watcher intervals).
        BEHIND_GRACE_S = "1500"
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
# read-only formalization-pipeline lag probe -> Nomad var fleet/formalizer-lag
import datetime
import json
import os
import subprocess
import tempfile
import shutil

HVAR = "fleet/formalizer-lag"
CURSOR = "fleet/formalizer-cursor"
MATH_URL = os.environ.get("MATH_REPO_URL", "https://github.com/eliottcassidy2000/math.git")
MATH_BRANCH = os.environ.get("MATH_BRANCH", "main")
GRACE = int(os.environ.get("BEHIND_GRACE_S", "1500") or "1500")
WATCH_JOB = "formalize-watch"
FORMALIZER_JOB = "math-formalizer"

now = datetime.datetime.now(datetime.timezone.utc)
now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")

def run(args, timeout=60):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        class R:
            pass
        r = R(); r.returncode = 1; r.stdout = ""; r.stderr = str(e)
        return r

def var_items(path):
    r = run(["nomad", "var", "get", "-out=json", path])
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout).get("Items", {}) or {}
    except Exception:
        return None

def age_secs(ts):
    if not ts:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ",
                "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%f%z"):
        try:
            t = datetime.datetime.strptime(ts, fmt)
            if t.tzinfo is None:
                t = t.replace(tzinfo=datetime.timezone.utc)
            return max(0, int((now - t).total_seconds()))
        except Exception:
            continue
    return None

def age_label(s):
    if s is None:
        return "?"
    if s < 3600:
        return "%dm" % (s // 60)
    if s < 172800:
        return "%dh" % (s // 3600)
    return "%dd" % (s // 86400)

def job_state(job_id):
    # returns one of: running, dead, stopped, missing
    r = run(["nomad", "job", "inspect", job_id])
    if r.returncode != 0:
        return "missing"
    try:
        obj = json.loads(r.stdout)
        j = obj.get("Job", obj) or {}
        if j.get("Stop"):
            return "stopped"
        return (j.get("Status") or "unknown").lower()
    except Exception:
        return "unknown"

# ---- read pipeline state -----------------------------------------------------
cursor = var_items(CURSOR)
last_sha = (cursor or {}).get("last_sha", "")
cursor_updated = (cursor or {}).get("updated", "")
cursor_age = age_secs(cursor_updated)

r = run(["git", "ls-remote", MATH_URL, "refs/heads/" + MATH_BRANCH])
remote_sha = ""
if r.returncode == 0 and r.stdout.strip():
    remote_sha = r.stdout.split()[0]

watch_state = job_state(WATCH_JOB)
formalizer_state = job_state(FORMALIZER_JOB)

# ---- evaluate ----------------------------------------------------------------
status = "healthy"
reasons = []
commits_behind = "0"
newest_age = None
behind = bool(last_sha and remote_sha and remote_sha != last_sha)

if remote_sha == "":
    # monitor-side network blip reaching the math repo: don't false-warn the pipeline.
    status = "unknown"
    reasons.append("could not reach math repo (ls-remote failed)")
elif cursor is None or not last_sha:
    status = "warn"
    reasons.append("formalizer cursor %s missing/uninitialized" % CURSOR)

if behind:
    # Only when behind do we do the (cheap, blob-less) clone to measure how far/long.
    work = tempfile.mkdtemp(prefix="formalizer-lag.")
    try:
        cr = run(["git", "clone", "--quiet", "--filter=blob:none", "--no-checkout",
                  "--depth", "50", MATH_URL, work + "/math"], timeout=90)
        if cr.returncode == 0:
            cb = run(["git", "-C", work + "/math", "rev-list", "--count",
                      "%s..%s" % (last_sha, remote_sha)])
            if cb.returncode == 0 and cb.stdout.strip().isdigit():
                commits_behind = cb.stdout.strip()
            ct = run(["git", "-C", work + "/math", "log", "-1", "--format=%cI", remote_sha])
            if ct.returncode == 0 and ct.stdout.strip():
                newest_age = age_secs(ct.stdout.strip())
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if newest_age is None or newest_age > GRACE:
        # sustainedly behind (or couldn't date HEAD but still behind) -> stalled pipeline
        if status != "unknown":
            status = "warn"
        reasons.append("math-lean behind: %s commit(s), newest unprocessed %s old (> %dm grace)"
                       % (commits_behind, age_label(newest_age), GRACE // 60))
    else:
        reasons.append("behind %s commit(s) but newest only %s old (in-flight, normal)"
                       % (commits_behind, age_label(newest_age)))

# watcher liveness: a dead/stopped/missing formalize-watch is the real "stalled pipeline"
# even when no commits have arrived.
if watch_state in ("dead", "stopped", "missing"):
    if status != "unknown":
        status = "warn"
    reasons.append("%s job is %s (watcher not running)" % (WATCH_JOB, watch_state))

# the formalizer job itself must exist + be schedulable (periodic shows running).
if formalizer_state in ("stopped", "missing"):
    if status != "unknown":
        status = "warn"
    reasons.append("%s job is %s" % (FORMALIZER_JOB, formalizer_state))

if not reasons:
    reasons.append("caught up: cursor at math HEAD %s; watcher+formalizer running"
                   % (remote_sha[:8] if remote_sha else "?"))

detail = "; ".join(reasons)[:240]

prev = var_items(HVAR) or {}
prev_status = prev.get("status", "none")
changed_at = prev.get("changed_at")
ca = changed_at if (changed_at and prev_status == status) else now_s

args = ["nomad", "var", "put", "-force", HVAR,
        "status=" + status,
        "detail=" + detail,
        "behind=" + ("true" if behind else "false"),
        "commits_behind=" + commits_behind,
        "newest_unprocessed_age_s=" + (str(newest_age) if newest_age is not None else "0"),
        "cursor_last_sha=" + (last_sha[:12] if last_sha else "none"),
        "math_head=" + (remote_sha[:12] if remote_sha else "unknown"),
        "cursor_age_s=" + (str(cursor_age) if cursor_age is not None else "unknown"),
        "watcher_job=" + watch_state,
        "formalizer_job=" + formalizer_state,
        "prev_status=" + prev_status,
        "changed_at=" + ca,
        "ts=" + now_s]
wr = run(args)
if wr.returncode != 0:
    print("[formalizer-lag] WARN: nomad var put failed: %s" % wr.stderr.strip())
print("[formalizer-lag] status=%s behind=%s watcher=%s formalizer=%s detail=%s"
      % (status, behind, watch_state, formalizer_state, detail))
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 64
      }

      kill_timeout = "20s"
    }
  }
}
