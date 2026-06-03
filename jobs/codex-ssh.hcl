# codex-ssh — on every Linux node, run a dedicated plain sshd on :2222 with an `autocodex`
# passwordless-sudo user, so the ChatGPT Codex iOS app can SSH in (custom port 2222) and run
# Codex there. Tailscale SSH on :22 is left untouched (this is a separate sshd on 2222, which
# Tailscale SSH does not intercept). Key auth only; the app's public key comes from
# secret/codex-ssh. Codex auth is shared from the node's logged-in codex user.

job "codex-ssh" {
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

  group "ssh" {
    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    network {
      mode = "host"
      port "ssh2222" {
        static = 2222
      }
    }

    task "sshd" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      template {
        destination = "local/key.pub"
        data        = "{{ with nomadVar \"secret/codex-ssh\" }}{{ .pubkey }}{{ end }}\n"
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          U=autocodex
          log() { echo "[codex-ssh $(date '+%H:%M:%S')] $*"; }

          id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
          # useradd leaves the password LOCKED ('!'), and sshd refuses ALL logins (even pubkey)
          # to a locked account. Set it to '*' = no password but unlocked, so key auth works.
          usermod -p '*' "$U"
          echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/autocodex && chmod 440 /etc/sudoers.d/autocodex
          H="$(getent passwd "$U" | cut -d: -f6)"
          # sshd StrictModes: HOME + ~/.ssh must be owned by the user and not group/world-writable,
          # or pubkey auth is silently rejected. Enforce it (the user may have pre-existed home-less).
          mkdir -p "$H"; chown "$U:$U" "$H"; chmod 0755 "$H"
          install -d -m 700 -o "$U" -g "$U" "$H/.ssh"

          KP="$NOMAD_TASK_DIR/key.pub"
          if [ -s "$KP" ] && grep -q ssh "$KP"; then
            cp "$KP" "$H/.ssh/authorized_keys"
            chmod 600 "$H/.ssh/authorized_keys"; chown "$U:$U" "$H/.ssh/authorized_keys"
            log "installed app pubkey for $U"
          else
            log "no app pubkey in secret/codex-ssh yet — set it to grant access"
          fi

          # Share codex auth from the node's logged-in codex user so `autocodex` can run codex.
          for au in e ubuntu bigo eliott; do
            ah="$(getent passwd "$au" | cut -d: -f6)"; [ -n "$ah" ] || continue
            if [ -f "$ah/.codex/auth.json" ]; then
              [ -e "$H/.codex" ] || ln -s "$ah/.codex" "$H/.codex"
              log "codex auth shared from $au"; break
            fi
          done

          mkdir -p /run/sshd 2>/dev/null || true
          CFG="$NOMAD_TASK_DIR/sshd_autocodex.conf"
          {
            echo "Port 2222"
            echo "PermitRootLogin no"
            echo "PasswordAuthentication no"
            echo "PubkeyAuthentication yes"
            echo "AllowUsers autocodex"
            echo "PidFile $NOMAD_TASK_DIR/sshd.pid"
            for k in /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_ecdsa_key; do
              [ -f "$k" ] && echo "HostKey $k"
            done
          } > "$CFG"
          command -v codex >/dev/null 2>&1 || log "WARN: codex not on PATH for sshd sessions"
          # Kill any orphaned autocodex sshd from a prior alloc so this fresh one can bind :2222.
          pkill -f sshd_autocodex.conf 2>/dev/null && sleep 1 || true
          log "autocodex ready; starting sshd on :2222"
          exec /usr/sbin/sshd -D -e -f "$CFG"
        SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
