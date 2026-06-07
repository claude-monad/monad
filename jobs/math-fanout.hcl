# math-fanout — keep one Claude math worker on EVERY capable node, sustained.
#
# Periodic: each pass, scripts/math-fanout.sh launches a node-pinned worker on every ready Linux
# Claude node that isn't overloaded and isn't already running one (so it maintains ~one-per-node
# as deep sessions finish). The research brief is read from the campaign var. "All the nodes that
# can handle it", kept topped up. Pause by stopping this job: nomad job stop math-fanout.
#
# NOTE on cost: this sustains ~5 concurrent Claude sessions on the single Max account — they will
# rate-limit/back off under contention. To stop: `nomad job stop math-fanout`.

job "math-fanout" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/30 * * * *"]  # top up per-node coverage every 30 min
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

  group "fanout" {
    count = 1

    task "run" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$home" ] || continue
            repo="$home/monad"
            [ -f "$repo/scripts/math-fanout.sh" ] || continue
            if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then exec su - "$u" -c "exec bash '$repo/scripts/math-fanout.sh'"
            else exec bash "$repo/scripts/math-fanout.sh"; fi
          done
          WORK="$NOMAD_TASK_DIR/mf-monad"
          [ -f "$WORK/scripts/math-fanout.sh" ] || { rm -rf "$WORK"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || true; }
          [ -f "$WORK/scripts/math-fanout.sh" ] && exec bash "$WORK/scripts/math-fanout.sh"
          echo "math-fanout: no checkout found" >&2; exit 1
        EOC
        ]
      }

      env {
        CAMPAIGN_VAR = "monad/campaign/signed-lrc"
        NOMAD_ADDR   = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    restart {
      attempts = 1
      interval = "30m"
      delay    = "1m"
      mode     = "fail"
    }
  }
}
