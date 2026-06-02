# `meta/agent/mesh/` — the Tailscale agent mesh

Gives each Monad agent **its own node on the Tailscale network** so agents can see and
message each other directly to coordinate on problems.

```
   agent-helper (codex)              agent-reviewer (claude)
   ┌───────────────────┐            ┌───────────────────┐
   │ LLM ── agent-msg ──┼──┐      ┌──┼── agent-msg ── LLM │
   │ tsnet-sidecar      │  │      │  │      tsnet-sidecar │
   │ ip 100.x.x.a       │  └─tailnet─┘  │       ip 100.x.x.b │
   └───────────────────┘   (POST /msg)  └───────────────────┘
```

## How it works

Each agent container runs the **tsnet sidecar** beside the LLM. The sidecar joins the
tailnet as `agent-<name>` (own IP + MagicDNS) using a reusable+ephemeral auth key, and
serves:

- **mesh API** on the tailnet IP (`MESH_PORT` 8472) — how peers reach this agent:
  `POST /msg {from,body}` (deliver to inbox), `GET /id`.
- **local API** on `127.0.0.1:LOCAL_PORT` (8473) — how this agent's LLM drives the mesh:
  `GET /whoami`, `GET /peers`, `POST /send {to,body}`, `GET /recv`.

The LLM uses the **`agent-msg`** CLI (a thin wrapper over the local API):

```bash
agent-msg whoami                  # my mesh name + tailnet IP
agent-msg peers                   # other agent-* nodes on the tailnet
agent-msg send <peer> <message…>  # message a peer
agent-msg recv                    # read messages sent to me
```

Discovery = online tailnet nodes whose name starts with `agent-`.

## Components

| File | Role |
|------|------|
| `sidecar/main.go`, `go.mod` | the tsnet sidecar (Go); built into the image |
| `agent-msg.sh`  | the LLM's mesh CLI (`/usr/local/bin/agent-msg` in the image) |
| `entrypoint.sh` | start sidecar → wait for mesh → run agent (briefed) or idle as a peer |
| `Dockerfile`    | `monad-agent-mesh` image: claude + codex + sidecar (non-root `ubuntu`) |
| `build-image.sh`| build the image on a docker node |
| `../../../jobs/agent-mesh.hcl` | Nomad job; `TS_AUTHKEY` templated from `secret/agent-mesh` |

## Auth

The Tailscale auth key (reusable + ephemeral, ideally `tag:agent`) lives in the Nomad
variable `secret/agent-mesh` → `tailscale_authkey`, injected into containers by the job.
Ephemeral means nodes auto-deregister from the tailnet when the agent exits.

## Usage

> **Image distribution:** Nomad's docker driver here only uses *registry* images, not local
> builds, so `build-image.sh` builds **and** pushes a multi-arch manifest to the registry in
> Nomad var `infra/registry` when present. Until the shared registry is deployed, it falls
> back to `localhost:5000`. The image also remaps `ubuntu` to the host uid/gid so mounted
> engine creds are readable.

```bash
meta/agent/mesh/build-image.sh                      # build + push linux/amd64 + linux/arm64
REGISTRY=100.78.218.70:5000 meta/agent/mesh/build-image.sh
# a working agent that can talk to peers:
nomad job dispatch -meta agent_name=agent-helper \
  -meta prompt="…task…" -meta engine=codex agent-mesh
# a persistent reachable peer (no task):
nomad job dispatch -meta agent_name=agent-idle agent-mesh
```

## Status / next

Core verified: two sidecars joined the tailnet with their own IPs and exchanged messages
both ways. Next: bring the per-node **maintenance agents** onto the mesh (so the standing
fleet can coordinate), and generalize the job beyond oraclebox1 once creds + docker exist
on more nodes. See [[agent-engine-abstraction]] and `meta/agent/README.md`.
