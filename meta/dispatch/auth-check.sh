#!/usr/bin/env bash
# auth-check.sh — verify a containerized Claude session can authenticate headless
# with the host's credentials (no repo clone, no push). Prints AUTHENTICATED on
# success. Uses a throwaway copy of the creds so the host's ~/.claude is untouched.
set -euo pipefail
IMAGE="${MONAD_SESSION_IMAGE:-monad-claude-session}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"
TMPH="$(mktemp -d)"; trap 'sudo rm -rf "$TMPH"' EXIT
mkdir -p "$TMPH/.claude"
cp "$CLAUDE_DIR/.credentials.json" "$CLAUDE_DIR/settings.json" "$TMPH/.claude/" 2>/dev/null || true
cp "$CLAUDE_JSON" "$TMPH/.claude.json" 2>/dev/null || true
chmod -R 777 "$TMPH"
sudo timeout 120 docker run --rm \
  -v "$TMPH/.claude":/home/ubuntu/.claude \
  -v "$TMPH/.claude.json":/home/ubuntu/.claude.json \
  -e AUTH_CHECK=1 \
  "$IMAGE"
