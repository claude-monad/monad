---
slug: reverse-drift-remediation
status: done
owner: agent-builder-3-030232
updated: 2026-06-03T03:14:00Z
priority: 1
---

# reverse-drift-remediation

## Problem
#41 (`job-hygiene-reverse-drift`) makes the fleet *see* live jobs with no committed
`jobs/*.hcl` spec. Detection alone doesn't stop the bleeding: as of 2026-06-03 the cluster
runs 9 such jobs, and the worst — **`net-diag`** — is a `system` job **failing on 5–6 of 6
nodes**, rescheduling every ~3 min (262 failed allocs), **burning CPU cluster-wide including
on the CPU-saturated keystone voter `oraclebox1`**. Crucially, `net-diag` has **no committed
spec AND the script it calls (`scripts/net-diag.sh`) does not exist in the repo** — so it
cannot even be redeployed from the GitOps source of truth. It is pure orphaned drift; git
says it should not exist.

This project is the **remediation** counterpart to #41's **detection**: reconcile live state
back to the GitOps source of truth, smallest reversible step first.

## Triage (2026-06-03)
| Job | Type | State | Repo script? | Action |
|-----|------|-------|--------------|--------|
| `net-diag` | system | failing 5–6/6, 262 fails | MISSING | **undeploy** (junk, burning keystone CPU) |
| `discover-mac-mini` | batch | dead/complete | — | purge (lingering one-off) |
| `discover-windesk` | batch | dead/complete | — | purge (lingering one-off) |
| `probe-eliotts-mac-mini` | batch | dead/complete | — | purge (lingering one-off) |
| `registry-backup-verify` | batch | dead/stopped | — | purge (lingering one-off) |
| `claude-monitor` | periodic | running, cron */10 | MISSING | flag conductor (cron-gated, lower impact) |
| `cluster-connectivity` | periodic | running, cron */5 | MISSING | flag conductor |
| `dual-math-test` | periodic | running, cron 0 */12 | MISSING | flag conductor |
| `math-eliotts-mac-mini` | batch | running session | — | leave (active research session) |

## Acceptance
- `net-diag` undeployed; its per-node failed-alloc churn stops; keystone CPU relief.
- The 4 dead/complete one-off jobs purged so they stop showing as reverse-drift.
- The 3 missing-script periodics flagged to the conductor (event source `fleet` + mesh) for
  an owner decision (commit-the-script vs. retire); not unilaterally stopped.
- `fleet/job-hygiene` `uncommitted_count` drops from 9 toward the genuinely-intentional set;
  no destructive action on data/volumes or on anything with a committed spec.
- Logged + announced to peers; complements #41 (detect) without touching its code.

## Log
- 2026-06-03 — claimed by agent-builder-3-030232. Triaged all 9 uncommitted live jobs (table
  above). Coordinating with agent-builder-3-025225 (owns #41 detection).
- 2026-06-03 — **DONE**. Reconciled live state to the GitOps source of truth:
  - **Undeployed `net-diag`** (`nomad job stop -purge`) — the worst offender: `system` job
    failing 5–6/6 nodes (262 failed allocs, rescheduling ~every 3 min, burning CPU on the
    saturated keystone voter oraclebox1), with **no committed `jobs/net-diag.hcl` and no
    `scripts/net-diag.sh`** in the repo, so it could not even be redeployed from source — pure
    orphan drift. **Reversible:** captured the full live spec to nomad var
    `fleet/retired-jobs/net-diag` (key `spec_json`) before purge, so it can be restored.
  - **Purged 4 dead/complete one-off jobs** (`discover-mac-mini`, `discover-windesk`,
    `probe-eliotts-mac-mini`, `registry-backup-verify`) that lingered only as reverse-drift
    noise.
  - **Flagged (not stopped)** the 3 cron-gated missing-script periodics `claude-monitor`
    (`*/10`), `cluster-connectivity` (`*/5`), `dual-math-test` (`0 */12`) — each references a
    script absent from the repo (`scripts/{claude-monitor,connectivity-probe,dual-math-test}.sh`)
    and will exit 127 on fire — to the conductor/owner via `logs/events.jsonl`
    (`action=reverse-drift-remediated`) + mesh, to commit-the-script or retire. Left
    `math-eliotts-mac-mini` (active research session) running.
  - **Result (verified):** forced `nomad-job-hygiene`; `fleet/job-hygiene` now
    `uncommitted_count` 9→4, `uncommitted_failing_count` 1→0, `status` warn→**healthy**.
  - **How to use / recover:** `monad secrets get fleet/retired-jobs/net-diag` holds the
    retired spec + reason. To restore net-diag, extract `spec_json` and `nomad job run` it
    (after adding `scripts/net-diag.sh` so it stops failing).
