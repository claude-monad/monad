job "cluster-control" {
  datacenters = ["dc1"]
  type        = "service"

  # Always-on control plane node
  constraint {
    attribute = "${meta.role}"
    value     = "server"
  }

  group "control" {
    count = 1

    network {
      port "status" {
        static = 8765
      }
    }

    # ── Nomad native service registration ────────────────────────────────────
    service {
      name     = "cluster-control"
      provider = "nomad"
      port     = "status"
      tags     = ["remote-control", "claude", "cluster-mgmt"]
    }

    restart {
      attempts = 999
      interval = "24h"
      delay    = "30s"
      mode     = "delay"
    }

    # ── Task 1: the persistent remote-control Claude session ─────────────────
    task "session" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "exec \"${HOME}/.local/bin/claude\" --remote-control cluster-control --dangerously-skip-permissions --add-dir \"${MONAD_REPO_DIR}\""]
      }

      env {
        HOME           = "/home/bigo"
        MONAD_REPO_DIR = "/home/bigo/Documents/monad"
        NOMAD_ADDR     = "http://100.87.219.108:4646"
        PATH           = "/home/bigo/.local/bin:/usr/local/bin:/usr/bin:/bin"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      kill_timeout = "10s"
    }

    # ── Task 2: HTTP status sidecar — tailscale serve proxies this on the Tailnet ──
    task "status" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      config {
        command = "/bin/bash"
        args    = ["-c", <<-CMD
          python3 - <<'PYEOF'
          import http.server, socket, time, os

          class Handler(http.server.BaseHTTPRequestHandler):
              def log_message(self, *a): pass
              def do_GET(self):
                  body = (
                      "cluster-control OK\n"
                      f"host: {socket.gethostname()}\n"
                      f"time: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n"
                  ).encode()
                  self.send_response(200)
                  self.send_header("Content-Type", "text/plain")
                  self.send_header("Content-Length", str(len(body)))
                  self.end_headers()
                  self.wfile.write(body)

          server = http.server.HTTPServer(("0.0.0.0", 8765), Handler)
          server.serve_forever()
          PYEOF
        CMD
        ]
      }

      env {
        HOME = "/home/bigo"
        PATH = "/usr/bin:/bin"
      }

      resources {
        cpu    = 50
        memory = 64
      }

      kill_timeout = "5s"
    }
  }
}
