# cluster-capability — honest per-node engine capability tracker.
#
# sysbatch + periodic → on each schedule tick, runs scripts/capability-probe.sh on EVERY
# eligible node. Each node actually runs a tiny claude AND codex math session and reports
# its real ability to the cluster as Nomad var `capability/<node>` {claude,codex,ts,...}.
# The dashboard renders all `capability/*` vars as a node × engine matrix.
#
# Force a full sweep now:  nomad job periodic force cluster-capability
job "cluster-capability" {
  datacenters = ["dc1"]
  type        = "sysbatch"

  periodic {
    crons            = ["0 */6 * * *"]   # every 6 hours
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "probe" {
    restart {
      attempts = 0
      mode     = "fail"
    }

    task "probe" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # Run the probe as the engine-credentialed user. If Nomad runs as root, find the
        # user whose ~/monad exists (that user is logged in to the engines) and su to them;
        # otherwise run directly (e.g. claudebox/mac-mini run the client as that user). In
        # all cases clone a FRESH copy into that user's home so the latest probe script and
        # their engine creds (~/.claude, ~/.codex / Keychain) line up.
        args = ["-c", <<-EOC
          run_as_self() {
            D="$HOME/.cap-monad"; rm -rf "$D"
            git clone --depth 1 https://github.com/eliott-monad/monad "$D" >/dev/null 2>&1 \
              && exec bash "$D/scripts/capability-probe.sh"
          }
          if [ "$(id -u)" != 0 ]; then run_as_self; fi
          for u in ubuntu bigo e eliott; do
            home="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$home" ] || continue
            [ -d "$home/monad/.git" ] || continue
            exec su - "$u" -c 'D="$HOME/.cap-monad"; rm -rf "$D"; git clone --depth 1 https://github.com/eliott-monad/monad "$D" >/dev/null 2>&1 && exec bash "$D/scripts/capability-probe.sh"'
          done
          # No credentialed user found — run as root so the matrix still records an honest
          # (likely engine-absent / not-authed) result for this node.
          run_as_self
        EOC
        ]
      }

      env {
        NOMAD_ADDR = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 100
        memory = 512
      }

      kill_timeout = "15s"
    }
  }
}
