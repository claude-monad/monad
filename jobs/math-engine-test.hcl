# math-engine-test — a SCHEDULED cluster task (capability test).
#
# On each fire it runs one small autonomous math session with claude AND one with codex
# (scripts/math-engine-test.sh, via the engine abstraction) and reports how both went back
# to the cluster: Nomad vars `math-engine-test/{claude,codex,last}` + a report block in the
# alloc logs. Pinned to oraclebox1 — the only node with BOTH engines logged in
# (agent_engines=claude,codex). Periodic, so the cluster runs it automatically; force one
# now with: nomad job periodic force math-engine-test
job "math-engine-test" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["30 15 * * *"]   # daily 15:30 UTC
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # oraclebox1 is the dual-engine node (claude+codex). raw_exec for the bash session script.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "test" {
    count = 1

    reschedule {
      attempts  = 0
      unlimited = false
    }
    restart {
      attempts = 0
      mode     = "fail"
    }

    task "run" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # Nomad runs as root here; su into the engine-credentialed user (whose ~/monad has
        # the logged-in claude+codex), pull latest, and run the session script as them.
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott; do
            home="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$home" ] || continue
            [ -d "$home/monad/.git" ] || continue
            if [ "$(id -u)" = 0 ]; then
              exec su - "$u" -c "cd ~/monad && git pull -q origin main 2>/dev/null; exec bash scripts/math-engine-test.sh"
            else
              cd "$home/monad" && git pull -q origin main 2>/dev/null
              exec bash "$home/monad/scripts/math-engine-test.sh"
            fi
          done
          echo "[math-engine-test] no engine-credentialed user with ~/monad on $(hostname)" >&2
          exit 2
        EOC
        ]
      }

      env {
        NOMAD_ADDR = "http://100.75.75.39:4646"
      }

      # Modest reservation so it fits on oraclebox1 (which also runs conductor/foreman/
      # registry/maintenance). raw_exec doesn't hard-cap CPU, so the LLM sessions still
      # use what they need above this.
      resources {
        cpu    = 100
        memory = 512
      }

      kill_timeout = "20s"
    }
  }
}
