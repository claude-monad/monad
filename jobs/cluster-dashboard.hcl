job "cluster-dashboard" {
  datacenters = ["dc1"]
  type        = "service"

  # bigo-server: amd64, abundant CPU, on the tailnet (so `tailscale status` can list
  # mesh peers), and off the Raft leader. Reachable at 100.78.218.70:8088.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "dashboard" {
    count = 1

    # Host networking so the server binds the tailnet interface, not just the LAN.
    network {
      mode = "host"
      port "http" {
        static = 8088
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    task "dashboard" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<SCRIPT
#!/bin/bash
# Self-contained: clone the (public) monad repo into the alloc, then serve the
# dashboard from it. server.py git-pulls the clone every minute to stay fresh.
set -uo pipefail
REPO="$NOMAD_TASK_DIR/monad"
if [ ! -d "$REPO/.git" ]; then
  echo "[dashboard] cloning monad repo into $REPO"
  git clone --depth 1 https://github.com/eliott-monad/monad "$REPO" \
    || { echo "[dashboard] FAIL: git clone"; exit 1; }
fi
command -v python3 >/dev/null 2>&1 || { echo "[dashboard] FAIL: python3 not found"; exit 1; }
export REPO_DIR="$REPO"
export NOMAD_ADDR="$${NOMAD_ADDR:-http://100.75.75.39:4646}"
export DASH_PORT="8088"
export REFRESH_SECS="60"
export EVENT_STREAM_SECS="5"
exec python3 "$REPO/meta/dashboard/server.py"
SCRIPT
      }

      env {
        NOMAD_ADDR    = "http://100.75.75.39:4646"
        DASH_RELEASE  = "2026-06-03T00:12:00Z"
      }

      resources {
        cpu    = 100
        memory = 128
      }

      service {
        name     = "cluster-dashboard"
        port     = "http"
        provider = "nomad"

        check {
          type     = "http"
          path     = "/healthz"
          port     = "http"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
