#!/usr/bin/env bash
# Agent-mesh container entrypoint: bring this agent onto the Tailscale mesh, then run it.
#
#   1. start the tsnet sidecar  → joins the tailnet as agent-<name> (own IP + mailbox)
#   2. wait for the local mesh API
#   3. run the agent (claude or codex) on PROMPT, with a briefing on how to talk to peers;
#      or, with no PROMPT, idle as a persistent mesh node (a reachable peer).
set -uo pipefail

: "${TS_AUTHKEY:?TS_AUTHKEY required (templated from secret/agent-mesh)}"
: "${AGENT_NAME:=agent-$(hostname)-$RANDOM}"
export AGENT_NAME
export LOCAL_PORT="${LOCAL_PORT:-8473}"
export MESH_PORT="${MESH_PORT:-8472}"
export TS_STATE_DIR="${TS_STATE_DIR:-/tmp/tsnet-$AGENT_NAME}"

echo "[agent-entrypoint] starting tsnet sidecar as '$AGENT_NAME'"
/usr/local/bin/tsnet-sidecar & SIDE=$!

for _ in $(seq 1 45); do
  curl -sf --max-time 3 "http://127.0.0.1:$LOCAL_PORT/whoami" >/dev/null 2>&1 && break
  sleep 1
done
WHO="$(curl -s --max-time 5 "http://127.0.0.1:$LOCAL_PORT/whoami" 2>/dev/null)"
echo "[agent-entrypoint] mesh identity: ${WHO:-<not up>}"

# git push auth (so builders can commit via monad) — configure a credential helper if a
# token was injected (templated from a Nomad secret by the job).
if [ -n "${GH_TOKEN:-}" ]; then
  git config --global credential.helper '!f() { echo username=x-access-token; echo "password=${GH_TOKEN}"; }; f' 2>/dev/null || true
  git config --global --add safe.directory /work 2>/dev/null || true
fi

# A ROLE (e.g. "builder") loads its prompt from the repo if no explicit PROMPT was given.
if [ -z "${PROMPT:-}" ] && [ -n "${ROLE:-}" ] && [ -f "/work/meta/agent/prompts/${ROLE}.md" ]; then
  PROMPT="$(cat "/work/meta/agent/prompts/${ROLE}.md")"
  echo "[agent-entrypoint] loaded role prompt: ${ROLE}"
fi

MESH_BRIEF="You are agent '$AGENT_NAME' on the Monad cluster's Tailscale agent mesh. Peer agents are reachable with the 'agent-msg' command: 'agent-msg peers' lists them, 'agent-msg send <peer-name> <text>' messages one, 'agent-msg recv' reads messages addressed to you. When a problem benefits from another node's perspective or work, coordinate with peers via these commands."

if [ -n "${PROMPT:-}" ]; then
  RA="${RUN_AGENT:-/work/meta/agent/run-agent.sh}"
  { printf '%s\n\n' "$MESH_BRIEF"; printf '%s' "$PROMPT"; } > /tmp/agent-prompt.txt
  echo "[agent-entrypoint] running agent (engine=${MONAD_ENGINE:-auto}) on prompt"
  exec "$RA" --engine "${MONAD_ENGINE:-auto}" --cwd /work --timeout "${AGENT_TIMEOUT:-2700}" "@/tmp/agent-prompt.txt"
else
  echo "[agent-entrypoint] no PROMPT — idling as a persistent mesh node (peers can reach me)"
  wait "$SIDE"
fi
