# nomad-vars-backup — automated, retained backups of the Nomad variable store.
#
# The Nomad KV holds the cluster's secrets (secret/*, infra/*, nomad/jobs/* creds) and ALL
# fleet coordination/health state (fleet/*, monad/maintenance/*, messages, task results).
# Unlike Postgres (postgres-backup) and the registry (registry-backup) it had NO backup:
# a loss of Raft state destroys every secret with no recovery. This job READS every
# variable via the Nomad CLI (ACLs are disabled cluster-wide, so reads need no token) and
# writes a compressed, timestamped, verified JSONL dump to a directory it owns. It deletes
# nothing it did not create (retention prunes only its own dumps).
#
# SENSITIVITY: the dump contains plaintext secrets. v1 stores it on a tailnet-internal,
# root-restricted node with strict perms (dir 700, files 600) — the same trust posture as
# the other on-host backups. At-rest encryption is a sensible owner-gated follow-up.
job "nomad-vars-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  # Daily, offset from postgres-backup (04:00), registry-backup (05:30) to avoid overlap.
  periodic {
    crons            = ["0 6 * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to bigo-server: that is where the other backups live and where backup-health (also
  # raw_exec + python3, with the nomad CLI on PATH) runs. Dumps land in a host path here.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "backup" {
    count = 1

    restart {
      attempts = 2
      interval = "30m"
      delay    = "30s"
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "dump-vars" {
      driver = "raw_exec"

      env {
        NOMAD_ADDR      = "http://100.75.75.39:4646"
        VARS_DIR        = "/opt/monad-vars-backups"
        RETENTION_KEEP  = "14"
      }

      config {
        command = "/usr/bin/env"
        args    = ["python3", "local/backup.py"]
      }

      template {
        destination = "local/backup.py"
        perms       = "755"
        data        = <<-SCRIPT
#!/usr/bin/env python3
# Dump every Nomad variable (decrypted Items) to a gzip'd JSONL file, verify it, prune old
# dumps. One line per variable = the exact object `nomad var get -out=json <path>` returns,
# which is a valid `nomad var put -in=json` spec. Restore (per line):
#   gunzip -c <dump>.json.gz | while IFS= read -r line; do
#     printf '%s' "$line" > /tmp/v.json
#     nomad var put -force -in=json @/tmp/v.json
#   done
import datetime, glob, gzip, json, os, subprocess, sys

VARS_DIR = os.environ.get("VARS_DIR", "/opt/monad-vars-backups")
KEEP     = int(os.environ.get("RETENTION_KEEP", "14") or "14")

now   = datetime.datetime.now(datetime.timezone.utc)
stamp = now.strftime("%Y%m%dT%H%M%SZ")

def run(args, timeout=45):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)

# Directory the job owns; strict perms because the dump holds plaintext secrets.
os.makedirs(VARS_DIR, exist_ok=True)
try:
    os.chmod(VARS_DIR, 0o700)
except OSError:
    pass

# 1) enumerate all variable paths
r = run(["nomad", "var", "list", "-out=json"])
if r.returncode != 0:
    print("[nomad-vars-backup] FAIL: var list: %s" % r.stderr.strip(), file=sys.stderr)
    sys.exit(1)
try:
    paths = [v["Path"] for v in json.loads(r.stdout)]
except Exception as e:
    print("[nomad-vars-backup] FAIL: parse var list: %s" % e, file=sys.stderr)
    sys.exit(1)
expected = len(paths)
print("[nomad-vars-backup] %d variables to dump" % expected)
if expected == 0:
    print("[nomad-vars-backup] FAIL: live store reports 0 variables", file=sys.stderr)
    sys.exit(1)

out = os.path.join(VARS_DIR, "nomad-vars-%s.json.gz" % stamp)
tmp = out + ".partial"

# 2) fetch each variable's decrypted Items, write one JSON object per line
got = 0
skipped = []
# create the partial with restrictive perms up front (umask-independent)
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with gzip.open(os.fdopen(fd, "wb"), "wt", encoding="utf-8") as f:
    for p in paths:
        rg = run(["nomad", "var", "get", "-out=json", p])
        if rg.returncode != 0:
            # A var vanishing mid-run (concurrent delete) is explainable; record + continue.
            skipped.append(p)
            print("[nomad-vars-backup] WARN: get %s failed: %s" % (p, rg.stderr.strip()),
                  file=sys.stderr)
            continue
        try:
            obj = json.loads(rg.stdout)  # validates and strips the CLI's stderr UI hint
        except Exception as e:
            skipped.append(p)
            print("[nomad-vars-backup] WARN: parse %s failed: %s" % (p, e), file=sys.stderr)
            continue
        f.write(json.dumps(obj, separators=(",", ":")) + "\n")
        got += 1

# 3) integrity: every listed path must be either dumped or explainably skipped, and at
#    least one var must be captured. Unexplained loss (got+skipped != expected) fails.
if got == 0:
    print("[nomad-vars-backup] FAIL: dumped 0 variables", file=sys.stderr)
    os.remove(tmp); sys.exit(1)
if got + len(skipped) != expected:
    print("[nomad-vars-backup] FAIL: accounted %d (got %d + skipped %d) != listed %d" % (
        got + len(skipped), got, len(skipped), expected), file=sys.stderr)
    os.remove(tmp); sys.exit(1)

# 4) verify: re-read the gzip, parse every line, count must match what we wrote
reread = 0
try:
    with gzip.open(tmp, "rt", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            json.loads(line)
            reread += 1
except Exception as e:
    print("[nomad-vars-backup] FAIL: re-read verify: %s" % e, file=sys.stderr)
    os.remove(tmp); sys.exit(1)
if reread != got:
    print("[nomad-vars-backup] FAIL: re-read %d != written %d" % (reread, got),
          file=sys.stderr)
    os.remove(tmp); sys.exit(1)

os.replace(tmp, out)
try:
    os.chmod(out, 0o600)
except OSError:
    pass
size = os.path.getsize(out)
note = ""
if skipped:
    note = " (skipped %d: %s)" % (len(skipped), ",".join(skipped)[:160])
print("[nomad-vars-backup] wrote %s: %d bytes, %d vars%s" % (out, size, got, note))

# 5) prune our own dumps beyond the retention window (timestamped names sort chronologically)
if KEEP > 0:
    dumps = sorted(glob.glob(os.path.join(VARS_DIR, "nomad-vars-*.json.gz")))
    for old in dumps[:-KEEP]:
        try:
            os.remove(old); print("[nomad-vars-backup] prune %s" % old)
        except OSError as e:
            print("[nomad-vars-backup] WARN: prune %s: %s" % (old, e), file=sys.stderr)

print("[nomad-vars-backup] done")
SCRIPT
      }

      resources {
        cpu    = 200
        memory = 128
      }

      kill_timeout = "30s"
    }
  }
}
