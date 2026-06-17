job "monad-sync" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/5 * * * *"]
    prohibit_overlap = true
  }

  constraint {
    attribute = "${meta.role}"
    value     = "server"
  }

  group "sync" {
    count = 1

    volume "monad-repo" {
      type      = "host"
      source    = "monad-repo"
      read_only = false
    }

    task "git-sync" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOC
          for u in claude ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$home" ] || continue
            for repo in "$home/monad" "$home/Documents/monad" "$home/Documents/GitHub/monad"; do
              [ -x "$repo/scripts/sync.sh" ] || continue
              if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then
                exec su - "$u" -c "MONAD_REPO_DIR='$repo' NOMAD_ADDR='${NOMAD_ADDR}' exec bash '$repo/scripts/sync.sh'"
              else
                export MONAD_REPO_DIR="$repo"
                exec bash "$repo/scripts/sync.sh"
              fi
            done
          done
          WORK="$${NOMAD_TASK_DIR:-/tmp}/monad-sync"
          rm -rf "$WORK"
          git clone -q --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || exit 1
          export MONAD_REPO_DIR="$WORK"
          exec bash "$WORK/scripts/sync.sh"
        EOC
        ]
      }

      env {
        NOMAD_ADDR     = "http://100.87.219.108:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
