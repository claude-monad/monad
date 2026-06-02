#!/usr/bin/env bash
# agent-msg — coordinate with peer agents over the tailnet via the local tsnet sidecar.
#
# Every mesh agent has this. The sidecar (running beside the LLM) exposes a local API;
# this wraps it so an agent can discover and talk to peers with simple commands:
#
#   agent-msg whoami                 -> this agent's mesh name + tailnet IP
#   agent-msg peers                  -> other agent-* nodes on the tailnet [{name,ip}]
#   agent-msg send <peer> <message…> -> send a message to peer <peer>
#   agent-msg recv                   -> drain + print messages sent to this agent
set -uo pipefail
L="http://127.0.0.1:${LOCAL_PORT:-8473}"
cmd="${1:-}"; shift || true
case "$cmd" in
  whoami) curl -s --max-time 8 "$L/whoami"; echo ;;
  peers)  curl -s --max-time 10 "$L/peers"; echo ;;
  recv)   curl -s --max-time 8 "$L/recv"; echo ;;
  send)
    to="${1:-}"; shift || true; body="$*"
    { [ -z "$to" ] || [ -z "$body" ]; } && { echo "usage: agent-msg send <peer> <message>" >&2; exit 2; }
    code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -XPOST "$L/send" \
      -H 'content-type: application/json' \
      -d "$(jq -nc --arg to "$to" --arg body "$body" '{to:$to,body:$body}')")"
    [ "$code" = 204 ] && echo "sent to $to" || { echo "send failed (http $code)" >&2; exit 1; } ;;
  *) echo "usage: agent-msg {whoami|peers|send <peer> <msg>|recv}" >&2; exit 2 ;;
esac
