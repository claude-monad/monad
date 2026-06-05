# codex-ssh — on every Linux node, run a dedicated plain sshd on :2222 with an `autocodex`
# passwordless-sudo user, so the ChatGPT Codex iOS app can SSH in (custom port 2222) and run
# Codex there. Tailscale SSH on :22 is left untouched (this is a separate sshd on 2222, which
# Tailscale SSH does not intercept). The app's public key and optional password hash come from
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
        destination = "local/password_hash"
        data        = "{{ with nomadVar \"secret/codex-ssh\" }}{{ .password_hash }}{{ end }}\n"
      }

      template {
        destination = "local/password"
        data        = "{{ with nomadVar \"secret/codex-ssh\" }}{{ .password }}{{ end }}\n"
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          U=autocodex
          log() { echo "[codex-ssh $(date '+%H:%M:%S')] $*"; }
          # On a system job, a task that exits (even 0) is restarted by the restart policy, so a
          # plain `exit` would still restart-storm + pin the alloc `pending`. To cleanly degrade
          # on a node that can't host sshd, idle the alloc as a healthy long-running no-op.
          skip() { log "$* — idling (codex-ssh not hostable on this node)"; exec sleep infinity; }

          # --- preflight: self-heal or cleanly degrade (never crash-loop) ---
          # This job needs root (to create the autocodex user) and the openssh-server `sshd`
          # binary. On nodes lacking either (e.g. V1410-1/claudebox), idle cleanly instead of
          # restart-storming exit 127 on a missing binary or permission error.
          if [ "$(id -u)" != 0 ]; then
            if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
              log "not root (uid=$(id -u)) — re-running setup through passwordless sudo"
              exec sudo -n -E /bin/bash "$0"
            fi
            skip "not root (uid=$(id -u)) and passwordless sudo unavailable — cannot create $U / manage sshd"
          fi
          SSHD="$(command -v sshd 2>/dev/null || echo /usr/sbin/sshd)"
          if ! [ -x "$SSHD" ]; then
            log "sshd not found — attempting to install openssh-server"
            if command -v apt-get >/dev/null 2>&1; then
              DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
              DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server >/dev/null 2>&1 || true
            elif command -v dnf >/dev/null 2>&1; then dnf install -y openssh-server >/dev/null 2>&1 || true
            elif command -v yum >/dev/null 2>&1; then yum install -y openssh-server >/dev/null 2>&1 || true
            elif command -v apk >/dev/null 2>&1; then apk add --no-cache openssh-server >/dev/null 2>&1 || true
            fi
            SSHD="$(command -v sshd 2>/dev/null || echo /usr/sbin/sshd)"
          fi
          if ! [ -x "$SSHD" ]; then
            skip "openssh-server unavailable after install attempt"
          fi
          # ensure host keys exist (a fresh install or minimal image may have none)
          ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A >/dev/null 2>&1 || true

          id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
          # useradd leaves the password LOCKED ('!'), and sshd refuses ALL logins (even pubkey)
          # to a locked account. If secret/codex-ssh has password or password_hash, install it;
          # otherwise set '*' = no password but unlocked, so key auth still works.
          PW="$(tr -d '\r\n' < "$NOMAD_TASK_DIR/password" 2>/dev/null || true)"
          PH="$(tr -d '\r\n' < "$NOMAD_TASK_DIR/password_hash" 2>/dev/null || true)"
          PASSAUTH=no
          if [ -n "$PW" ]; then
            printf '%s:%s\n' "$U" "$PW" | chpasswd
            PASSAUTH=yes
            log "installed password auth for $U via chpasswd"
          elif [ -n "$PH" ]; then
            usermod -p "$PH" "$U"
            PASSAUTH=yes
            log "installed password auth for $U via password_hash"
          else
            usermod -p '*' "$U"
            log "no password/password_hash in secret/codex-ssh — password auth disabled"
          fi
          echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/autocodex && chmod 440 /etc/sudoers.d/autocodex
          H="$(getent passwd "$U" | cut -d: -f6)"
          # sshd StrictModes: HOME + ~/.ssh must be owned by the user and not group/world-writable,
          # or pubkey auth is silently rejected. Enforce it (the user may have pre-existed home-less).
          mkdir -p "$H"; chown "$U:$U" "$H"; chmod 0755 "$H"
          install -d -m 700 -o "$U" -g "$U" "$H/.ssh"

          # OpenSSH runs remote commands through the user's shell. Use a small wrapper so
          # `ssh autocodex@node codex app-server ...` sees the user-local Codex CLI even in
          # non-interactive shells where bash startup files are not read.
          SHELL_WRAP=/usr/local/bin/autocodex-shell
          cat > "$SHELL_WRAP" <<'WRAP'
#!/bin/sh
export HOME=/home/autocodex
export PATH=/home/autocodex/.local/bin:/home/autocodex/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/snap/bin
exec /bin/bash "$@"
WRAP
          chmod 755 "$SHELL_WRAP"
          grep -qxF "$SHELL_WRAP" /etc/shells 2>/dev/null || echo "$SHELL_WRAP" >> /etc/shells
          usermod -s "$SHELL_WRAP" "$U"

          KP="$NOMAD_TASK_DIR/key.pub"
          if [ -s "$KP" ] && grep -q ssh "$KP"; then
            cp "$KP" "$H/.ssh/authorized_keys"
            chmod 600 "$H/.ssh/authorized_keys"; chown "$U:$U" "$H/.ssh/authorized_keys"
            log "installed app pubkey for $U"
          else
            log "no app pubkey in secret/codex-ssh yet — set it to grant access"
          fi

          # Share Codex auth from the node's logged-in Codex user without symlinking the
          # whole .codex directory. The app-server reads config files under $HOME/.codex;
          # a symlink into another user's home can make those files unreadable to autocodex.
          if [ -L "$H/.codex" ]; then
            rm -f "$H/.codex"
          fi
          install -d -m 700 -o "$U" -g "$U" "$H/.codex"
          touch "$H/.codex/environments.toml"
          chown "$U:$U" "$H/.codex/environments.toml"
          chmod 600 "$H/.codex/environments.toml"
          for au in e ubuntu bigo eliott; do
            ah="$(getent passwd "$au" | cut -d: -f6)"; [ -n "$ah" ] || continue
            if [ -f "$ah/.codex/auth.json" ]; then
              cp "$ah/.codex/auth.json" "$H/.codex/auth.json"
              chown "$U:$U" "$H/.codex/auth.json"
              chmod 600 "$H/.codex/auth.json"
              for cf in config.toml AGENTS.md instructions.md; do
                if [ -f "$ah/.codex/$cf" ]; then
                  cp "$ah/.codex/$cf" "$H/.codex/$cf"
                  chown "$U:$U" "$H/.codex/$cf"
                  chmod 600 "$H/.codex/$cf"
                fi
              done
              log "codex auth copied from $au"; break
            fi
          done

          # Codex App SSH hosts must be able to run `codex app-server` from the remote user's
          # login shell. Avoid snap wrappers in this Nomad-launched sshd path (they fail cgroup
          # checks on some nodes) by installing the npm CLI into autocodex's own prefix and
          # placing a real wrapper in ~/.local/bin. npm also creates ~/.local/bin/codex as a
          # symlink into node_modules, so always remove it before writing our wrapper.
          install -d -m 755 -o "$U" -g "$U" "$H/.local" "$H/.local/bin"
          CODEX_JS="$H/.local/node_modules/@openai/codex/bin/codex.js"
          CODEX_ARM="$H/.local/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex"
          CODEX_X64="$H/.local/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex"
          CODEX_NATIVE=""
          CODEX_NATIVE_PACKAGE=""
          CODEX_NATIVE_SUFFIX=""
          case "$(uname -m)" in
            aarch64|arm64)
              CODEX_NATIVE="$CODEX_ARM"
              CODEX_NATIVE_PACKAGE="@openai/codex-linux-arm64"
              CODEX_NATIVE_SUFFIX="linux-arm64"
              ;;
            x86_64|amd64)
              CODEX_NATIVE="$CODEX_X64"
              CODEX_NATIVE_PACKAGE="@openai/codex-linux-x64"
              CODEX_NATIVE_SUFFIX="linux-x64"
              ;;
          esac
          NEED_CODEX_INSTALL=no
          [ -n "$CODEX_NATIVE" ] && [ -x "$CODEX_NATIVE" ] || NEED_CODEX_INSTALL=yes
          [ -f "$CODEX_JS" ] || NEED_CODEX_INSTALL=yes
          if [ -f "$CODEX_JS" ] && grep -q 'case "$(uname -m)"' "$CODEX_JS"; then
            log "detected corrupted @openai/codex entrypoint; reinstalling"
            NEED_CODEX_INSTALL=yes
          fi
          if [ "$NEED_CODEX_INSTALL" = yes ] && ! command -v npm >/dev/null 2>&1; then
            log "npm not found — attempting to install nodejs/npm"
            if command -v apt-get >/dev/null 2>&1; then
              DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
              DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs npm >/dev/null 2>&1 || true
            elif command -v dnf >/dev/null 2>&1; then dnf install -y nodejs npm >/dev/null 2>&1 || true
            elif command -v yum >/dev/null 2>&1; then yum install -y nodejs npm >/dev/null 2>&1 || true
            elif command -v apk >/dev/null 2>&1; then apk add --no-cache nodejs npm >/dev/null 2>&1 || true
            fi
          fi
          if [ "$NEED_CODEX_INSTALL" = yes ]; then
            if command -v npm >/dev/null 2>&1; then
              log "installing @openai/codex for $U under $H/.local"
              rm -rf "$H/.local/node_modules/@openai/codex" "$H/.local/node_modules/@openai/codex-linux-arm64" "$H/.local/node_modules/@openai/codex-linux-x64"
              rm -f "$H/.local/bin/codex"
              NPM_LOG="$NOMAD_TASK_DIR/npm-codex-install.log"
              if command -v runuser >/dev/null 2>&1; then
                if command -v timeout >/dev/null 2>&1; then
                  timeout 240 runuser -u "$U" -- npm install --prefix "$H/.local" --include=optional --force @openai/codex >"$NPM_LOG" 2>&1 || true
                else
                  runuser -u "$U" -- npm install --prefix "$H/.local" --include=optional --force @openai/codex >"$NPM_LOG" 2>&1 || true
                fi
              else
                if command -v timeout >/dev/null 2>&1; then
                  timeout 240 su - "$U" -c "npm install --prefix '$H/.local' --include=optional --force @openai/codex" >"$NPM_LOG" 2>&1 || true
                else
                  su - "$U" -c "npm install --prefix '$H/.local' --include=optional --force @openai/codex" >"$NPM_LOG" 2>&1 || true
                fi
              fi
              if [ -n "$CODEX_NATIVE" ] && [ ! -x "$CODEX_NATIVE" ] && [ -n "$CODEX_NATIVE_PACKAGE" ] && [ -n "$CODEX_NATIVE_SUFFIX" ]; then
                CODEX_VERSION="$(node -p "require('$H/.local/node_modules/@openai/codex/package.json').version" 2>/dev/null || true)"
                [ -n "$CODEX_VERSION" ] || CODEX_VERSION="$(npm view @openai/codex version 2>/dev/null || true)"
                if [ -n "$CODEX_VERSION" ]; then
                  CODEX_NATIVE_ALIAS="$CODEX_NATIVE_PACKAGE@npm:@openai/codex@$CODEX_VERSION-$CODEX_NATIVE_SUFFIX"
                  log "installing native codex package alias $CODEX_NATIVE_ALIAS"
                  if command -v runuser >/dev/null 2>&1; then
                    if command -v timeout >/dev/null 2>&1; then
                      timeout 240 runuser -u "$U" -- npm install --prefix "$H/.local" --include=optional --force "$CODEX_NATIVE_ALIAS" >>"$NPM_LOG" 2>&1 || true
                    else
                      runuser -u "$U" -- npm install --prefix "$H/.local" --include=optional --force "$CODEX_NATIVE_ALIAS" >>"$NPM_LOG" 2>&1 || true
                    fi
                  else
                    if command -v timeout >/dev/null 2>&1; then
                      timeout 240 su - "$U" -c "npm install --prefix '$H/.local' --include=optional --force '$CODEX_NATIVE_ALIAS'" >>"$NPM_LOG" 2>&1 || true
                    else
                      su - "$U" -c "npm install --prefix '$H/.local' --include=optional --force '$CODEX_NATIVE_ALIAS'" >>"$NPM_LOG" 2>&1 || true
                    fi
                  fi
                fi
              fi
              if [ -s "$NPM_LOG" ]; then
                sed -n '1,20p' "$NPM_LOG" | sed 's/^/[npm-codex] /'
              fi
              chown -R "$U:$U" "$H/.local" 2>/dev/null || true
            else
              log "WARN: npm not available; cannot install user-local codex CLI"
            fi
          fi
          if [ -x "$H/.local/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex" ] \
             || [ -x "$H/.local/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex" ] \
             || [ -f "$H/.local/node_modules/@openai/codex/bin/codex.js" ]; then
            rm -f "$H/.local/bin/codex"
            cat > "$H/.local/bin/codex" <<CODEXWRAP
#!/bin/sh
case "\$(uname -m)" in
  aarch64|arm64)
    native="$H/.local/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex"
    ;;
  x86_64|amd64)
    native="$H/.local/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex"
    ;;
  *)
    native=""
    ;;
esac
if [ -n "\$native" ] && [ -x "\$native" ]; then
  exec "\$native" "\$@"
fi
exec node "$H/.local/node_modules/@openai/codex/bin/codex.js" "\$@"
CODEXWRAP
            chmod 755 "$H/.local/bin/codex"
            chown "$U:$U" "$H/.local/bin/codex" 2>/dev/null || true
          fi
          if ! env HOME="$H" PATH="$H/.local/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/snap/bin" codex app-server --help >/dev/null 2>&1; then
            log "WARN: user-local codex app-server check failed; falling back to any system codex"
          fi
          # Clear app-server daemons/proxies left behind by older SSH attempts. The Codex App
          # will start a fresh daemon through SSH when it reconnects.
          pkill -u "$U" -f "codex app-server" 2>/dev/null || true
          rm -rf "$H/.codex/app-server-control"
          install -d -m 700 -o "$U" -g "$U" "$H/.codex/app-server-control"

          # Give the app concrete remote project folders to discover/use.
          for spec in \
            "monad https://github.com/eliott-monad/monad.git" \
            "math https://github.com/eliottcassidy2000/math.git" \
            "math-lean https://github.com/eliott-monad/math-lean.git"
          do
            set -- $spec
            name="$1"; url="$2"; dir="$H/$name"
            if [ ! -d "$dir/.git" ] && command -v git >/dev/null 2>&1; then
              log "cloning $name for $U"
              if command -v timeout >/dev/null 2>&1; then
                timeout 120 git clone --depth 1 "$url" "$dir" >/dev/null 2>&1 || true
              else
                git clone --depth 1 "$url" "$dir" >/dev/null 2>&1 || true
              fi
              chown -R "$U:$U" "$dir" 2>/dev/null || true
            fi
          done

          mkdir -p /run/sshd 2>/dev/null || true
          CFG="$NOMAD_TASK_DIR/sshd_autocodex.conf"
          {
            echo "Port 2222"
            echo "PermitRootLogin no"
            echo "PasswordAuthentication $PASSAUTH"
            echo "KbdInteractiveAuthentication $PASSAUTH"
            echo "PermitEmptyPasswords no"
            echo "PubkeyAuthentication yes"
            echo "AllowUsers autocodex"
            echo "PidFile $NOMAD_TASK_DIR/sshd.pid"
            for k in /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_ecdsa_key; do
              [ -f "$k" ] && echo "HostKey $k"
            done
          } > "$CFG"
          env HOME="$H" PATH="$H/.local/bin:$H/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:/snap/bin" codex app-server --help >/dev/null 2>&1 \
            && log "codex app-server available for $U" \
            || log "WARN: codex app-server still unavailable for $U"
          # Kill any orphaned autocodex sshd from a prior alloc so this fresh one can bind :2222.
          pkill -f sshd_autocodex.conf 2>/dev/null && sleep 1 || true
          log "autocodex ready; starting sshd on :2222"
          exec "$SSHD" -D -e -f "$CFG"
        SCRIPT
      }

      resources {
        cpu    = 100
        memory = 768
      }
    }
  }
}
