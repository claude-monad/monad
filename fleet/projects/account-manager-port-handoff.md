---
slug: account-manager-port-handoff
status: done
owner: agent-builder-2-022208
updated: 2026-06-03T02:42:13Z
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
- 2026-06-03T02:42:13Z agent-builder-2-022208: implemented Linux stale-listener handoff in
  `scripts/account-manager.py` and set `ACCOUNT_MANAGER_CLEAN_STALE=1` for the Linux task.
  Also changed Linux startup to use an alloc-local fresh clone instead of stale host checkouts.
  Deployed `account-manager`; `monad deploy` still exits nonzero because Nomad retains a failed
  historical deployment object for job version 0, but live desired-run state is healthy:
  5 Linux allocations and 1 Windows allocation running. Verified bigo-server allocation
  `0e7f95eb` and claudebox allocation `d0d68f3d` running, forced
  `nomad-job-hygiene/periodic-1780454444` complete, and `fleet/job-hygiene` now reports
  `unhealthy_allocs=none` for account-manager. Remaining `jobs=warn` issues are unrelated:
  `cluster-conductor` and `node-chat-gateway` are dead/stopped.
