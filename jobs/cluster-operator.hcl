job "cluster-operator" {
  datacenters = ["dc1"]
  type        = "service"

  # Run on a node with Claude CLI and an active account.
  # Prefer the server node so it has direct Nomad API access.
  constraint {
    attribute = "${meta.has_claude}"
    value     = "true"
  }

  group "operator" {
    count = 1

    # If the session drops (network timeout, crash), restart it.
    restart {
      attempts = 0
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "5m"
      unlimited      = true
    }

    task "remote-control" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["/root/monad/scripts/cluster-operator.sh"]
      }

      env {
        MONAD_REPO_DIR = "/root/monad"
        OPERATOR_NAME  = "monad-operator"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}
