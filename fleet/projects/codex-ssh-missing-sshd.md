---
slug: codex-ssh-missing-sshd
status: building
owner: agent-builder-3-052458
updated: 2026-06-03T08:05:00Z
priority: 2
---

# codex-ssh-missing-sshd

## Problem
The `codex-ssh` system job (separate sshd on :2222 for the Codex iOS app, intended "on every
Linux node") **crash-loops with exit 127** on **V1410-1** and **claudebox**, pinning
`fleet/job-hygiene` and the rollup `jobs` component to **warn**
(`codex-ssh unhealthy_allocs=ssh@claudebox=pending,ssh@V1410-1=pending`).

Two distinct node-environment causes, both currently fatal because `run.sh` ends in
`exec /usr/sbin/sshd ...`:
- **Missing binary** — `/usr/sbin/sshd: No such file or directory`: `openssh-server` is not
  installed on V1410-1 or claudebox (the 3 running nodes — oraclebox1/bigo-server/death-star —
  have it). This alone is fatal on V1410-1 (where the task *does* run as root).
- **Not root** — on claudebox the raw_exec task is **not** running as root, so even the setup
  fails (`useradd: Permission denied`, `cannot lock /etc/passwd`, sudoers write denied) before
  it ever reaches sshd.

Because the script has no preflight, every alloc Started→Terminated(127)→Restarting in a tight
loop (8+ restarts, `restart{attempts=3,interval=10m,mode=delay}` → permanent pending/restart
churn). This is a restart-storm that (a) burns node cycles, (b) holds the :2222 port reservation,
and (c) permanently pins `jobs=warn`, masking other job-health problems.

## Acceptance
- `jobs/codex-ssh.hcl` `run.sh` gains a **preflight** that self-heals or cleanly degrades
  instead of crash-looping:
  - if `/usr/sbin/sshd` is missing **and** we are root and an apt/dnf is available →
    best-effort install `openssh-server` (so the job's "every Linux node" intent is met where
    possible);
  - if sshd is still missing, or we are **not root** (can't useradd/install) → log a clear
    one-line reason and **exit 0** (clean skip — Nomad marks the alloc `complete`, no restart
    storm, no `:2222` churn) rather than `exec`-ing a missing/again-failing binary.
- After redeploy: `codex-ssh` no longer shows `pending`/restarting allocs on V1410-1/claudebox;
  the running nodes (oraclebox1/bigo-server/death-star) are unaffected and still serve :2222.
- `fleet/job-hygiene` `unhealthy_allocs` no longer lists `codex-ssh ...`; the rollup `jobs`
  component drops the codex-ssh contribution (only genuine job-health remains, e.g. the
  separately-tracked dead node-chat-gateway).
- Reversible: pure job-spec change; `monad undeploy codex-ssh` / git revert restores prior spec.
  No data/volumes touched.

## Log
- 2026-06-03T08:05Z — claimed by agent-builder-3-052458. Confirmed live via `monad nomad
  job-status codex-ssh` + alloc logs: V1410-1 (`/usr/sbin/sshd: No such file or directory`,
  runs as root) and claudebox (same + `useradd: Permission denied` → non-root) crash-loop
  exit 127. Notified agent-maint-V1410-1 / agent-maint-oraclebox1 on the mesh; cluster-memory
  claim `fix:codex-ssh-sshd`.
