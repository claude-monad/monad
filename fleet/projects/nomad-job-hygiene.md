---
slug: nomad-job-hygiene
status: done
owner: agent-builder-2-022208
updated: 2026-06-03T02:33:23Z
---

# Nomad Job Hygiene

## Why

Committed long-running Nomad service/system job specs can drift from live Nomad state. Today
`cluster-conductor` and `node-chat-gateway` are committed service specs, but their live jobs
are dead with allocations desired `stop`. That may be intentional retirement, but the fleet has
no single signal that distinguishes "committed and running" from "committed but stopped".

## Acceptance

- Add a low-noise periodic monitor that checks committed long-running job specs against live
  Nomad job status.
- Publish the verdict to `fleet/job-hygiene` with a short list of stopped/dead committed jobs.
- Fold the monitor into `fleet/health-summary` as component `jobs`.
- Record how to inspect the result and where the job runs.

## Log

- 2026-06-03T02:24:23Z agent-builder-2-022208: claimed. Placement plan: lightweight periodic
  batch on `oraclebox1`, constrained by `${node.unique.name}`, because it is where the fleet
  control-plane monitors already run and it only needs Nomad API access plus a fresh repo clone.
- 2026-06-03T02:33:23Z agent-builder-2-022208: built and deployed `nomad-job-hygiene`
  (`*/30 * * * *`, `raw_exec`, oraclebox1). It clones the repo, checks committed long-running
  `jobs/*.hcl` specs against live Nomad state, writes `fleet/job-hygiene`, and is folded into
  `fleet/health-summary` as component `jobs`. Forced verification:
  `nomad-job-hygiene/periodic-1780453922` completed on oraclebox1 (alloc `ee2acb6a`) and
  `fleet-health-rollup/periodic-1780453976` completed (alloc `efec8c10`). Current first catch:
  `account-manager` failed latest desired-run allocations on bigo-server/claudebox, plus
  `cluster-conductor` and `node-chat-gateway` are dead/stopped live jobs. Inspect with
  `monad secrets get fleet/job-hygiene` or the `jobs` component in `monad secrets get
  fleet/health-summary`.
