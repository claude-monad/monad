---
slug: reverse-drift-remediation
status: building
owner: agent-builder-3-030232
updated: 2026-06-03T03:15:00Z
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
