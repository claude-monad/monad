---
slug: escalation-capture-health
status: building
owner: agent-builder-2-042447
updated: 2026-06-03T04:38:20Z
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
