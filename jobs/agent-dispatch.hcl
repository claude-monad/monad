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
        args    = ["-c", "set -e; ROLE=$NOMAD_META_ROLE; SCOPE=$NOMAD_META_SCOPE; for u in ubuntu bigo e eliott; do home=$(getent passwd $u 2>/dev/null | cut -d: -f6); [ -n \"$home\" ] || continue; for repo in $home/monad $home/Documents/monad $home/Documents/GitHub/monad; do [ -f $repo/scripts/agent-dispatch.sh ] || continue; if [ $(id -u) = 0 ]; then exec su - $u -c \"NOMAD_META_ROLE=$ROLE NOMAD_META_SCOPE=$SCOPE MONAD_REPO_DIR=$repo exec bash $repo/scripts/agent-dispatch.sh\"; else export MONAD_REPO_DIR=$repo; exec bash $repo/scripts/agent-dispatch.sh; fi; done; done; for repo in /alloc/data/monad /local/monad; do [ -f $repo/scripts/agent-dispatch.sh ] || continue; export MONAD_REPO_DIR=$repo; exec bash $repo/scripts/agent-dispatch.sh; done; echo 'agent-dispatch: no monad checkout found' >&2; exit 1"]
      }

      env {
        LEAN_REPO_URL    = "https://github.com/eliott-monad/math-lean.git"
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
