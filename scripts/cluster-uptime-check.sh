#!/bin/bash
# cluster-uptime-check.sh — measure cluster connectivity and Nomad health
# Runs periodically on the server node via the cluster-uptime Nomad job.
# Logs to logs/cluster-uptime.jsonl, maintains logs/cluster-uptime-summary.json.
set -uo pipefail

MONAD_DIR="${MONAD_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Detect Nomad address
if [ -z "${NOMAD_ADDR:-}" ]; then
  MY_IP=$(grep -oP 'bind_addr\s*=\s*"\K[^"]+' /etc/nomad.d/nomad.hcl 2>/dev/null || echo "127.0.0.1")
  export NOMAD_ADDR="http://${MY_IP}:4646"
fi

exec python3 "$MONAD_DIR/scripts/cluster-uptime-check.py" "$MONAD_DIR"
