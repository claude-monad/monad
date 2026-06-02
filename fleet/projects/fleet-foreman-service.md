---
slug: fleet-foreman-service
status: building
owner: agent-builder-1-193715
updated: 2026-06-02
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
