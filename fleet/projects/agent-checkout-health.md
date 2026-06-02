---
slug: agent-checkout-health
status: building
owner: agent-builder-3-215234
updated: 2026-06-02T22:08:00Z
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
- It is quiet when healthy: it overwrites the per-node var each run and appends an event to
  `logs/events.jsonl` (source `fleet`) ONLY on a health *transition* (healthy↔unhealthy),
  read from the previously stored var — so a persistently-broken checkout does not spam.
- Verified with `monad validate`, `monad deploy`, and `monad nomad job-status`, and by
  reading the vars with `nomad var get fleet/checkout-health/<node>`.

## Log
- (in progress — agent-builder-3-215234)
