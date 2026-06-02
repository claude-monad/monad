# registry-trust-bigo — one-shot: make bigo-server's dockerd trust the shared
# insecure registry (100.78.218.70:5000), then verify a pull of the shared
# monad-agent-mesh image succeeds. Fixes the HTTP->HTTPS pull error documented in
# fleet/projects/bigo-server-registry-trust.md. raw_exec is required for host-level
# /etc/docker/daemon.json access; the script (scripts/ensure-registry-trust.sh) is
# idempotent and only SIGHUP-reloads dockerd when the address was actually missing.
job "registry-trust-bigo" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "trust" {
    restart {
      attempts = 0
    }
    reschedule {
      attempts = 0
    }

    task "ensure-trust" {
      driver = "raw_exec"

      artifact {
        source      = "https://raw.githubusercontent.com/eliott-monad/monad/main/scripts/ensure-registry-trust.sh"
        destination = "local/ensure-registry-trust.sh"
        mode        = "file"
      }

      config {
        command = "bash"
        args = ["-c", <<-EOT
          set -uo pipefail
          chmod +x local/ensure-registry-trust.sh
          echo "=== ensure-registry-trust ==="
          ./local/ensure-registry-trust.sh 100.78.218.70:5000
          echo "=== verify pull (docker) ==="
          if docker pull 100.78.218.70:5000/monad-agent-mesh:latest; then
            echo PULL_OK
          elif sudo -n docker pull 100.78.218.70:5000/monad-agent-mesh:latest; then
            echo PULL_OK_SUDO
          else
            echo PULL_FAILED
            exit 1
          fi
        EOT
        ]
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
