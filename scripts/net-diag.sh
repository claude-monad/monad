#!/usr/bin/env bash
# Lightweight network probe for raw_exec nodes.

set -euo pipefail

LOOP_SECONDS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --loop)
      LOOP_SECONDS="${2:-0}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

SERVER_URL="${NOMAD_ADDR:-http://100.75.75.39:4646}"
INTERVAL="${NET_DIAG_INTERVAL:-60}"

probe_once() {
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  host="$(hostname 2>/dev/null || echo unknown)"
  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -1 || true)"

  if curl -fsS --connect-timeout 5 "${SERVER_URL}/v1/status/leader" >/dev/null 2>&1; then
    nomad_status="ok"
  else
    nomad_status="fail"
  fi

  printf '%s host=%s tailscale_ip=%s nomad=%s server=%s\n' \
    "$ts" "$host" "${tailscale_ip:-none}" "$nomad_status" "$SERVER_URL"
}

if [ "$LOOP_SECONDS" -gt 0 ]; then
  end=$(( $(date +%s) + LOOP_SECONDS ))
  while [ "$(date +%s)" -lt "$end" ]; do
    probe_once
    sleep "$INTERVAL"
  done
else
  probe_once
fi
