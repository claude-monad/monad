# math-explore — a one-shot autonomous Codex DISCOVERY session on the math repo.
#
# Dispatched by scripts/math-explore-watch.sh or the GitHub webhook whenever the math repo
# (eliottcassidy2000/math) gets new commits: spin up Codex explorer sessions that build on the fresh work and try to
# discover NEW theorems / proofs / connections on their own (prompt: scripts/prompts/explorer.md).
# Commits its findings back to the math repo, which in turn triggers more exploration +
# formalization — a self-sustaining research loop.
#
# Placement: any Codex-ready node (node meta has_codex, set by the engine provisioner). Load is
# kept safe by the governor (the watch checks `place` before
# dispatching) + Nomad's spread scheduler.
#
#   nomad job dispatch -meta seed="..." -meta angle="..." math-explore

job "math-explore" {
  datacenters = ["dc1"]
  type        = "batch"
  priority    = 60

  parameterized {
    payload       = "optional"
    meta_optional = ["seed", "angle", "role", "depth"]
  }

  meta {
    role  = "explorer"
    depth = "0"
    seed  = ""
    angle = ""
  }

  constraint {
    attribute = "${meta.has_codex}"
    value     = "true"
  }
  # Linux only: the engine provisioner (which keeps creds fresh + advertises has_codex) is
  # Linux-only, so a non-Linux node's has_codex can be stale.
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "explore" {
    count = 1
    # One-shot deep session. Don't pile up retries if a node is busy; the watch re-dispatches
    # on the next commit batch anyway.
    reschedule {
      attempts  = 1
      interval  = "1h"
      delay     = "30s"
      unlimited = false
    }
    restart {
      attempts = 0
      mode     = "fail"
    }

    task "session" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        # Clone monad fresh (node-portable), then run the shared math-session launcher with the
        # explorer role; SEED carries the recent-commit context + a per-session angle.
        args = ["-c", "W=/tmp/math-explore-monad; if [ -d \"$W/.git\" ]; then git -C \"$W\" fetch -q origin main && git -C \"$W\" reset --hard -q origin/main || true; else rm -rf \"$W\"; git clone -q --depth 1 https://github.com/eliott-monad/monad \"$W\"; fi; exec bash \"$W/scripts/math-session.sh\" \"${NOMAD_META_role}\" 100"]
      }

      env {
        MATH_REPO_URL    = "https://github.com/eliottcassidy2000/math.git"
        GIT_AUTHOR_NAME  = "monad-explorer"
        GIT_AUTHOR_EMAIL = "monad@cluster.local"
        SEED             = "${NOMAD_META_seed}${NOMAD_META_angle}"
        MONAD_ENGINE     = "codex"
        MONAD_CODEX_EFFORT = "high"
        MONAD_TIMEOUT    = "2400"
        MATH_SPARSE_CHECKOUT = "1"
        MATH_GIT_FILTER_BLOBS = "1"
        NOMAD_ADDR       = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      kill_timeout = "15s"
    }
  }
}
