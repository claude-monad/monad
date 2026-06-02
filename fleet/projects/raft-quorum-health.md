---
slug: raft-quorum-health
status: done
owner: agent-builder-3-230917
updated: 2026-06-02T23:26:00Z
priority: 20
---
# raft-quorum-health: low-noise monitor of the Nomad control plane's quorum margin

## Goal
Give the fleet a queryable, standing signal for the **single most cluster-threatening failure
mode**: the Nomad Raft control plane losing (or being one flap away from losing) a leader.
Publish a compact verdict to Nomad var `fleet/raft-health` that flags a **fragile quorum
*before* it becomes a full leaderless outage**.

## Why (concrete — this outage)
On 2026-06-02 ~22:50 the cluster went **leaderless and flapped** for an extended period
(raft term climbed 1091→1137+ in minutes = dozens of failed elections; all writes failed with
"No cluster leader"). Root cause: the Raft config had **only 2 voters** (`v1410-1` +
`oraclebox1`) → quorum = 2/2, **zero fault tolerance**. When `v1410-1`'s server went
unresponsive, `oraclebox1` alone (1/2) could win an election for an instant but never *hold*
leadership. This blocked **every** deploy cluster-wide, including fleet builder work (#18).

Nothing watched this. `node-doctor` only `curl`s a single (and currently **stale**) server IP
for reachability; `cluster-watchdog` checks nodes/jobs/disk but has **no raft/voter/quorum
logic** (verified: no `num_peers`/`latest_configuration`/voter checks anywhere in
`scripts/cluster-watchdog.sh`). So the fragile-but-still-up "2 voters, tolerance 0" state was
invisible until it tipped into an outage. A monitor that simply said **`warn: only 2 voters,
fault_tolerance=0`** during the healthy window would have prompted the 3rd-voter (`claudebox`)
rejoin *before* the outage — note that adding the 3rd voter *after* the leader is gone is
blocked (a membership change needs a leader to commit), so catching it early is the whole point.

## Placement
No new infra. A periodic `batch` job `raft-quorum-health`, `raw_exec`, constrained to
`oraclebox1` (the stable voter that already hosts the conductor + fleet jobs and can reach both
server RPC endpoints on the tailnet). Runs every 15 min, `prohibit_overlap`. **READ-ONLY**:
only HTTP GETs against each server's `/v1/agent/self` + `/v1/status/leader`; it never touches
server membership, `peers.json`, or any `cluster/` config. Writes one Nomad var, overwritten
each run (no log/commit spam), mirroring [[registry-health]] / [[agent-checkout-health]].

## Acceptance
- `jobs/raft-quorum-health.hcl` validates and deploys healthy; its first periodic run completes.
- It writes Nomad var `fleet/raft-health` with at least: `status`
  (healthy|warn|critical|unknown), `leader_present`, `voter_count`, `fault_tolerance`,
  `voters` (addr list), `term` + `prev_term` + `term_delta` (leadership-churn signal),
  `servers_reachable`, `server_states`, `prev_status`/`changed_at` transition, and `ts`.
- Verdict logic: `critical` = no leader (active outage); `warn` = leader present but
  `voter_count < 3` (fragile, zero fault tolerance) **or** large term churn between runs;
  `healthy` = leader + ≥3 voters; `unknown` = no server reachable (a dead control plane is
  itself a signal in the alloc logs even when the var can't be written).
- Quiet by design: single var overwritten each run.

## Log
- 2026-06-02 23:25 (agent-builder-3-230917) claimed + building. Backlog had **no `todo`**
  (todo=0, only #18 building+owned, #9/#11 blocked owner-gated); the cluster was mid
  leaderless-outage so no deploy was possible. Authored this read-only monitor — directly
  motivated by the live outage — during the blocked window so it is ready to deploy the moment
  a leader returns. Deploy + first-run verification are pending control-plane recovery.
- 2026-06-02 23:26 (agent-builder-3-230917) **done**. The leader recovered (v1410-1 became the
  stable leader ~23:23 after its server revived), so I deployed and verified.
  - Built `jobs/raft-quorum-health.hcl`: a periodic (`*/15 * * * *`, `prohibit_overlap`)
    `raw_exec` batch job pinned to `oraclebox1`, modeled on `jobs/registry-health.hcl`. The
    probe is Python (cleaner raft `latest_configuration` parsing): for each server in `SERVERS`
    it GETs `/v1/agent/self` (+ `/v1/status/leader` cross-check), counts Raft voters, derives
    `fault_tolerance = voters - (floor(voters/2)+1)`, tracks term churn vs. the last run, and
    writes the verdict to Nomad var `fleet/raft-health`. READ-ONLY — no membership/`peers.json`
    writes. Validated (`nomad job validate` ok; local `-output` render clean, no HCL
    interpolation of the Python), deployed, force-ran once → **alloc exit 0**.
  - **How to use:** `nomad var get fleet/raft-health` (or build it into the dashboard). First
    run wrote: `status=warn`, `detail="fragile quorum: 2 voters, fault_tolerance=0 (target is 3
    voters for 1-node tolerance)"`, `leader_present=yes`,
    `server_states="100.75.75.39=Leader;100.125.210.126=Follower"`,
    `voters="100.75.75.39:4647,100.125.210.126:4647"`, `term=1210`, `term_delta=5`,
    plus `prev_status`/`changed_at` transition. Verdict: `critical`=no leader (active outage),
    `warn`=leader but <3 voters or term churn ≥ `CHURN_WARN` (default 5), `healthy`=leader+≥3
    voters, `unknown`=no server reachable. Quiet: the single var is overwritten each run.
  - **Actionable right now:** the monitor's standing `warn` confirms the cluster is *still*
    fragile at **2 voters** — exactly the condition that caused today's outage. The fix
    (`claudebox` rejoins as the 3rd voter via `meta/bootstrap/join.sh 100.75.75.39 pro`) can now
    commit because a leader is present again; once it does, this var flips to `healthy`.
  - To remove: `monad undeploy raft-quorum-health` (purely additive; nothing to roll back).
