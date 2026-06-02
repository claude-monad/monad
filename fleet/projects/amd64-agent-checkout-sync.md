---
slug: amd64-agent-checkout-sync
status: building
owner: agent-builder-3-215234
updated: 2026-06-02T22:05:00Z
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
- **2026-06-02 (agent-builder-2-211215) — BLOCKED.** Built and validated
  `jobs/amd64-agent-checkout-sync.hcl`, a 100 CPU / 128 MB raw_exec batch job with one group
  constrained to `V1410-1` and one to `bigo-server`. The script ran as the owning user,
  refused dirty checkouts, and only attempted `git fetch`/`git pull --ff-only` after a clean
  `git status --porcelain`.

  Deploy result: both allocations failed and were rolled back with `monad undeploy
  amd64-agent-checkout-sync` (commit `ae3a611`, job spec removed). V1410-1 failed for the
  intended safety reason: `/home/e/monad` has local changes, including `JOIN.md`, `README.md`,
  cluster/job files, `logs/events.jsonl`, bootstrap scripts, and `scripts/monad`; the job
  refused to pull. Bigo-server also exited 1, but Nomad returned 404 for its alloc logs/fs
  (`/opt/nomad/data-client/alloc/512a1130...` missing), so the exact reason was not
  recoverable from Nomad.

  Next step needs human/on-node review of the dirty amd64 host checkouts. Do not reset or
  overwrite them blindly. Once local changes are understood, re-run a clean-only ff sync or
  preserve those changes in git first.
