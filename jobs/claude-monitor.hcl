job "claude-monitor" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/10 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  constraint {
    attribute = "${node.unique.name}"
    value     = "death-star"
  }

  group "monitor" {
    count = 1

    restart {
      attempts = 2
      interval = "10m"
      delay    = "15s"
      mode     = "fail"
    }

    task "claude-check" {
      driver = "raw_exec"

      config {
        command = "/home/e/monad/scripts/claude-monitor.sh"
      }

      env {
        HOME       = "/home/e"
        NOMAD_ADDR = "http://100.75.75.39:4646"
        PATH       = "/home/e/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
