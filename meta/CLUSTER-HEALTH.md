# CLUSTER-HEALTH.md — the standing mandate: every node keeps every node healthy

**This is a standing task for ALL agents on ALL nodes, every session, forever.** It is not a
one-shot queue item. If you are an agent running anywhere in this cluster — a maintenance
agent, a node-doctor pass, a research session between tasks, an interactive operator session —
part of your job is the **constant mutual health of the whole roster**. Read this, then act on
it whenever you have a spare cycle.

## The roster (the canonical 5 nodes)

| node | Tailscale IP | OS | Nomad role |
|------|--------------|----|------------|
| `v1410-1`           | 100.75.75.39    | Linux  | server (leader) + client |
| `oraclebox1`        | 100.125.210.126 | Linux  | server (voter) + client — *offline since ~2026-06-07, queue holds heal/restore tasks* |
| `claudebox`         | 100.87.219.108  | Linux  | server (voter, RaftProtocol 3) + client — converged to 3rd voter |
| `eliotts-mac-mini`  | 100.113.252.45  | macOS  | client |
| `windesk`           | 100.94.210.54   | Windows| client |

Server RPC / `NOMAD_ADDR`: `http://100.75.75.39:4646` (or any alive server). The 3-voter Raft
target is **v1410-1 + oraclebox1 + claudebox**; the rest are clients. Keep this table current —
if a node is added/removed, update it here and in `CLAUDE.md`.

## What "healthy" means, per node

1. **Reachable** on the tailnet (`tailscale ping <ip>` succeeds; not "offline").
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
export NOMAD_ADDR=http://100.75.75.39:4646
nomad server members            # are both voters alive? quorum?
nomad node status               # is every roster client 'ready' + 'eligible'?
tailscale status                # which roster nodes are offline?
nomad job status maintenance-agent   # one running alloc per member?
```

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
