#!/usr/bin/env bash
# rc-session.sh — run ONE persistent, app-attachable remote-control LLM session.
#
# Used by the concierge and by every spawned assistant. The session shows up in the Claude
# app (claude.ai/code) under RC_NAME; the owner chats with it there. Model is the "effort"
# dial — weak/cheap (haiku) for the concierge, stronger for assistants — and is controllable
# by the cluster brain (RC_MODEL, or RC_EFFORT=low|medium|high). The working dir (RC_CWD)
# carries the session's purpose (its CLAUDE.md), so each assistant has its own personality.
#
# Env: RC_NAME (required), RC_MODEL, RC_EFFORT (low|medium|high), RC_CWD (default /work),
#      GH_TOKEN (git push), NOMAD_ADDR.
set -uo pipefail

NAME="${RC_NAME:?RC_NAME required}"
MODEL="${RC_MODEL:-}"
EFFORT="${RC_EFFORT:-}"
CWD="${RC_CWD:-/work}"
[ -d "$CWD" ] || CWD=/work
cd "$CWD" 2>/dev/null || cd /

# Effort → model alias when an explicit model wasn't given (the brain can set either).
if [ -z "$MODEL" ] && [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    minimal|low)  MODEL=haiku ;;
    medium|med)   MODEL=sonnet ;;
    high|max)     MODEL=opus ;;
    *)            MODEL=haiku ;;
  esac
fi
MODEL="${MODEL:-haiku}"

# git push auth (so an assistant/concierge that edits the repo can commit).
if [ -n "${GH_TOKEN:-}" ]; then
  git config --global credential.helper '!f(){ echo username=x-access-token; echo "password=${GH_TOKEN}"; }; f' 2>/dev/null || true
  git config --global --add safe.directory '*' 2>/dev/null || true
fi

echo "[rc-session] '$NAME' model=$MODEL cwd=$CWD — attach from claude.ai/code"
# Foreground supervise loop: if the RC connection drops, restart it (Nomad supervises this
# script; the loop avoids a crash-restart of the whole alloc on a transient disconnect).
while true; do
  claude --model "$MODEL" remote-control "$NAME" --dangerously-skip-permissions || true
  echo "[rc-session] '$NAME' session ended; reconnecting in 10s"
  sleep 10
done
