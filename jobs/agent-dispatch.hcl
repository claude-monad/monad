job "agent-dispatch" {
  datacenters = ["dc1"]
  type        = "batch"

  # Parameterized: dispatched on demand by the webhook receiver and the dispatcher loop.
  #   nomad job dispatch -meta ROLE=formalizer -meta SCOPE="..." agent-dispatch
  parameterized {
    meta_required = ["ROLE"]
    meta_optional = ["SCOPE"]
  }

  group "agent" {
    count = 1

    # Run wherever a client is available. claudebox (pro) is the live worker; when the
    # max-account nodes rejoin, role-specific pinning can move back to dedicated jobs.
    task "session" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "exec \"$HOME/monad/scripts/agent-dispatch.sh\""]
      }

      env {
        LEAN_REPO_URL    = "https://github.com/claude-monad/math-lean.git"
        MATH_REPO_URL    = "https://github.com/eliottcassidy2000/math.git"
        GIT_AUTHOR_NAME  = "monad-claudebox"
        GIT_AUTHOR_EMAIL = "monad@cluster.local"
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      kill_timeout = "15s"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
