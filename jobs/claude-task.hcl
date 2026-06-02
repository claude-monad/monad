job "claude-task" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_required = ["prompt"]
    # engine = claude|codex|auto (default auto → node picks a ready engine)
    meta_optional = ["target_node", "target_account", "timeout", "task_id", "engine"]
  }

  group "session" {
    count = 1

    task "run" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # portable: repo is at $HOME/monad on every node (root or non-root)
        args    = ["-c", "exec \"$HOME/monad/scripts/run-claude-task.sh\""]
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
