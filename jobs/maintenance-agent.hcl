# maintenance-agent — a standing maintenance agent (claude OR codex) on every node.
#
# system job → exactly one alloc per eligible node. Each runs scripts/maintenance-agent.sh,
# which drains brain-delegated tasks from this node's queue (monad/maintenance/<node>/queue/*),
# runs periodic light self-maintenance, and reports to Nomad vars + logs/events.jsonl. Engine
# is auto (whatever the node has ready). No concurrency cap — the brain can also dispatch
# extra one-shot agents on top via claude-task.
#
# Delegate a task to a node's agent:
#   nomad var put monad/maintenance/<node>/queue/<id> prompt="...your maintenance task..."
# Read results:
#   nomad var get monad/maintenance/<node>/results/<id>   (and .../last for self-passes)

job "maintenance-agent" {
  datacenters = ["dc1"]
  type        = "system"

  # Linux nodes with raw_exec (the bash agent script). Windows agents come later.
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "agent" {
    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "maintainer" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # repo is at $HOME/monad on every node
        args    = ["-c", "exec \"$HOME/monad/scripts/maintenance-agent.sh\""]
      }

      env {
        MAINT_INTERVAL = "1800"   # self-maintenance pass cadence (s)
        POLL           = "60"     # delegated-queue poll cadence (s)
        MONAD_ENGINE   = "auto"   # claude|codex|auto
        NOMAD_ADDR     = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 300
        memory = 512
      }

      kill_timeout = "15s"
    }
  }
}
