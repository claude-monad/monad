#!/usr/bin/env bash
# enable-autonomous.sh — turn THIS node into an autonomous containerized-dispatch
# node, configured the same way as oraclebox1. Run once, after the node has:
#   * joined the cluster   (meta/bootstrap/join.sh)
#   * logged into Claude    (run `claude` once)
#   * logged into GitHub     (gh auth login)
#
# It builds the session image, verifies containerized Claude auth, and installs
# the auto-dispatch cron (one isolated containerized research session at a time,
# chosen + deduped by the frontier dispatcher).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${AUTO_DISPATCH_INTERVAL:-15}"   # minutes

echo "[enable] 1/3 building session image ..."
bash "$HERE/build-image.sh" || { echo "[enable] image build failed." >&2; exit 1; }

echo "[enable] 2/3 verifying containerized Claude auth ..."
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^session-'; then
  echo "[enable]   a session is already running — assuming auth OK, skipping the check."
elif bash "$HERE/auth-check.sh" 2>&1 | grep -q AUTHENTICATED; then
  echo "[enable]   auth OK (AUTHENTICATED)."
else
  echo "[enable] AUTH FAILED — run 'claude' on this host to log in, then re-run." >&2
  exit 1
fi

echo "[enable] 3/3 installing auto-dispatch cron (every ${INTERVAL} min) ..."
LINE="*/${INTERVAL} * * * * ${HERE}/auto-dispatch.sh >> /tmp/auto-dispatch.log 2>&1"
if crontab -l 2>/dev/null | grep -q "auto-dispatch.sh"; then
  echo "[enable]   cron already present."
else
  ( crontab -l 2>/dev/null; echo "$LINE" ) | crontab -
  echo "[enable]   installed."
fi

ACCT="$(grep -oP 'claude_account\s*=\s*"\K[^"]+' /etc/nomad.d/nomad.hcl 2>/dev/null | head -1)"
echo "[enable] DONE — this node now autonomously runs containerized '${ACCT:-?}' sessions."
echo "[enable] watch: tail -f /tmp/auto-dispatch.log ; sudo docker ps"
