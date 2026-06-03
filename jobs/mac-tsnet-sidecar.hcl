// mac-tsnet-sidecar — gives eliotts-mac-mini its own tsnet node on the Tailnet,
// mirroring windesk-tsnet-sidecar.hcl for darwin/arm64.
//
// The mac has only raw_exec (no docker). This job locates (or clones) the monad
// repo from the CANONICAL remote (eliott-monad/monad — NOT the eliottcassidy2000
// fork some nodes track), builds the darwin/arm64 sidecar natively if it isn't
// already present, then runs it as "agent-mac-mini" (mesh :8472, local :8473).
//
// On startup it also sends one hello to agent-windesk so the windesk<->mac-mini
// tsnet round-trip is self-verifying: windesk /recv shows mac->windesk, and this
// node's alloc logs show "rx from=agent-windesk" for windesk->mac.
//
// TS_AUTHKEY comes from the Nomad variable secret/agent-mesh.tailscale_authkey.

job "mac-tsnet-sidecar" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 60

  constraint {
    attribute = "${node.unique.name}"
    value     = "eliotts-mac-mini"
  }

  group "sidecar" {
    count = 1

    reschedule {
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }

    restart {
      attempts = 5
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    task "sidecar" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-lc", <<-SH
          set -uo pipefail
          log(){ echo "[mac-tsnet $(date -u +%H:%M:%S)] $*"; }

          # ── locate the monad repo (reuse mini-agent's checkout if present) ──
          M=""
          for p in "$HOME/monad" "/Users/$(whoami)/monad" /opt/monad /tmp/monad-tsnet; do
            [ -e "$p/meta/agent/mesh/sidecar/main.go" ] && { M="$p"; break; }
          done
          if [ -z "$M" ]; then
            M="/tmp/monad-tsnet"
            log "no repo found; cloning eliott-monad/monad -> $M"
            rm -rf "$M"
            git clone --depth 50 https://github.com/eliott-monad/monad "$M" || { log "clone FAILED"; exit 1; }
          fi
          log "repo: $M"
          cd "$M/meta/agent/mesh/sidecar" || { log "no sidecar dir"; exit 1; }

          # ── ensure a darwin/arm64 binary (native build if missing) ──────────
          BIN="bin/sidecar-darwin-arm64"
          if [ ! -x "$BIN" ]; then
            GO=""
            for g in go /opt/homebrew/bin/go /usr/local/go/bin/go /usr/local/bin/go; do
              command -v "$g" >/dev/null 2>&1 && { GO="$g"; break; }
            done
            [ -z "$GO" ] && { log "go not found (tried PATH, homebrew, /usr/local) — cannot build sidecar"; exit 1; }
            log "building darwin/arm64 sidecar with $GO (one-time)"
            mkdir -p bin
            GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 "$GO" build -trimpath -ldflags='-s -w' -o "$BIN" . \
              || { log "go build FAILED"; exit 1; }
          fi
          log "sidecar binary: $BIN"

          export AGENT_NAME="agent-mac-mini" MESH_PORT="8472" LOCAL_PORT="8473"
          export TS_STATE_DIR="$M/.tsnet/agent-mac-mini"
          mkdir -p "$TS_STATE_DIR"

          # ── start sidecar, then self-send a hello to prove mac->windesk ─────
          log "starting tsnet sidecar as agent-mac-mini"
          "./$BIN" &
          SID=$!
          for _ in $(seq 1 40); do
            curl -sf -m2 "http://127.0.0.1:8473/whoami" >/dev/null 2>&1 && break
            sleep 1
          done
          who=$(curl -sf -m4 "http://127.0.0.1:8473/whoami" 2>/dev/null || echo '{}')
          log "whoami: $who"
          if curl -sf -m8 -X POST "http://127.0.0.1:8473/send" \
               -H 'Content-Type: application/json' \
               -d '{"to":"agent-windesk","body":"hello from agent-mac-mini (Nomad sidecar) — round-trip leg mac->windesk"}' \
               -o /dev/null; then
            log "sent hello to agent-windesk (mac->windesk leg OK)"
          else
            log "could not reach agent-windesk yet (it may attach shortly; peers refresh)"
          fi

          wait "$SID"
        SH
        ]
      }

      template {
        destination = "secrets/mesh.env"
        env         = true
        data        = <<-TMPL
          TS_AUTHKEY={{ with nomadVar "secret/agent-mesh" }}{{ .tailscale_authkey }}{{ end }}
        TMPL
      }

      resources {
        cpu    = 150
        memory = 256
      }
    }
  }
}
