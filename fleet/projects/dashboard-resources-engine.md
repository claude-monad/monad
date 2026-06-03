---
slug: dashboard-resources-engine
status: todo
owner: ""
updated: ""
priority: 1
---
# Dashboard: per-node resources, overload detection, engine toggle, account usage

Extend the cluster dashboard (`meta/dashboard/server.py`, served by `cluster-dashboard` on
bigo-server :8088). It already shows nodes/jobs/mesh/events/backlog/health/capabilities and
reads the Nomad API. Add:

## 1. Per-node resource panel  (CPU / memory / disk)
For every node show **allocated vs total** and **live utilization** for CPU, memory, and
disk, from the Nomad API:
- allocation + capacity: `GET /v1/node/<id>` (`NodeResources` total, `ReservedResources`,
  and sum of running allocs' `AllocatedResources`) — same numbers as `nomad node status`.
- live util: `GET /v1/client/stats?node_id=<id>` (CPU %, used memory, disk).
Show each as used/total + a %.

## 2. Highlight stressed nodes
Flag nodes that are **low on a resource now** (e.g. memory or disk > 85%, or free CPU near 0)
AND nodes that have been **overloaded for a while** (sustained high CPU/mem). Use the metric
history the node-doctors already record (`logs/metrics-<node>.csv`) or a short rolling poll;
"for a while" = e.g. >85% across the last ~N samples. Sort/color so an at-a-glance "who's
hurting" is obvious. Today: **oraclebox1 is chronically saturated** (CPU ~100%, RAM ~85%)
while **death-star is nearly idle** (80 cores, 157 GiB) — the panel should make that obvious.

## 3. Engine toggle (Claude vs Codex)
Show the cluster's current default engine and let the owner flip it from the dashboard:
- read `GET /v1/var/cluster/engine` (item `engine` = `codex` | `claude` | `auto`; default codex).
- a control that writes it back (`PUT /v1/var/cluster/engine`). The engine abstraction
  (`meta/agent/engines.sh`) already reads this var, so flipping it changes what new agents use.

## 4. (Future) Anthropic + OpenAI account usage
A panel showing usage/limits for the Anthropic (Claude) and OpenAI (Codex) accounts — e.g.
rate-limit headroom, spend, recent token usage. Sources TBD (CLI `/usage`-style output,
provider APIs, or parsing session metrics in `~/.claude.json` / `~/.codex`). Owner said
"in the future" — stub the panel + wire real data when a source is settled.

## Acceptance
Dashboard shows per-node CPU/mem/disk with stressed-node highlighting, a working engine
toggle that flips `cluster/engine`, and a placeholder usage panel. Committed; reachable at
the dashboard address (`infra/dashboard`).

## Log
