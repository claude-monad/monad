# Node Doctor Report: claudebox

**Time:** 2026-07-19_0710
**Node:** claudebox

**Status: NEEDS ATTENTION (no local fix — escalated, no regression)**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Diagnosis

Not a local fault on claudebox. The **server node `v1410-1` (100.75.75.39) is itself
Tailscale-offline** — `tailscale status` shows "offline, last seen 16d ago" and
`tailscale ping` returns **"peer's node key has expired"**. Ports 4646/4647 are
unreachable because the host is down, not because of routing/agent trouble here.

Broader state (unchanged, no regression):
- Quorum **LOST 1/2**: v1410-1 offline 16d (expired key), oraclebox1 offline 42d.
- claudebox healthy: Tailscale active, disk 9% (798G free), git clean, engines ready.
- bigo-server reachable on Tailscale; death-star / mac-mini / windesk offline.

## Actions

- Verified claudebox's own Tailscale/mesh connectivity is fine (full roster visible).
- Confirmed disk healthy (9%) — **no cleanup needed**.
- **No safe in-band recovery** taken: reviving v1410-1 needs its expired Tailscale key
  re-authenticated on that host (console/physical access), which claudebox cannot do
  remotely. Did **not** perform peers.json / Raft surgery (against standing guidance at
  a single voter).
- Not duplicating escalation: still tracked under **GH#8** and task **t-0276** (re-used
  by the maintenance-agent roster sweep ~40 min prior — no new ticket).

## Status

Unreachable-server issue **root-caused, escalated, no local fix available**. Awaiting
off-cluster action to re-auth v1410-1's Tailscale key. claudebox self-healthy.
