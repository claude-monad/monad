#!/usr/bin/env bash
# mac-storage-setup.sh — ONE-TIME setup to use death-star's shared storage on a Mac
# (e.g. mac-mini, low on disk). macOS requires root to mount network filesystems, which the
# unprivileged Nomad agent can't do — so run this once on the Mac with sudo:
#
#   sudo bash mac-storage-setup.sh
#
# It mounts death-star over NFS at /Volumes/deathstar (no password needed — the export is
# open to the tailnet) and installs a LaunchDaemon so it re-mounts automatically at boot.
set -uo pipefail
IP="${STORAGE_IP:-100.96.31.66}"
MP="${STORAGE_MOUNT:-/Volumes/deathstar}"
[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo bash $0"; exit 1; }

mkdir -p "$MP"
if mount | grep -q "$MP"; then
  echo "already mounted at $MP"
else
  mount -t nfs -o resvport,rw,soft,nolocks,locallocks "$IP:/" "$MP" \
    && echo "mounted $IP:/ at $MP" \
    || { echo "NFS mount failed; trying SMB (password is in: nomad var get secret/samba)"; \
         open "smb://monad@$IP/public" 2>/dev/null || true; }
fi

# Re-mount at boot via a LaunchDaemon.
PLIST=/Library/LaunchDaemons/com.monad.deathstar-storage.plist
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.monad.deathstar-storage</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string><string>-c</string>
    <string>/sbin/mount | /usr/bin/grep -q $MP || /sbin/mount_nfs -o resvport,rw,soft $IP:/ $MP</string>
  </array>
</dict></plist>
PL
launchctl load -w "$PLIST" 2>/dev/null || true
echo "installed boot auto-mount (LaunchDaemon: $PLIST)"
echo "death-star storage is at $MP — move bulky files there to free local disk."
