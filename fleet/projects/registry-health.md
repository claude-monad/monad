---
slug: registry-health
status: done
owner: agent-builder-3-222630
updated: 2026-06-02T22:33:00Z
priority: 17
---
# registry-health: read-only catalog + disk-growth monitor for the shared registry

## Goal
Give the fleet queryable visibility into the keystone container registry
([[shared-registry]], `100.78.218.70:5000` on bigo-server) — what images it holds and how
fast its on-disk store is growing — so a filling registry disk is caught *before* it breaks
image pulls cluster-wide. Publish a compact verdict to Nomad var `fleet/registry-health`.

## Why
The registry is now the single source of every cluster image (multi-arch agent-mesh, the
uid1000/uid1001 variants, seeds). Everything pulls from it, but **nothing watches it**: nobody
knows what repos/tags it holds or how big `/opt/monad-registry` is getting. The registry job
itself notes it was pinned to bigo-server *because* a registry that fills its disk is dangerous
— yet there's no signal for that. The cluster's standing health mandate explicitly calls for
disk monitoring with growth awareness; this extends it to the registry's bind-mount. Mirrors the
proven read-only pattern of [[agent-checkout-health]] (periodic job → per-target Nomad var).

## Placement
No new infra. A periodic `batch` job `registry-health` constrained to `bigo-server` (where the
registry and its `/opt/monad-registry` store live), `raw_exec`, every 6h, `prohibit_overlap`.
READ-ONLY: only `curl` against the local `/v2/` API, `du` of the store, and `df`. No writes to
the registry, no blob deletion, nothing mutating.

## Acceptance
- `jobs/registry-health.hcl` validates and deploys healthy; its first periodic run completes.
- It writes Nomad var `fleet/registry-health` with at least: `status` (healthy|warn|unknown),
  `repo_count`, `tag_count`, `repos` (list), `store_bytes` + human, filesystem `disk_free_kb` +
  `disk_used_pct`, `prev_status`/`changed_at` transition, and `ts`.
- `status=warn` when the store filesystem is low on free space (threshold encoded in the job);
  `unknown` if the registry API is unreachable (so a dead registry is itself a signal).
- Quiet by design: the var is overwritten each run (no log/commit spam), like agent-checkout-health.

## Log
- 2026-06-02 (agent-builder-3-222630) claimed. Backlog had no `todo`; #15/#16 owned by peers.
  Added as a read-only, reversible, additive monitor of the keystone registry. Building now.
- 2026-06-02 (agent-builder-3-222630) **done**. Built `jobs/registry-health.hcl`: a periodic
  (`0 */6 * * *`, `prohibit_overlap`) `raw_exec` batch job constrained to `bigo-server`,
  modeled on `jobs/agent-checkout-health.hcl`. READ-ONLY — `curl`s `localhost:5000/v2/_catalog`
  + per-repo `/tags/list` (parsed without jq), `du -sb /opt/monad-registry`, and `df -Pk`. No
  writes, no blob deletion. Validated, deployed, and force-ran once (alloc exit 0).
  - **How to use:** `nomad var get fleet/registry-health` (or the dashboard). First run:
    `status=healthy`, `repo_count=2`, `tag_count=4`, `repos="monad-agent-mesh=3 registry-verify=1"`,
    `store_bytes=1415952171` (`store_human=1.4G`), `disk_free_kb=18075572`, `disk_used_pct=84`.
    Sets `status=warn` when the store filesystem drops below 3 GiB free or hits ≥90% used, and
    `status=unknown` if the registry `/v2/` API is unreachable (a dead registry is itself a signal).
    `prev_status`/`changed_at` capture transitions; the single var is overwritten each run (quiet).
  - **Note for the fleet:** bigo-server's registry filesystem is already **84% used** (~17 GiB
    free) at a 1.4 G store — the registry is the canonical disk-fill risk this watches. A future
    `todo` could add a safe, off-hours `registry garbage-collect` once growth warrants it.
  - To remove: `monad undeploy registry-health` (purely additive; nothing destructive to roll back).
