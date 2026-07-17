# Node Doctor Report: claudebox

**Time:** 2026-07-16_2244
**Node:** claudebox

**Status: NEEDS ATTENTION — escalated, blocked on owner action**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has 2 uncommitted changes

## Diagnosis (22:44–22:52 pass)

- claudebox Tailscale is **healthy**: UDP ok, DERP den 32ms, direct path to
  eliotts-mac-mini active. The unreachability is not local.
- `tailscale ping 100.75.75.39` → **"peer's node key has expired"**. v1410-1
  has been off the tailnet 14d because its Tailscale node key expired.
  ICMP/HTTP to 4646 time out as a consequence.
- oraclebox1 (100.125.210.126) also offline, last seen 39d (relay-only, rx 0).
- Local Nomad server on claudebox (pid 1490, bind 100.87.219.108) is running
  and serf-alive but **leaderless**: `/v1/agent/members` returns claudebox as
  sole member (200), `/v1/status/leader` and `/v1/agent/health` hang — the
  committed 2-voter Raft set cannot elect with v1410-1 gone. Left running so
  quorum restores automatically when a peer returns.
- Local health otherwise fine: disk 8% used (803G free), repo clean-ish.

## Actions taken

- No destructive action; **no single-voter Raft surgery** (per standing policy
  and t-0233).
- Verified escalation already in place — did not duplicate:
  - `meta/coordination/tasks/t-0233.json` (open, quorum-loss handoff)
  - GitHub #8 "v1410-1 Tailscale node key EXPIRED — quorum recovery needs
    interactive re-auth" and #6 "CRITICAL: Nomad quorum lost"
- Appended cluster event; committed this report.

## Blocked on

Owner interactive action: re-auth Tailscale on v1410-1 (or disable key expiry
in the admin console), then verify/start its Nomad → quorum 2/2 restores.
Fallback: restore/rejoin oraclebox1.
