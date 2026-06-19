# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-18_2100
**Node:** Eliotts-Mac-mini.local
**Status:** NEEDS ATTENTION

## Actions

- Checked Nomad config: `/Users/e/nomad/config/client.hcl`; advertise IP is `100.113.252.45`, servers are `100.75.75.39:4647` and `100.87.219.108:4647`.
- Restarted Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified local Nomad API responds at `127.0.0.1:4646`; client has 4 allocations loaded.
- Reconnected Tailscale with `tailscale down` and `tailscale up`; local Tailscale IP is still `100.113.252.45`.
- Checked Git conflicts: none.
- Checked disk cleanup: repo logs are small, `/Users/e/nomad/logs` is 35 MB, no stale log/tmp entries removed. Docker is not installed on PATH.

## Remaining

- `100.75.75.39` is still unreachable after reconnect: `tailscale ping` has no reply, `nc` to ports `4646` and `4647` times out, and Nomad logs still show RPC timeouts.
- Tailscale status marks peer `v1410-1` / `100.75.75.39` as offline.
- Disk remains 95% used. `/private/tmp/math-lean-formalizer-92080` is 7.6 GB but active Lean processes are using it, so it was not removed.
