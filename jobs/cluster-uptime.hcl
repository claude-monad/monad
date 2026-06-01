job "cluster-uptime" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/10 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  constraint {
    attribute = "${meta.role}"
    value     = "server"
  }

  group "uptime-check" {
    count = 1

    task "measure" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["/root/monad/scripts/cluster-uptime-check.sh"]
      }

      env {
        MONAD_REPO_DIR = "/root/monad"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    restart {
      attempts = 1
      interval = "10m"
      delay    = "30s"
      mode     = "fail"
    }
  }
}
