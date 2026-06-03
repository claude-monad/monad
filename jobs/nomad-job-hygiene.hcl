# nomad-job-hygiene — low-noise source-of-truth drift monitor for committed
# long-running Nomad jobs. It reads committed jobs/*.hcl from a fresh clone, compares
# live Nomad state, and writes fleet/job-hygiene.
job "nomad-job-hygiene" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/30 * * * *"]
    prohibit_overlap = true
  }

  # Same placement as the fleet rollup/backlog monitors: oraclebox1 has stable
  # Nomad API reachability and already runs the low-rate fleet control checks.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "job-hygiene" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "check" {
      driver = "raw_exec"

      env {
        NOMAD_ADDR = "http://100.125.210.126:4646"
        REPO_URL   = "https://github.com/eliott-monad/monad"
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
exec python3 "$REPO/scripts/nomad-job-hygiene.py" --repo "$REPO"
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "20s"
    }
  }
}
