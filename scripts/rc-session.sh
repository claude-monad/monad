#!/usr/bin/env bash
# rc-session.sh — run ONE persistent, app-attachable remote-control LLM session.
#
# Used by the concierge and by every spawned assistant. The session shows up in the Claude
# app (claude.ai/code) under RC_NAME; the owner chats with it there. Model is the "effort"
# dial — weak/cheap (haiku) for the concierge, stronger for assistants — controllable by the
# cluster brain (RC_MODEL, or RC_EFFORT=low|medium|high). The working dir (RC_CWD) carries the
# session's purpose (its CLAUDE.md), so each assistant has its own personality.
#
# Env: RC_NAME (required), RC_MODEL, RC_EFFORT (low|medium|high), RC_CWD (default /work),
#      GH_TOKEN (git push), NOMAD_ADDR.
set -uo pipefail

NAME="${RC_NAME:?RC_NAME required}"
MODEL="${RC_MODEL:-}"
EFFORT="${RC_EFFORT:-}"
CWD="${RC_CWD:-/work}"
[ -d "$CWD" ] || CWD=/work

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
cd "$CWD" 2>/dev/null || { cd /work; CWD=/work; }

# git push auth (so a session that edits the repo can commit).
if [ -n "${GH_TOKEN:-}" ]; then
  git config --global credential.helper '!f(){ echo username=x-access-token; echo "password=${GH_TOKEN}"; }; f' 2>/dev/null || true
  git config --global --add safe.directory '*' 2>/dev/null || true
fi

# Model isn't a remote-control flag — it's read from project settings. Write it into this
# session's working dir so the brain can make it weak (haiku) or strong (opus) by changing
# RC_MODEL/RC_EFFORT and restarting. (Runtime-written, not committed.)
mkdir -p "$CWD/.claude" 2>/dev/null || true
printf '{ "model": "%s" }\n' "$MODEL" > "$CWD/.claude/settings.json" 2>/dev/null || true

# The remote-control SERVER refuses untrusted workspaces and has no --dangerously-skip flag,
# so mark this dir trusted in ~/.claude.json. Edit IN PLACE (the file is bind-mounted, so a
# temp+rename would not update it) under an flock (claude writes this file too).
CJSON="${HOME:-/home/ubuntu}/.claude.json"
if [ -f "$CJSON" ]; then
  python3 - "$CWD" "$CJSON" <<'PY' 2>/dev/null || true
import json, sys, fcntl
cwd, p = sys.argv[1], sys.argv[2]
f = open(p, "r+"); fcntl.flock(f, fcntl.LOCK_EX)
try:
    data = json.load(f)
    e = data.setdefault("projects", {}).setdefault(cwd, {})
    e["hasTrustDialogAccepted"] = True
    e["hasCompletedProjectOnboarding"] = True
    f.seek(0); f.truncate(); json.dump(data, f)
finally:
    fcntl.flock(f, fcntl.LOCK_UN); f.close()
PY
fi

echo "[rc-session] '$NAME' model=$MODEL cwd=$CWD — attach from claude.ai/code"
# Foreground supervise loop: if the RC server drops, restart it (Nomad supervises this
# script; the loop avoids a crash-restart of the whole alloc on a transient disconnect).
while true; do
  claude remote-control --name "$NAME" --permission-mode bypassPermissions --spawn same-dir || true
  echo "[rc-session] '$NAME' session ended; reconnecting in 10s"
  sleep 10
done
