job "math-formalizer" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */4 * * *"]
    prohibit_overlap = true
    time_zone        = "America/Denver"
  }

  # Formalization is delegated to automated codex work (see meta/FORMALIZATION-POLICY.md),
  # so this must land on a node with a ready codex engine. codex has its own rate-limit pool,
  # independent of the Max/Pro Claude accounts, so it never competes with the Claude research
  # agents for quota.
  constraint {
    attribute = "${meta.has_codex}"
    value     = "true"
  }

  group "formalizer" {
    count = 1

    task "session" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "exec $${MONAD_REPO_DIR:-/home/$${USER:-bigo}/monad}/scripts/formalizer-session.sh 0"]
      }

      env {
        LEAN_REPO_URL     = "https://github.com/eliott-monad/math-lean.git"
        MATH_REPO_URL     = "https://github.com/eliottcassidy2000/math.git"
        GIT_AUTHOR_NAME   = "monad-formalizer"
        GIT_AUTHOR_EMAIL  = "monad@cluster.local"
        MONAD_ENGINE      = "codex"   # delegate formalization to codex
        MONAD_CODEX_EFFORT = "high"   # think as hard as possible
      }

      # Heavier than before: the agent both formalizes AND does genuine mathematical
      # exploration (implications, extensions, connections) within the session.
      resources {
        cpu    = 2000
        memory = 4096
      }

      kill_timeout = "30s"
    }

    restart {
      attempts = 1
      interval = "1h"
      delay    = "5m"
      mode     = "fail"
    }
  }
}
