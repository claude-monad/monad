#!/usr/bin/env bash
# migrate-mac.sh — Copy media from macOS machine to death-star storage via S3 (MinIO)
# Uses curl for S3 uploads — no root access or mount required.
set -uo pipefail

STORAGE_IP="100.96.31.66"
MINIO_URL="http://${STORAGE_IP}:9000"
MINIO_USER="monad-admin"
MINIO_PASS="7flNW73Yiq0V4dMGVAhAH9CngRPgXBaZ"
HOME_DIR="$HOME"
LOG="/tmp/monad-migration.log"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
report() {
    # Write progress to Nomad variable so we can monitor remotely
    nomad var put -force -address "$NOMAD_ADDR" monad/migration/mac-mini \
        status="$1" last_update="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        message="$2" 2>/dev/null || true
}

log "=== MAC MINI MEDIA MIGRATION ==="
log "Source: $HOME_DIR"
log "Destination: $MINIO_URL (S3)"

# Install mc if not present
if ! command -v mc &>/dev/null; then
    log "Installing MinIO client (mc)..."
    curl -fsSL "https://dl.min.io/client/mc/release/darwin-arm64/mc" -o /tmp/mc 2>&1
    chmod +x /tmp/mc
    MC="/tmp/mc"
else
    MC="mc"
fi

# Configure mc
$MC alias set monad "$MINIO_URL" "$MINIO_USER" "$MINIO_PASS" 2>&1 | tee -a "$LOG"
log "S3 client configured"
report "running" "S3 client configured, starting migration"

TOTAL_BYTES=0
FILE_COUNT=0

upload_dir() {
    local src="$1" bucket="$2" prefix="$3"
    if [ ! -d "$src" ]; then
        log "  Skip (not found): $src"
        return
    fi
    local size
    size=$(du -sh "$src" 2>/dev/null | cut -f1)
    log "  $src ($size) -> monad/$bucket/$prefix/"
    $MC mirror --overwrite --preserve "$src/" "monad/$bucket/$prefix/" 2>&1 | tail -5 | tee -a "$LOG"
}

upload_file() {
    local src="$1" bucket="$2"
    local name
    name=$(basename "$src")
    local sizeh
    sizeh=$(du -sh "$src" 2>/dev/null | cut -f1)
    log "  Uploading: $name ($sizeh)"
    $MC cp "$src" "monad/$bucket/$name" 2>&1 | tail -1 | tee -a "$LOG"
}

# --- Photo Libraries (the important ones) ---
log ""
log "=== PHOTO LIBRARIES ==="
report "running" "Migrating photo libraries"
find "$HOME_DIR" -maxdepth 5 \( -name "*.photoslibrary" -o -name "*.aplibrary" \) -prune 2>/dev/null | while read lib; do
    BASENAME=$(basename "$lib")
    SIZE=$(du -sh "$lib" 2>/dev/null | cut -f1)
    log "Photo library: $lib ($SIZE)"
    report "running" "Photo library: $BASENAME ($SIZE)"
    $MC mirror --overwrite --preserve "$lib/" "monad/media/photo-libraries/mac-mini/$BASENAME/" 2>&1 | tail -5 | tee -a "$LOG"
    log "  Done: $BASENAME"
done

# Also check /Volumes
for vol in /Volumes/*/; do
    VOLNAME=$(basename "$vol")
    [ "$VOLNAME" = "Macintosh HD" ] && continue
    [ "$VOLNAME" = "Recovery" ] && continue
    find "$vol" -maxdepth 3 \( -name "*.photoslibrary" -o -name "*.aplibrary" \) -prune 2>/dev/null | while read lib; do
        BASENAME=$(basename "$lib")
        SIZE=$(du -sh "$lib" 2>/dev/null | cut -f1)
        log "External photo library: $lib ($SIZE)"
        report "running" "External lib: $BASENAME ($SIZE)"
        $MC mirror --overwrite --preserve "$lib/" "monad/media/photo-libraries/mac-mini/$BASENAME/" 2>&1 | tail -5 | tee -a "$LOG"
    done
done

# --- Pictures ---
log ""
log "=== PICTURES ==="
report "running" "Migrating Pictures"
if [ -d "$HOME_DIR/Pictures" ]; then
    upload_dir "$HOME_DIR/Pictures" "media" "photos/mac-mini"
fi

# --- Movies ---
log ""
log "=== MOVIES ==="
report "running" "Migrating Movies"
if [ -d "$HOME_DIR/Movies" ]; then
    upload_dir "$HOME_DIR/Movies" "media" "videos/mac-mini"
fi

# --- Music ---
log ""
log "=== MUSIC ==="
report "running" "Migrating Music"
if [ -d "$HOME_DIR/Music" ]; then
    upload_dir "$HOME_DIR/Music" "media" "music/mac-mini"
fi

# --- Documents ---
log ""
log "=== DOCUMENTS ==="
report "running" "Migrating Documents"
if [ -d "$HOME_DIR/Documents" ]; then
    upload_dir "$HOME_DIR/Documents" "media" "documents/mac-mini"
fi

# --- Large downloads ---
log ""
log "=== LARGE DOWNLOADS ==="
report "running" "Migrating large downloads"
if [ -d "$HOME_DIR/Downloads" ]; then
    find "$HOME_DIR/Downloads" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.iso" -o -iname "*.dmg" \) -size +50M 2>/dev/null | while read f; do
        upload_file "$f" "media/downloads"
    done
fi

# --- Summary ---
log ""
log "=== MIGRATION SUMMARY ==="
$MC ls monad/media/ 2>/dev/null | tee -a "$LOG" || true
log ""
log "=== MIGRATION COMPLETE ==="
report "done" "Migration complete"

# Cleanup
[ -f /tmp/mc ] && rm -f /tmp/mc
