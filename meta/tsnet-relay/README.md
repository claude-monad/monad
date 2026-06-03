# math-agent-relay

A tsnet-based IPC relay for the math research agent network.

Each agent machine runs one instance. It advertises as `math-relay-<machine-id>` on the Tailnet and provides low-latency message delivery between Claude agents — complementing the durable but higher-latency git-based message passing.

## Architecture

```
Agent A (mac) ──POST /send──► math-relay-windesk (tsnet) ──► git inbox write
                                                           ──► in-memory queue
Agent B (windesk) ──GET /messages──► reads pending messages
```

The relay is a thin HTTP server running as a tsnet node. Messages are:
1. Delivered immediately over the Tailnet (sub-second for LAN-adjacent nodes)
2. Written through to `agents/<machine-id>/inbox/` in the math git repo for durability

`processor.py` tries the tsnet relay first and falls back to git silently.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/send` | Deliver a message (JSON body) |
| `GET`  | `/messages` | List pending (unread) messages |
| `POST` | `/messages/{id}/read` | Mark a message read (removes from queue) |
| `GET`  | `/health` | Liveness probe |

## Quick start

```bash
# Build (needs Go 1.22+ and internet for go mod download)
bash meta/tsnet-relay/build.sh

# Run manually (uses .machine-id in the math repo)
TS_AUTHKEY=<your-tailscale-authkey> \
  ~/monad/bin/math-agent-relay --repo ~/Documents/GitHub/math
```

## Nomad deployment

The Nomad job `jobs/math-agent-relay.hcl` runs this as a system job on every node
with `meta.math_agent = "true"`. To activate on windesk and mac-mini:

1. Add to each machine's Nomad client config (`client.hcl`):
   ```hcl
   meta {
     math_agent     = "true"
     claude_account = "pro"
   }
   ```
2. Store the Tailscale auth key as a Nomad variable:
   ```bash
   nomad var put nomad/jobs/math-agent-relay ts_authkey=<your-key>
   ```
3. Deploy: `monad deploy jobs/math-agent-relay.hcl`

## mac-mini note

The mac-mini has no internet access. To build the relay there:
1. On a connected machine: `cd meta/tsnet-relay && GOMODCACHE=/tmp/relay-cache go mod download`
2. rsync `/tmp/relay-cache` to mac-mini's GOPATH/pkg/mod
3. Then run `build.sh` on the mac-mini — it will find modules in the cache
