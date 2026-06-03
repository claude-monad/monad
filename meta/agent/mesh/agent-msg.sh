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
# Auto-discover the local sidecar port if not provided (mesh-attach writes this on attach),
# so any agent/delegated task can reach the mesh without env propagation.
[ -z "${LOCAL_PORT:-}" ] && [ -f /tmp/monad-mesh.env ] && . /tmp/monad-mesh.env 2>/dev/null || true
L="http://127.0.0.1:${LOCAL_PORT:-8473}"

# JSON-encode one string (no surrounding quotes) in pure bash, so `send` works on nodes
# without `jq` installed (e.g. death-star) — without it the POST body is malformed and
# the sidecar returns HTTP 400. Produces byte-identical output to `jq -Rn ...` for the
# characters that matter here (", \, control chars); UTF-8 bytes pass through unescaped,
# which is valid JSON.
json_escape() {
  local s=$1 out= c i code
  for (( i=0; i<${#s}; i++ )); do
    c=${s:i:1}
    case $c in
      '"')  out+='\"' ;;
      '\')  out+='\\' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *)
        printf -v code '%d' "'$c" 2>/dev/null || code=32
        if [ "$code" -ge 0 ] && [ "$code" -lt 32 ]; then
          out+=$(printf '\\u%04x' "$code")
        else
          out+=$c
        fi ;;
    esac
  done
  printf '%s' "$out"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  whoami) curl -s --max-time 8 "$L/whoami"; echo ;;
  peers)  curl -s --max-time 10 "$L/peers"; echo ;;
  recv)   curl -s --max-time 8 "$L/recv"; echo ;;
  send)
    to="${1:-}"; shift || true; body="$*"
    { [ -z "$to" ] || [ -z "$body" ]; } && { echo "usage: agent-msg send <peer> <message>" >&2; exit 2; }
    if command -v jq >/dev/null 2>&1; then
      payload="$(jq -nc --arg to "$to" --arg body "$body" '{to:$to,body:$body}')"
    else
      payload="{\"to\":\"$(json_escape "$to")\",\"body\":\"$(json_escape "$body")\"}"
    fi
    code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -XPOST "$L/send" \
      -H 'content-type: application/json' \
      -d "$payload")"
    [ "$code" = 204 ] && echo "sent to $to" || { echo "send failed (http $code)" >&2; exit 1; } ;;
  *) echo "usage: agent-msg {whoami|peers|send <peer> <msg>|recv}" >&2; exit 2 ;;
esac
