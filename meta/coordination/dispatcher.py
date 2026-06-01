#!/usr/bin/env python3
"""dispatcher.py — assign frontier work items to available agents/accounts each cycle.

This is the frontier-aware replacement for the fixed day-of-week cron rotation (see
meta/coordination/PROTOCOL.md). One cycle:

  1. build the frontier (frontier.py)
  2. discover idle, rate-limit-eligible accounts (max-1/2/3/pro)
  3. greedily match the highest-priority item whose best_role fits each free account
  4. claim + dispatch the matching Nomad parameterized job  (or print, with --dry-run)

Defaults to --dry-run unless --commit is passed, so it never disrupts the running rotation
until an operator opts in. stdlib only.

Usage:
    dispatcher.py [--commit] [--cache-dir DIR] [--max-dispatch N]
"""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

import frontier as F  # same directory

# Which role each Claude account's node specializes in (mirrors root CLAUDE.md). The
# dispatcher will also fall back to any free account for unclaimed high-priority items.
ACCOUNT_ROLE = {
    "max-1": "researcher",
    "max-2": "compute",
    "max-3": "reviewer",
    "pro": "formalizer",   # formalizer is light/short; pro account is fine for it
}
# Map a work item's best_role to the Nomad parameterized job that runs it.
ROLE_JOB = {
    "researcher": "math-researcher",
    "compute": "math-quick-compute",
    "reviewer": "math-reviewer",
    "formalizer": "math-formalizer",
}
# Prompt template (under monad/scripts/prompts/) for each role, used by the
# container execution backend (--exec container).
ROLE_PROMPT = {
    "researcher": "researcher.md",
    "compute": "compute.md",
    "reviewer": "reviewer.md",
    "formalizer": "formalizer.md",
}
_HERE = os.path.dirname(os.path.abspath(__file__))


def sh(args):
    return subprocess.run(args, capture_output=True, text=True)


def idle_accounts() -> list[str]:
    """Accounts whose node currently has no running allocation of its role's job.

    Uses `nomad` if reachable; otherwise assumes all accounts are free (dry-run friendly).
    """
    r = sh(["nomad", "job", "status"])
    if r.returncode != 0:
        print("[dispatch] nomad unreachable — treating all accounts as idle (dry-run only)",
              file=sys.stderr)
        return list(ACCOUNT_ROLE)
    running = r.stdout
    free = []
    for acct, role in ACCOUNT_ROLE.items():
        job = ROLE_JOB[role]
        # crude: if the job line shows 0 running, the account is free this cycle
        free.append(acct) if f"{job}" not in running else None
    return free or list(ACCOUNT_ROLE)


def claim(item_id: str, machine: str) -> bool:
    """Claim a work item via cluster-memory; returns True if the claim is ours."""
    here = os.path.dirname(os.path.abspath(__file__))
    cm = os.path.join(here, "..", "..", "scripts", "cluster-memory.sh")
    if not os.path.isfile(cm):
        return True  # cluster-memory absent (e.g. operator box) — assume claim ok
    sh(["bash", cm, "set", f"work:{item_id}", machine])
    got = sh(["bash", cm, "get", f"work:{item_id}"])
    return machine in got.stdout


def dispatch(job: str, item: F.WorkItem, commit: bool) -> str:
    payload = json.dumps({"id": item.id, "source": item.source, "type": item.type})
    if not commit:
        return f"DRY-RUN would dispatch {job}  ← {item.source}"
    r = sh(["nomad", "job", "dispatch", "-meta", f"WORK_ITEM={payload}", job])
    return ("dispatched " + job) if r.returncode == 0 else f"FAILED {job}: {r.stderr.strip()}"


# The two Claude job TYPES (container backend):
#   targeted  — lightweight, no warm-up, one specific question, fast (~20 min cap)
#   explorer  — deep, full warm-up, long pondering for hidden connections (~60 min)
MODE_PROMPT  = {"targeted": "targeted.md", "explorer": "explorer.md"}
MODE_TIMEOUT = {"targeted": "1200", "explorer": "3600"}  # CLAUDE_TIMEOUT seconds


def _mode_prompt(mode: str, item: F.WorkItem) -> str:
    """Load the job-type prompt template and append the dispatched frontier item
    (the prompt files end with their own focus/seed header)."""
    pf = os.path.join(_HERE, "..", "..", "scripts", "prompts", MODE_PROMPT.get(mode, "explorer.md"))
    base = open(pf, encoding="utf-8").read() if os.path.isfile(pf) else ""
    return (base + f"\n  source: {item.source}\n  type:   {item.type}\n  id:     {item.id}\n")


def dispatch_container(mode: str, item: F.WorkItem, account: str, commit: bool) -> str:
    """Launch a containerized Claude session on THIS host (detached). `mode` is the
    job type (targeted|explorer): it picks the prompt and the wall-clock timeout.
    One container per account at a time (serialized on the shared credentials);
    honours the same claim() dedup as the Nomad path."""
    launcher = os.path.join(_HERE, "..", "dispatch", "run-container-session.sh")
    if not os.path.isfile(launcher):
        return f"FAILED container: launcher missing ({launcher})"
    machine = f"container-{account}-{mode}-{int(time.time())}"
    if not commit:
        return f"DRY-RUN would launch {mode} container {machine} ← {item.source}"
    # don't stack a second session on the same account's credentials
    ps = sh(["bash", "-c", "sudo docker ps --format '{{.Names}}' 2>/dev/null"])
    if f"session-container-{account}" in ps.stdout:
        return f"skip: a {account} container is already running"
    prompt = _mode_prompt(mode, item)
    env = dict(os.environ, CLAUDE_TIMEOUT=MODE_TIMEOUT.get(mode, "2700"))
    r = subprocess.run(["bash", launcher, machine, prompt, "--detach"],
                       capture_output=True, text=True, env=env)
    return f"launched {mode} container {machine}" if r.returncode == 0 \
        else f"FAILED container {machine}: {(r.stderr or r.stdout).strip()[:200]}"


def plan(items: list[F.WorkItem], free: list[str], limit: int):
    """Greedy: for each free account, the top item matching its (or any) role."""
    assignments = []
    used = set()
    # first pass: role-matched
    for acct in free:
        want = ACCOUNT_ROLE[acct]
        for w in items:
            if w.id in used:
                continue
            if w.best_role == want:
                assignments.append((acct, w)); used.add(w.id); break
    # second pass: fill remaining free accounts with any top unclaimed item
    for acct in free:
        if any(a == acct for a, _ in assignments):
            continue
        for w in items:
            if w.id not in used:
                assignments.append((acct, w)); used.add(w.id); break
    return assignments[:limit]


def main():
    ap = argparse.ArgumentParser(description="assign frontier work to idle agents")
    ap.add_argument("--commit", action="store_true",
                    help="actually claim + dispatch (default: dry-run, dispatch nothing)")
    ap.add_argument("--exec", choices=["nomad", "container"], default="nomad",
                    help="execution backend: nomad parameterized jobs (default) or "
                         "containerized Claude sessions on THIS host")
    ap.add_argument("--account", default=None,
                    help="restrict dispatch to this Claude account only (the account "
                         "this host is logged into; required for --exec container)")
    ap.add_argument("--mode", choices=["targeted", "explorer"], default="explorer",
                    help="container job type: 'explorer' (deep, full warm-up, long; "
                         "default/bread-and-butter) or 'targeted' (lightweight, no "
                         "warm-up, one question, fast)")
    ap.add_argument("--cache-dir", default=os.path.join(tempfile.gettempdir(), "monad-frontier"))
    ap.add_argument("--max-dispatch", type=int, default=4)
    args = ap.parse_args()
    os.makedirs(args.cache_dir, exist_ok=True)

    items = F.build_frontier(args.cache_dir)
    free = idle_accounts()
    if args.account:  # single-host container model: only this host's account
        free = [a for a in free if a == args.account] or [args.account]
    print(f"[dispatch] frontier: {len(items)} item(s) | idle accounts: {', '.join(free) or 'none'}")
    if not items:
        print("[dispatch] nothing to do."); return

    assignments = plan(items, free, args.max_dispatch)
    if not assignments:
        print("[dispatch] no eligible assignments this cycle."); return

    runmode = "COMMIT" if args.commit else "DRY-RUN"
    jobtype = f" ({args.mode})" if args.exec == "container" else ""
    print(f"[dispatch] {runmode} via {args.exec}{jobtype}: {len(assignments)} assignment(s)")
    for acct, w in assignments:
        if args.commit and not claim(w.id, f"{args.exec}-{acct}"):
            print(f"  {acct:<6} skip {w.id} (claimed elsewhere)"); continue
        if args.exec == "container":
            result = dispatch_container(args.mode, w, acct, args.commit)
        else:
            result = dispatch(ROLE_JOB[w.best_role], w, args.commit)
        print(f"  {acct:<6} {w.best_role:<11} p={w.priority:.2f}  {result}")

    if not args.commit:
        print("\n[dispatch] dry-run only. Re-run with --commit to dispatch for real.")


if __name__ == "__main__":
    main()
