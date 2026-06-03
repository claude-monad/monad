# fleet-foreman — a standing service that keeps the fleet building the backlog.
#
# Wraps scripts/fleet-foreman.sh in --loop mode: every INTERVAL it git-pulls the repo,
# reads fleet/projects/*.md, tops up builders (via the fleet-builder parameterized job) up
# to FOREMAN_N, and records a summary to the Nomad var fleet/status + logs/events.jsonl
# (source "fleet"). Without this, building only happens when a human runs the script.
#
# Singleton on oraclebox1 — the always-on node that runs a local Nomad server and is where
# fleet-builder is constrained to run (so the foreman dispatches builders onto the same node).
# The service runs from an alloc-local clone so a dirty host checkout cannot make fleet/status
# stale. raw_exec so it uses host nomad/git/python binaries directly.
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
        args = ["-c", <<-EOC
          set -e
          WORK="$NOMAD_TASK_DIR/monad"
          clone_repo() {
            rm -rf "$WORK"
            git clone --depth 50 "$REPO_URL" "$WORK" >/dev/null
          }
          [ -f "$WORK/scripts/fleet-foreman.sh" ] || clone_repo
          git -C "$WORK" pull --ff-only --quiet >/dev/null 2>&1 || clone_repo
          export INTERVAL="$INTERVAL" NOMAD_ADDR="$NOMAD_ADDR"
          export FOREMAN_EVENTS_FILE="$NOMAD_TASK_DIR/foreman-events.jsonl"
          exec bash "$WORK/scripts/fleet-foreman.sh" "$FOREMAN_N" --loop
        EOC
        ]
      }

      env {
        FOREMAN_N  = "3"                              # generous but bounded builder count
        INTERVAL   = "600"                            # top-up cadence (s)
        NOMAD_ADDR = "http://100.125.210.126:4646"    # oraclebox1's local server
        REPO_URL   = "https://github.com/eliott-monad/monad"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      kill_timeout = "15s"
    }
  }
}
