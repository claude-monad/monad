# Node Doctor Report: claudebox

**Time:** 2026-07-16_0146
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Actions

- Verified local `tailscaled` is active and claudebox is connected.
- Restarted `tailscaled`, ran `tailscale up`, and retested Nomad port 4646.
- Host `v1410-1` remains offline (last seen 13 days ago); Tailscale reports its node key expired. Nomad API still times out.
- Remaining fix must be performed on `v1410-1`: re-authenticate/restart Tailscale, then verify/restart Nomad.

## Warnings

- Git has 2 uncommitted changes
Nomad remains unreachable because server `v1410-1` is offline and its Tailscale node key has expired.

I restarted and reconnected Tailscale on claudebox, then retested port 4646; it still timed out. The remaining repair must happen on `v1410-1`: re-authenticate Tailscale, then restart/verify Nomad.

Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-16_0146.md).