---
slug: fleet-foreman-service
status: done
owner: agent-builder-1-193715
updated: 2026-06-02T20:33Z
priority: 5
---
# Fleet foreman as a standing service

## Goal
Turn `scripts/fleet-foreman.sh` into a standing Nomad service that keeps the fleet working:
ensures N builder agents are running, watches the backlog, and reports fleet progress to the
conductor — so building continues without a human kicking it off.

## Acceptance
- A Nomad `service` job (singleton, e.g. on oraclebox1) that periodically: reads the backlog,
  ensures up to N builders are dispatched on capable nodes, and reaps finished ones.
- Concurrency is bounded but generous (the owner wants the cluster busy). Reports a summary
  to `logs/events.jsonl` (source `fleet`) and a Nomad var `fleet/status` each cycle.

## Log
- 2026-06-02 (agent-builder-1-193715): **done.** Deployed `jobs/fleet-foreman.hcl` — a
  `service`-type singleton (raw_exec) pinned to **oraclebox1**, running
  `scripts/fleet-foreman.sh 3 --loop` (FOREMAN_N=3, INTERVAL=600s, ~200MHz/256MB). Each cycle
  it git-pulls, counts `fleet/projects/*.md` statuses, tops up `fleet-builder` dispatches up
  to N, and records:
    - Nomad var **`fleet/status`** — `nomad var get fleet/status` (running/target,
      dispatched_this_cycle, backlog_todo/building/blocked/done, updated).
    - an event line in **`logs/events.jsonl`** (source `fleet`, action `foreman-cycle`) →
      `monad events`.
  Enhanced the script: (a) reports backlog counts + a `fleet` event each cycle; (b) **fixed a
  dispatch pile-up bug** — `fleet-builder` is a *parameterized* job so `job status` has no
  unified Allocations table; the old `running_builders` always read 0 and re-dispatched every
  cycle, leaving many capacity-blocked Pending children. Now `active_builders` counts
  Pending+Running from the Parameterized Job Summary, so it bounds total active builders at N
  (queued-but-unplaced builders count) and uses `-detach` so the loop never blocks on
  placement. Verified live: cycle logged `builders=3/3 dispatched=1`, var shows running=3
  target=3, no pile-up (1 Pending waiting for capacity since oraclebox1 CPU is currently
  full — it places automatically when a builder finishes). Note: real builder *placement* is
  capacity-bound on oraclebox1 until `multiarch-agent-image` lets builders run on other nodes.
