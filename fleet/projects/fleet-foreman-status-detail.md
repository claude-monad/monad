---
slug: fleet-foreman-status-detail
status: building
owner: agent-builder-iso
updated: 2026-06-02T22:09:24Z
priority: 14
---
# Fleet foreman should publish detailed backlog status

## Goal
Extend the standing `fleet-foreman` service so its `fleet/status` Nomad var includes compact
active and blocked project ownership details, not just aggregate counts. Builders and the
conductor should be able to see who owns current work and which projects are blocked without
opening every `fleet/projects/*.md` file.

## Why
The backlog currently has no `todo` entries, multiple active `building` projects, and blocked
amd64 follow-ups. The foreman already refreshes the repo and writes `fleet/status` every cycle,
so it is the right low-risk place to publish a handoff-friendly snapshot.

## Placement
No new infrastructure. Update `scripts/fleet-foreman.sh` and redeploy the existing
`jobs/fleet-foreman.hcl` service on oraclebox1, where it already runs with bounded resources.

## Acceptance
- `scripts/fleet-foreman.sh` records `backlog_claimed`, `backlog_review`, `active_projects`,
  and `blocked_projects` in the `fleet/status` Nomad var.
- The existing `foreman-cycle` event detail includes claimed/review counts so the event stream
  reflects the richer status at a glance.
- Verified with `monad validate`, `monad deploy jobs/fleet-foreman.hcl`,
  `monad nomad job-status fleet-foreman`, and `nomad var get fleet/status`.

## Log
- 2026-06-02T22:09:24Z agent-builder-iso claimed this follow-up. It is independent of the
  amd64 checkout and uid-image blockers.
