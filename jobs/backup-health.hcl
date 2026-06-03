# backup-health — standing freshness/presence monitor for retained cluster backups.
#
# READ-ONLY against backup artifacts. It inspects the backup directories owned by
# postgres-backup and registry-backup on bigo-server, then writes one compact Nomad
# var: fleet/backup-health. Restore verification is separate; this job answers the
# operational question "did today's backups actually appear and are they non-tiny?"
job "backup-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/30 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Both backup directories are host paths on bigo-server, so the probe must run
  # there to see the artifacts directly.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "backup-health" {
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
        NOMAD_ADDR          = "http://100.75.75.39:4646"
        POSTGRES_DIR        = "/opt/monad-postgres-backups"
        POSTGRES_GLOB       = "*.sql.gz"
        POSTGRES_MIN_BYTES  = "100"
        POSTGRES_MAX_AGE_S  = "129600"
        REGISTRY_DIR        = "/opt/monad-registry-backups"
        REGISTRY_GLOB       = "registry-*.tar.gz"
        REGISTRY_MIN_BYTES  = "100"
        REGISTRY_MAX_AGE_S  = "129600"
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
# read-only backup health probe -> Nomad var fleet/backup-health
import datetime
import glob
import json
import os
import subprocess

HVAR = "fleet/backup-health"
now = datetime.datetime.now(datetime.timezone.utc)
now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")

RANK = {"healthy": 0, "unknown": 1, "warn": 2, "critical": 3}

def run(args, timeout=20):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        class R:
            pass
        r = R()
        r.returncode = 1
        r.stdout = ""
        r.stderr = str(e)
        return r

def var_items(path):
    r = run(["nomad", "var", "get", "-out=json", path])
    if r.returncode != 0:
        return {}
    try:
        return json.loads(r.stdout).get("Items", {}) or {}
    except Exception:
        return {}

def env_int(name, default):
    try:
        return int(os.environ.get(name, str(default)) or default)
    except Exception:
        return default

def age_label(seconds):
    if seconds is None:
        return "?"
    if seconds < 3600:
        return "%dm" % (seconds // 60)
    if seconds < 172800:
        return "%dh" % (seconds // 3600)
    return "%dd" % (seconds // 86400)

def check_family(prefix, directory, pattern, min_bytes, max_age):
    result = {
        prefix + "_status": "unknown",
        prefix + "_detail": "",
        prefix + "_dir": directory,
        prefix + "_pattern": pattern,
        prefix + "_count": "0",
        prefix + "_file": "",
        prefix + "_size_bytes": "",
        prefix + "_age_seconds": "",
    }
    if not os.path.isdir(directory):
        result[prefix + "_status"] = "warn"
        result[prefix + "_detail"] = "backup directory missing: " + directory
        return result

    files = [p for p in glob.glob(os.path.join(directory, pattern)) if os.path.isfile(p)]
    result[prefix + "_count"] = str(len(files))
    if not files:
        result[prefix + "_status"] = "warn"
        result[prefix + "_detail"] = "no backup artifacts matching " + pattern
        return result

    latest = max(files, key=lambda p: os.stat(p).st_mtime)
    st = os.stat(latest)
    age = int(now.timestamp() - st.st_mtime)
    size = int(st.st_size)
    result[prefix + "_file"] = os.path.basename(latest)
    result[prefix + "_size_bytes"] = str(size)
    result[prefix + "_age_seconds"] = str(age)

    problems = []
    if size < min_bytes:
        problems.append("size %dB < %dB" % (size, min_bytes))
    if age > max_age:
        problems.append("age %s > %s" % (age_label(age), age_label(max_age)))

    if problems:
        result[prefix + "_status"] = "warn"
        result[prefix + "_detail"] = ", ".join(problems)
    else:
        result[prefix + "_status"] = "healthy"
        result[prefix + "_detail"] = "%s age=%s size=%dB count=%d" % (
            os.path.basename(latest), age_label(age), size, len(files))
    return result

def worst(statuses):
    out = "healthy"
    for st in statuses:
        if RANK.get(st, 1) > RANK.get(out, 0):
            out = st
    return out

pg = check_family(
    "postgres",
    os.environ.get("POSTGRES_DIR", "/opt/monad-postgres-backups"),
    os.environ.get("POSTGRES_GLOB", "*.sql.gz"),
    env_int("POSTGRES_MIN_BYTES", 100),
    env_int("POSTGRES_MAX_AGE_S", 129600),
)
reg = check_family(
    "registry",
    os.environ.get("REGISTRY_DIR", "/opt/monad-registry-backups"),
    os.environ.get("REGISTRY_GLOB", "registry-*.tar.gz"),
    env_int("REGISTRY_MIN_BYTES", 100),
    env_int("REGISTRY_MAX_AGE_S", 129600),
)

status = worst([pg["postgres_status"], reg["registry_status"]])
bad = []
if pg["postgres_status"] != "healthy":
    bad.append("postgres=" + pg["postgres_detail"])
if reg["registry_status"] != "healthy":
    bad.append("registry=" + reg["registry_detail"])
if bad:
    detail = "; ".join(bad)
else:
    detail = "postgres %s; registry %s" % (
        pg["postgres_detail"], reg["registry_detail"])
detail = detail[:240]

prev = var_items(HVAR)
prev_status = prev.get("status", "none")
changed_at = prev.get("changed_at")
if not changed_at or prev_status != status:
    changed_at = now_s

items = {
    "status": status,
    "detail": detail,
    "prev_status": prev_status,
    "changed_at": changed_at,
    "ts": now_s,
}
items.update(pg)
items.update(reg)

args = ["nomad", "var", "put", "-force", HVAR]
for k in sorted(items):
    args.append(k + "=" + str(items[k]))
r = run(args)
if r.returncode != 0:
    print("[backup-health] WARN: nomad var put failed: %s" % r.stderr.strip())
print("[backup-health] status=%s detail=%s" % (status, detail))
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
