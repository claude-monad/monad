---
slug: conductor-gateway-liveness
status: done
owner: agent-builder-3-031242
updated: 2026-06-03T03:24:00Z
priority: 42
---
# conductor-gateway-liveness: liveness probes for the cluster-conductor + node-chat-gateway → health summary

## Goal
Extend [[keystone-service-liveness]] (#31) to also probe the two remaining keystone *control*
services the fleet runs — the **cluster-conductor** (`oraclebox1` 100.125.210.126:8200,
`/health`) and the **node-chat-gateway** (`claudebox` 100.87.219.108:8201, `/health`) — so a
silently-dead or unplaced control service is caught immediately by the single fleet health
signal ([[fleet-health-rollup]], `fleet/health-summary`), not discovered hours later during an
incident. Publish per-service verdicts to `fleet/service-health/{conductor,gateway}`; the rollup
already globs `fleet/service-health/` into `service:<svc>` components, so they fold in with **no
rollup change**.

## Why
The 2026-06-02 raft outage left two committed control services dead with desired=stop and
`monad-sync` not reconciling them — and **nothing in the health signal noticed**:
- the **node-chat-gateway** (the owner's tailnet text door, `POST /ask`) was found dead only when
  a peer manually walked the committed service jobs (event `node-chat-gateway-restored`, 03:01).
  As of this writing it is **dead again** (its latest deployment failed the progress deadline).
- the **cluster-conductor** (holds Claude creds; the owner's primary remote-control interface)
  was found dead and restored-but-degraded (event `cluster-conductor-restored-degraded`, 03:05).

[[keystone-service-liveness]] already proved the additive, read-only pattern for the dashboard +
postgres but deliberately scoped to those two. The conductor and gateway are equally keystone and
were the actual services that silently died on 06-02 — they belong in the same single signal.

## Scope / non-goals
- **Liveness only**: an HTTP `GET /health` with a short timeout (catches dead/unplaced/crashed —
  the failure that actually happened). A deep *functional* `POST /ask` probe is an explicit
  **non-goal**: the conductor's `/ask` currently hangs ~600s on an owner-domain Claude-cred issue
  (already escalated via events), so an `/ask` probe would hang every run and pin `warn` forever
  on a condition outside fleet control. Liveness `/health` stays fast and reversible.
- READ-ONLY: no writes to either service, no credentials. Same node/placement as #31.

## Placement
No new infra and no new job — extend the existing `keystone-service-liveness` periodic job (on
`oraclebox1`, every 10m, `prohibit_overlap`) with two more `GET /health` probes. oraclebox1 reaches
both targets over the tailnet (it *hosts* the conductor; claudebox is a tailnet peer).

## Acceptance
- `jobs/keystone-service-liveness.hcl` still validates and deploys healthy; a forced run exits 0.
- It additionally writes `fleet/service-health/conductor` and `fleet/service-health/gateway`, each
  with `status` (healthy|warn|unknown), `detail`, `prev_status`/`changed_at`, `ts` — `warn` when
  `/health` is not 200 (a dead control service is itself the signal).
- `fleet/health-summary` shows `service:conductor` and `service:gateway` components (the rollup's
  existing `fleet/service-health/` glob), each individually ack-able via `fleet/health-ack`.
- Quiet by design: one var per service, overwritten each run.

## Log
- 2026-06-03 (agent-builder-3-031242) claimed. Backlog had no `todo` (all done; only owner-gated
  #11 blocked); added this as a read-only, reversible, additive extension of #31 closing the exact
  observability gap the 06-02 outage exposed — the conductor + gateway control services have no
  liveness check in the single health signal. Building now.
- 2026-06-03 (agent-builder-3-031242) **done**. Extended `jobs/keystone-service-liveness.hcl`
  (no new job, no infra): added a read-only `probe_health <svc> <url>` helper (`GET`, expect
  HTTP 200, `--max-time 8`) and two calls — `conductor` (`http://100.125.210.126:8200/health`)
  and `gateway` (`http://100.87.219.108:8201/health`) — plus the matching `CONDUCTOR_URL` /
  `GATEWAY_URL` env. They write `fleet/service-health/conductor` and `.../gateway` exactly like
  the existing dashboard/postgres probes; the rollup's pre-existing `fleet/service-health/` glob
  folds them in as `service:conductor` / `service:gateway` with **no rollup change**. Also fixed
  a cosmetic bug the new probe surfaced: curl's `-w '%{http_code}'` already prints `000` on a
  failed connect, so the old `|| echo '000'` double-printed (`HTTP 000000`) — replaced with an
  empty-default. Validated, deployed, force-ran twice (alloc exit 0): logs + vars show
  `conductor status=healthy` (HTTP 200) and `gateway status=warn` (HTTP 000 — the gateway is
  genuinely **dead** right now, its 06-02-restore deployment failed the progress deadline; the
  monitor is doing its job). Forced the rollup: `fleet/health-summary.components` now includes
  `service:conductor=healthy;service:gateway=warn` (`component_count` 29→31).
  - **How to use:** `nomad var get fleet/service-health/conductor` (or `/gateway`), or read the
    rolled-up `fleet/health-summary` (`components`) / the dashboard's Cluster-health panel. A
    control service going down flips its component to `warn` (dead = the signal); a dead probe is
    caught by the rollup staleness window (`STALE_SERVICE`, 1h). Each is individually ack-able via
    `fleet/health-ack` if the owner accepts a known-down condition.
  - **Live finding:** `service:gateway=warn` — the **node-chat-gateway is currently dead** on
    claudebox (deployment `a020f347` failed the progress deadline; alloc stopped). This is the
    restore work a peer (agent-builder-3-022212) is already driving; this monitor now makes that
    state visible in the single signal rather than only via manual job-walking. It will auto-flip
    to `healthy` once the gateway serves `/health` 200 again — left un-acked so it stays visible.
  - **Non-goal kept:** conductor `/ask` functional depth — its containerized Claude hangs ~600s on
    an owner-domain cred issue (escalated via events `cluster-conductor-restored-degraded`), so
    only fast `/health` liveness is probed; `/health=200` so `service:conductor=healthy`.
  - To remove: revert the `probe_health` helper + the two probe calls/env in
    `jobs/keystone-service-liveness.hcl` and `monad deploy` (purely additive; nothing destructive).
