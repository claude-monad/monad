#!/usr/bin/env bash
# mesh-agent-loop — a REACTIVE LLM that converses with peers in real time over the mesh relay.
#
# The missing piece for inter-LLM comms: LLM sessions are one-shot, so messages used to sit in a
# queue until something polled. This loop makes an agent live: it long-polls the relay (idle =
# free, no busy-spin), and the instant a peer message arrives it feeds it to the engine (with
# conversational continuity) and dispatches any replies the LLM emits. Real back-and-forth.
#
# The LLM directs replies by emitting lines:  @<peer> <message>   (@all = broadcast).
#
# Env: AGENT_NAME (required), AGENT_ROLE (persona), MONAD_ENGINE (codex|claude, default codex),
#      MESH_RELAY, AGENT_GREET (optional opening broadcast), AGENT_MAX_TURNS (0=unlimited).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${AGENT_NAME:?set AGENT_NAME}"
: "${MESH_RELAY:=http://100.75.75.39:8477}"; export MESH_RELAY AGENT_NAME
ROLE="${AGENT_ROLE:-You are a collaborating agent in the Monad cluster, coordinating real work with peers.}"
ENGINE="${MONAD_ENGINE:-codex}"
MAXT="${AGENT_MAX_TURNS:-0}"
AM="bash $HERE/agent-msg.sh"
WORK="${AGENT_WORK:-/tmp/mesh-agent-$AGENT_NAME}"; mkdir -p "$WORK"
SID=""
log() { echo "[loop $AGENT_NAME $(date '+%H:%M:%S')] $*"; }

run_engine() {  # $1=prompt -> stdout reply
  local prompt="$1" o; o="$(mktemp)"
  if [ "$ENGINE" = codex ]; then
    if [ -n "$SID" ]; then
      codex exec resume --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -o "$o" "$SID" "$prompt" >/dev/null 2>&1
    else
      local raw; raw="$(mktemp)"
      codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -C "$WORK" -o "$o" "$prompt" >"$raw" 2>&1
      SID="$(grep -oiE 'session id:[[:space:]]*[0-9a-f-]{8,}' "$raw" | grep -oiE '[0-9a-f-]{8,}' | head -1)"
      rm -f "$raw"
    fi
    cat "$o" 2>/dev/null
  else
    printf '%s' "$prompt" | claude --print --dangerously-skip-permissions 2>/dev/null
  fi
  rm -f "$o" 2>/dev/null
}

$AM register >/dev/null 2>&1
log "online via $MESH_RELAY (engine=$ENGINE, role set)"
[ -n "${AGENT_GREET:-}" ] && { $AM send all "$AGENT_GREET" >/dev/null 2>&1; log "greeted: $AGENT_GREET"; }

turns=0
while true; do
  msgs="$($AM recv --wait 25 2>/dev/null)"
  $AM register >/dev/null 2>&1   # heartbeat keeps us "online" in /peers
  cnt="$(printf '%s' "$msgs" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  [ "${cnt:-0}" -gt 0 ] 2>/dev/null || continue
  log "received $cnt message(s)"
  incoming="$(printf '%s' "$msgs" | python3 -c 'import json,sys;[print("FROM %s: %s"%(m["from"],m["body"])) for m in json.load(sys.stdin)]' 2>/dev/null)"
  peers="$($AM peers 2>/dev/null)"
  prompt="$ROLE

You are agent '$AGENT_NAME' on the Monad cluster mesh. Peers seen: $peers
New messages to you:
$incoming

To reply, output lines EXACTLY as:  @<peer-name> <message>   (use @all to broadcast).
One line per message. If nothing needs saying, output nothing. Be concise and purposeful."
  reply="$(run_engine "$prompt")"
  printf '%s\n' "$reply" | grep -E '^@[A-Za-z0-9._-]+[[:space:]]' | while IFS= read -r line; do
    peer="$(printf '%s' "$line" | sed -E 's/^@([A-Za-z0-9._-]+)[[:space:]].*/\1/')"
    text="$(printf '%s' "$line" | sed -E 's/^@[A-Za-z0-9._-]+[[:space:]]+//')"
    $AM send "$peer" "$text" >/dev/null 2>&1 && log "-> $peer: $text"
  done
  turns=$((turns+1))
  if [ "$MAXT" -gt 0 ] && [ "$turns" -ge "$MAXT" ]; then log "reached max turns ($MAXT), exiting"; break; fi
done
