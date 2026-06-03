---
slug: health-summary-acknowledge
status: building
owner: agent-builder-3-001214
updated: 2026-06-03T00:15:00Z
priority: 23
---
# fleet/health-summary: acknowledge owner-gated conditions so the top-line signal stays actionable

## Why
[[fleet-health-rollup]] (#22) rolled the scattered monitors into one `fleet/health-summary`
var + dashboard panel so "is the cluster healthy?" is **one signal**. But the very first
verdict is `status: warn`, and it will stay `warn` **indefinitely** — because the only
degraded components are the wrong-origin host checkouts on `V1410-1` and `bigo-server`
([[amd64-agent-checkout-sync]] #11). That fix is **owner-gated** (it discards local
commits/edits a builder may not touch per PROTOCOL) and explicitly **deprioritized / off the
critical path**. So the rollup's top-line is pinned to `warn` for an accepted, un-actionable
condition.

A health signal that is permanently `warn` for a known-and-accepted reason trains everyone to
ignore it — which defeats #22's purpose: a *new* problem (registry filling, raft losing a
voter, a monitor dying) would not change the top-line and would be missed.

## Goal
Add a lightweight **acknowledgement layer** so accepted conditions don't pin the top-line,
**without hiding them**:
- A new Nomad var `fleet/health-ack` maps a component name to the worst status that is
  *accepted* for it, plus a short reason (e.g. `checkout:V1410-1=warn` reason
  `owner-gated-#11`).
- The rollup computes the top-line `status` as the worst of **un-acknowledged** components
  (a component is covered only while its current effective status is **no worse** than its
  acked level — if it worsens beyond what was accepted, it counts again, so new degradation
  still surfaces).
- Full transparency is preserved: keep a `raw_status` (worst of *all* components, the old
  behavior) and add an `acknowledged` field listing covered components + their reason. The
  per-component `components`/`d_*` details are unchanged.

## Acceptance
1. `jobs/fleet-health-rollup.hcl` reads `fleet/health-ack` (absent ⇒ no acks ⇒ behaves
   exactly as today) and writes `fleet/health-summary` with new keys: `raw_status`,
   `acknowledged` (e.g. `checkout:V1410-1=warn(owner-gated-#11),checkout:bigo-server=warn(owner-gated-#11)`),
   and a top-line `status` that excludes covered components. `prev_status`/`changed_at`
   track the new top-line `status`.
2. A `fleet/health-ack` var is seeded for the two owner-gated checkouts (reason references
   #11) so the top-line goes `warn → healthy` while `raw_status` stays `warn` and the two
   checkouts remain visible under `acknowledged` and in `components`.
3. A component that degrades **beyond** its acked level (e.g. a checkout going `warn →
   critical`, or any *un-acked* component degrading) still trips the top-line `status`.
4. Validates clean (`monad validate`); force-run repopulates `fleet/health-summary`; job
   healthy in Nomad. oraclebox1 placement unchanged.
5. Dashboard panel still renders (it reads `status`/`components`); ideally shows the
   `acknowledged` line so accepted conditions are explicit, not invisible.

## Constraint
Edits the just-built [[fleet-health-rollup]] job. Keep the change **additive** (no-ack path
must be byte-equivalent in behavior), validate before deploy, verify the force-run output,
and roll back (`monad undeploy` + redeploy prior spec) if the rollup regresses.

## Log
- 2026-06-03 ~00:15 (agent-builder-3-001214) — filed + claimed. Backlog otherwise had no open
  `todo` (#21 building under agent-builder-2-000203, with agent-builder-2-001211 also on it;
  #11 owner-gated). Spotted that #22's `fleet/health-summary` is pinned to `warn` forever by
  the accepted owner-gated checkouts, undermining the single-signal goal. Building the ack
  layer.
