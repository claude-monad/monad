# dual-engine-math-test — a self-scheduling CLUSTER CAPABILITY TEST.
#
# A Nomad PERIODIC job: the cluster scheduler fires it automatically (no manual
# trigger). Each run executes ONE bounded autonomous math-research session with
# claude AND one with codex, then reports back to the cluster (events.jsonl, a
# committed report, a math-fleet broadcast). Pinned to a node that has both engines.
#
# This is a one-shot demonstration: it is purged after the first auto-run reports.
job "dual-engine-math-test" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons             = ["*/5 * * * *"]   # fires automatically every 5 min
    prohibit_overlap  = true              # never two runs at once (each shares one account)
    time_zone         = "UTC"
  }

  # Pin to oraclebox1: advertises agent_engines = claude,codex, has the repo + creds.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "test" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "run" {
      driver = "raw_exec"
      user   = "ubuntu"          # claude/codex refuse to run as root; creds live in ~ubuntu

      config {
        command = "/bin/bash"
        args    = ["-c", "exec \"$HOME/monad/scripts/dual-engine-math-test.sh\""]
      }

      env {
        MONAD_REPO_DIR    = "/home/ubuntu/monad"
        MATH_REPO_URL     = "https://github.com/eliottcassidy2000/math.git"
        PER_ENGINE_TIMEOUT = "720"
        HOME              = "/home/ubuntu"
      }

      resources {
        cpu    = 2000
        memory = 2048
      }

      kill_timeout = "30s"
    }
  }
}
