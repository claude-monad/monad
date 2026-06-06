# math-explore-watch — every new math-repo commit spins up autonomous Claude discovery sessions.
#
# Polls eliottcassidy2000/math HEAD; when it moves, scripts/math-explore-watch.sh dispatches a
# bounded number of `math-explore` Claude sessions (governor-admitted) seeded with the recent
# commits. The companion of formalize-watch: that one formalizes the new results, this one tries
# to discover the NEXT ones. Cheap (one git ls-remote per pass; spawns only when HEAD moves).

job "math-explore-watch" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]  # every 15 minutes
    prohibit_overlap = true
    time_zone        = "America/Denver"
  }

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
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$home" ] || continue
            repo="$home/monad"
            [ -f "$repo/scripts/math-explore-watch.sh" ] || continue
            if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then exec su - "$u" -c "exec bash '$repo/scripts/math-explore-watch.sh'"
            else exec bash "$repo/scripts/math-explore-watch.sh"; fi
          done
          WORK="$NOMAD_TASK_DIR/mew-monad"
          [ -f "$WORK/scripts/math-explore-watch.sh" ] || { rm -rf "$WORK"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || true; }
          [ -f "$WORK/scripts/math-explore-watch.sh" ] && exec bash "$WORK/scripts/math-explore-watch.sh"
          echo "math-explore-watch: no checkout found" >&2; exit 1
        EOC
        ]
      }

      env {
        MATH_REPO_URL  = "https://github.com/eliottcassidy2000/math.git"
        MATH_BRANCH    = "main"
        EXPLORE_JOB    = "math-explore"
        MAX_CONCURRENT = "2"
        PER_BATCH      = "2"
        NOMAD_ADDR     = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    restart {
      attempts = 1
      interval = "15m"
      delay    = "1m"
      mode     = "fail"
    }
  }
}
