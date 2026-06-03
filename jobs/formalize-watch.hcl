job "formalize-watch" {
  datacenters = ["dc1"]
  type        = "batch"

  # Poll the informal math repo often so math-lean tracks it closely. Cheap: one
  # git ls-remote per pass, a trigger only when HEAD actually moves. count=1 + periodic
  # means exactly one watcher pass runs cluster-wide per tick.
  periodic {
    crons            = ["*/10 * * * *"]  # every 10 minutes
    prohibit_overlap = true
    time_zone        = "America/Denver"
  }

  # Any Linux node with raw_exec: the watcher only needs git + the nomad CLI (NOMAD_ADDR is
  # set below) + network to the math repo. No host volume, no role pin.
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "watch" {
    count = 1

    task "poll" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # Discover a monad checkout (so events.jsonl appends land in the repo) and run the
        # watcher from it; fall back to an alloc-local clone. Same pattern as maintenance-agent.
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$home" ] || continue
            for repo in "$home/monad" "$home/Documents/monad"; do
              [ -f "$repo/scripts/formalize-watch.sh" ] || continue
              if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then
                exec su - "$u" -c "exec bash '$repo/scripts/formalize-watch.sh'"
              else
                exec bash "$repo/scripts/formalize-watch.sh"
              fi
            done
          done
          WORK="$NOMAD_TASK_DIR/monad"
          [ -n "$NOMAD_TASK_DIR" ] || WORK="/tmp/formalize-watch-monad"
          if command -v git >/dev/null 2>&1; then
            [ -f "$WORK/scripts/formalize-watch.sh" ] || { rm -rf "$WORK"; \
              git clone --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || true; }
            if [ -f "$WORK/scripts/formalize-watch.sh" ]; then
              echo "formalize-watch: using alloc-local clone at $WORK" >&2
              exec bash "$WORK/scripts/formalize-watch.sh"
            fi
          fi
          echo "formalize-watch: no monad checkout found and clone failed" >&2
          exit 1
        EOC
        ]
      }

      env {
        MATH_REPO_URL  = "https://github.com/eliottcassidy2000/math.git"
        MATH_BRANCH    = "main"
        FORMALIZER_JOB = "math-formalizer"
        NOMAD_ADDR     = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    restart {
      attempts = 1
      interval = "10m"
      delay    = "1m"
      mode     = "fail"
    }
  }
}
