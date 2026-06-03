#!/usr/bin/env bash
# Build the math-agent-relay binary and install it to ~/monad/bin/.
# Run this once on each new machine (windesk, mac-mini, etc.) after joining the cluster.
#
# Usage: bash meta/tsnet-relay/build.sh
#
# Requires: Go 1.22+, TS_AUTHKEY env var (for running), internet access (for go mod download).
# On mac-mini (no internet): pre-download the module cache on a connected machine and rsync it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONAD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_DIR="$MONAD_ROOT/bin"
mkdir -p "$BIN_DIR"

echo "==> Downloading dependencies..."
cd "$SCRIPT_DIR"
go mod download

echo "==> Building math-agent-relay..."
go build -o "$BIN_DIR/math-agent-relay" .

echo "==> Installed: $BIN_DIR/math-agent-relay"
echo ""
echo "To run manually:"
echo "  TS_AUTHKEY=<key> $BIN_DIR/math-agent-relay --machine \$(cat ~/.machine-id 2>/dev/null || hostname) --repo ~/Documents/GitHub/math"
echo ""
echo "The Nomad job (jobs/math-agent-relay.hcl) will run it automatically once math_agent=true"
echo "is set in this node's Nomad client config (meta block)."
