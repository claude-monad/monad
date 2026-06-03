#!/usr/bin/env bash
# agent-dispatch.sh — run one scoped agent session by ROLE. Invoked by the parameterized
# Nomad job jobs/agent-dispatch.hcl (dispatched by the webhook receiver and the dispatcher
# loop). This is how claudebox runs autonomous jobs.
#
# Usage: agent-dispatch.sh <role> [scope]
#   role: formalizer | researcher | compute | reviewer | dispatch | echo
#
# Notes:
#   * formalizer pushes to eliott-monad/math-lean (we own it) — fully autonomous here.
#   * researcher/compute/reviewer target upstream eliottcassidy2000/math, which claudebox
#     cannot push to (403); those sessions must use the fork+PR flow (the prompt handles it).
#   * echo is a harmless plumbing test.
set -uo pipefail

# ROLE/SCOPE come from CLI args or, when dispatched by Nomad, from injected meta env vars
# (Nomad exposes dispatch meta as NOMAD_META_<KEY>, casing varies — check both).
ROLE="${1:-${NOMAD_META_ROLE:-${NOMAD_META_role:-}}}"
SCOPE="${2:-${NOMAD_META_SCOPE:-${NOMAD_META_scope:-}}}"
[ -n "$ROLE" ] || { echo "usage: agent-dispatch.sh <role> [scope]  (or NOMAD_META_ROLE)" >&2; exit 2; }

# Claude refuses --dangerously-skip-permissions when run as root. If we are root, re-exec
# as the first non-root user who owns a monad checkout (same logic as maintenance-agent).
if [ "$(id -u)" = 0 ]; then
  for u in ubuntu bigo e eliott; do
    home="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
    [ -n "$home" ] || continue
    for repo in "$home/monad" "$home/Documents/monad" "$home/Documents/GitHub/monad"; do
      [ -f "$repo/scripts/agent-dispatch.sh" ] || continue
      exec su - "$u" -c "NOMAD_META_ROLE='$ROLE' NOMAD_META_SCOPE='${SCOPE:-}' MONAD_REPO_DIR='$repo' exec bash '$repo/scripts/agent-dispatch.sh'"
    done
  done
  echo "[agent-dispatch] running as root but no non-root monad checkout found" >&2
  exit 1
fi

DIR="${MONAD_REPO_DIR:-$HOME/monad}/scripts"
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

echo "[agent-dispatch] role=$ROLE scope=${SCOPE:-<none>} $(date -u +%FT%TZ)"

case "$ROLE" in
  formalizer)
    exec "$DIR/formalizer-session.sh" 0
    ;;
  researcher|compute|reviewer)
    exec "$DIR/math-session.sh" "$ROLE" 100
    ;;
  dispatch)
    exec python3 "$DIR/../meta/coordination/dispatcher.py" --commit
    ;;
  echo)
    echo "[agent-dispatch] ECHO ok on $(hostname) as $(whoami); scope=$SCOPE"
    ;;
  *)
    echo "[agent-dispatch] unknown role: $ROLE" >&2; exit 2
    ;;
esac
