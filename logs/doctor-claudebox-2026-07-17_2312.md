# Node Doctor Report: claudebox

**Time:** 2026-07-17_2312
**Node:** claudebox

**Status: NEEDS ATTENTION — remote/owner fix required (no safe local action)**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has uncommitted changes

## Diagnosis

Root cause is **remote, not local**. The server node `v1410-1` (100.75.75.39) is
**offline on Tailscale — "last seen 15d ago"** (`tailscale status`), so ping and TCP to
:4646/:4647 both fail (i/o timeout). This matches **t-0247**: v1410-1's Tailscale auth key
expired → **owner re-auth required**. The 2nd voter `oraclebox1` (100.125.210.126) is also
offline (40d). Both target master voters are down ⇒ **Raft quorum lost**.

claudebox is itself running a Nomad **server** (pid 1490, bound to 100.87.219.108:4646/47/48),
stuck in a perpetual candidate loop — logs show repeated `entering candidate state` /
`failed to make requestVote RPC ... 100.75.75.39:4647: i/o timeout` / `No cluster leader`
(term 1649). It cannot win an election with 2 of 3 voters unreachable. (Local API on
127.0.0.1 refuses because it binds to the Tailscale IP, not localhost — expected.)

## Local health (all OK)

- **Tailscale:** claudebox connected; peers bigo-server, eliotts-mac-mini, windesk **active**.
- **Disk:** 68G/916G used (8%) — fine.
- **Local nomad server process:** alive, correctly bound; only blocked by missing quorum.

## Actions taken

- Verified this is a remote outage, not a claudebox connectivity fault.
- **No local fix attempted.** Restarting the local server would not help (quorum still absent),
  and reducing to a single voter via peers.json surgery is prohibited (quorum-fragility rule).
- Quorum loss is **already escalated** as t-0247 / t-0248; state unchanged this pass.

## Owner action needed

- **Re-authenticate `v1410-1` in the Tailscale admin console** (expired key) to restore the
  mesh + Raft leader; bring `oraclebox1` back online to re-establish a ≥2-voter quorum.
