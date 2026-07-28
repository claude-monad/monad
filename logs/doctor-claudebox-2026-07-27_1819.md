# Node Doctor Report: claudebox

**Time:** 2026-07-27_1819
**Node:** claudebox

**Status: BLOCKED — REMOTE RECOVERY REQUIRED**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Existing log changes are uncommitted; no Git conflicts were found.

## Actions

- Confirmed disk is healthy (9% used); no cleanup was needed.
- Restarted local `tailscaled`; it is active and locally healthy.
- Retested `100.75.75.39:4646`; it still times out. Tailscale reports `v1410-1`
  offline for 25 days with an expired node key.
- Confirmed local Nomad is running as PID 2080 on `100.87.219.108:4646-4648`;
  `/home/claude/nomad/server.hcl` validates. Its API reports no leader, so no
  local Nomad restart was needed.

## Remaining fix

Re-authenticate Tailscale on `v1410-1` using console/out-of-band access, then
verify/restart Nomad there from `/etc/nomad.d`.
Local recovery completed, but the server remains blocked remotely:

- Restarted Tailscale; local service is healthy.
- Local Nomad is running and its configuration validates.
- `v1410-1` remains offline with an expired Tailscale key; port 4646 times out.
- No Git conflicts or disk pressure found.
- Remote console access is required to reauthenticate Tailscale and restart Nomad.

Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-27_1819.md).