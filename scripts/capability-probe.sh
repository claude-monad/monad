#!/usr/bin/env bash
# capability-probe.sh — honestly test THIS node's ability to run an autonomous math
# session with each engine (claude + codex), and report the result to the cluster as a
# per-node Nomad var `capability/<node>`. The dashboard renders these as a matrix.
#
# "Honest" = it actually RUNS each installed engine on a tiny math prompt and classifies
# by the real outcome (not just whether creds files exist — that misses macOS Keychain
# auth). States per engine:
#   ok          rc=0 and a non-empty reply
#   ran-empty   rc=0 but no output (e.g. the codex --quiet capture gap, t-0015)
#   error-rcN   the engine exited non-zero (e.g. not logged in)
#   timeout     exceeded the probe wall-clock
#   absent      the CLI is not installed on this node
#
# Invoked by jobs/cluster-capability.hcl (sysbatch + periodic → every node, on a schedule).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
RA="$REPO/meta/agent/run-agent.sh"
# shellcheck source=/dev/null
. "$REPO/meta/agent/engines.sh" 2>/dev/null || true
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin:$PATH"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"

NODE="$(hostname)"
PROMPT='In ONE short line state a true fact about tournaments or the Lonely Runner Conjecture, then on a second line write exactly: CAPABLE'

probe() {  # $1=engine -> echoes a state word (HONEST: detects run-agent's silent fallback)
  local eng="$1" out rc o chosen errf
  command -v "$eng" >/dev/null 2>&1 || { echo "absent"; return; }
  errf="$(mktemp)"
  # --print-engine logs the engine run-agent actually CHOSE to stderr. run-agent falls back
  # to another ready engine if the requested one isn't ready — so if chosen != requested,
  # THIS engine is not actually usable here (e.g. codex requested, claude run). Report that
  # honestly instead of crediting a fallback as success.
  out="$(timeout 240 bash "$RA" --engine "$eng" --print-engine --quiet --timeout 200 "$PROMPT" 2>"$errf")"; rc=$?
  chosen="$(grep -oE 'engine=[a-z]+' "$errf" | head -1 | cut -d= -f2)"; rm -f "$errf"
  [ "$rc" = 124 ] && { echo "timeout"; return; }
  [ -z "$chosen" ] && { echo "not-ready"; return; }          # run-agent found no ready engine
  [ "$chosen" != "$eng" ] && { echo "not-ready"; return; }   # fell back to a different engine
  [ "$rc" != 0 ] && { echo "error-rc$rc"; return; }
  o="$(printf '%s' "$out" | tr -d '[:space:]')"
  [ -z "$o" ] && { echo "ran-empty"; return; }
  echo "ok"
}

echo "[capability] probing $NODE (user $(whoami))…" >&2
CL="$(probe claude)"
CX="$(probe codex)"
TS="$(date -u +%FT%TZ)"

nomad var put -force "capability/$NODE" \
  node="$NODE" user="$(whoami)" ts="$TS" \
  claude="$CL" codex="$CX" >/dev/null 2>&1 \
  && echo "[capability] $NODE claude=$CL codex=$CX (reported)" \
  || echo "[capability] $NODE claude=$CL codex=$CX (var write FAILED)"
