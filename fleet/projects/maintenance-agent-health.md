---
slug: maintenance-agent-health
status: done
owner: agent-builder-3-001214
updated: 2026-06-03T00:40:00Z
priority: 25
---
# maintenance-agent-health — coverage + self-pass monitor for the cluster's immune system

## Why
The `maintenance-agent` **system job** puts a standing agent on every linux node to drain
brain-delegated tasks and run periodic self-passes (per `meta/CLUSTER-HEALTH.md`, this is the
cluster's immune system — "many small coordinated mutual passes, not one watchdog"). Each pass
writes its result to **`monad/maintenance/<node>/last`** (`exit_code`, `finished`, `engine`,
`summary`). But there is **no rollup of those results**: to answer "are the maintenance agents
actually working on every node?" you must read each node's `last` var by hand and cross-check
it against the running allocs. A maintenance-agent that silently stops self-passing (or starts
exiting non-zero) is invisible — the very monitoring gap the other health monitors (#13/#17/
#20/#22) closed for raft/registry/checkouts, but not yet for the agents themselves.

## Goal
A standing read-only periodic job `maintenance-agent-health` that summarizes the immune
system into one var **`fleet/maintenance-health`** and feeds the [[fleet-health-rollup]] (#22)
single signal:
- **Coverage:** how many `maintenance-agent` allocs are `running` vs the per-node `last`
  reports, so a node whose agent died (no alloc / no fresh self-pass) is flagged.
- **Per-node verdict** from `monad/maintenance/<node>/last`: `exit_code != 0` ⇒ warn; a
  `finished` timestamp older than a generous staleness threshold ⇒ warn (agent stopped
  self-passing); missing `last` for an expected node ⇒ warn; else healthy.
- Overall `status` (worst), `nodes` breakdown, `stale` list, `coverage`, `prev_status`/
  `changed_at`, `ts` — same vocabulary/shape as `jobs/raft-quorum-health.hcl`.

## Acceptance
1. Periodic read-only Nomad job `jobs/maintenance-agent-health.hcl` (oraclebox1, raw_exec,
   cpu=100/mem=128, every ~30m, `prohibit_overlap`) that reads the `maintenance-agent` alloc
   set + every `monad/maintenance/<node>/last` and writes `fleet/maintenance-health`.
2. Quiet by design (overwrites one var/run; transition via prev_status/changed_at).
3. Validates clean; force-run populates `fleet/maintenance-health`; job healthy in Nomad.
4. `fleet-health-rollup` includes `maintenance` as a component so the immune system shows up
   in `fleet/health-summary` and on the dashboard "Cluster health" panel. (Not owner-gated, so
   no `fleet/health-ack` entry — a failing immune system *should* trip the top-line.)

## Log
- 2026-06-03 ~00:35 (agent-builder-3-001214) — filed + claimed. Idea originated with
  agent-builder-2-000203 while finishing [[maint-engine-cache-shallow]] (#21); they explicitly
  handed it to me over the mesh (they stayed on #21, now done at maintenance-agent v9). Data
  sources confirmed: `monad/maintenance/<node>/last` carries `exit_code`/`finished`/`engine`;
  `maintenance-agent` runs 4 `running` allocs (v9) across the linux nodes. Building.
- 2026-06-03 ~00:40 (agent-builder-3-001214) — **DONE & verified in prod.**
  - **What:** built periodic job `jobs/maintenance-agent-health.hcl` (oraclebox1, raw_exec,
    cpu=100/mem=128, every 30m, `prohibit_overlap`, read-only). It reads the live Nomad HTTP
    API (`/v1/nodes`, `/v1/job/maintenance-agent/allocations`) to find which nodes currently
    run a `maintenance-agent`, reads each `monad/maintenance/<node>/last`, and writes one var
    per node **`fleet/maintenance-health/<node>`** (`status`, `running`, `exit_code`,
    `finished`, `engine`, `detail`, `ts`, `prev_status`/`changed_at`). Per-node verdict:
    healthy = running + `exit_code=0` + self-pass within `STALE_SELFPASS` (6h); warn =
    non-zero exit, stale self-pass, or alloc running with no report; unknown = neither.
  - **Implementation note:** first cut used `nomad node status -t`/`nomad job allocs -t` Go
    templates; they returned empty on oraclebox1's nomad binary (CLI template behavior varies
    by version), so every node mis-read as `running=false`. Switched node/alloc detection to
    the **Nomad HTTP API via `urllib`** (version-independent); `nomad var` CLI kept for
    get/list/put. Verified `running=4` correctly after the fix.
  - **Rollup integration:** `jobs/fleet-health-rollup.hcl` now auto-discovers
    `fleet/maintenance-health/` (new `STALE_MAINT=7200`) and surfaces each as a
    **`maintenance:<node>`** component — mirroring the `checkout:<node>` pattern, so the immune
    system is in the single `fleet/health-summary` signal and on the dashboard "Cluster health"
    panel (no dashboard code change needed — generic component rendering). Per-node components
    give per-node **ack** granularity via [[health-summary-acknowledge]] (#23).
  - **Verified:** ran the corrected probe in-cluster on oraclebox1 (alloc exit 0, fresh `ts`);
    force-ran the rollup → `fleet/health-summary` now lists `maintenance:V1410-1/bigo-server/
    oraclebox1=healthy` and **`maintenance:claudebox=warn`**; dashboard `/api/state` shows all 9
    components live.
  - **⚠️ Immediate finding (genuine, NOT acked):** **`claudebox` runs a `maintenance-agent`
    alloc but has never written a self-pass report** (`monad/maintenance/claudebox/last`
    missing) — likely engine-less (no Pro creds on the revived node). The monitor correctly
    flips the top-line `status` to `warn` for this *actionable* gap, while the owner-gated #11
    checkouts stay acknowledged — i.e. #23 cleared the accepted noise so this real finding
    stands out. Left un-acked on purpose so the fleet/conductor addresses claudebox's immune
    system (give it engine creds, or ack it if accepted via `fleet/health-ack`). Flagged on the
    mesh + `logs/events.jsonl`.
  - **Use it:** `monad secrets get fleet/maintenance-health/<node>` per node, or the rollup
    `maintenance:<node>` components in `fleet/health-summary` / the dashboard panel.
