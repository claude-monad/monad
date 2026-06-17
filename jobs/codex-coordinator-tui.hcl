# codex-coordinator-tui — browser TUI for the standing Codex cluster coordinator.
#
# Runs on claudebox, which already has a working logged-in Codex CLI. Reach it over the tailnet
# at http://100.87.219.108:8091 and keep using the default session name `coordinator`.

job "codex-coordinator-tui" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 80

  constraint {
    attribute = "${node.unique.name}"
    value     = "claudebox"
  }

  group "tui" {
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

    network {
      mode = "host"
      port "http" {
        static = 8091
      }
    }

    task "server" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args = ["-c", <<-EOC
          export HOME=/home/claude/snap/codex/34
          export CODEX_HOME=/home/claude/snap/codex/34
          export PATH=/home/claude/snap/codex/34/tmp/arg0/codex-arg0w3jOWk:/snap/codex/34/usr/sbin:/snap/codex/34/usr/bin:/snap/codex/34/sbin:/snap/codex/34/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
          export LD_LIBRARY_PATH=/var/lib/snapd/lib/gl:/var/lib/snapd/lib/gl32:/snap/codex/34/usr/lib:/snap/codex/34/usr/lib/x86_64-linux-gnu
          cat > /tmp/codex-coordinator-bin <<'EOF'
#!/bin/bash
export HOME=/home/claude/snap/codex/34
export CODEX_HOME=/home/claude/snap/codex/34
export PATH=/home/claude/snap/codex/34/tmp/arg0/codex-arg0w3jOWk:/snap/codex/34/usr/sbin:/snap/codex/34/usr/bin:/snap/codex/34/sbin:/snap/codex/34/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
exec /snap/core24/1643/usr/lib64/ld-linux-x86-64.so.2 \
  --library-path /snap/core24/1643/usr/lib/x86_64-linux-gnu:/snap/core24/1643/lib/x86_64-linux-gnu:/snap/core24/1643/usr/lib:/snap/core24/1643/lib:/var/lib/snapd/lib/gl:/var/lib/snapd/lib/gl32:/snap/codex/34/usr/lib:/snap/codex/34/usr/lib/x86_64-linux-gnu \
  /snap/codex/34/bin/codex "$@"
EOF
          chmod 755 /tmp/codex-coordinator-bin
          export CODEX_BIN=/tmp/codex-coordinator-bin
          export CODEX_TUI_PORT=8091
          export CODEX_TUI_WORKDIR=/home/claude/monad
          export CODEX_TUI_DEFAULT_SESSION=coordinator
          export CODEX_TUI_LABEL="Codex Coordinator"
          export CODEX_TUI_PREAMBLE="$(cat /home/claude/monad/codex-worker/cluster-coordinator.md)"
          exec python3 /home/claude/monad/meta/codex-tui/server.py
        EOC
        ]
      }

      resources {
        cpu    = 300
        memory = 384
      }

      service {
        name     = "codex-coordinator-tui"
        port     = "http"
        provider = "nomad"
        check {
          type     = "http"
          path     = "/health"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }
  }
}
