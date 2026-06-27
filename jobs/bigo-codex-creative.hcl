job "bigo-codex-creative" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "agent" {
    count = 1

    restart {
      attempts = 3
      delay    = "30s"
      interval = "30m"
      mode     = "delay"
    }

    task "creative" {
      driver = "raw_exec"
      user   = "bigo"

      config {
        command = "/bin/bash"
        args = ["-lc", <<-EOC
          exec /home/bigo/Documents/monad/scripts/launch-codex-math-swarm.sh
        EOC
        ]
      }

      env {
        HOME                = "/home/bigo"
        CODEX_HOME          = "/home/bigo/.codex"
        USER_HOME           = "/home/bigo"
        SWARM_BASE_DIR      = "/home/bigo/.cache/monad-swarm/bigo-codex-creative"
        MONAD_CODEX_EFFORT  = "high"
        AGENT_TIMEOUT       = "2400"
        SWARM_SLEEP_SECONDS = "1200"
        SWARM_NICE_LEVEL    = "12"
        MATH_SPARSE_CHECKOUT = "1"
        MATH_GIT_FILTER_BLOBS = "1"
      }

      resources {
        cpu    = 300
        memory = 512
      }

      kill_timeout = "20s"
    }
  }
}
