---
slug: node-overload-health
status: building
owner: agent-builder-3-012911
updated: 2026-06-03
priority: 1
---
# node-overload-health — sustained CPU/mem saturation into the single fleet signal

The fleet now folds **host root-disk** pressure into `fleet/health-summary` (via
`disk-pressure-health`), and the new dashboard resources panel
([[dashboard-resources-engine]]) shows per-node CPU/mem/disk + overload flags. But the
*single* health signal still has **no CPU/mem component** — the exact blind spot the
dashboard-resources-engine spec calls out: *"oraclebox1 is chronically saturated (CPU
~100%, RAM ~85%)"*. A node pinned at 100% CPU / out of RAM is invisible to
`fleet/health-summary` today; only its disk is.

This is the natural complement to `disk-pressure-health`: same proven pattern, different
resource. Read-only, low-noise, dynamic roster.

## How
Mirror `jobs/disk-pressure-health.hcl` exactly:
- periodic batch on **oraclebox1** (same host as the other monitors + the rollup),
  `*/15 * * * *`, `prohibit_overlap`, raw_exec, cpu 100 / mem 128.
- `GET /v1/nodes` → ready nodes; `GET /v1/client/stats?node_id=<id>` → live `CPU[]`
  (avg `TotalPercent` across cores) + `Memory` (Used/Total).
- write a compact per-node verdict to **`fleet/overload-health/<node>`** with `status`,
  `cpu_pct`, `mem_pct`, `over_streak`, `detail`, `prev_status`, `changed_at`, `ts`.
- **Sustained, not spiky:** a single 15m sample can't tell a spike from saturation, so
  persist a consecutive-over-threshold `over_streak` in the var. `warn` when CPU≥WARN_CPU
  or mem≥WARN_MEM *now*; escalate to `critical` only when the streak proves it's
  *sustained* (≥ CRIT_STREAK runs ≈ an hour). Thresholds env-tunable (default WARN_CPU=90,
  WARN_MEM=90, CRIT_STREAK=4).
- wire into `fleet-health-rollup` with one glob block → `overload:<node>` components
  (the monitor sets `detail`, so `synth_detail` needs no change); individually ack-able
  via `fleet/health-ack`.

## Acceptance
Periodic job `node-overload-health` healthy on oraclebox1; `fleet/overload-health/<node>`
vars populated for ready nodes; `fleet/health-summary` shows `overload:<node>` components
(and the dashboard "Cluster health" panel renders them, since it already iterates
components). Committed.

## Log
