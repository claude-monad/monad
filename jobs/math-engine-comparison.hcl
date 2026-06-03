job "math-engine-comparison" {
  datacenters = ["dc1"]
  type        = "batch"

  # Run on death-star (max-2 account, has both claude and codex)
  constraint {
    attribute = "${meta.claude_account}"
    value     = "max-2"
  }

  group "compare" {
    count = 1

    task "run" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["/home/e/monad/scripts/math-engine-compare.sh"]
      }

      env {
        MATH_REPO_URL    = "https://github.com/eliottcassidy2000/math.git"
        NOMAD_ADDR       = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 2000
        memory = 2048
      }

      kill_timeout = "30s"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
