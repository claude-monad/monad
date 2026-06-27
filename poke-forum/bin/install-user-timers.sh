#!/usr/bin/env bash
# Install Poke Forum recurring sessions as user systemd timers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORUM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT_DIR="$FORUM_DIR/systemd"
USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$USER_DIR"
cp "$UNIT_DIR"/poke-*.service "$UNIT_DIR"/poke-*.timer "$USER_DIR"/

systemctl --user daemon-reload
systemctl --user enable --now poke-coordinator.timer poke-math-explorer.timer poke-math-investigator.timer
systemctl --user list-timers --all 'poke-*' --no-pager
