---
slug: codex-tui-availability
status: todo
owner:
updated: 2026-06-03
priority: 1
---
# codex web TUI keeps going down: owner gets network errors querying codex

**Owner report (2026-06-03):** querying codex through the web TUI returns **network errors**.

## Diagnosis (done)
The `codex-tui` web chat (`http://<host>:8090`, `jobs/codex-tui.hcl` → `meta/codex-tui/server.py`)
shells out to `codex exec` and returns the reply. Browser "network errors" = the fetch to
`:8090` fails because **nothing is serving it** (the JS catch renders any fetch failure as an
error bubble). Root causes, in order:

1. **death-star is flapping.** The job was **hard-pinned to death-star, count=1, with
   `reschedule { attempts = 0 }`.** death-star repeatedly drops to "No path to node"
   (Nomad marks the node `down`; maintenance self-passes fail rc=1 at 08:20/08:50; allocs die
   with "alloc is lost since its node is down"). A single-node pin + no reschedule meant any
   death-star blip took the TUI down **with nowhere to recover** — it stayed dead until a
   manual re-run.
2. **No capable failover host.** The launch script needs a node with a **non-root
   codex-credentialed user** (`~/.codex/auth.json`) that also has a `~/monad` checkout — in
   practice only death-star and oraclebox1 (both `ubuntu`). `meta.has_codex=true` is **not
   sufficient**: claudebox/v1410-1 advertise it, but the script finds "no codex-credentialed
   user with ~/monad" there and **crash-loops**. And oraclebox1 is chronically CPU-saturated
   (see node-overload-health), so it often can't place the TUI either.

## Mitigation already applied (this commit)
`jobs/codex-tui.hcl`: removed the single-node pin; constrained to `^(death-star|oraclebox1)$`,
added `affinity` for death-star (idle, off saturated oraclebox1), and set `reschedule`
unlimited. Net: the TUI now **auto-recovers** the moment death-star is stably up (or oraclebox1
frees capacity), instead of staying dead. Verified it migrated off claudebox; it currently
oscillates with death-star's flapping (places when up, fails when it drops).

## What still needs doing (the real fix — needs on-node access)
1. **Stabilize death-star** (the dominant cause). It keeps dropping off Nomad/Tailscale. Find
   why (Tailscale relay vs direct? power/sleep? nomad client crash? clock?) and make it stay
   `ready`. Until then the idle 80-core node can't be relied on for always-up services.
2. **Make the TUI node-portable** so any `has_codex` node can host it (then claudebox/v1410-1
   become real failover, and we can widen the constraint back to `has_codex=true`). Mirror
   `jobs/maintenance-agent.hcl`: discover codex creds across users **including root + snap**
   (`~/.codex/auth.json`, `~/snap/codex/*/auth.json` — see `meta/agent/engines.sh`
   `engine_authed`), set `CODEX_HOME` accordingly, and **clone monad into the alloc dir** if no
   `~/monad`. Confirm `codex exec` actually reaches its backend on the chosen node (the owner's
   "network error" wording could *also* be codex→backend connectivity — verify on whatever node
   ends up hosting; if codex itself errors, that's a node-level codex/auth/network fix).
3. Consider folding a `codex-tui` reachability signal into `fleet/health-summary` so this outage
   is visible next time (probe `/health`).

## Acceptance
- `http://<host>:8090/health` returns 200 from the tailnet, and a test query through the TUI
  returns a real codex reply (not a network/timeout error), and survives death-star flapping
  (auto-reschedules to a healthy codex node within the backoff window).
