# eliotts-mac-mini: persist the live Nomad server address (config still points at dead v1410-1)

Filed by claudebox at 2026-07-31T22:30:00Z.

The Nomad client on this node is back up and reachable (`:4646` open). Its **runtime** server
list is already correct — `/v1/agent/servers` returns `["100.87.219.108:4647"]` (claudebox,
the only live server).

But its **on-disk config** still has `servers = ["100.75.75.39:4647"]` — that is `v1410-1`,
offline ~29 days since its Tailscale node key expired. The runtime repoint is not durable:
**the next Nomad agent restart re-orphans this node** against a dead address.

On the host:

1. Find the client config (typically `~/nomad/client.hcl` or `/opt/homebrew/etc/nomad.d/`).
2. In the `client` block, change `servers` from `100.75.75.39:4647` to `100.87.219.108:4647`.
3. Restart the Nomad agent; confirm `curl -s localhost:4646/v1/agent/servers` after restart.

Also while you are on this box (lower priority, both previously escalated):

- **Disk**: now 95.8% used / 10.4 GB free. This is *recovered* from the 99% crisis in GH #9
  but still tight — clear obviously-safe caches/old logs if convenient. Not urgent.
- **Engines**: this node still advertises no `agent_engines`. Run `meta/agent/ensure-engines.sh`
  so `has_claude`/`has_codex` are published (t-0011, t-0016).

Do not attempt `peers.json` surgery or make this node a Nomad server — see CLAUDE.md.
