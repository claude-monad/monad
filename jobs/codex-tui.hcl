# codex-tui — web chat to self-hosted Codex over the tailnet (desktop/iOS browser).
# Codex has no cloud remote-control relay (local unix-socket only), so this is the way to
# reach Codex sessions remotely. Runs on oraclebox1 (codex creds at /home/ubuntu/.codex);
# CODEX_HOME points codex at those creds even though raw_exec runs as root.
# Reach it at http://<oraclebox1-tailscale-ip>:8090  (advertised in infra/codex-tui).

job "codex-tui" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 70

  # death-star: idle (80 cores) + codex-ready, so the TUI is always-up and off the saturated
  # oraclebox1. Reach it at http://100.96.31.66:8090.
  constraint {
    attribute = "${node.unique.name}"
    value     = "death-star"
  }

  group "tui" {
    count = 1
    reschedule {
      attempts       = 0
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }
    restart {
      attempts = 3
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    network {
      mode = "host"
      port "http" {
        static = 8090
      }
    }

    task "server" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        # Find the user logged into codex (has ~/.codex/auth.json + ~/monad), refresh their
        # checkout, then run the TUI as root with CODEX_HOME pointed at their creds (so codex
        # authenticates) and CODEX_BIN the codex on PATH. Node-portable.
        args = ["-c", <<-EOC
          for u in e ubuntu bigo eliott; do
            h="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$h" ] || continue
            [ -f "$h/.codex/auth.json" ] && [ -d "$h/monad/.git" ] || continue
            su - "$u" -c "cd '$h/monad' && git fetch -q origin main && git reset --hard origin/main -q" 2>/dev/null || true
            export CODEX_HOME="$h/.codex"
            export CODEX_BIN="$(command -v codex || echo /usr/local/bin/codex)"
            export CODEX_TUI_PORT=8090 CODEX_TUI_WORKDIR=/tmp/codex-tui-work
            echo "codex-tui: user=$u CODEX_HOME=$CODEX_HOME bin=$CODEX_BIN"
            exec python3 "$h/monad/meta/codex-tui/server.py"
          done
          echo "codex-tui: no codex-credentialed user with ~/monad found" >&2; sleep 120
        EOC
        ]
      }
      resources {
        cpu    = 200
        memory = 256
      }
      service {
        name     = "codex-tui"
        port     = "http"
        provider = "nomad"
        check {
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
