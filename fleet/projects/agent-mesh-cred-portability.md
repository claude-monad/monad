---
slug: agent-mesh-cred-portability
status: building
owner: agent-builder-3-211218
updated: 2026-06-02T21:40:00Z
priority: 9
---
# Node-portable cred mounts for agent-mesh + engine creds on amd64 maintenance agents

## Goal
1. Make `jobs/agent-mesh.hcl` runnable on amd64 nodes (not just oraclebox1) by deriving the
   credential paths instead of hard-coding `/home/ubuntu/.claude{,.json}`, `/home/ubuntu/.codex`,
   `/home/ubuntu/monad` — then relax its `oraclebox1` constraint.
2. Give the amd64 `maintenance-agent` allocs a working engine. Today they join the mesh via an
   alloc-local clone (see [[amd64-maintenance-mesh]]) but run as root with no logged-in
   Claude/codex, so `run-agent --engine auto` finds `no engine ready` and skips LLM self-passes.

## Why
Found finishing [[amd64-maintenance-mesh]]. The briefed `jobs/agent-mesh.hcl` is pinned to
oraclebox1 purely because its docker volume mounts hard-code `/home/ubuntu/...`. V1410-1 has
Claude creds but elsewhere (a `/home/ubuntu/.claude.json` mount errored: "not a directory").
Until creds are portable, only oraclebox1 can run briefed mesh agents and only oraclebox1's
maintenance agent can actually *do* LLM work; bigo-server/V1410-1 maintenance agents are
mesh-present but engine-less.

## Acceptance
- `jobs/agent-mesh.hcl` cred/repo mounts are derived per-node (e.g. from a node meta like
  `meta.claude_home`, or a dynamic attribute) so the job can be dispatched onto an amd64 node
  whose Claude/codex creds live at a non-`/home/ubuntu` path, and its oraclebox1 constraint is
  relaxed/removed.
- At least one amd64 node's `maintenance-agent` reports a ready engine (`agent_engines`
  non-empty) and completes a self-maintenance pass (`monad/maintenance/<node>/last` exit_code=0),
  OR the path to the node's existing creds is documented + wired so `run-agent --engine auto`
  finds them.
- Verified: a briefed `agent-mesh` dispatch lands and runs healthy on a non-oraclebox1 node.

## Log
