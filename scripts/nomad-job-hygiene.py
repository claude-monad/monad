#!/usr/bin/env python3
"""Publish hygiene status for committed long-running Nomad jobs."""

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

VAR_PATH = "fleet/job-hygiene"
OK_ALLOC_STATUSES = {"running"}
LONG_RUNNING_TYPES = {"service", "system"}


def now_utc():
    return dt.datetime.now(dt.timezone.utc)


def fmt_ts(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def run(args, timeout=15):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception as exc:
        class Result:
            returncode = 1
            stdout = ""
            stderr = str(exc)
        return Result()


def first_match(pattern, text):
    match = re.search(pattern, text, re.MULTILINE)
    return match.group(1) if match else ""


def committed_jobs(repo):
    jobs_dir = Path(repo) / "jobs"
    jobs = []
    for path in sorted(jobs_dir.glob("*.hcl")):
        text = path.read_text(errors="replace")
        job_id = first_match(r'^\s*job\s+"([^"]+)"\s*\{', text)
        job_type = first_match(r'^\s*type\s*=\s*"([^"]+)"', text)
        if not job_id or not job_type:
            continue
        periodic = bool(re.search(r"^\s*periodic\s*\{", text, re.MULTILINE))
        if job_type in LONG_RUNNING_TYPES or periodic:
            jobs.append({
                "id": job_id,
                "type": job_type,
                "periodic": periodic,
                "path": str(path.relative_to(repo)),
            })
    return jobs


def inspect_job(job_id):
    result = run(["nomad", "job", "inspect", "-json", job_id])
    if result.returncode != 0:
        return None, result.stderr.strip()
    try:
        return json.loads(result.stdout), ""
    except Exception as exc:
        return None, "invalid inspect json: %s" % exc


def status_json(job_id):
    result = run(["nomad", "job", "status", "-json", job_id], timeout=20)
    if result.returncode != 0:
        return None, result.stderr.strip()
    try:
        data = json.loads(result.stdout)
        if isinstance(data, list) and data:
            return data[0], ""
        if isinstance(data, dict):
            return data, ""
        return {}, ""
    except Exception as exc:
        return None, "invalid status json: %s" % exc


def latest_desired_run_allocs(job_type, allocations):
    latest = {}
    for alloc in allocations or []:
        if alloc.get("DesiredStatus") != "run":
            continue
        if job_type == "system":
            key = "%s/%s" % (alloc.get("NodeID", ""), alloc.get("TaskGroup", ""))
        else:
            key = alloc.get("Name") or alloc.get("ID")
        old = latest.get(key)
        if old is None or int(alloc.get("CreateTime") or 0) > int(old.get("CreateTime") or 0):
            latest[key] = alloc
    return list(latest.values())


def alloc_label(alloc):
    node = alloc.get("NodeName") or alloc.get("NodeID", "?")[:8]
    group = alloc.get("TaskGroup") or "task"
    return "%s@%s=%s" % (group, node, alloc.get("ClientStatus", "?"))


def summarize(parts, limit=1800):
    out = []
    used = 0
    for part in parts:
        text = " ".join(str(part).split())
        extra = len(text) + (1 if out else 0)
        if used + extra > limit:
            out.append("truncated:%d-more" % (len(parts) - len(out)))
            break
        out.append(text)
        used += extra
    return ";".join(out) if out else "none"


def check(repo):
    jobs = committed_jobs(repo)
    issues = []
    missing = []
    live = 0
    stopped = []
    bad_allocs = []

    for spec in jobs:
        info, err = inspect_job(spec["id"])
        if info is None:
            missing.append(spec["id"])
            continue
        live += 1
        status = (info.get("Status") or "unknown").lower()
        if status != "running":
            stopped.append("%s=%s" % (spec["id"], status))
            issues.append("%s status=%s" % (spec["id"], status))
            continue
        if spec["type"] not in LONG_RUNNING_TYPES:
            continue
        detail, err = status_json(spec["id"])
        if detail is None:
            issues.append("%s alloc_status_error=%s" % (spec["id"], err or "unknown"))
            continue
        latest = latest_desired_run_allocs(spec["type"], detail.get("Allocations") or [])
        unhealthy = [a for a in latest if (a.get("ClientStatus") or "").lower() not in OK_ALLOC_STATUSES]
        if unhealthy:
            labels = [alloc_label(a) for a in unhealthy[:8]]
            text = "%s unhealthy_allocs=%s" % (spec["id"], ",".join(labels))
            bad_allocs.append(text)
            issues.append(text)

    status = "warn" if issues else "healthy"
    detail = "all %d live committed long-running jobs healthy (%d committed missing/optional)" % (
        live, len(missing))
    if issues:
        detail = "warn: %d issue(s); %s" % (len(issues), issues[0])
    return {
        "status": status,
        "detail": detail[:220],
        "issues": summarize(issues),
        "issue_count": str(len(issues)),
        "checked_count": str(len(jobs)),
        "live_count": str(live),
        "missing_count": str(len(missing)),
        "missing_jobs": summarize(missing, limit=900),
        "stopped_jobs": summarize(stopped, limit=900),
        "unhealthy_allocs": summarize(bad_allocs, limit=900),
    }


def publish(items):
    args = ["nomad", "var", "put", "-force", VAR_PATH]
    for key, value in items.items():
        args.append("%s=%s" % (key, value))
    result = run(args)
    if result.returncode != 0:
        print("[nomad-job-hygiene] var put failed: %s" % result.stderr.strip(), file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    args = parser.parse_args()

    items = check(args.repo)
    items["ts"] = fmt_ts(now_utc())
    rc = publish(items)
    print("[nomad-job-hygiene] status=%s detail=%s" % (items["status"], items["detail"]))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
