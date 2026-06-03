# fleet-backlog-health — periodic linter for fleet/BACKLOG.md and
# fleet/projects/*.md metadata. READ-ONLY against git; writes one Nomad var:
# fleet/backlog-health.
job "fleet-backlog-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]
    prohibit_overlap = true
  }

  # Same central placement as fleet-foreman and fleet-health-rollup: oraclebox1
  # has local Nomad API reachability and is already the low-rate fleet-control
  # monitor host.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "backlog-health" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "lint" {
      driver = "raw_exec"

      env {
        NOMAD_ADDR         = "http://100.125.210.126:4646"
        REPO_URL           = "https://github.com/eliott-monad/monad"
        ACTIVE_STALE_HOURS = "6"
      }

      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
set -euo pipefail

REPO="$NOMAD_TASK_DIR/monad"
rm -rf "$REPO"
git clone --depth 1 "$REPO_URL" "$REPO" >/dev/null
exec python3 "$REPO/scripts/fleet-backlog-health.py" --repo "$REPO"
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 128
      }

      kill_timeout = "20s"
    }
  }
}
