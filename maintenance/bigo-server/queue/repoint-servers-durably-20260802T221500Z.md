# Task: make bigo-server's Nomad server list survive a restart

**Filed by:** claudebox cluster-health sweep, 2026-08-02T22:15Z
**Claim:** `health:bigo-server` (released after filing — take it if you act)
**Severity:** latent (not currently breaking), but a restart strands this node
**Related:** GH #6, #8 (quorum), GH #3 (connectivity mission)

## What's wrong

`bigo-server` is **alive and healthy** on the tailnet (direct connection, disk 79.9%,
mem 25%). Its Nomad agent answers on `http://100.78.218.70:4646` as **client-only**
(`Server.Enabled=false`, `Client.Enabled=true`).

Its *runtime* server list is correct — `GET /v1/agent/servers` returns:

```
["100.87.219.108:4647"]     # claudebox, the only server that answers
```

But that value was set at runtime by an earlier sweep. The **on-disk client config still
has the dead v1410-1 address**:

```
Client.Servers = ["100.75.75.39:4647"]
```

`100.75.75.39` has been unreachable for ~30 days (v1410-1 Tailscale node key expired,
GH #8). So the moment the Nomad agent on this box restarts — reboot, crash, upgrade — it
reverts to a dead server and this node drops off the cluster entirely, silently.

## What to do (run locally on bigo-server)

1. Find the client config Nomad is actually loading:

   ```bash
   pgrep -af "nomad agent"          # look at the -config= path
   ```

2. Edit the `servers` list in that config's `client` block so claudebox is listed
   **first**, keeping v1410-1 as a fallback for when quorum is restored:

   ```hcl
   client {
     enabled = true
     servers = ["100.87.219.108:4647", "100.75.75.39:4647"]
   }
   ```

3. Reload rather than restart if possible (`SIGHUP` re-reads config without dropping
   the node); only restart the agent if a reload doesn't pick it up.

4. Verify it stuck across a restart:

   ```bash
   curl -s http://localhost:4646/v1/agent/servers
   # expect claudebox 100.87.219.108:4647 present
   ```

## Expected outcome, and what it does NOT fix

After this, bigo-server keeps finding the cluster across restarts.

It will **still not register as a ready client** until Raft quorum returns — the client's
`heartbeat_ttl` is currently `0s` because node registration is a write, and writes fail
with *"No cluster leader"*. That is expected and is **not** a bug on this node. Quorum is
blocked on v1410-1 (GH #8) and is owner-blocked pending interactive Tailscale re-auth.

**Do not** attempt to fix that by enabling `server`/`bootstrap_expect` on this box — the
committed voter set is exactly `{v1410-1, claudebox}`, and standing up another server here
would form a second, private Raft. See `CLAUDE.md` and `meta/CLUSTER-HEALTH.md`.
