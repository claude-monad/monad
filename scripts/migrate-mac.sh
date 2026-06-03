#!/usr/bin/env bash
# migrate-mac.sh — Copy media from macOS machine to death-star storage
set -uo pipefail

STORAGE_IP="100.96.31.66"
NFS_EXPORT="/srv/samba/public"
MOUNT_POINT="/tmp/monad-storage"
MEDIA="$MOUNT_POINT/media"
HOME_DIR="$HOME"
LOG="/tmp/monad-migration.log"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== MAC MINI MEDIA MIGRATION ==="
log "Source: $HOME_DIR"
log "Destination: $STORAGE_IP:$NFS_EXPORT/media"
log ""

# Mount NFS
mkdir -p "$MOUNT_POINT"
if mount | grep -q "$MOUNT_POINT"; then
    log "NFS already mounted"
else
    log "Mounting NFS..."
    mount -t nfs -o resvport,rw,soft,timeo=30,retrans=3 \
        "$STORAGE_IP:$NFS_EXPORT" "$MOUNT_POINT" 2>&1 | tee -a "$LOG"
    if ! mount | grep -q "$MOUNT_POINT"; then
        log "NFS failed. Trying SMB..."
        mount -t smbfs "//monad:monad@$STORAGE_IP/media" "$MOUNT_POINT" 2>&1 | tee -a "$LOG"
        MEDIA="$MOUNT_POINT"
        if ! mount | grep -q "$MOUNT_POINT"; then
            log "ERROR: Cannot mount storage. Aborting."
            exit 1
        fi
    fi
fi
log "Storage mounted at $MOUNT_POINT"

# Create destination dirs
mkdir -p "$MEDIA/photos/mac-mini" "$MEDIA/videos/mac-mini" \
         "$MEDIA/music/mac-mini" "$MEDIA/documents/mac-mini" \
         "$MEDIA/photo-libraries/mac-mini" "$MEDIA/downloads" 2>/dev/null || true

# --- Photo Libraries ---
log ""
log "=== MIGRATING PHOTO LIBRARIES ==="
find "$HOME_DIR" -maxdepth 5 \( -name "*.photoslibrary" -o -name "*.aplibrary" \) -prune 2>/dev/null | while read lib; do
    BASENAME=$(basename "$lib")
    DEST="$MEDIA/photo-libraries/mac-mini/$BASENAME"
    SIZE=$(du -sh "$lib" 2>/dev/null | cut -f1)
    log "Photo library: $lib ($SIZE)"
    mkdir -p "$DEST"
    rsync -a --partial --no-perms --no-owner --no-group \
        "$lib/" "$DEST/" 2>&1 | tail -3 | tee -a "$LOG"
    log "  Done: $BASENAME"
done

# Also check /Volumes for external photo libraries
for vol in /Volumes/*/; do
    VOLNAME=$(basename "$vol")
    [ "$VOLNAME" = "Macintosh HD" ] && continue
    [ "$VOLNAME" = "Recovery" ] && continue
    find "$vol" -maxdepth 3 \( -name "*.photoslibrary" -o -name "*.aplibrary" \) -prune 2>/dev/null | while read lib; do
        BASENAME=$(basename "$lib")
        DEST="$MEDIA/photo-libraries/mac-mini/$BASENAME"
        SIZE=$(du -sh "$lib" 2>/dev/null | cut -f1)
        log "External photo library: $lib ($SIZE)"
        mkdir -p "$DEST"
        rsync -a --partial --no-perms --no-owner --no-group \
            "$lib/" "$DEST/" 2>&1 | tail -3 | tee -a "$LOG"
        log "  Done: $BASENAME"
    done
done

# --- Pictures ---
log ""
log "=== MIGRATING PICTURES ==="
if [ -d "$HOME_DIR/Pictures" ]; then
    SIZE=$(du -sh "$HOME_DIR/Pictures" 2>/dev/null | cut -f1)
    log "Pictures ($SIZE) -> $MEDIA/photos/mac-mini/"
    rsync -a --partial --no-perms --no-owner --no-group \
        --exclude '*.photoslibrary' --exclude '*.aplibrary' \
        "$HOME_DIR/Pictures/" "$MEDIA/photos/mac-mini/" 2>&1 | tail -3 | tee -a "$LOG"
fi

# --- Movies ---
log ""
log "=== MIGRATING MOVIES ==="
if [ -d "$HOME_DIR/Movies" ]; then
    SIZE=$(du -sh "$HOME_DIR/Movies" 2>/dev/null | cut -f1)
    log "Movies ($SIZE) -> $MEDIA/videos/mac-mini/"
    rsync -a --partial --no-perms --no-owner --no-group \
        "$HOME_DIR/Movies/" "$MEDIA/videos/mac-mini/" 2>&1 | tail -3 | tee -a "$LOG"
fi

# --- Music (including iTunes/Apple Music) ---
log ""
log "=== MIGRATING MUSIC ==="
if [ -d "$HOME_DIR/Music" ]; then
    SIZE=$(du -sh "$HOME_DIR/Music" 2>/dev/null | cut -f1)
    log "Music ($SIZE) -> $MEDIA/music/mac-mini/"
    rsync -a --partial --no-perms --no-owner --no-group \
        "$HOME_DIR/Music/" "$MEDIA/music/mac-mini/" 2>&1 | tail -3 | tee -a "$LOG"
fi

# --- Documents ---
log ""
log "=== MIGRATING DOCUMENTS ==="
if [ -d "$HOME_DIR/Documents" ]; then
    SIZE=$(du -sh "$HOME_DIR/Documents" 2>/dev/null | cut -f1)
    log "Documents ($SIZE) -> $MEDIA/documents/mac-mini/"
    rsync -a --partial --no-perms --no-owner --no-group \
        "$HOME_DIR/Documents/" "$MEDIA/documents/mac-mini/" 2>&1 | tail -3 | tee -a "$LOG"
fi

# --- Large downloads ---
log ""
log "=== MIGRATING LARGE DOWNLOADS ==="
if [ -d "$HOME_DIR/Downloads" ]; then
    find "$HOME_DIR/Downloads" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.iso" -o -iname "*.dmg" -o -iname "*.zip" \) -size +50M 2>/dev/null | while read f; do
        BASENAME=$(basename "$f")
        DEST="$MEDIA/downloads/$BASENAME"
        if [ ! -f "$DEST" ]; then
            SIZE=$(du -sh "$f" 2>/dev/null | cut -f1)
            log "  Copying: $BASENAME ($SIZE)"
            cp "$f" "$MEDIA/downloads/"
        else
            log "  Skip (exists): $BASENAME"
        fi
    done
fi

# --- Summary ---
log ""
log "=== MIGRATION SUMMARY ==="
du -sh "$MEDIA"/* 2>/dev/null | tee -a "$LOG" || true
log ""
log "=== MIGRATION COMPLETE ==="

# Unmount
umount "$MOUNT_POINT" 2>/dev/null || true
