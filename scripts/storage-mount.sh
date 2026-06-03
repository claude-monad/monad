#!/usr/bin/env bash
# storage-mount.sh — Mount death-star cluster storage on any platform.
#
# Usage:
#   Linux/macOS:  curl -sL <raw-url> | bash
#   Or locally:   ./storage-mount.sh [mount|unmount|status|setup-s3]
#
# Picks the best protocol per OS:
#   Linux  → NFS (fastest, native kernel mount)
#   macOS  → NFS (native, no extra software)
#   Windows → Run storage-mount.ps1 instead (SMB native)
#
# All traffic runs over Tailscale — no port forwarding or VPN needed.
set -euo pipefail

STORAGE_IP="100.96.31.66"
STORAGE_HOST="death-star"
NFS_EXPORT="/srv/samba/public"
MOUNT_POINT="${MONAD_MOUNT:-/mnt/monad}"
MINIO_URL="http://${STORAGE_IP}:9000"
MINIO_CONSOLE="http://${STORAGE_IP}:9001"

ok()   { echo "  ✓ $*"; }
err()  { echo "  ✗ $*" >&2; }
step() { echo ""; echo "==> $*"; }

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "mac" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

check_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        err "Tailscale not installed. Get it at https://tailscale.com/download"
        return 1
    fi
    if ! tailscale ip -4 &>/dev/null; then
        err "Tailscale not connected. Run: tailscale up"
        return 1
    fi
    ok "Tailscale connected"
}

check_storage_reachable() {
    if curl -sf --connect-timeout 3 "${MINIO_URL}/minio/health/live" &>/dev/null; then
        ok "Storage node reachable (${STORAGE_HOST} / ${STORAGE_IP})"
    else
        err "Cannot reach storage node at ${STORAGE_IP}. Is death-star online?"
        return 1
    fi
}

cmd_mount() {
    local OS
    OS="$(detect_os)"

    step "Mounting cluster storage"
    check_tailscale
    check_storage_reachable

    case "$OS" in
        linux)  mount_nfs_linux ;;
        mac)    mount_nfs_mac ;;
        windows)
            err "On Windows, use: .\\storage-mount.ps1"
            err "Or mount manually: net use Z: \\\\${STORAGE_IP}\\public"
            return 1
            ;;
        *)
            err "Unknown OS: $(uname -s). Use S3 access instead:"
            err "  mc alias set monad ${MINIO_URL} <user> <pass>"
            return 1
            ;;
    esac
}

mount_nfs_linux() {
    step "Mounting via NFS (Linux)"

    # Ensure NFS client tools are available
    if ! command -v mount.nfs &>/dev/null && ! command -v mount.nfs4 &>/dev/null; then
        echo "  Installing NFS client..."
        sudo apt-get install -y -qq nfs-common 2>/dev/null \
          || sudo yum install -y -q nfs-utils 2>/dev/null \
          || sudo pacman -S --noconfirm nfs-utils 2>/dev/null \
          || { err "Could not install NFS client. Install nfs-common manually."; return 1; }
    fi

    sudo mkdir -p "$MOUNT_POINT"

    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        ok "Already mounted at $MOUNT_POINT"
        return 0
    fi

    sudo mount -t nfs "${STORAGE_IP}:${NFS_EXPORT}" "$MOUNT_POINT" \
        -o rw,nolock,soft,timeo=30,retrans=3
    ok "Mounted at $MOUNT_POINT"

    # Offer to persist in fstab
    if ! grep -q "${STORAGE_IP}:${NFS_EXPORT}" /etc/fstab 2>/dev/null; then
        echo ""
        echo "  To mount automatically at boot, add to /etc/fstab:"
        echo "  ${STORAGE_IP}:${NFS_EXPORT}  ${MOUNT_POINT}  nfs  rw,nolock,soft,timeo=30,retrans=3,_netdev  0  0"
    fi
}

mount_nfs_mac() {
    step "Mounting via NFS (macOS)"

    sudo mkdir -p "$MOUNT_POINT"

    if mount | grep -q "$MOUNT_POINT" 2>/dev/null; then
        ok "Already mounted at $MOUNT_POINT"
        return 0
    fi

    # macOS NFS mount — resvport needed for macOS NFS client
    sudo mount -t nfs -o resvport,rw,soft,timeo=30,retrans=3 \
        "${STORAGE_IP}:${NFS_EXPORT}" "$MOUNT_POINT"
    ok "Mounted at $MOUNT_POINT"

    echo ""
    echo "  To mount at boot, add to /etc/auto_master or use:"
    echo "    sudo vifs  # add: ${STORAGE_IP}:${NFS_EXPORT} ${MOUNT_POINT} nfs resvport,rw,soft"
}

cmd_unmount() {
    step "Unmounting cluster storage"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null || mount | grep -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT"
        ok "Unmounted $MOUNT_POINT"
    else
        echo "  Not currently mounted at $MOUNT_POINT"
    fi
}

cmd_status() {
    step "Cluster Storage Status"
    echo "  Storage node:  ${STORAGE_HOST} (${STORAGE_IP})"
    echo "  NFS export:    ${NFS_EXPORT}"
    echo "  S3 endpoint:   ${MINIO_URL}"
    echo "  S3 console:    ${MINIO_CONSOLE}"
    echo ""

    # Reachability
    check_storage_reachable || true

    # Mount status
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null || mount | grep -q "$MOUNT_POINT" 2>/dev/null; then
        ok "NFS mounted at $MOUNT_POINT"
        df -h "$MOUNT_POINT" 2>/dev/null | tail -1 | awk '{print "     Size: "$2"  Used: "$3"  Avail: "$4"  Use%: "$5}'
    else
        echo "  NFS not mounted (run: monad storage mount)"
    fi

    # S3 buckets
    if command -v mc &>/dev/null && mc alias list monad &>/dev/null 2>&1; then
        echo ""
        echo "  S3 Buckets:"
        mc ls monad/ 2>/dev/null | while read -r line; do echo "    $line"; done
    fi
}

cmd_setup_s3() {
    step "Setting up S3 (MinIO) client"

    # Install mc if needed
    if ! command -v mc &>/dev/null; then
        local OS
        OS="$(detect_os)"
        echo "  Installing MinIO client (mc)..."
        case "$OS" in
            linux)
                local ARCH
                ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
                curl -fsSL "https://dl.min.io/client/mc/release/linux-${ARCH}/mc" -o /tmp/mc
                chmod +x /tmp/mc && sudo mv /tmp/mc /usr/local/bin/mc
                ;;
            mac)
                if command -v brew &>/dev/null; then
                    brew install minio/stable/mc
                else
                    curl -fsSL "https://dl.min.io/client/mc/release/darwin-amd64/mc" -o /tmp/mc
                    chmod +x /tmp/mc && sudo mv /tmp/mc /usr/local/bin/mc
                fi
                ;;
            *)
                err "Install mc manually: https://min.io/docs/minio/linux/reference/minio-mc.html"
                return 1
                ;;
        esac
        ok "mc installed"
    else
        ok "mc already installed"
    fi

    # Fetch credentials from Nomad if available
    local USER="monad-admin"
    local PASS=""
    if command -v nomad &>/dev/null; then
        PASS=$(NOMAD_ADDR=http://100.75.75.39:4646 nomad var get -json nomad/jobs/minio-storage 2>/dev/null \
            | python3 -c "import sys,json; print(json.load(sys.stdin)['Items']['MINIO_ROOT_PASSWORD'])" 2>/dev/null || true)
    fi

    if [ -n "$PASS" ]; then
        mc alias set monad "$MINIO_URL" "$USER" "$PASS" 2>&1
        ok "S3 alias 'monad' configured"
        echo ""
        echo "  Usage:"
        echo "    mc ls monad/                       # list buckets"
        echo "    mc cp file.txt monad/scratch/      # upload a file"
        echo "    mc cp monad/math-results/out.txt . # download a file"
        echo "    mc find monad/ --name '*.py'       # search files"
    else
        echo "  Could not auto-fetch credentials. Configure manually:"
        echo "    mc alias set monad ${MINIO_URL} <user> <password>"
        echo ""
        echo "  Get credentials from any cluster node:"
        echo "    NOMAD_ADDR=http://100.75.75.39:4646 nomad var get nomad/jobs/minio-storage"
    fi
}

usage() {
    cat <<'USAGE'
storage-mount.sh — Mount or access death-star cluster storage

Commands:
  mount       Mount storage via NFS (Linux/macOS) or SMB (Windows)
  unmount     Unmount storage
  status      Show storage status and capacity
  setup-s3    Install and configure MinIO S3 client (works everywhere)

Environment:
  MONAD_MOUNT   Override mount point (default: /mnt/monad)

Protocols by platform:
  Linux     NFS (port 2049 over Tailscale)
  macOS     NFS (port 2049 over Tailscale)
  Windows   SMB (port 445 over Tailscale) — use storage-mount.ps1

Universal S3 access (any platform):
  mc alias set monad http://100.96.31.66:9000 <user> <pass>
  mc cp localfile.txt monad/bucket-name/
USAGE
}

CMD="${1:-}"
case "$CMD" in
    mount)     cmd_mount ;;
    unmount)   cmd_unmount ;;
    status)    cmd_status ;;
    setup-s3)  cmd_setup_s3 ;;
    help|--help|-h|"") usage ;;
    *)
        err "Unknown command: $CMD"
        usage
        exit 1
        ;;
esac
