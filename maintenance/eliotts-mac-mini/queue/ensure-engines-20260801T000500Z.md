# Task: advertise agent engines on eliotts-mac-mini

**Filed by:** claudebox cluster-health sweep, 2026-08-01T00:05Z
**Claim:** `health:eliotts-mac-mini` (released after filing — take it if you act)

## What's wrong

The Nomad client on this node is **up and healthy** (`http://100.113.252.45:4646` answers,
pointed at `100.87.219.108:4647`), but its node meta carries no engine attributes:

```json
{"location": "mac-mini", "claude_account": "pro", "role": "worker"}
```

There is no `has_claude`, no `has_codex`, no `agent_engines`. Every other live node
advertises these (bigo-server has `has_claude=true`; claudebox now advertises
`agent_engines=claude,codex`). Engine-aware dispatch therefore cannot schedule any agent
work here even once quorum returns — this node is invisible to `--engine claude|codex`.

## Fix (on the box)

```bash
cd ~/monad && ./scripts/monad git pull
bash meta/agent/ensure-engines.sh
```

That installs/detects both CLIs and applies the dynamic meta. **This works even though the
cluster has no Raft leader** — `nomad node meta apply` without `-node-id` is a client-local
endpoint. (Passing `-node-id` routes through the server and *does* need a leader; don't.)
Verified on claudebox this pass: it succeeded while Raft was at 1/2.

If it reports `claude=installed-NOT-logged-in`, run `claude` once interactively to log in
(this node is the `pro` account) — auth is a human, once-per-machine step.

## Context

- Disk here was a crisis (GH #9); it is now **stable at 95.7% used / 10.4 GB free** — flat
  across the 21:22Z and 00:05Z passes, not worsening. Still worth reclaiming space.
- Cluster quorum remains **DOWN (1/2 voters)**; v1410-1's Tailscale key expired ~2026-07-02
  and needs interactive re-auth (GH #8). Nothing here depends on that being fixed first.

---

> **UPDATE 2026-08-01T19:4xZ (claudebox sweep, t-0354) — STALE PREMISE, DO THIS LAST.**
> The line above ("The Nomad client on this node is **up and healthy**") is **no longer true**.
> As of this sweep the host is fully off the tailnet: `tailscale ping -c 5` → 5/5 timeouts,
> TCP :4646 CLOSED, last seen ~1h ago. Between 00:05Z and now the agent went healthy →
> HTTP-wedged (t-0353) → host gone.
>
> **Ordering when the node returns:** (1) reclaim disk — see
> `disk-cleanup-20260801T081500Z.md`, the probable root cause at 96.53% used; (2) restart the
> Nomad agent against **100.87.219.108:4647**; (3) only then run ensure-engines as described
> below. Advertising engines needs a live agent *and* a leader, and the cluster still has
> neither (quorum 1/2, owner-blocked on GH #8), so this step cannot succeed until both return.
