# CODEX-ON-WIN-MAC.md — run codex agents (in a container) on windesk + mac-mini

**Goal (set 2026-06-03 by claudebox, owner-directed):** let agents run on the two non-linux
nodes — **windesk** (Windows 11, amd64) and **eliotts-mac-mini** (macOS, arm64). The concrete
target is: **run the `monad-agent-mesh` container there so codex runs well**. One container gives
the node *both* a working codex engine *and* a Tailscale-mesh identity — so this doubles as the
**tsnet inter-process-communication test** the owner asked for.

## Why a container (not native)

The bash/PowerShell `maintenance-agent` is `kernel.name = linux`-constrained, so it never lands on
windesk/mac. Rather than port the whole agent stack twice, run the **already-built Linux image**
under each box's Linux-container runtime (Docker Desktop on Win/Mac, or Colima on Mac). The image
has `codex` + `claude` + the `tsnet-sidecar` baked in.

## Verified preconditions (claudebox checked these 2026-06-03 — all GREEN)

- **Image published, multi-arch:** `100.78.218.70:5000/monad-agent-mesh:latest`
  → OCI index with **amd64** (windesk) and **arm64** (mac-mini) manifests. Codex baked in
  (`npm i -g @openai/codex`).
- **Registry** `100.78.218.70:5000` is on bigo-server, reachable on the tailnet. It is **plain
  HTTP**, so each Docker daemon must trust it as an *insecure registry* (see below).
- **Mesh auth key:** `nomad var get -item=tailscale_authkey secret/agent-mesh` (reusable+ephemeral).
- Run-contract: `meta/agent/mesh/entrypoint.sh` + `jobs/agent-mesh.hcl` (mounts, env, clone-wrapper).

## Per-node setup (do this ON windesk / ON the mac — owner/agent on that box)

1. **Install a Linux-container runtime**
   - Windows 11 Home: Docker Desktop (WSL2 backend). Mac: Docker Desktop *or* `brew install colima && colima start`.
2. **Trust the insecure registry** `100.78.218.70:5000`
   - Docker Desktop → Settings → Docker Engine, add:
     `{ "insecure-registries": ["100.78.218.70:5000"] }` then Apply & Restart.
   - Colima: `colima start --edit` and add the same under `docker:`.
3. **codex login (one-time, human ChatGPT login)** so `~/.codex/auth.json` exists on the host:
   `codex login`  (or `codex login --device-auth` if no browser). This file gets mounted in.
4. **Pull the image** (picks the right arch automatically):
   `docker pull 100.78.218.70:5000/monad-agent-mesh:latest`

## Run a codex agent in the container

The image's default entrypoint expects the repo at `/work`, so replicate the job's clone-wrapper
(from `jobs/agent-mesh.hcl`). One-shot codex task that also tests the mesh:

```bash
AUTHKEY="$(nomad var get -item=tailscale_authkey secret/agent-mesh)"   # or paste it on the box
docker run --rm \
  --entrypoint /bin/bash \
  -e TS_AUTHKEY="$AUTHKEY" \
  -e AGENT_NAME=agent-rc-windesk \   # or agent-rc-mac-mini
  -e MONAD_ENGINE=codex \
  -e REPO_URL=https://github.com/eliott-monad/monad \
  -e PROMPT="Report your hostname, OS/arch, and confirm codex is running inside a container. Then run 'agent-msg peers' and 'agent-msg send agent-maint-v1410-1 hello-from-<node>'." \
  -v "$HOME/.codex:/home/ubuntu/.codex" \
  -v "$HOME/.claude:/home/ubuntu/.claude" \
  100.78.218.70:5000/monad-agent-mesh:latest \
  -c 'set -e; if [ ! -e /work/.git ]; then git clone --depth 50 "$REPO_URL" /work; fi; exec /usr/local/bin/agent-entrypoint'
```

- **Omit `PROMPT`** to keep the container up as a *persistent reachable mesh peer* (`agent-rc-<node>`)
  that other agents can `agent-msg send` to, and into which you can `docker exec ... codex exec "..."`.
- Windows: run the same in PowerShell/WSL (`$HOME` → `$env:USERPROFILE`; or run from a WSL shell
  where `$HOME` works and Docker Desktop's WSL integration is on).

## Verify (the tsnet IPC test)

- In the container logs you should see `mesh identity: {"name":"agent-rc-<node>","ip":"100.x.y.z"}`.
- From any meshed agent (e.g. a maintenance-agent node): `agent-msg peers` should now list
  `agent-rc-windesk` / `agent-rc-mac-mini`, and `agent-msg send agent-rc-<node> "ping"` should be
  drained by `agent-msg recv` inside the container. That round-trip = tsnet IPC working cross-platform.
- `codex` running rc=0 with real output in the logs = "codex container runs well".

## Report back

Reply on the cluster mailbox so claudebox/peers can track it:
`bash ~/monad/scripts/cluster-msg.sh send claudebox "win-mac-codex" "<node>: runtime=<docker/colima> codex-login=<y/n> pull=<ok> container-codex=<rc> mesh-peer=<seen?> blockers=<...>"`
(On windesk use the PowerShell equivalent or run cluster-msg from WSL.) Record gaps as a task via
`meta/coordination/task.sh emit infra eliott-monad/monad "<what's blocked on win/mac>"`.

## Known sharp edges

- `latest` tag = in-container user `ubuntu` uid **1001**. Docker Desktop (Win/Mac) runs a Linux VM
  that's generally permissive about mounted-file ownership, so the uid1001 ↔ host-user mount usually
  just works; if codex can't read `~/.codex/auth.json`, `chmod -R a+rX ~/.codex` on the host or use
  the `uid1000` tag.
- Nomad has **no docker driver** on windesk/mac (only `raw_exec`), so this is a **manual `docker run`**,
  not a Nomad-scheduled alloc. That's expected and fine — the container still joins the mesh itself.
- The registry is HTTP-only; the `insecure-registries` step is mandatory or `docker pull` fails TLS.
