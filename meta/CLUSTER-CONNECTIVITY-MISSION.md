# Mission: Full Cluster Connectivity & Uptime

**Created**: 2026-06-01
**Status**: Active
**Goal**: All monad cluster nodes maintain persistent Tailscale connectivity and Nomad registration, measured continuously.

---

## The Problem

The cluster has been fragmented — nodes go offline for days/weeks without detection or recovery. When the Nomad server goes down, no one notices until a human intervenes. We need **self-healing connectivity** where every node works independently toward keeping the cluster whole.

## Current State (2026-06-01)

| Node | Tailscale | Nomad | Server |
|------|-----------|-------|--------|
| **v1410-1** | UP | ready | **active server** (bootstrap_expect=1) |
| **oraclebox1** | UP | ready | client → v1410-1 |
| **windesk** | UP | ready | client → v1410-1 |
| claudebox | DOWN | — | former server, offline |
| eliotts-mac-mini | DOWN | — | offline 71d |
| death-star | DOWN | — | offline 67d |

**Active server**: v1410-1 (100.75.75.39) — took over from offline claudebox.

## How We Measure

The `cluster-uptime` Nomad job (periodic, every 10 minutes) runs on the server and:

1. **Tailscale pings** every known node — measures reachability and latency
2. **Queries Nomad** node status — are nodes registered and eligible?
3. **Logs results** to `logs/cluster-uptime.jsonl` (append-only event stream)
4. **Computes rolling summary** in `logs/cluster-uptime-summary.json`:
   - 24-hour average connectivity % and cluster %
   - Per-node uptime percentages
5. **Targets**:
   - **Connectivity**: 100% of live nodes reachable via Tailscale
   - **Cluster**: 100% of reachable nodes registered in Nomad as `ready`

## What Each Node Should Do

### Every node (via node-doctor or agent session):
- Keep Tailscale running and authenticated
- Keep Nomad client running and pointed at the active server (currently `100.75.75.39`)
- If this node can't reach the server, try all known server candidates in order:
  1. `100.75.75.39` (v1410-1, current)
  2. `100.87.219.108` (claudebox, when it returns)
- Pull `monad` repo regularly to stay in sync
- If you notice another node is down, log it — don't just ignore it

### The server node (v1410-1):
- Run the `cluster-uptime` job
- Run `cluster-watchdog` for broader health
- Monitor `logs/cluster-uptime-summary.json` — if connectivity drops, investigate
- If a node comes back online, help it rejoin cleanly

### Offline nodes (when they come back):
- Read this file first
- Update Nomad config to point at the active server
- Run `node-doctor` to verify health
- Check `logs/cluster-uptime-summary.json` to see what you missed

## Server Failover

If the current server (v1410-1) goes down:
1. Any node with `server { enabled = true }` in its config can become the new server
2. Update the other nodes' `servers = [...]` to point at the new server
3. Update this document with the new server info
4. The `cluster-uptime` job will automatically run on the new server

## Coordination via Git

This is a **GitOps cluster** — all coordination happens through this repo:
- `logs/cluster-uptime.jsonl` — raw measurements (machine-readable)
- `logs/cluster-uptime-summary.json` — rolling 24h dashboard (human + machine readable)
- This file — the mission brief, read by every agent on startup
- `monad-sync` pulls every 5 minutes — changes propagate automatically

No Slack, no email, no out-of-band coordination. If you need to tell other nodes something, commit it.
