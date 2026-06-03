#!/usr/bin/env bash
# ensure-engines.sh — make this node able to run agent jobs with BOTH engines
# (claude + codex), and advertise which engines are READY via dynamic Nomad node
# metadata so the cluster brain can schedule either type here.
#
# Idempotent and cron-safe. node-doctor calls this every pass, so each machine keeps
# itself set up. Also runnable standalone and from join.sh.
#
#   has_claude / has_codex   -> "true" only if the CLI is installed AND logged in
#   agent_engines            -> comma list of ready engines (e.g. "claude,codex")
#
# It will try to INSTALL a missing CLI, but it cannot log you in — auth is a human,
# once-per-machine step (`claude`, `codex login`). Missing auth is a warning, not a
# failure, so a half-ready node still advertises what it can do.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/engines.sh"

log()  { printf '\033[0;36m[ensure-engines]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[ensure-engines]\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="linux"; [ "$(uname -s)" = "Darwin" ] && OS="macos"
SUDO=""; [ "$(id -u)" -ne 0 ] && have sudo && SUDO="sudo"

install_claude() {
  have claude && return 0
  log "installing claude CLI…"
  curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null \
    || warn "claude install failed — install manually, then run 'claude' to log in."
}

install_codex() {
  have codex && return 0
  log "installing codex CLI…"
  if have npm; then
    $SUDO npm install -g @openai/codex 2>/dev/null || npm install -g @openai/codex 2>/dev/null \
      || warn "codex npm install failed."
  elif [ "$OS" = macos ] && have brew; then
    brew install codex 2>/dev/null || warn "codex brew install failed."
  else
    warn "no npm/brew to install codex — install @openai/codex manually, then 'codex login'."
  fi
}

install_claude
install_codex

# Re-detect after any install.
# Use plain variables instead of associative array for bash 3.2 compat (macOS ships 3.2).
READY_claude=false; READY_codex=false
SUMMARY=""
for e in claude codex; do
  if engine_available "$e"; then
    if engine_authed "$e"; then
      eval "READY_${e}=true"; SUMMARY="$SUMMARY $e=ready"
    else
      eval "READY_${e}=false"; SUMMARY="$SUMMARY $e=installed-NOT-logged-in"
      warn "$e is installed but not logged in — run '$([ "$e" = codex ] && echo "codex login" || echo claude)' once."
    fi
  else
    eval "READY_${e}=false"; SUMMARY="$SUMMARY $e=absent"
  fi
done
log "engine status:${SUMMARY}"

ENGINES_CSV="$(engines_ready | tr ' ' ',')"

# Advertise via dynamic node metadata (no nomad restart; ~10s to propagate).
# On macOS (and Linux nodes that bind to Tailscale IP not 127.0.0.1), probe the
# local client first, then fall back to the Tailscale IP (the actual bind_addr).
if [ -z "${NOMAD_ADDR:-}" ]; then
  tip="$(tailscale ip -4 2>/dev/null | head -1)"
  # Prefer localhost; fall back to Tailscale IP (macOS Nomad clients bind there)
  if curl -sf http://127.0.0.1:4646/v1/agent/self >/dev/null 2>&1; then
    export NOMAD_ADDR="http://127.0.0.1:4646"
  elif [ -n "$tip" ] && curl -sf "http://${tip}:4646/v1/agent/self" >/dev/null 2>&1; then
    export NOMAD_ADDR="http://${tip}:4646"
  else
    export NOMAD_ADDR="http://${tip:-127.0.0.1}:4646"
  fi
fi
if have nomad && nomad node meta apply \
      "has_claude=${READY_claude}" \
      "has_codex=${READY_codex}" \
      "agent_engines=${ENGINES_CSV:-none}" >/dev/null 2>&1; then
  log "advertised dynamic node meta: has_claude=${READY_claude} has_codex=${READY_codex} agent_engines=${ENGINES_CSV:-none} (via $NOMAD_ADDR)"
else
  warn "could not apply dynamic node meta (is the local nomad client up at $NOMAD_ADDR?) — engines still usable, just not advertised."
fi

# Non-fatal: a node with at least one ready engine is useful.
[ -n "$ENGINES_CSV" ] || warn "no ready engine on this node yet (install + log in to claude and/or codex)."
exit 0
