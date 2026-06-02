# `meta/agent/` — the engine abstraction

Monad runs LLM agents to do work. There are two **interchangeable engines**:

| engine | CLI | one-shot | persistent / brain | auth |
|--------|-----|----------|--------------------|------|
| `claude` | Claude Code | `claude --print --dangerously-skip-permissions` | `claude remote-control --name X` | `~/.claude/.credentials.json` |
| `codex`  | OpenAI Codex | `codex exec --dangerously-bypass-approvals-and-sandbox` | `codex remote-control start` | `~/.codex/auth.json` (ChatGPT) |

Everything that launches an agent should go through this layer instead of hard-coding one
CLI, so the cluster brain is free to launch **either type** and load spreads across the two
vendors' independent rate-limit pools.

## Files

- **`engines.sh`** — sourceable library. Detection (`engine_ready`, `engines_ready`),
  selection policy (`engine_pick`), and the canonical command builders
  (`engine_exec_argv`, `engine_session_argv`).
- **`run-agent.sh`** — the single front door to run one agent task:
  ```bash
  run-agent.sh [--engine claude|codex|auto] [--mode exec|session] \
               [--quiet] [--cwd DIR] [--timeout SEC] [--name NAME] <prompt|@file|->
  ```
  `--engine auto` (default) picks any ready engine per `MONAD_ENGINE_PREFERENCE`
  (default `claude codex`). `--quiet` normalizes output to just the agent's final
  message for both engines. Exit code is the agent's (124 = timed out).
- **`ensure-engines.sh`** — per-node self-setup. Installs any missing CLI, checks auth,
  and advertises the **ready** engines via dynamic Nomad node metadata
  (`has_claude`, `has_codex`, `agent_engines`). node-doctor runs this every pass, so each
  machine keeps itself set up. It can install a CLI but cannot log you in — auth is a
  one-time human step per machine (`claude`, `codex login`).
- **`ensure-engines.ps1`** — Windows port (the bash `maintenance-agent` system job
  doesn't land on Windows nodes). Same detect/advertise contract
  (`%USERPROFILE%\.claude\.credentials.json`, `%USERPROFILE%\.codex\auth.json`). Run via
  `powershell -ExecutionPolicy Bypass -File meta\agent\ensure-engines.ps1` and wire it
  into the Windows node-doctor scheduled task / `node-manager-windows` so the box
  self-sets-up every pass. Still needs a one-time human `codex login` / `claude`.

## Scheduling on engine capability

Nodes advertise `has_claude` / `has_codex` / `agent_engines` as dynamic node meta. Pin a
job to a capable node with a constraint, e.g.:

```hcl
constraint { attribute = "${meta.has_codex}"  value = "true" }      # needs codex
# or engine-agnostic: just needs *some* agent
constraint { attribute = "${meta.agent_engines}" operator = "is_set" }
```

## Selecting an engine at runtime

- Env: `MONAD_ENGINE=codex run-agent.sh ...`, or `--engine codex`.
- Default preference order: `MONAD_ENGINE_PREFERENCE="codex claude"` to prefer codex.
- The brain/dispatch passes an engine per task; `auto` lets the node choose what's ready.
