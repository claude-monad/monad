# samba-storage — native SMB/CIFS server on the storage node (death-star), exporting the
# SAME tree as NFS (/srv/samba/public) so Windows (windesk) and macOS (mac-mini) can mount
# death-star's 1.8 TB seamlessly (NFS is painful on Windows). Mirrors nfs-storage.hcl:
# a raw_exec watchdog manages native smbd. Auth: user from secret/samba; the tailnet is the
# network boundary. force user = root keeps files interoperable with the NFS export
# (no_root_squash). Clients: \\<death-star-tailnet-ip>\public  (smb://...  on macOS).

job "samba-storage" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${meta.role}"
    value     = "storage"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "smb" {
    count = 1

    network {
      port "smb" {
        static = 445
      }
    }

    task "smbd-watchdog" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/watchdog.sh"]
      }

      # SMB user + password from the encrypted Nomad variable.
      template {
        destination = "secrets/smb.env"
        env         = true
        data        = <<-EOT
          SMB_USER={{ with nomadVar "secret/samba" }}{{ .username }}{{ end }}
          SMB_PASS={{ with nomadVar "secret/samba" }}{{ .password }}{{ end }}
        EOT
      }

      template {
        destination = "local/watchdog.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          SHARE_PATH="$${SMB_SHARE_PATH:-/srv/samba/public}"
          SMB_USER="$${SMB_USER:-monad}"
          SMB_PASS="$${SMB_PASS:-}"
          log() { echo "[samba-storage $(date '+%H:%M:%S')] $*"; }

          # 1. Ensure samba is installed.
          if ! command -v smbd >/dev/null 2>&1; then
            log "installing samba…"
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq && apt-get install -y -qq samba || { log "ERROR: samba install failed"; sleep 120; exit 1; }
          fi

          mkdir -p "$SHARE_PATH"; chmod 0775 "$SHARE_PATH" 2>/dev/null || true

          # 2. Ensure the unix + samba user exists with the current password (idempotent).
          id "$SMB_USER" >/dev/null 2>&1 || useradd -M -s /usr/sbin/nologin "$SMB_USER"
          if [ -n "$SMB_PASS" ]; then
            printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -s -a "$SMB_USER" >/dev/null 2>&1 \
              || printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -s "$SMB_USER" >/dev/null 2>&1 || log "WARN: smbpasswd failed"
          fi

          # 3. Ensure the [public] share is configured (idempotent). Use echo lines (not a
          #    nested heredoc) to avoid terminator issues inside this HCL heredoc.
          if ! grep -q '^\[public\]' /etc/samba/smb.conf 2>/dev/null; then
            log "adding [public] share for $SHARE_PATH"
            {
              echo ""
              echo "[public]"
              echo "   path = $SHARE_PATH"
              echo "   browseable = yes"
              echo "   read only = no"
              echo "   guest ok = no"
              echo "   valid users = $SMB_USER"
              echo "   force user = root"
              echo "   create mask = 0664"
              echo "   directory mask = 0775"
            } >> /etc/samba/smb.conf
          fi

          # 4. Ensure smbd + nmbd are running.
          systemctl enable --now smbd nmbd >/dev/null 2>&1 || { service smbd restart >/dev/null 2>&1; service nmbd restart >/dev/null 2>&1; }
          log "smbd active; share '//<this-node>/public' → $SHARE_PATH; monitoring…"

          # 5. Watchdog loop.
          while true; do
            if ! (systemctl is-active smbd >/dev/null 2>&1 || service smbd status >/dev/null 2>&1); then
              log "WARN: smbd down, restarting…"
              systemctl restart smbd >/dev/null 2>&1 || service smbd restart >/dev/null 2>&1
            fi
            sleep 60
          done
        SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      service {
        name     = "samba-storage"
        port     = "smb"
        provider = "nomad"
        check {
          type     = "tcp"
          port     = "smb"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
