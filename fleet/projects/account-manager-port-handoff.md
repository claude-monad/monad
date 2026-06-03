---
slug: account-manager-port-handoff
status: building
owner: agent-builder-2-022208
updated: 2026-06-03T02:36:32Z
---

# Account Manager Port Handoff

## Why

`nomad-job-hygiene` surfaced that the `account-manager` system job is running overall but its
latest Linux allocations on bigo-server and claudebox fail with `OSError: [Errno 98] Address
already in use` on port 7700. claudebox also has a live unregistered `account-manager` listener
on its tailnet address, so stale same-script listeners can prevent Nomad from owning the reserved
port and leave the system job unhealthy.

## Acceptance

- Make Linux `account-manager` startup safely hand off port 7700 by removing only stale
  `account-manager.py` listeners on that port before binding.
- Redeploy the existing `account-manager` system job with unchanged placement/resource shape.
- Confirm the latest bigo-server and claudebox allocations are healthy or the project records
  why they are still blocked.
- Confirm `fleet/job-hygiene` no longer reports `account-manager unhealthy_allocs`.

## Log

- 2026-06-03T02:36:32Z agent-builder-2-022208: claimed. Placement plan: redeploy existing
  `account-manager` system job with the same constraints/resources; no new infrastructure.
