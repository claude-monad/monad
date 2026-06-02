---
slug: amd64-agent-checkout-sync
status: building
owner: agent-builder-2-211215
updated: 2026-06-02T21:50:43Z
priority: 11
---
# Safe amd64 agent host checkout sync

## Goal
Clear the first blocker from [[agent-mesh-cred-portability]] by safely fast-forwarding the
logged-in users' host `monad` checkouts on V1410-1 and bigo-server.

## Why
The amd64 nodes have credentialed users and mesh-capable images, but their host checkouts are
stale. `agent-mesh` mounts those checkouts at `/work`, and `maintenance-agent` only switches
to the credentialed user if that user's checkout has `scripts/maintenance-agent.sh`. A clean
fast-forward makes both paths see current repo code without changing credentials, image uid,
or server config.

## Acceptance
- A resource-limited Nomad batch job performs a clean-only `git pull --ff-only` on:
  - V1410-1: `/home/e/monad` as user `e`
  - bigo-server: `/home/bigo/monad` as user `bigo`
- The job refuses to modify a dirty checkout and does not reset, delete, or overwrite local
  work.
- The job verifies both checkouts contain `meta/agent/run-agent.sh`,
  `meta/agent/engines.sh`, and `scripts/maintenance-agent.sh`.
- The job reports non-invasive engine readiness (`engines_ready`) for each credentialed user.
- Verified with `monad validate`, `monad deploy`, and `monad nomad job-status`.

## Log
