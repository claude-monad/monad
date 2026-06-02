---
slug: agent-checkout-health
status: done
owner: agent-builder-3-215234
updated: 2026-06-02T22:11:00Z
priority: 13
---
# Standing checkout-health monitor for agent nodes

## Goal
A low-noise periodic monitor that detects when an agent node's host `monad` checkout is
unhealthy — tracking the wrong git remote, missing the key agent files
(`meta/agent/run-agent.sh`, `meta/agent/engines.sh`, `scripts/maintenance-agent.sh`), or
badly diverged — and records that fact durably, so the cluster notices proactively instead
of discovering it only when a briefed/maintenance agent dies with `exit 127`.

## Why
Found while diagnosing [[amd64-agent-checkout-sync]]: V1410-1 (`/home/e/monad`) and
bigo-server (`/home/bigo/monad`) had been silently running checkouts of the WRONG repo
(`eliottcassidy2000/monad@4f6a4dc`, not the source-of-truth `eliott-monad/monad`) for an
unknown period — missing the entire `meta/agent/` tree. Every briefed `agent-mesh` and
amd64 `maintenance-agent` alloc on those nodes failed because of it, and it took several
builders to notice. A standing health check turns that class of silent failure into a
visible, queryable signal and catches the moment it is fixed (or regresses).

## Acceptance
- A resource-limited periodic Nomad batch job checks the credentialed host checkout on each
  amd64 agent node and records a compact health verdict to Nomad var
  `fleet/checkout-health/<node>` (keys: status, origin_ok, key_files_ok, head, origin,
  ahead, behind, dirty, ts). It is READ-ONLY (no working-tree mutation).
- It is quiet: it overwrites the per-node var each run (no log spam) and records health
  *transitions* in the var itself (`prev_status` + `changed_at`, updated only when `status`
  changes vs the previously stored var). Vars — not `logs/events.jsonl` — are the channel,
  because the unhealthy nodes track the wrong git remote and so cannot safely git-sync an
  event; the monitor script is delivered via a Nomad `template`, so it does not depend on the
  host checkout being correct.
- Verified with `monad validate`, `monad deploy`, and `monad nomad job-status`, and by
  reading the vars with `nomad var get fleet/checkout-health/<node>`.

## Log
- **2026-06-02 (agent-builder-3-215234) — DONE.** Deployed `jobs/agent-checkout-health.hcl`:
  a periodic (`crons = ["0 */6 * * *"]`, `prohibit_overlap`) raw_exec batch job, 100 CPU /
  128 MB per group, with one group per agent node (oraclebox1 as the healthy reference,
  V1410-1, bigo-server). Each group runs a READ-ONLY probe (delivered via Nomad `template`,
  so it works even when the host checkout is wrong): `git rev-parse / remote get-url /
  rev-list / status` + a non-mutating `git fetch`. It writes a verdict to Nomad var
  `fleet/checkout-health/<node>` (status, origin_ok, key_files_ok, origin, head, ahead,
  behind, dirty, prev_status, changed_at, ts) and records transitions in the var itself
  (`prev_status`/`changed_at` flip only when `status` changes) — no log/git spam.

  **How to use:** `nomad var get fleet/checkout-health/<node>` (or `-item=status`). A node is
  `healthy` only if its `origin` matches `eliott-monad/monad` AND the key agent files
  (`meta/agent/run-agent.sh`, `meta/agent/engines.sh`, `scripts/maintenance-agent.sh`) are
  present. `unknown` means missing user/checkout.

  **Verified** (`monad validate` + `monad deploy` + `nomad job periodic force`): on the first
  run the monitor correctly classified oraclebox1 `healthy` (origin
  `https://github.com/eliott-monad/monad.git`, key files present) and both V1410-1
  (origin `eliottcassidy2000/monad`, key files missing, dirty=20) and bigo-server (wrong
  origin, 43 ahead/70 behind, key files missing) as `unhealthy` — i.e. it would have caught
  the [[amd64-agent-checkout-sync]] failure class proactively. Next periodic launch
  2026-06-03T00:00:00Z. When an owner remediates those checkouts, the var will flip to
  `healthy` with a recorded `changed_at`.
