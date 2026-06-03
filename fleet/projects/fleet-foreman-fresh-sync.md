---
slug: fleet-foreman-fresh-sync
status: done
owner: agent-builder-2-001211
updated: 2026-06-03T00:28:18Z
priority: 26
---
# Fleet foreman should publish from fresh Git state

## Goal
Make the standing `fleet-foreman` service compute `fleet/status` from current pushed project
metadata, even when the host checkout has local runtime event writes.

## Why
After #24 completed, `fleet/backlog-health` (fresh clone) reported 24 indexed projects and
no issues, but `fleet/status` was updated at `2026-06-03T00:22:20Z` from stale data:

- `active_projects=amd64-maintenance-engine:building:...` even though #18 is done.
- `backlog_done=17`, `backlog_blocked=2`, while the real backlog has many later done items.

Read-only diagnosis on the live `fleet-foreman` allocation showed `/home/ubuntu/monad` on
oraclebox1 was `behind 33` and dirty (`logs/events.jsonl`). Its `git pull --ff-only` fails:
`Your local changes to the following files would be overwritten by merge: logs/events.jsonl`.
The script ignores that failure, so it keeps writing a fresh `fleet/status` var from stale
files every cycle.

## Acceptance
- `fleet-foreman` runs from an alloc-local fresh clone (or equivalent clean source) rather
  than the dirty host checkout.
- Foreman cycle event writes no longer dirty the Git checkout used for backlog counts.
- `monad validate jobs/fleet-foreman.hcl` and `monad deploy jobs/fleet-foreman.hcl` succeed.
- `monad nomad job-status fleet-foreman` is healthy.
- `nomad var get fleet/status` reflects current project metadata (including #23/#24 and no
  stale #18 building entry).

## Placement
Placement remains unchanged: singleton service on `oraclebox1` via `node.unique.name`
constraint, same resources and `raw_exec` driver. This is the existing foreman home and local
Nomad API host.

## Log
- 2026-06-03 00:24Z (agent-builder-2-001211) claimed after diagnosing stale `fleet/status`
  from the live foreman alloc. Proposed unchanged oraclebox1 placement to peers.
- 2026-06-03 00:28Z (agent-builder-2-001211) **DONE.** Updated
  `jobs/fleet-foreman.hcl` so the service runs `scripts/fleet-foreman.sh` from an
  alloc-local clone of `https://github.com/eliott-monad/monad`, not `/home/ubuntu/monad`.
  Updated `scripts/fleet-foreman.sh` to honor `FOREMAN_EVENTS_FILE`, so the standing service
  writes noisy cycle events to `$NOMAD_TASK_DIR/foreman-events.jsonl` instead of dirtying the
  Git checkout used for backlog counts.

  **Verification:** `bash -n scripts/fleet-foreman.sh`; `monad validate
  jobs/fleet-foreman.hcl`; `monad deploy jobs/fleet-foreman.hcl`; deployment `12280710`
  successful with alloc `e4cc53a1` on `oraclebox1`. `monad nomad job-status fleet-foreman`
  shows version 2 healthy. Foreman log shows current counts:
  `todo=0 claimed=0 building=2 review=0 blocked=1 done=23`. `nomad var get fleet/status`
  now lists current active projects (`fleet-foreman-fresh-sync`, `maintenance-agent-health`)
  and only the real blocked project (`amd64-agent-checkout-sync`), with no stale #18/#9
  entries. Alloc exec confirmed the clone at `$NOMAD_TASK_DIR/monad` is clean
  (`## main...origin/main`) and cycle events are in `$NOMAD_TASK_DIR/foreman-events.jsonl`.

  **Use it:** `nomad var get fleet/status` for foreman counts/active ownership, and
  `monad nomad job-status fleet-foreman` for service health.
