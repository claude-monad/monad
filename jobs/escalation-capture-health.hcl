# escalation-capture-health -- surface durable gh-less escalation captures.
#
# READ-ONLY against captured issue vars. gh-escalation-resilience (#34) makes
# `monad gh issue` on gh-less nodes write would-be GitHub issues under
# fleet/pending-issues/*; this monitor turns those durable captures into a single
# health var so they cannot sit unnoticed.
job "escalation-capture-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/10 * * * *"]
    prohibit_overlap = true
  }

  # Same placement as fleet-health-rollup: a lightweight control-plane monitor
  # that reads Nomad vars and writes one compact verdict.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "escalation-capture-health" {
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
# read-only captured-escalation probe -> Nomad var fleet/escalation-health
import datetime
import json
import subprocess

HVAR = "fleet/escalation-health"
PREFIX = "fleet/pending-issues/"
now = datetime.datetime.now(datetime.timezone.utc)
now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")

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
        return {}, {}
    try:
        obj = json.loads(r.stdout)
        return obj.get("Items", {}) or {}, obj
    except Exception:
        return {}, {}

def age_seconds_from_created(created, create_ns=None):
    if created:
        for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
            try:
                t = datetime.datetime.strptime(created, fmt).replace(tzinfo=datetime.timezone.utc)
                return max(0, int((now - t).total_seconds()))
            except Exception:
                pass
    try:
        if create_ns:
            t = datetime.datetime.fromtimestamp(int(create_ns) / 1000000000, tz=datetime.timezone.utc)
            return max(0, int((now - t).total_seconds()))
    except Exception:
        pass
    return None

def age_label(seconds):
    if seconds is None:
        return "?"
    if seconds < 3600:
        return "%dm" % (seconds // 60)
    if seconds < 172800:
        return "%dh" % (seconds // 3600)
    return "%dd" % (seconds // 86400)

def prev_value(item):
    items, _ = var_items(HVAR)
    return items.get(item, "")

prev_status = prev_value("status") or "none"
changed_at = prev_value("changed_at")

r = run(["nomad", "var", "list", "-out=json", PREFIX])
captures = []
if r.returncode != 0:
    status = "unknown"
    detail = "could not list " + PREFIX + ": " + (r.stderr.strip() or "nomad var list failed")
else:
    try:
        paths = [v.get("Path", "") for v in json.loads(r.stdout)]
        paths = sorted(p for p in paths if p.startswith(PREFIX))
    except Exception as e:
        paths = []
        status = "unknown"
        detail = "could not parse var list for " + PREFIX + ": " + str(e)

    if "status" not in locals():
        for path in paths:
            items, obj = var_items(path)
            created = items.get("created") or ""
            age_s = age_seconds_from_created(created, obj.get("CreateTime"))
            title = " ".join((items.get("title", "") or "").split())
            node = " ".join((items.get("node", "") or "").split())
            captures.append({
                "path": path,
                "kind": items.get("kind", "issue") or "issue",
                "title": title,
                "node": node,
                "created": created,
                "age_s": age_s,
            })
        captures.sort(key=lambda c: (c["age_s"] if c["age_s"] is not None else -1), reverse=True)
        if captures:
            status = "warn"
            oldest = captures[0]
            labels = []
            for c in captures[:5]:
                title = c["title"] or c["path"].rsplit("/", 1)[-1]
                if len(title) > 48:
                    title = title[:45] + "..."
                node = ("@" + c["node"]) if c["node"] else ""
                labels.append("%s:%s%s age=%s" % (c["kind"], title, node, age_label(c["age_s"])))
            detail = "%d pending captured escalation(s); oldest %s age=%s" % (
                len(captures), oldest["path"].rsplit("/", 1)[-1], age_label(oldest["age_s"]))
            titles = "; ".join(labels)
        else:
            status = "healthy"
            detail = "no pending captured GitHub escalations"
            titles = "none"

if status == "unknown":
    titles = "unknown"

oldest_age = "0"
oldest_path = "none"
if captures:
    oldest_age = "unknown" if captures[0]["age_s"] is None else str(captures[0]["age_s"])
    oldest_path = captures[0]["path"]

ca = changed_at if (changed_at and prev_status == status) else now_s
args = ["nomad", "var", "put", "-force", HVAR,
        "status=" + status,
        "detail=" + detail[:240],
        "pending_count=" + str(len(captures)),
        "oldest_age_s=" + oldest_age,
        "oldest_path=" + oldest_path,
        "titles=" + titles[:500],
        "prev_status=" + prev_status,
        "changed_at=" + ca,
        "ts=" + now_s]
wr = run(args)
if wr.returncode != 0:
    print("[escalation-health] WARN: nomad var put failed: %s" % wr.stderr.strip())
print("[escalation-health] status=%s pending=%d detail=%s" % (status, len(captures), detail))
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
