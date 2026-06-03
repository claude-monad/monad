# Codex Worker — reaching Codex nodes without `remote-control`

OpenAI's **Codex CLI has no `remote-control` command** — that is Claude-Code-specific
(`claude --remote-control <name>` registers a session with your Anthropic account so
the Claude app can attach to it). So codex workers can't be reached from the Claude
app the way Claude workers are.

This component gives codex workers the cluster's **model-agnostic** connectivity
instead, mirroring the Claude `conductor/`: **two doors, one codex brain.**

| | Claude worker | Codex worker |
|---|---|---|
| Programmatic / phone | conductor text gateway (`:8200/ask`) | **this gateway** (`:8300/ask`) |
| Hands-on / live | Claude app remote-control session | **tmux + Tailscale SSH attach** |

## Door 1 — text gateway (`gateway.py`)

An always-on HTTP service bound to the node's **Tailscale IP**, port **8300**. It
serializes prompts into a continuity-preserving headless `codex exec` thread and
returns the reply.

```bash
# ask this worker something (raw text in, text out)
curl -s -X POST http://<node-tailscale-ip>:8300/ask -d 'what are you working on?'

# JSON in / JSON out
curl -s -X POST http://<node-tailscale-ip>:8300/ask \
  -H 'Content-Type: application/json' -d '{"text":"run the test suite and summarize"}'

# health, and starting a fresh thread
curl -s http://<node-tailscale-ip>:8300/health
curl -s -X POST http://<node-tailscale-ip>:8300/ask -d '/reset'
```

Every `/ask` continues the **same** codex thread (via `codex exec resume --last`,
reliable because the gateway is the node's single serialized codex consumer in a
fixed workdir). Send `/reset` to start a new thread.

## Door 2 — interactive attach (tmux over Tailscale SSH)

`start-codex-worker.sh` also keeps a live `codex` TUI alive in a detached tmux
session (`codex-worker`). Attach to drive it by hand:

```bash
ssh <node> -t 'tmux attach -t codex-worker'      # needs Tailscale SSH on the node
# or, from anywhere with the monad CLI:
monad codex connect <node>
```

> The interactive session and the gateway are **separate codex threads** (Codex has
> no shared-session primitive across exec/TUI). Use door 1 for scripted/phone asks
> and door 2 to sit down and drive.

## Running it

**Manually on a codex node:**
```bash
codex login status                  # must show "Logged in"
codex-worker/start-codex-worker.sh  # foreground gateway + background tmux watchdog
```

**Under Nomad (supervised, auto-restart):** deploy `jobs/codex-worker.hcl`. It runs
on any node tagged `meta.codex = "true"` (set that in the node's client.hcl `meta`
block, then restart Nomad). See that file for the constraint.

## Configuration (env)

| Var | Default | Meaning |
|---|---|---|
| `CODEX_PORT` | `8300` | gateway port |
| `CODEX_BIND` | `tailscale ip -4` | bind address (tailnet-only; never 0.0.0.0) |
| `CODEX_WORKDIR` | monad repo root | codex working root |
| `CODEX_SANDBOX` | `bypass` | `bypass` (full access, matches `codex --yolo`) or `read-only` / `workspace-write` / `danger-full-access` |
| `CODEX_MODEL` | — | optional `-m <model>` override |
| `CODEX_TOKEN` | — | optional bearer token (`Authorization: Bearer …` or `?token=`) |
| `CODEX_PREAMBLE` | `codex-worker/CODEX.md` | persona prepended to the first turn of a thread |
| `CODEX_TIMEOUT` | `600` | per-request wall-clock seconds |
| `ENABLE_INTERACTIVE` | `1` | also run the tmux attach session |

## Security

Bind is the **tailnet IP only** — reachable solely by tailnet peers. For a second
factor set `CODEX_TOKEN`. Note `CODEX_SANDBOX=bypass` gives codex unsandboxed shell
access (parity with the `codex --yolo` you already run); downgrade to
`workspace-write` if you want codex confined to the workspace.
