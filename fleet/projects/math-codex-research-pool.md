---
slug: math-codex-research-pool
status: todo
owner: null
updated: 2026-06-04T20:55:01Z
priority: 1
---

# math-codex-research-pool

## Owner Request
Keep a small, always-available pool of containerized Codex math researchers online so the
owner can query them back and forth during research. Target shape: about a handful of
researchers available most of the time, with at least one placed on nodes that have real
compute capacity for math work.

## Desired State

- A supervised Nomad-backed pool of roughly 4-5 containerized Codex math researchers.
- Placement should prefer or spread onto nodes with usable compute and Codex credentials, not
  pile up on the saturated keystone nodes.
- Each researcher must have an identity, a fresh isolated working tree, math-specific prompt
  context, and a reachable conversation path.
- Researchers should be restartable/self-healing and discoverable from the dashboard, mesh, or
  a simple CLI command.
- This should build on the existing `monad-agent-mesh` / `agent-mesh` container path and the
  `codex-worker` gateway path instead of inventing a separate agent stack.

## Acceptance

- Add a committed job or small set of jobs that automatically maintain the pool.
- Pool instances use `MONAD_ENGINE=codex`, mount/read the node's Codex auth through the existing
  portable credential machinery, and clone the math repo or receive the math repo context in an
  isolated per-container workspace.
- The pool exposes a clear owner-facing roster: researcher name, host node, reachability method,
  current status, and last interaction.
- At least one instance places on each currently eligible compute-capable Codex node, subject to
  cluster capacity. Use Nomad `constraint`/`spread`/node metadata instead of hand-placing.
- The pool has bounded CPU/memory reservations and does not starve `v1410-1`, `oraclebox1`, or
  other keystone services.
- The owner can send a prompt to a chosen researcher and receive the response without manually
  discovering alloc IDs.

## Implementation Notes

- Existing pieces to reuse:
  - `jobs/agent-mesh.hcl`: containerized Codex/Claude agent with tsnet mesh identity.
  - `meta/agent/mesh/entrypoint.sh`: already supports persistent mesh peers and Codex.
  - `codex-worker/gateway.py`: continuity-preserving text gateway for Codex.
  - `scripts/prompts/explorer.md` / `scripts/prompts/researcher.md`: math-specific research
    prompt material.
- Likely work:
  - Add a persistent pool mode that combines mesh identity with a text/chat door for the owner.
  - Add lightweight health/roster publication, probably via Nomad vars.
  - Add node metadata for `math_codex_pool=true` or reuse `agent_mesh_ready=true` plus
    `has_codex=true`, then spread across `node.unique.name`.

## Log

- 2026-06-04 — Owner requested a handful of containerized math-specific Codex researchers that
  can be queried back and forth and are spun up automatically across capable cluster nodes.
- 2026-06-24 — Cadence/runtime requirement tightened: recurring math exploration/forum work
  should launch every 20 minutes cluster-wide, get at least 40 minutes of runtime budget, reuse
  existing checkouts where possible, and start agent sessions inside the math git repo.
