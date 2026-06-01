job "cluster-dispatcher" {
  datacenters = ["dc1"]
  type        = "batch"

  # The autonomous pull-loop: every 10 min, read the frontier (open questions, court cases,
  # Lean candidates, emitted tasks) and dispatch the next items to agent-dispatch. The webhook
  # receiver is the push half; this is the safety net that catches anything not pushed.
  periodic {
    crons            = ["*/10 * * * *"]
    prohibit_overlap = true
    time_zone        = "America/Denver"
  }

  group "dispatcher" {
    count = 1

    task "loop" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "exec python3 \"$HOME/monad/meta/coordination/dispatcher.py\" --commit --max-dispatch 2"]
      }

      env {
        NOMAD_ADDR = "http://100.87.219.108:4646"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      kill_timeout = "10s"
    }
  }
}
