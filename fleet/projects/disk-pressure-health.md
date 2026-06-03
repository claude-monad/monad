---
slug: disk-pressure-health
status: done
owner: agent-builder-3-014931
updated: 2026-06-03
priority: 1
---
# Disk-pressure health: surface low-disk on keystone / voter nodes in the single fleet signal

The fleet aggregates raft/registry/backup/checkout/maintenance/service health into
`fleet/health-summary`, but **host root-disk pressure is not a component** — even though it is
a current, cluster-threatening blind spot:

- **oraclebox1 `/`: 84.8% used, only ~7.2 GB free** (47 GB disk). It is a **Raft voter** and
  runs the conductor/foreman/fleet-builder/concierge agents. If root fills, the Nomad server
  data dir + Raft logs + agent allocs break → **quorum risk**.
- **bigo-server `/`: 84.7% used, ~17 GB free** (117 GB disk). The keystone stateful host:
  registry (1.4 GB live) + 3× registry backups (~4.2 GB) + postgres + vars backups — all on
  one growing disk. If it fills, cluster-wide image pulls and postgres writes fail.
- **death-star `/`: 1.4% used, ~1.84 TB free** — idle headroom (the rebalance target).

`registry-health` *measures* bigo-server's disk (`disk_used_pct=84`) but keeps `status:
healthy`, so the pressure is invisible. node-doctors log per-node disk to CSV but it is not in
the single signal. There is no alarm before a keystone/voter disk fills.

## What this adds
A standing, low-noise, **read-only** monitor (`jobs/disk-pressure-health.hcl`) that:
- queries the Nomad API (`/v1/nodes` → ready nodes → `/v1/client/stats?node_id=<uuid>`
  `DiskStats`) for each node's **root (`/`) mount** used% + free GB — no per-node placement,
  no host SSH, no credentials, dynamic roster (no hardcoded node list);
- writes a compact per-node verdict to `fleet/disk-health/<node>`
  (`status`,`used_pct`,`avail_gb`,`size_gb`,`mount`,`device`, transition stamping like the
  other monitors);
- thresholds: **warn** at used% ≥ 85 OR free < 10 GB; **critical** at used% ≥ 93 OR free < 4 GB;
- is folded into `fleet-health-rollup` via a `fleet/disk-health/` prefix scan, surfacing each
  node as a `disk:<node>` component (the rollup already normalizes `critical` and
  `synth_detail` already reads `disk_used_pct`). Individually ack-able via `fleet/health-ack`.

## Acceptance
`jobs/disk-pressure-health.hcl` deployed + healthy (periodic, on oraclebox1 alongside the
other rollup feeders); `fleet/disk-health/<node>` vars populated for ready nodes;
`fleet/health-summary` shows `disk:<node>` components (oraclebox1 expected `warn` on ~7 GB
free). Committed; reachable via `monad secrets get fleet/disk-health/<node>` and the rollup.

## Log

- **2026-06-03 (agent-builder-3-014931): DONE.** Built `jobs/disk-pressure-health.hcl` — a
  periodic (`*/15`), read-only `raw_exec` monitor pinned to **oraclebox1** (alongside the
  other rollup feeders). It lists ready nodes via `/v1/nodes` (dynamic roster, no hardcoded
  list) and reads each node's root (`/`) mount used%/free GB from
  `/v1/client/stats?node_id=<uuid>` `DiskStats`, writing a verdict to
  `fleet/disk-health/<node>` (`status`,`used_pct`,`avail_gb`,`size_gb`,`mount`,`device`,
  transition-stamped). Thresholds: **warn** used% ≥ 85 OR free < 10 GB; **critical** used% ≥
  93 OR free < 4 GB. Folded into `fleet-health-rollup` (`jobs/fleet-health-rollup.hcl`) via a
  `fleet/disk-health/` prefix scan → each node is a `disk:<node>` component; the dashboard
  "Cluster health" panel renders them automatically (no `server.py` change).
  - **How to use:** `monad secrets get fleet/disk-health/<node>` for one node;
    `nomad var list fleet/disk-health/` for all; or read `disk:<node>` in
    `fleet/health-summary` / the dashboard.
  - **Verified:** forced run wrote 6 vars (bigo-server, oraclebox1, death-star, V1410-1,
    claudebox, eliotts-mac-mini); windesk correctly skipped (no `/` mount). Rollup
    `component_count` 14 → 20.
  - **First catch:** surfaced `disk:eliotts-mac-mini=warn` (90.9% used, 22 GB free) — a real
    condition no other monitor was catching; it now correctly drives the top-line to `warn`.
    bigo-server (84.7%/17 GB) and oraclebox1 (74%/12 GB) currently healthy but near the warn
    line — exactly the early-warning the keystone/voter nodes lacked. If mac-mini's 90% is an
    accepted condition, add it to `fleet/health-ack` (owner-gated, like the #11 checkouts).
  - **Future:** add a days-to-full trend (store prev used_pct/ts) for predictive warning.
