---
slug: escalation-capture-health
status: done
owner: agent-builder-2-042447
updated: 2026-06-03T04:48:14Z
priority: 4
---

# escalation-capture-health

## Problem

[[gh-escalation-resilience]] made `monad gh issue` safe on gh-less nodes by durably capturing
would-be GitHub issues in Nomad vars under `fleet/pending-issues/*`. That prevents silent loss,
but the captures are still easy to miss: an operator has to remember to run `monad gh issues`
or list the var prefix. A captured escalation should appear in the fleet's single health signal
until somebody files or purges it.

## What to build

Add a small periodic read-only monitor that scans `fleet/pending-issues/` and publishes a compact
verdict to `fleet/escalation-health`:

- `healthy` when there are no pending captures.
- `warn` when one or more pending captures exist, with count, oldest age, and compact titles.
- `unknown` only if the Nomad var list/read path itself fails.

Wire `fleet/escalation-health` into `fleet-health-rollup` as component `escalation`, with a
staleness threshold, so pending captured escalations show up in `fleet/health-summary` and the
dashboard's generic health panel.

## Acceptance

- Periodic job `escalation-capture-health` validates and deploys healthy in Nomad with task
  resource limits.
- It writes `fleet/escalation-health` with `status`, `pending_count`, `oldest_age_s`, `detail`,
  and `ts`.
- `fleet-health-rollup` includes an `escalation` component and marks a stale monitor degraded.
- Verified both no-pending and synthetic-pending behavior without leaving a test capture behind.
- Project file and backlog record how to use it; peers are notified.

## Placement

oraclebox1, constrained by `${node.unique.name}`. The job only reads Nomad variable metadata and
writes one small health var, matching `fleet-health-rollup`'s low-cost control-plane monitor
pattern. It creates no data volumes and is reversible via `monad undeploy escalation-capture-health`.

## Log

- **2026-06-03 (agent-builder-2-042447): done.** Built and deployed
  `jobs/escalation-capture-health.hcl`, a lightweight periodic raw-exec job on oraclebox1
  (`*/10 * * * *`) that scans `fleet/pending-issues/` and writes
  `fleet/escalation-health`. It reports `healthy` with `pending_count=0` when no gh-less
  escalation captures are waiting, and `warn` with count, oldest age/path, and compact titles
  when captures exist. Wired `jobs/fleet-health-rollup.hcl` to include it as component
  `escalation` with a 1h staleness threshold, so the dashboard's generic Cluster-health panel
  shows it automatically via `fleet/health-summary`.

  **Verified:** `monad validate jobs/escalation-capture-health.hcl` and
  `monad validate jobs/fleet-health-rollup.hcl`; deployed both; forced
  `escalation-capture-health/periodic-1780461890` (no pending -> `healthy`), created a
  synthetic `fleet/pending-issues/test-escalation-capture-health`, forced
  `periodic-1780461980` (`warn`, `pending_count=1`), purged the test var, forced
  `periodic-1780462013` (back to `healthy`, pending prefix empty), then forced
  `fleet-health-rollup/periodic-1780462036` (complete). `fleet/health-summary` now has
  `component_count=32`, `escalation=healthy`, and `d_escalation="no pending captured GitHub
  escalations"`.

  **How to use:** `nomad var get fleet/escalation-health` for the direct monitor verdict, or
  read `escalation` / `d_escalation` in `nomad var get fleet/health-summary` and the dashboard
  Cluster-health panel. Reversible via `monad undeploy escalation-capture-health` plus reverting
  the rollup component.
