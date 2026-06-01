#!/usr/bin/env bash
# run-container-session.sh — launch ONE containerized, headless Claude research
# session on this host. Fully isolated (fresh clone inside the container), so it
# never collides with other sessions' working trees.
#
# Usage:
#   run-container-session.sh <machine-id> <prompt-string|@prompt-file> [--detach]
#
# Auth: mounts the host's ~/.claude + ~/.claude.json (Claude OAuth, rw so token
# refresh persists) and injects `gh auth token` for git push. Requires the
# monad-claude-session image (build: meta/dispatch/build-image.sh).
set -euo pipefail

MACHINE_ID="${1:?usage: run-container-session.sh <machine-id> <prompt|@file> [--detach]}"
PROMPT_SRC="${2:?prompt string or @file required}"
DETACH=""; [ "${3:-}" = "--detach" ] && DETACH="-d"

IMAGE="${MONAD_SESSION_IMAGE:-monad-claude-session}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"

# prompt: literal string, or @path to a file
if [ "${PROMPT_SRC:0:1}" = "@" ]; then
  PROMPT="$(cat "${PROMPT_SRC:1}")"
else
  PROMPT="$PROMPT_SRC"
fi

# git push token (host gh credential)
if ! TOKEN="$(gh auth token 2>/dev/null)"; then
  echo "[run-container] ERROR: 'gh auth token' failed — host is not gh-authenticated." >&2
  exit 1
fi
[ -f "$CLAUDE_DIR/.credentials.json" ] || { echo "[run-container] ERROR: $CLAUDE_DIR/.credentials.json missing (run 'claude' to log in)." >&2; exit 1; }

echo "[run-container] launching session '$MACHINE_ID' (image $IMAGE) ..."
exec sudo docker run --rm $DETACH \
  --name "session-${MACHINE_ID}" \
  -v "$CLAUDE_DIR":/home/ubuntu/.claude \
  -v "$CLAUDE_JSON":/home/ubuntu/.claude.json \
  -e GH_TOKEN="$TOKEN" \
  -e MACHINE_ID="$MACHINE_ID" \
  -e PROMPT="$PROMPT" \
  "$IMAGE"
