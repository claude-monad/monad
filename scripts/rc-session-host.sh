#!/usr/bin/env bash
# rc-session-host.sh — raw_exec launcher for a remote-control session ON THE HOST (no Docker).
#
# Replaces the node-local Docker image (localhost:5000/monad-agent-mesh) that pinned concierge +
# assistants to oraclebox1. Now that Claude creds + CLI are on every node (engine-provision),
# an RC session runs directly as the host's Claude-credentialed user: pick that user, clone monad
# fresh into their work dir, then run scripts/rc-session.sh AS them (the provisioner unlocks the
# user so `su -` works; on nodes where raw_exec already runs as that user we run directly).
#
# Env: RC_NAME (required), RC_MODEL/RC_EFFORT, RC_USER (override), GH_TOKEN, NOMAD_ADDR, REPO_URL.
set -uo pipefail
: "${RC_NAME:?RC_NAME required}"
REPO_URL="${REPO_URL:-https://github.com/eliott-monad/monad}"

pick_user() {
  local u h
  for u in ${RC_USER:-} claude ubuntu e eliott bigo; do
    h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"; [ -n "$h" ] || continue
    [ -f "$h/.claude/.credentials.json" ] && { echo "$u"; return; }
  done
  for u in $(getent passwd | awk -F: '$3>=1000 && $3<65000 && $6 ~ /^\/home\//{print $1}'); do
    h="$(getent passwd "$u" | cut -d: -f6)"
    [ -f "$h/.claude/.credentials.json" ] && { echo "$u"; return; }
  done
  id -un
}
U="$(pick_user)"; H="$(getent passwd "$U" | cut -d: -f6)"
WORK="$H/.rc-work/$RC_NAME"
echo "[rc-host] RC_NAME=$RC_NAME user=$U home=$H work=$WORK"

# The command run as $U: refresh a private clone, set env, exec the (portable) rc-session.sh.
read -r -d '' CMD <<EOF || true
set -e
mkdir -p '$WORK'
if [ -e '$WORK/.git' ]; then
  git -C '$WORK' fetch -q origin main && git -C '$WORK' reset --hard -q origin/main || true
else
  git clone -q --depth 50 '$REPO_URL' '$WORK'
fi
export PATH=/usr/local/bin:\$HOME/.local/bin:\$HOME/.claude/local:/snap/bin:/usr/bin:/bin
export RC_NAME='$RC_NAME' RC_MODEL='${RC_MODEL:-}' RC_EFFORT='${RC_EFFORT:-}'
export RC_CWD='$WORK/assistants/$RC_NAME'
export NOMAD_ADDR='${NOMAD_ADDR:-http://100.75.75.39:4646}' GH_TOKEN='${GH_TOKEN:-}'
exec bash '$WORK/scripts/rc-session.sh'
EOF

if [ "$(id -un)" = "$U" ]; then
  exec bash -c "$CMD"
elif [ "$(id -u)" = 0 ]; then
  exec su - "$U" -c "$CMD"
else
  exec sudo -n -u "$U" -H bash -c "$CMD"
fi
