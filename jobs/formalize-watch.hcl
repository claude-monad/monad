job "formalize-watch" {
  datacenters = ["dc1"]
  type        = "batch"

  # Poll the informal math repo often so math-lean tracks it closely. Cheap: one
  # git ls-remote per pass, a trigger only when HEAD actually moves.
  periodic {
    crons            = ["*/10 * * * *"]  # every 10 minutes
    prohibit_overlap = true
    time_zone        = "America/Denver"
  }

  # Runs on the server: needs Nomad API access (to force the formalizer + read/write
  # the formalize state/inbox vars) and the monad-repo volume for the events log.
  constraint {
    attribute = "${meta.role}"
    value     = "server"
  }

  group "watch" {
    count = 1

    volume "monad-repo" {
      type      = "host"
      source    = "monad-repo"
      read_only = false
    }

    task "poll" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "exec $${MONAD_REPO_DIR:-/home/bigo/Documents/monad}/scripts/formalize-watch.sh"]
      }

      volume_mount {
        volume      = "monad-repo"
        destination = "/monad"
        read_only   = false
      }

      env {
        MONAD_REPO_DIR = "/monad"
        MATH_REPO_URL  = "https://github.com/eliottcassidy2000/math.git"
        MATH_BRANCH    = "main"
        FORMALIZER_JOB = "math-formalizer"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    restart {
      attempts = 1
      interval = "10m"
      delay    = "1m"
      mode     = "fail"
    }
  }
}
