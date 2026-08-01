# CLUSTER-HEALTH.md — the standing mandate: every node keeps every node healthy

**This is a standing task for ALL agents on ALL nodes, every session, forever.** It is not a
one-shot queue item. If you are an agent running anywhere in this cluster — a maintenance
agent, a node-doctor pass, a research session between tasks, an interactive operator session —
part of your job is the **constant mutual health of the whole roster**. Read this, then act on
it whenever you have a spare cycle.

## The roster (the canonical 7 nodes)

| node | Tailscale IP | OS | Nomad role |
|------|--------------|----|------------|
| `v1410-1`           | 100.75.75.39    | Linux  | server (voter) + client — *DOWN since ~2026-07-02, Tailscale key expired; quorum blocker, GH #8* |
| `bigo-server`       | 100.78.218.70    | Linux  | client |
| `claudebox`         | 100.87.219.108   | Linux  | server (voter, RaftProtocol 3) + client |
| `death-star`        | 100.96.31.66     | Linux  | client |
| `eliotts-mac-mini`  | 100.113.252.45   | macOS  | client |
| `oraclebox1`        | 100.125.210.126 | Linux  | server (voter) + client — *offline since ~2026-06-07, queue holds heal/restore tasks* |
| `windesk`           | 100.94.210.54   | Windows| client |

Server RPC / `NOMAD_ADDR`: **`http://100.87.219.108:4646` (claudebox — the only server that
answers).** `100.75.75.39` is unreachable and each `nomad` call against it blocks ~30s; sourcing
`scripts/nomad-addr.sh` and calling `resolve_nomad_addr` picks a reachable server automatically.
The committed voter set is **{v1410-1, claudebox}** (oraclebox1 is *not* a voter), so Raft is at
**1/2 — no leader** until v1410-1 returns. The 3-voter target remains **v1410-1 + oraclebox1 +
claudebox**; the rest are clients. Keep this table current — if a node is added/removed, update
it here and in `CLAUDE.md`.

## What "healthy" means, per node

1. **Reachable** on the tailnet — judged by `tailscale ping <ip>` succeeding, *not* by the
   `offline` column in `tailscale status` (see the probe note in the sweep section below).
2. **Nomad up**: a server node is an alive Raft peer; a client node shows `ready` in
   `nomad node status` and is `eligible` (not down/draining).
3. **Quorum**: at least 2 of the server set are alive (Raft majority). Losing quorum is a
   🔴 cluster-down event.
4. **Engines ready**: the node advertises at least one of `has_claude` / `has_codex`
   (`nomad node status -verbose <id> | grep agent_engines`). See `meta/agent/`.
5. **Maintenance loop alive**: the node has a running `maintenance-agent` alloc (or, on
   Windows / a non-member like a freshly-wiped claudebox, an equivalent: node-doctor cron or a
   re-join). A node whose agent is crash-looping (e.g. bigo-server's "no user with ~/monad")
   is **unhealthy** even if Nomad says `ready`.
6. **Disk/clean**: not near-full; repo clean and not far behind `origin/main`.

## The sweep (do this when you have a spare cycle)

For **self** and then **every peer** in the roster:

```bash
# self first (cheap, always safe)
~/monad/scripts/node-doctor.sh            # disk/git/nomad/engines/claude on THIS node
~/monad/meta/agent/ensure-engines.sh      # keep engines installed + advertised

# then the peers, from any node that can reach a server:
export NOMAD_ADDR=$(~/monad/scripts/nomad-addr.sh)   # NEVER hardcode 100.75.75.39 — it is dead
nomad server members            # are both voters alive? quorum?
nomad node status               # is every roster client 'ready' + 'eligible'?
nomad job status maintenance-agent   # one running alloc per member?
```

### Probe reachability with `tailscale ping`, NOT the `tailscale status` column

`tailscale status` reports each peer's online flag **from the local netmap**, which is only as
fresh as this node's connection to the Tailscale coordination server. When that control
connection is stale — check `tailscale status --json | jq .Health`, and note that a *frozen*
age string ("hasn't received a network map in 2m10s", unchanged across successive minutes) means
the health tracker itself is stuck — every peer can be misreported as `offline` even though DERP
and direct paths still carry traffic fine.

This has repeatedly produced **false flapping** in the sweep history: windesk was recorded as
"regressed to tailnet-unreachable" and then "recovered" (commits `84eb90e`, `a637949`) on
consecutive passes with no change on windesk's side at all. On 2026-08-01 claudebox's status
listed windesk `offline, last seen 12m ago` while `tailscale ping 100.94.210.54` returned pongs
via DERP(den) in ~70-90ms.

So, before escalating or queueing anything on a "peer is offline" reading:

```bash
tailscale ping -c 5 <ip>   # authoritative — see the -c 5 note below; -c 1 lies
bash -c 'cat </dev/null >/dev/tcp/<ip>/4646' && echo OPEN || echo CLOSED   # is its Nomad up?
```

**Always pass `-c 5`; a single-shot `tailscale ping` produces false "down" readings.** A peer
reached only over DERP has no warm path until the relay handshake completes, and the first
probe (sometimes the first four) times out before it does. Declare a peer unreachable **only
when every one of 5+ probes fails.**

Measured on claudebox 2026-08-01T11:0xZ, in the same sweep: `-c 1` reported windesk *and*
eliotts-mac-mini as no-reply; `-c 5` got pongs from both — windesk on probe 2 (DERP(den) 964ms,
then direct IPv6 474ms) and mac-mini on probe 5 (DERP(den) 1.98s). Both had just been escalated
as "tailnet-unreachable" off single-shot probes (t-0350). By contrast death-star, oraclebox1 and
v1410-1 stayed silent across all 6 probes — that is what genuinely down looks like. Slow ≠ down:
mac-mini's Nomad API answered HTTP 200 in ~10s, so use a generous `curl -m` (30-40s) on
DERP-only peers rather than reading a short timeout as "Nomad down".

A peer that pings but refuses :4646 is **up on the tailnet with Nomad down** — that is a queue
item for its own node-doctor, not a Tailscale re-auth. Do not file a re-auth task for it.

## Acting on an unhealthy peer — COORDINATE, do not stampede

Five nodes all trying to fix the same thing at once is its own outage. **Claim before you act:**

```bash
cm=~/monad/scripts/cluster-memory.sh
bash $cm set  "health:<peer>" "$(hostname)"      # claim it
bash $cm get  "health:<peer>"                    # only proceed if the value is YOU
```

If the claim is held by another node, skip — they're on it. If it's yours, take the **smallest
corrective action that fixes it**, preferring delegation/escalation over direct cross-node exec:

- **Engines missing on a peer** → write a task to that peer's queue (it self-heals next poll):
  `nomad var put -force monad/maintenance/<peer>/queue/<id> prompt="run meta/agent/ensure-engines.sh and report"`.
- **A failed/stuck alloc** → `nomad alloc stop <id>` / `nomad job restart <job>` so Nomad reschedules it.
- **maintenance-agent missing/crash-looping on a peer** → fix the prereq (e.g. provision
  `~/monad` on the peer), then redeploy: `~/monad/scripts/monad deploy jobs/maintenance-agent.hcl`.
- **A server down → quorum at risk** → bring a server back (`scripts/claudebox-server.sh start`
  on claudebox, or rejoin via `meta/bootstrap/join.sh`); this is top priority.
- **A node offline on Tailscale** → you usually can't fix it remotely; record it and escalate
  (it needs the machine powered on / `tailscale up`).
- **You are claudebox and not a Nomad member** → rejoin: `meta/bootstrap/join.sh 100.75.75.39 pro`
  (claudebox was wiped of its old orphaned single-node server on 2026-06-02).

**"Spawn programs as needed" is authorized** — restart Nomad, relaunch the maintenance-agent,
run ensure-engines, redeploy a job, start node-doctor — as long as you (a) claimed the target,
(b) pick the least-disruptive fix, and (c) avoid destructive/irreversible actions (no data wipes,
no force-pushes, no cluster-wide restarts). When a fix is risky or you're unsure, **escalate
instead of acting**: log it and leave a task.

## Record + hand off (always)

- Append health events to `logs/events.jsonl` (the maintenance-agent's `event()` helper does this).
- For anything you couldn't fix, emit a follow-up task (`meta/coordination/task.sh emit infra
  eliott-monad/monad "<what's wrong on which node>"`) so the next agent picks it up.
- Release your claim when done: `bash $cm set "health:<peer>" "DONE-$(date -u +%FT%TZ)"`.
- Keep the roster table above accurate.

This is the cluster's immune system: **many small, coordinated, mutually-directed health passes**,
not one big watchdog. Every node watches every node. Work begets health begets work.
