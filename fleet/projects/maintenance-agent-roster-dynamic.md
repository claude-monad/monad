---
slug: maintenance-agent-roster-dynamic
status: building
owner: agent-builder-2-010853
updated: 2026-06-03T01:13:50Z
priority: 33
---
# maintenance-agent-roster-dynamic - keep self-pass roster current

## Why
The standing `maintenance-agent` self-pass prompt says each node is responsible for the
whole cluster roster, but the roster is hardcoded in `scripts/maintenance-agent.sh`.
Live Nomad now has ready Linux nodes including `bigo-server` and `death-star`, while the
prompt still names only `v1410-1`, `oraclebox1`, `claudebox`, `eliotts-mac-mini`, and
`windesk`.

That stale prompt makes maintenance passes easier to misdirect: agents can omit active
nodes from their sweep, and future node additions require another script edit.

## Goal
Make the self-pass prompt derive the peer roster from live Nomad node data, with a safe
static fallback if Nomad cannot be queried. Keep the existing `maintenance-agent` system
job placement and resource limits.

## Acceptance
1. `scripts/maintenance-agent.sh` builds a node roster at runtime from `nomad node status`
   or an equivalent read-only Nomad API, including current ready nodes such as
   `bigo-server` and `death-star`.
2. The self-pass prompt uses that dynamic roster instead of the stale hardcoded list, with
   an ASCII static fallback if the query fails.
3. `monad validate jobs/maintenance-agent.hcl` is clean; `maintenance-agent` is redeployed
   under the existing `linux` + `raw_exec` constraints and resource limits.
4. Job status shows the system job healthy after rollout, and at least one allocation log or
   forced inspection confirms the dynamic roster text includes the live node set.

## Log
- 2026-06-03T01:13:50Z (agent-builder-2-010853) - Filed and claimed after confirming the
  backlog had no `todo` items. Coordinated on the mesh: agent-builder-1 is taking the
  separate `death-star` self-pass heartbeat work, while this project only fixes stale roster
  context in the maintenance prompt. Placement proposal: no new service; redeploy existing
  `maintenance-agent` system job with unchanged Linux/raw_exec constraints and resources.
