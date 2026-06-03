#!/usr/bin/env python3
"""Lint fleet backlog/project metadata and publish fleet/backlog-health."""

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

VALID_STATUS = {"todo", "claimed", "building", "review", "done", "blocked"}
ACTIVE_STATUS = {"claimed", "building", "review"}
VAR_PATH = "fleet/backlog-health"
STATUS_RANK = {"healthy": 0, "warn": 1, "critical": 2}


def now_utc():
    return dt.datetime.now(dt.timezone.utc)


def fmt_ts(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_updated(value):
    if not value:
        return None
    value = value.strip().strip('"')
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%MZ", "%Y-%m-%d"):
        try:
            parsed = dt.datetime.strptime(value, fmt)
            return parsed.replace(tzinfo=dt.timezone.utc)
        except ValueError:
            pass
    return None


def frontmatter(path):
    text = path.read_text(errors="replace")
    if not text.startswith("---\n"):
        return {}, "missing frontmatter fence"
    end = text.find("\n---", 4)
    if end == -1:
        return {}, "unterminated frontmatter fence"
    data = {}
    for line in text[4:end].splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    return data, None


def parse_backlog(path):
    rows = []
    link_re = re.compile(r"\[([^\]]+)\]\(projects/([^)]+)\)")
    if not path.exists():
        return rows
    for lineno, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        raw = line.strip()
        if not raw.startswith("|"):
            continue
        cells = [c.strip() for c in raw.strip("|").split("|")]
        if len(cells) < 4 or cells[0] in {"Pri", "----:"} or set(cells[0]) <= set("-: "):
            continue
        match = link_re.search(cells[1])
        slug = ""
        if match:
            target = match.group(2)
            slug = target[:-3] if target.endswith(".md") else target
        status_word = cells[3].split(None, 1)[0].strip().lower() if cells[3] else ""
        rows.append({
            "lineno": lineno,
            "priority": cells[0],
            "slug": slug,
            "status": status_word,
            "status_text": cells[3],
        })
    return rows


def issue(severity, code, subject, detail):
    return {
        "severity": severity,
        "code": code,
        "subject": subject,
        "detail": " ".join(str(detail).split()),
    }


def worst_status(issues):
    status = "healthy"
    for item in issues:
        sev = "critical" if item["severity"] == "critical" else "warn"
        if STATUS_RANK[sev] > STATUS_RANK[status]:
            status = sev
    return status


def summarize_issues(issues, limit=1800):
    if not issues:
        return "none"
    parts = []
    used = 0
    for item in issues:
        text = "%s:%s:%s:%s" % (
            item["severity"], item["code"], item["subject"], item["detail"])
        if used + len(text) + 1 > limit:
            parts.append("truncated:%d-more" % (len(issues) - len(parts)))
            break
        parts.append(text)
        used += len(text) + 1
    return ";".join(parts)


def lint(repo, stale_hours):
    repo = Path(repo)
    projects_dir = repo / "fleet" / "projects"
    backlog_path = repo / "fleet" / "BACKLOG.md"
    current = now_utc()
    issues = []
    projects = {}

    if not projects_dir.is_dir():
        return {
            "status": "critical",
            "detail": "missing fleet/projects directory",
            "issues": "critical:missing-projects:fleet/projects:directory missing",
            "issue_count": "1",
            "critical_count": "1",
            "warn_count": "0",
            "project_count": "0",
            "backlog_count": "0",
            "active_count": "0",
            "stale_active_count": "0",
        }

    for path in sorted(projects_dir.glob("*.md")):
        slug = path.stem
        data, err = frontmatter(path)
        projects[slug] = data
        if err:
            issues.append(issue("critical", "frontmatter", slug, err))
            continue
        fm_slug = data.get("slug", "")
        status = data.get("status", "")
        updated = data.get("updated", "")
        if fm_slug != slug:
            issues.append(issue("warn", "slug-mismatch", slug, "frontmatter slug=%s" % (fm_slug or "missing")))
        if status not in VALID_STATUS:
            issues.append(issue("critical", "invalid-status", slug, "status=%s" % (status or "missing")))
        if not data.get("owner", "") and status in ACTIVE_STATUS:
            issues.append(issue("warn", "active-no-owner", slug, "active project has no owner"))
        parsed = parse_updated(updated)
        if parsed is None:
            issues.append(issue("warn", "updated-invalid", slug, "updated=%s" % (updated or "missing")))
        elif status in ACTIVE_STATUS:
            age = current - parsed
            if age > dt.timedelta(hours=stale_hours):
                hours = int(age.total_seconds() // 3600)
                issues.append(issue("warn", "active-stale", slug, "status=%s updated=%s age=%dh" % (status, updated, hours)))

    backlog_rows = parse_backlog(backlog_path)
    backlog_slugs = set()
    for row in backlog_rows:
        slug = row["slug"]
        if not slug:
            issues.append(issue("warn", "backlog-link", "line-%s" % row["lineno"], "missing project link"))
            continue
        if slug in backlog_slugs:
            issues.append(issue("warn", "backlog-duplicate", slug, "duplicate BACKLOG row"))
        backlog_slugs.add(slug)
        if slug not in projects:
            issues.append(issue("critical", "backlog-missing-project", slug, "BACKLOG row links to missing project file"))
            continue
        row_status = row["status"]
        project_status = projects[slug].get("status", "")
        if row_status in VALID_STATUS and project_status in VALID_STATUS and row_status != project_status:
            issues.append(issue(
                "warn", "status-drift", slug,
                "BACKLOG=%s project=%s" % (row_status, project_status)))
        elif row_status and row_status not in VALID_STATUS:
            issues.append(issue("warn", "backlog-status", slug, "unrecognized BACKLOG status '%s'" % row_status))

    for slug in sorted(set(projects) - backlog_slugs):
        issues.append(issue("warn", "project-not-indexed", slug, "project file is absent from BACKLOG"))

    status = worst_status(issues)
    active = [s for s, data in projects.items() if data.get("status") in ACTIVE_STATUS]
    stale_active = [i for i in issues if i["code"] == "active-stale"]
    detail = "all %d projects indexed and consistent" % len(projects)
    if issues:
        detail = "%s: %d issue(s); first=%s/%s/%s" % (
            status, len(issues), issues[0]["severity"], issues[0]["code"], issues[0]["subject"])

    return {
        "status": status,
        "detail": detail,
        "issues": summarize_issues(issues),
        "issue_count": str(len(issues)),
        "critical_count": str(sum(1 for i in issues if i["severity"] == "critical")),
        "warn_count": str(sum(1 for i in issues if i["severity"] != "critical")),
        "project_count": str(len(projects)),
        "backlog_count": str(len(backlog_slugs)),
        "active_count": str(len(active)),
        "stale_active_count": str(len(stale_active)),
    }


def nomad_var_items(path):
    try:
        raw = subprocess.run(
            ["nomad", "var", "get", "-out=json", path],
            capture_output=True, text=True, timeout=15)
    except Exception:
        return {}
    if raw.returncode != 0:
        return {}
    try:
        return json.loads(raw.stdout).get("Items", {}) or {}
    except Exception:
        return {}


def publish(items):
    args = ["nomad", "var", "put", "-force", VAR_PATH]
    args.extend("%s=%s" % (k, v) for k, v in items.items())
    return subprocess.run(args, text=True, timeout=20)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=os.getcwd())
    parser.add_argument("--stale-hours", type=float, default=float(os.environ.get("ACTIVE_STALE_HOURS", "6")))
    parser.add_argument("--no-publish", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    ts = fmt_ts(now_utc())
    items = lint(args.repo, args.stale_hours)
    prev = nomad_var_items(VAR_PATH)
    prev_status = prev.get("status", "none")
    changed_at = prev.get("changed_at", "")
    if prev_status != items["status"] or not changed_at:
        changed_at = ts
    items.update({
        "prev_status": prev_status,
        "changed_at": changed_at,
        "ts": ts,
    })

    if args.json:
        print(json.dumps(items, sort_keys=True, indent=2))
    else:
        print("[backlog-health] status=%s issue_count=%s detail=%s" % (
            items["status"], items["issue_count"], items["detail"]))

    if not args.no_publish:
        result = publish(items)
        if result.returncode != 0:
            print("[backlog-health] WARN: nomad var put failed", file=sys.stderr)
            return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
