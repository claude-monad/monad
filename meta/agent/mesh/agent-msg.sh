#!/usr/bin/env bash
# agent-msg — coordinate with peer agents in real time over the mesh relay.
#
# Transport: a central relay (jobs/mesh-relay.hcl) reachable over the hosts' regular Tailscale,
# because ephemeral-tsnet P2P delivery between agent nodes was unreliable (dial timeouts). The
# relay supports long-poll, so `recv --wait N` blocks until a message arrives = real-time.
#
#   agent-msg whoami                 -> this agent's mesh name
#   agent-msg peers                  -> other agents the relay has seen [{name,online,age_s}]
#   agent-msg send <peer> <message…> -> send to peer <peer>  (peer "all" = broadcast)
#   agent-msg recv [--wait N]        -> drain inbox; with --wait, long-poll up to N seconds
#   agent-msg register               -> announce presence to the relay
#
# Env: AGENT_NAME (this agent's name), MESH_RELAY (relay base URL). If MESH_RELAY is unset it is
# discovered from the Nomad var infra/mesh-relay, else defaults to the leader v1410-1.
set -uo pipefail

[ -z "${AGENT_NAME:-}" ] && [ -f /tmp/monad-mesh.env ] && . /tmp/monad-mesh.env 2>/dev/null || true
NAME="${AGENT_NAME:-agent-$(hostname 2>/dev/null || echo unknown)}"

discover_relay() {
  [ -n "${MESH_RELAY:-}" ] && { echo "$MESH_RELAY"; return; }
  local v
  v="$(nomad var get -item=url infra/mesh-relay 2>/dev/null)"
  [ -n "$v" ] && { echo "$v"; return; }
  echo "http://100.75.75.39:8477"   # leader fallback
}
R="$(discover_relay)"

http_get() { # url timeout
  local url="$1" timeout="${2:-10}"
  if command -v curl >/dev/null 2>&1; then
    curl -s --max-time "$timeout" "$url"
    return
  fi
  python3 - "$url" "$timeout" <<'PY'
import sys, urllib.request
url, timeout = sys.argv[1], float(sys.argv[2])
with urllib.request.urlopen(url, timeout=timeout) as r:
    sys.stdout.write(r.read().decode())
PY
}

http_post() { # url json timeout [print_code]
  local url="$1" body="$2" timeout="${3:-10}" print_code="${4:-0}"
  if command -v curl >/dev/null 2>&1; then
    if [ "$print_code" = "1" ]; then
      curl -s --max-time "$timeout" -o /dev/null -w '%{http_code}' -XPOST "$url" \
        -H 'content-type: application/json' -d "$body"
    else
      curl -s --max-time "$timeout" -XPOST "$url" \
        -H 'content-type: application/json' -d "$body"
    fi
    return
  fi
  python3 - "$url" "$body" "$timeout" "$print_code" <<'PY'
import sys, urllib.request
url, body, timeout, print_code = sys.argv[1], sys.argv[2].encode(), float(sys.argv[3]), sys.argv[4] == "1"
req = urllib.request.Request(url, data=body, method="POST", headers={"content-type": "application/json"})
with urllib.request.urlopen(req, timeout=timeout) as r:
    if print_code:
        sys.stdout.write(str(r.status))
    else:
        sys.stdout.write(r.read().decode())
PY
}

json_escape() {  # pure-bash JSON string escape (nodes without jq, e.g. death-star)
  local s=$1 out= c i code
  for (( i=0; i<${#s}; i++ )); do c=${s:i:1}; case $c in
    '"') out+='\"';; '\') out+='\\';; $'\n') out+='\n';; $'\r') out+='\r';; $'\t') out+='\t';;
    *) printf -v code '%d' "'$c" 2>/dev/null || code=32
       if [ "$code" -ge 0 ] && [ "$code" -lt 32 ]; then out+=$(printf '\\u%04x' "$code"); else out+=$c; fi;;
  esac; done; printf '%s' "$out"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  whoami) echo "$NAME" ;;
  register)
    http_post "$R/register" "{\"name\":\"$(json_escape "$NAME")\"}" 8 >/dev/null && echo "registered $NAME at $R" ;;
  peers)  http_get "$R/peers?self=$NAME" 10; echo ;;
  recv)
    wait=0; [ "${1:-}" = "--wait" ] && wait="${2:-25}"
    http_get "$R/recv?agent=$NAME&wait=$wait" "$((wait+10))"; echo ;;
  send)
    to="${1:-}"; shift || true; body="$*"
    { [ -z "$to" ] || [ -z "$body" ]; } && { echo "usage: agent-msg send <peer> <message>" >&2; exit 2; }
    payload="{\"from\":\"$(json_escape "$NAME")\",\"to\":\"$(json_escape "$to")\",\"body\":\"$(json_escape "$body")\"}"
    code="$(http_post "$R/send" "$payload" 12 1)"
    [ "$code" = 204 ] && echo "sent to $to" || { echo "send failed (http $code) via $R" >&2; exit 1; } ;;
  *) echo "usage: agent-msg {whoami|peers|send <peer> <msg>|recv [--wait N]|register}" >&2; exit 2 ;;
esac
