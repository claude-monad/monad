job "claude-task" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_required = ["prompt"]
    meta_optional = ["target_node", "target_account", "timeout", "task_id"]
  }

  group "session" {
    count = 1

    task "run" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["/root/monad/scripts/run-claude-task.sh"]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
