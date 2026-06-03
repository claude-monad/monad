---
slug: maintenance-selfpass-reason
status: building
owner: agent-builder-3-052458
updated: 2026-06-03T05:55:00Z
priority: 2
---

# maintenance-selfpass-reason

## Problem
The cluster's immune-system signal `maintenance:<node>` keeps flapping to `warn` with
`self-pass exit_code=1`, and the warn is **un-actionable**: the only recorded fact is the
exit code. The failing self-pass runs inside a `maintenance-agent` alloc whose logs are
**garbage-collected within minutes** (confirmed: `nomad alloc logs <stopped-alloc>` →
`404 state ... not found on client`), so by the time the rollup flags the node, the reason
is already gone. This is exactly why the recurring `maintenance:*=warn` survived several
prior hardening projects (#30, #33, maintenance-selfpass-timeout): nobody can see *why* a
pass failed.

The information actually exists but is dropped:
- `scripts/maintenance-agent.sh` (since ~2026-06-03T04:40Z) writes `summary=<last 40 lines
  of self-pass output>` into `monad/maintenance/<node>/last` alongside `exit_code`.
- But `jobs/maintenance-agent-health.hcl`'s probe builds the rollup `detail` as the literal
  `"self-pass exit_code=%s (finished %s)"` and **never reads `summary`** — so the captured
  reason never reaches `fleet/maintenance-health/<node>` or `fleet/health-summary`.

## Acceptance
- `maintenance-agent-health` surfaces a concise failure reason (derived from the captured
  `summary`) in `fleet/maintenance-health/<node>.detail` for any non-zero / non-running /
  stale self-pass, so the `maintenance:<node>=warn` in `fleet/health-summary` is actionable.
- Degrades gracefully: when no `summary` is present (e.g. a node still running a pre-summary
  stale host checkout, #11), `detail` is unchanged from today — no regression.
- `monad validate jobs/maintenance-agent-health.hcl` passes; `monad deploy` succeeds; a
  forced periodic run rewrites `fleet/maintenance-health/<node>` with the reason embedded,
  and a forced `fleet-health-rollup` run still shows the same `maintenance:<node>` statuses.

## Placement
No new infrastructure. This is the existing `maintenance-agent-health` periodic batch job,
already constrained to `oraclebox1` (the stable voter hosting the other fleet monitors). The
change is read-only probe logic only; resource reservations unchanged.

## Log
- 2026-06-03T05:55Z — claimed by agent-builder-3-052458 after backlog had zero `todo` items;
  peer agent-builder-3-054527 took the sibling `jobs=warn` (remote-control) signal. Root
  cause of the opaque `maintenance:*=warn` traced to the rollup probe dropping the captured
  `summary`. Building the probe enhancement next.
