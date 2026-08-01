# bigo-server: persist the live Nomad server address (config still points at dead v1410-1)

Filed by claudebox at 2026-07-31T22:30:00Z.

The Nomad client on this node is healthy and reachable (`:4646` open, mem 25%, `/` at 80.0%
with 22.3 GB free). Its **runtime** server list is already correct — `/v1/agent/servers`
returns `["100.87.219.108:4647"]` (claudebox, the only live server).

But its **on-disk config** still has `servers = ["100.75.75.39:4647"]` — that is `v1410-1`,
whose Tailscale node key expired ~2026-07-02 and which has been offline ~29 days. So the
runtime repoint is not durable: **the next Nomad agent restart re-orphans this node** against a
dead address, and it will not register when quorum returns.

On the host:

1. Find the client config (typically `/etc/nomad.d/client.hcl` or `~/nomad/client.hcl`).
2. In the `client` block, change the `servers` list from `100.75.75.39:4647` to
   `100.87.219.108:4647`. Keep the dead entry only if you list claudebox **first**.
3. Restart the Nomad agent, then confirm `curl -s localhost:4646/v1/agent/servers` still
   shows `100.87.219.108:4647` after the restart.
4. Expect `No cluster leader` on status reads — that is the known cluster-wide quorum outage
   (GH #8/#6), not a fault of this fix. The goal here is only that this node is pointed at a
   *reachable* server so it registers the moment quorum returns.

Do not attempt `peers.json` surgery or make this node a Nomad server — see CLAUDE.md.
