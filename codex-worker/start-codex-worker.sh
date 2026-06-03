#!/usr/bin/env bash
# start-codex-worker.sh — make a codex worker reachable on the tailnet (both doors).
#
# OpenAI's Codex CLI has no `remote-control` command, so a codex worker cannot be
# attached from the Claude app the way Claude workers are. This brings up the two
# model-agnostic doors instead, mirroring conductor/start-conductor.sh:
#
#   DOOR 1  TEXT GATEWAY  (codex-worker/gateway.py) — run in the FOREGROUND so the
#           supervisor (Nomad raw_exec) tracks it and restarts on failure.
#           Reach it:  curl -s -X POST http://<tailscale-ip>:8300/ask -d 'hi'
#
#   DOOR 2  INTERACTIVE  — a live `codex` TUI kept alive in a detached tmux session
#           by a small background watchdog. Attach over Tailscale SSH:
#           ssh <node> -t 'tmux attach -t codex-worker'   (or: monad codex connect <node>)
#
# Env (all optional):
#   CODEX_WORKDIR          default: the monad repo root
#   CODEX_BIND             default: this node's `tailscale ip -4`
#   CODEX_PORT             default: 8300
#   CODEX_TOKEN            optional shared bearer token for the gateway
#   CODEX_SANDBOX          "bypass" (default) | read-only | workspace-write | danger-full-access
#   ENABLE_INTERACTIVE     "1" (default) to also run the tmux attach session
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONAD_ROOT="$(cd "$HERE/.." && pwd)"
WORKDIR="${CODEX_WORKDIR:-$MONAD_ROOT}"
RC_TMUX="codex-worker"
ENABLE_INT="${ENABLE_INTERACTIVE:-1}"
SANDBOX="${CODEX_SANDBOX:-bypass}"

CODEX_BIN_RESOLVED="${CODEX_BIN:-$(command -v codex || echo /snap/bin/codex)}"

# NOMAD_ADDR for cluster ops, if not already set
if [ -z "${NOMAD_ADDR:-}" ]; then
  MYIP="$(tailscale ip -4 2>/dev/null | head -1)"
  [ -n "$MYIP" ] && export NOMAD_ADDR="http://${MYIP}:4646"
fi

log() { echo "[start-codex-worker $(date -u +%H:%M:%S)] $*"; }

# interactive flags mirror the gateway's sandbox choice
int_flags() {
  if [ "$SANDBOX" = "bypass" ]; then
    echo "--dangerously-bypass-approvals-and-sandbox"
  else
    echo "--sandbox $SANDBOX --full-auto"
  fi
}

# ── interactive watchdog: keep a live codex TUI alive in tmux for SSH attach ────
int_watchdog() {
  command -v tmux >/dev/null 2>&1 || { log "tmux not found; interactive door disabled"; return; }
  [ -x "$CODEX_BIN_RESOLVED" ] || command -v codex >/dev/null 2>&1 || {
    log "codex not found; interactive door disabled"; return; }
  local flags; flags="$(int_flags)"
  while true; do
    if ! tmux has-session -t "$RC_TMUX" 2>/dev/null; then
      log "launching interactive codex session in tmux ($RC_TMUX)"
      tmux new-session -d -s "$RC_TMUX" -x 220 -y 50 \
        "cd '$WORKDIR' && exec '$CODEX_BIN_RESOLVED' $flags"
    fi
    sleep 30
  done
}

if [ "$ENABLE_INT" = "1" ]; then
  int_watchdog &
  log "interactive watchdog started (pid $!) — attach: tmux attach -t $RC_TMUX"
else
  log "interactive door disabled (ENABLE_INTERACTIVE=$ENABLE_INT)"
fi

# ── the text gateway in the foreground (this is what the supervisor tracks) ─────
log "starting codex text gateway (workdir=$WORKDIR, sandbox=$SANDBOX)"
exec python3 "$HERE/gateway.py"
