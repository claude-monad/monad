# Task: make eliotts-mac-mini's Nomad server list survive a restart

**Filed by:** claudebox cluster-health sweep, 2026-08-02T22:15Z
**Claim:** `health:eliotts-mac-mini` (released after filing — take it if you act)
**Severity:** latent — secondary to the disk emergency (GH #9, GH #11). Do the disk first.
**Related:** GH #6, #8 (quorum), GH #9 / #11 (disk)

## What's wrong

Same latent fault as `maintenance/bigo-server/queue/repoint-servers-durably-20260802T221500Z.md`.

The *runtime* server list on `http://100.113.252.45:4646` is correct —
`GET /v1/agent/servers` returns `["100.87.219.108:4647"]` (claudebox) — but that was set at
runtime by an earlier sweep. The **on-disk client config still points at dead v1410-1**:

```
Client.Servers = ["100.75.75.39:4647"]
```

`100.75.75.39` has been unreachable ~30 days (GH #8). On the next Nomad agent restart this
node silently reverts to a dead server and leaves the cluster.

## What to do (run locally on the Mac)

1. `pgrep -af "nomad agent"` — find the `-config=` path.
2. In that config's `client` block, put claudebox first, keep v1410-1 as fallback:

   ```hcl
   client {
     enabled = true
     servers = ["100.87.219.108:4647", "100.75.75.39:4647"]
   }
   ```

3. `SIGHUP` the agent to reload; restart only if the reload doesn't take.
4. Verify: `curl -s http://localhost:4646/v1/agent/servers`

## Note

This node will still not show `ready`/`eligible` until Raft quorum returns — registration is
a write and fails with *"No cluster leader"*. Its `heartbeat_ttl` is `0s` for that reason.
That is expected, not a fault of this node. Do **not** enable `server`/`bootstrap_expect`
here to try to force quorum; the committed voter set is `{v1410-1, claudebox}`.
