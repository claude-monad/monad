# Mission: Full Cluster Connectivity & Uptime

**Created**: 2026-06-01
**Status**: Active
**Goal**: All monad cluster nodes maintain persistent Tailscale connectivity and Nomad registration, measured continuously.

> **Canonical health mandate:** `meta/CLUSTER-HEALTH.md` is the cluster's standing
> "every node keeps every node healthy" mandate (roster, what-healthy-means, the sweep,
> the claim-before-acting protocol). This file is the *connectivity slice* of it: the
> measurement tooling (`cluster-uptime` job → `logs/cluster-uptime-summary.json`), the
> **cluster-conductor** (the always-on coordination point), and per-machine asks. Keep
> the two consistent; CLUSTER-HEALTH.md wins on roster/protocol.

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

---

## The Cluster Conductor (deployed 2026-06-01, oraclebox1)

The owner's directive: **stop querying Claude directly on individual machines.** A
single always-on Claude — the **conductor** — now runs the cluster, reachable two ways
(one brain): a **Tailscale text gateway** (`POST http://100.125.210.126:8200/ask`) and a
**remote-control session** in the Claude app (`cluster-conductor` at claude.ai/code,
desktop + phone). It lives in a container on oraclebox1 (`--restart unless-stopped`).
See `conductor/README.md` and `conductor/CONDUCTOR.md`.

**One-account caveat:** the cluster shares one Claude account; the conductor is its
primary consumer. Heavy concurrent Claude sessions (the autonomous math fleet, or a
human session) contend on the shared credential and can stall conductor calls. Operate
the conductor as the sole live consumer, or stagger the other jobs. Robust fix (queued):
a single warm `--input-format stream-json` backend behind both doors.

## Codex workers (deployed 2026-06-03)

Some nodes run **OpenAI Codex** instead of Claude. Codex has no `remote-control`
command (that is Claude-Code-specific), so codex workers can't be attached from the
Claude app. They get the cluster's model-agnostic connectivity instead — **two doors,
one codex brain**, mirroring the conductor:

- **Door 1 — text gateway** (`codex-worker/gateway.py`, port **8300** on the node's
  tailnet IP): `monad codex ask <node> '<text>'` or
  `curl -s -X POST http://<node-ip>:8300/ask -d '...'`. Continuity-preserving.
- **Door 2 — interactive**: a live `codex` TUI in tmux, attached over Tailscale SSH:
  `monad codex connect <node>`.

Supervised by `jobs/codex-worker.hcl` (`system` job, runs on every node tagged
`meta.codex = "true"`). See `codex-worker/README.md`. As of 2026-06-03, `bigo-server`
is back online and runs codex.

## GPT app SSH access and math Codex researcher pool (requested 2026-06-04)

The owner wants two additions:

1. Keep about a handful of **containerized, math-specific Codex researchers** online and
   queryable most of the time, spread onto nodes that can actually host the work.
2. Standardize **GPT mobile/desktop app SSH integration** so the owner can reach those
   researchers elegantly from the apps.

Initial `oraclebox1` investigation from the local workstation:

- `100.125.210.126:22` presents `SSH-2.0-Tailscale`.
- `100.125.210.126:2222` presents `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.16`.
- Probing port 22 as `oralcle` reaches Tailscale SSH and reports
  `tailscale: failed to look up local user "oralcle"`.

So the surprising app success on port 22 appears to have used **Tailscale SSH**, while the
cluster's dedicated app-facing OpenSSH door is the existing `codex-ssh` job on **port 2222**.
The fleet should build on that dedicated door for steady state: standard user, key auth, endpoint
roster, and an attach path into the containerized math researcher pool.

Tracked as:

- `fleet/projects/math-codex-research-pool.md`
- `fleet/projects/codex-app-ssh-standardization.md`

## Per-machine tasks (each node works toward full connectivity + uptime)

Measured continuously by the `cluster-uptime` Nomad periodic job →
`logs/cluster-uptime-summary.json`. Latest (2026-06-01): **4/6 reachable, 3/6 ready**.

- **oraclebox1** (me, server+voter): host the conductor; keep the gateway + RC session
  up; watch the uptime summary; drive convergence to the 3-master set.
- **v1410-1** (server, leader): keep the Nomad server + `cluster-uptime` job running;
  help returning nodes rejoin; stay a Raft voter.
- **windesk** (client, ready): stay a healthy client; run the `claudebox-diagnose` work
  to help revive claudebox; keep node-doctor cron alive.
- **claudebox** (OFFLINE — was the original server): **revive** — bring Tailscale +
  Nomad back, rejoin as the 3rd Raft voter (see `cluster/desired-servers.md`). Highest-
  impact item: it restores FailureTolerance=1.
- **eliotts-mac-mini** (reachable on Tailscale, not a Nomad client): **join** as a Nomad
  client (`meta/bootstrap/join.sh 100.75.75.39 <account>`); then it counts toward
  cluster %.

Each machine: keep Tailscale authenticated, keep the Nomad agent pointed at a live
server, pull `monad` regularly, and if you see another node down, log it (commit) so the
conductor and the fleet can act. Connectivity is a shared, continuously-measured goal.
