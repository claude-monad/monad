job "math-formalizer" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */4 * * *"]  # safety-net sweep; formalize-watch forces runs on commits
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
        # Find the credentialed user's monad checkout (that user is logged in to codex) and
        # exec the formalizer session as them, so engine creds + repo path line up. Falls back
        # to an alloc-local clone. Mirrors jobs/maintenance-agent.hcl — the pattern that places
        # reliably on this cluster (no host volume, no HCL ${..:-} interpolation).
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$home" ] || continue
            for repo in "$home/monad" "$home/Documents/monad"; do
              [ -f "$repo/scripts/formalizer-session.sh" ] || continue
              if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then
                exec su - "$u" -c "exec bash '$repo/scripts/formalizer-session.sh' 0"
              else
                exec bash "$repo/scripts/formalizer-session.sh" 0
              fi
            done
          done
          WORK="$NOMAD_TASK_DIR/monad"
          [ -n "$NOMAD_TASK_DIR" ] || WORK="/tmp/formalizer-monad"
          if command -v git >/dev/null 2>&1; then
            [ -f "$WORK/scripts/formalizer-session.sh" ] || { rm -rf "$WORK"; \
              git clone --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || true; }
            if [ -f "$WORK/scripts/formalizer-session.sh" ]; then
              echo "math-formalizer: using alloc-local clone at $WORK" >&2
              exec bash "$WORK/scripts/formalizer-session.sh" 0
            fi
          fi
          echo "math-formalizer: no monad checkout found and clone failed" >&2
          exit 1
        EOC
        ]
      }

      env {
        LEAN_REPO_URL      = "https://github.com/eliott-monad/math-lean.git"
        MATH_REPO_URL      = "https://github.com/eliottcassidy2000/math.git"
        GIT_AUTHOR_NAME    = "monad-formalizer"
        GIT_AUTHOR_EMAIL   = "monad@cluster.local"
        MONAD_ENGINE       = "codex"   # delegate formalization to codex
        MONAD_CODEX_EFFORT = "high"    # think as hard as possible
        NOMAD_ADDR         = "http://100.75.75.39:4646"  # read the formalize inbox var
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
