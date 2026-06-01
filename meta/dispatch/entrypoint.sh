#!/usr/bin/env bash
# entrypoint for a containerized Claude research session.
#
# Env:
#   PROMPT        the task prompt for Claude (required for a real session)
#   MACHINE_ID    .machine-id to use (default: monad-container-<rand>)
#   GH_TOKEN      GitHub token for git push (from host `gh auth token`)
#   REPO_URL      repo to clone (default: the math repo)
#   AUTH_CHECK    if "1", just verify Claude auth (prints a one-word reply) and exit
#   CLONE_DEPTH   git clone depth (default 100)
set -uo pipefail

REPO_URL="${REPO_URL:-https://github.com/eliottcassidy2000/math.git}"
MACHINE_ID="${MACHINE_ID:-monad-container-$RANDOM}"
CLONE_DEPTH="${CLONE_DEPTH:-100}"

# ── git push auth via the injected token ──────────────────────────────────────
if [ -n "${GH_TOKEN:-}" ]; then
  git config --global credential.helper \
    '!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'
fi
git config --global user.email "${GIT_EMAIL:-${MACHINE_ID}@math-research}"
git config --global user.name  "${GIT_NAME:-${MACHINE_ID}}"
git config --global --add safe.directory '*'

# ── fast path: just verify Claude auth works headless in this container ───────
if [ "${AUTH_CHECK:-0}" = "1" ]; then
  echo "[entrypoint] AUTH_CHECK: asking Claude to reply with a single token..."
  claude --print --dangerously-skip-permissions \
    "Reply with exactly the word: AUTHENTICATED. Nothing else." 2>&1
  exit $?
fi

# ── real session: clone, identify, run Claude on the prompt ───────────────────
if [ -z "${PROMPT:-}" ]; then
  echo "[entrypoint] ERROR: PROMPT is empty; nothing to do." >&2
  exit 2
fi

echo "[entrypoint] cloning $REPO_URL (depth $CLONE_DEPTH) ..."
git clone --depth "$CLONE_DEPTH" "$REPO_URL" math || { echo "clone failed" >&2; exit 3; }
cd math
echo "$MACHINE_ID" > .machine-id
python3 agents/processor.py --register 2>/dev/null || true

# Hard wall-clock cap so a stalled session (rate-limit backoff, a hung call) can
# never run forever and pin the account's credentials. Default 45 min; override
# with CLAUDE_TIMEOUT (seconds, 0 = no limit).
LIMIT="${CLAUDE_TIMEOUT:-2700}"
echo "[entrypoint] launching Claude session as '$MACHINE_ID' (timeout ${LIMIT}s) ..."
if [ "$LIMIT" = "0" ]; then
  claude --print --dangerously-skip-permissions "$PROMPT"; rc=$?
else
  timeout --signal=TERM "$LIMIT" claude --print --dangerously-skip-permissions "$PROMPT"; rc=$?
  [ "$rc" = "124" ] && echo "[entrypoint] session hit the ${LIMIT}s timeout and was stopped."
fi
echo "[entrypoint] Claude session exited rc=$rc"
exit $rc
