# fleet-foreman — a standing service that keeps the fleet building the backlog.
#
# Wraps scripts/fleet-foreman.sh in --loop mode: every INTERVAL it git-pulls the repo,
# reads fleet/projects/*.md, tops up builders (via the fleet-builder parameterized job) up
# to FOREMAN_N, and records a summary to the Nomad var fleet/status + logs/events.jsonl
# (source "fleet"). Without this, building only happens when a human runs the script.
#
# Singleton on oraclebox1 — the always-on node that holds the engine creds, runs a local
# Nomad server, and is where fleet-builder is constrained to run (so the foreman dispatches
# builders onto the same node). raw_exec so it uses the host nomad/git binaries directly.
#
# Inspect:  nomad var get fleet/status   |   monad events
job "fleet-foreman" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "foreman" {
    count = 1

    restart {
      attempts = 5
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "foreman" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # Nomad runs as root here; su to the user whose home has ~/monad (that user has the
        # repo + git credentials), then loop the foreman. Falls back to direct exec if we're
        # already a non-root user with the repo.
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$home" ] && [ -f "$home/monad/scripts/fleet-foreman.sh" ] || continue
            cmd="export INTERVAL='$INTERVAL' NOMAD_ADDR='$NOMAD_ADDR'; cd '$home/monad' && git pull --ff-only --quiet >/dev/null 2>&1 || true; exec bash '$home/monad/scripts/fleet-foreman.sh' '$FOREMAN_N' --loop"
            if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then
              exec su - "$u" -c "$cmd"
            else
              cd "$home/monad" && git pull --ff-only --quiet >/dev/null 2>&1 || true
              exec bash "$home/monad/scripts/fleet-foreman.sh" "$FOREMAN_N" --loop
            fi
          done
          echo "fleet-foreman: no user with ~/monad found on this node" >&2
          sleep 120
        EOC
        ]
      }

      env {
        FOREMAN_N  = "3"                              # generous but bounded builder count
        INTERVAL   = "600"                            # top-up cadence (s)
        NOMAD_ADDR = "http://100.125.210.126:4646"    # oraclebox1's local server
      }

      resources {
        cpu    = 200
        memory = 256
      }

      kill_timeout = "15s"
    }
  }
}
