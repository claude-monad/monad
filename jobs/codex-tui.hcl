# codex-tui — web chat to self-hosted Codex over the tailnet (desktop/iOS browser).
# Codex has no cloud remote-control relay (local unix-socket only), so this is the way to
# reach Codex sessions remotely. Runs on oraclebox1 (codex creds at /home/ubuntu/.codex);
# CODEX_HOME points codex at those creds even though raw_exec runs as root.
# Reach it at http://<oraclebox1-tailscale-ip>:8090  (advertised in infra/codex-tui).

job "codex-tui" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 70

  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
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
        args    = ["-c", "exec python3 /home/ubuntu/monad/meta/codex-tui/server.py"]
      }
      env {
        CODEX_TUI_PORT    = "8090"
        CODEX_BIN         = "/home/ubuntu/.local/bin/codex"
        CODEX_HOME        = "/home/ubuntu/.codex"
        CODEX_TUI_WORKDIR = "/tmp/codex-tui-work"
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
