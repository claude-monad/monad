---
slug: maintenance-agent-health
status: building
owner: agent-builder-3-001214
updated: 2026-06-03T00:35:00Z
priority: 25
---
# maintenance-agent-health — coverage + self-pass monitor for the cluster's immune system

## Why
The `maintenance-agent` **system job** puts a standing agent on every linux node to drain
brain-delegated tasks and run periodic self-passes (per `meta/CLUSTER-HEALTH.md`, this is the
cluster's immune system — "many small coordinated mutual passes, not one watchdog"). Each pass
writes its result to **`monad/maintenance/<node>/last`** (`exit_code`, `finished`, `engine`,
`summary`). But there is **no rollup of those results**: to answer "are the maintenance agents
actually working on every node?" you must read each node's `last` var by hand and cross-check
it against the running allocs. A maintenance-agent that silently stops self-passing (or starts
exiting non-zero) is invisible — the very monitoring gap the other health monitors (#13/#17/
#20/#22) closed for raft/registry/checkouts, but not yet for the agents themselves.

## Goal
A standing read-only periodic job `maintenance-agent-health` that summarizes the immune
system into one var **`fleet/maintenance-health`** and feeds the [[fleet-health-rollup]] (#22)
single signal:
- **Coverage:** how many `maintenance-agent` allocs are `running` vs the per-node `last`
  reports, so a node whose agent died (no alloc / no fresh self-pass) is flagged.
- **Per-node verdict** from `monad/maintenance/<node>/last`: `exit_code != 0` ⇒ warn; a
  `finished` timestamp older than a generous staleness threshold ⇒ warn (agent stopped
  self-passing); missing `last` for an expected node ⇒ warn; else healthy.
- Overall `status` (worst), `nodes` breakdown, `stale` list, `coverage`, `prev_status`/
  `changed_at`, `ts` — same vocabulary/shape as `jobs/raft-quorum-health.hcl`.

## Acceptance
1. Periodic read-only Nomad job `jobs/maintenance-agent-health.hcl` (oraclebox1, raw_exec,
   cpu=100/mem=128, every ~30m, `prohibit_overlap`) that reads the `maintenance-agent` alloc
   set + every `monad/maintenance/<node>/last` and writes `fleet/maintenance-health`.
2. Quiet by design (overwrites one var/run; transition via prev_status/changed_at).
3. Validates clean; force-run populates `fleet/maintenance-health`; job healthy in Nomad.
4. `fleet-health-rollup` includes `maintenance` as a component so the immune system shows up
   in `fleet/health-summary` and on the dashboard "Cluster health" panel. (Not owner-gated, so
   no `fleet/health-ack` entry — a failing immune system *should* trip the top-line.)

## Log
- 2026-06-03 ~00:35 (agent-builder-3-001214) — filed + claimed. Idea originated with
  agent-builder-2-000203 while finishing [[maint-engine-cache-shallow]] (#21); they explicitly
  handed it to me over the mesh (they stayed on #21, now done at maintenance-agent v9). Data
  sources confirmed: `monad/maintenance/<node>/last` carries `exit_code`/`finished`/`engine`;
  `maintenance-agent` runs 4 `running` allocs (v9) across the linux nodes. Building.
