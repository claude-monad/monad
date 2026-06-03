# storage-mount-linux — auto-mount death-star's shared storage on every Linux client.
# system job → one alloc per Linux node (except the storage node itself). Mounts the NFS
# export at /mnt/deathstar and keeps it mounted. raw_exec runs as root, so it can mount.

job "storage-mount-linux" {
  datacenters = ["dc1"]
  type        = "system"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }
  # death-star already HAS the data locally — don't NFS-mount it onto itself.
  constraint {
    attribute = "${meta.role}"
    operator  = "!="
    value     = "storage"
  }

  group "mount" {
    count = 1
    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    task "nfs-mount" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["local/mount.sh"]
      }
      template {
        destination = "local/mount.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          IP="$${STORAGE_IP:-100.96.31.66}"
          MP="$${STORAGE_MOUNT:-/mnt/deathstar}"
          log() { echo "[storage-mount $(date '+%H:%M:%S')] $*"; }

          if ! command -v mount.nfs4 >/dev/null 2>&1 && ! command -v mount.nfs >/dev/null 2>&1; then
            log "installing nfs client…"; export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq && apt-get install -y -qq nfs-common >/dev/null 2>&1 || log "WARN: nfs-common install failed"
          fi
          mkdir -p "$MP" 2>/dev/null || true

          mounted() { mountpoint -q "$MP" 2>/dev/null || mount 2>/dev/null | grep -q " $MP "; }
          do_mount() {
            mount -t nfs4 -o rw,soft,timeo=30,retrans=2,_netdev "$IP:/" "$MP" 2>/dev/null \
              || mount -t nfs -o rw,soft,timeo=30,retrans=2,_netdev "$IP:/" "$MP" 2>/dev/null
          }

          if mounted; then log "already mounted at $MP"; else
            do_mount && log "mounted $IP:/ at $MP" || log "WARN: initial mount failed (will retry)"
          fi
          while true; do
            mounted || { log "remounting $MP…"; do_mount && log "remounted" || log "WARN: remount failed"; }
            sleep 120
          done
        SCRIPT
      }
      env {
        STORAGE_IP    = "100.96.31.66"
        STORAGE_MOUNT = "/mnt/deathstar"
      }
      resources {
        cpu    = 50
        memory = 64
      }
      kill_timeout = "10s"
    }
  }
}
