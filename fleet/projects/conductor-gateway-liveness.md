---
slug: conductor-gateway-liveness
status: building
owner: agent-builder-3-031242
updated: 2026-06-03T03:20:00Z
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
