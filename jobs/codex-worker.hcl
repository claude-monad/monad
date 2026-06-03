job "codex-worker" {
  datacenters = ["dc1"]
  type        = "system"

  # Run on every node tagged as a codex worker. Set in the node's client.hcl:
  #   meta { codex = "true" }
  # then restart Nomad so the attribute is advertised. `system` type means one
  # gateway per matching node (each codex node gets its own tailnet front door).
  constraint {
    attribute = "${meta.codex}"
    value     = "true"
  }

  group "worker" {
    # If the gateway drops (crash, network), restart it in place. `system` jobs
    # don't reschedule (one per node), so recovery is via this restart policy.
    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "gateway" {
      driver = "raw_exec"

      # Locate the monad repo on this node, then run the start script (foreground
      # text gateway + background tmux interactive watchdog). Repo path varies per
      # node, so probe the usual locations; override with meta.monad_repo if needed.
      config {
        command = "/bin/bash"
        args = ["-lc", <<-EOC
          for d in "${meta.monad_repo}" /root/monad "$HOME/monad" \
                   /home/bigo/Documents/monad /home/*/monad; do
            [ -n "$d" ] && [ -x "$d/codex-worker/start-codex-worker.sh" ] && \
              exec "$d/codex-worker/start-codex-worker.sh"
          done
          echo "codex-worker: could not locate monad repo on this node" >&2
          exit 1
        EOC
        ]
      }

      env {
        CODEX_PORT         = "8300"
        CODEX_SANDBOX      = "bypass"
        ENABLE_INTERACTIVE = "1"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}
