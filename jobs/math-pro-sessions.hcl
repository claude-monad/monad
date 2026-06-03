// math-pro-sessions: dispatches math research sessions to the two new pro machines
// (windesk and mac-mini). Parameterized by ROLE so the same job serves researcher,
// compute, and formalizer workloads on these nodes.
//
// Usage:
//   nomad job dispatch -meta ROLE=researcher -meta SCOPE="" math-pro-sessions
//   nomad job dispatch -meta ROLE=compute    math-pro-sessions

job "math-pro-sessions" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    meta_required = ["ROLE"]
    meta_optional = ["SCOPE"]
  }

  // Constrain to math_agent=true nodes with the pro account.
  constraint {
    attribute = "${meta.math_agent}"
    value     = "true"
  }

  constraint {
    attribute = "${meta.claude_account}"
    value     = "pro"
  }

  group "agent" {
    count = 1

    task "session" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", <<-CMD
          set -e
          ROLE=${NOMAD_META_ROLE}
          SCOPE=${NOMAD_META_SCOPE:-}

          # Find monad repo across common user homes
          MONAD=""
          for u in ubuntu bigo e eliott; do
            home=$(getent passwd $u 2>/dev/null | cut -d: -f6)
            [ -n "$home" ] || continue
            for repo in "$home/monad" "$home/Documents/GitHub/monad" "$home/Documents/monad"; do
              [ -f "$repo/scripts/agent-dispatch.sh" ] && MONAD="$repo" && break 2
            done
          done
          [ -n "$MONAD" ] || { echo "monad not found"; exit 1; }

          export MONAD_REPO_DIR="$MONAD"
          export NOMAD_META_ROLE="$ROLE"
          export NOMAD_META_SCOPE="$SCOPE"
          exec bash "$MONAD/scripts/agent-dispatch.sh"
        CMD
        ]
      }

      env {
        MATH_REPO_URL    = "https://github.com/eliottcassidy2000/math.git"
        LEAN_REPO_URL    = "https://github.com/eliott-monad/math-lean.git"
        GIT_AUTHOR_NAME  = "monad-pro"
        GIT_AUTHOR_EMAIL = "monad@cluster.local"
      }

      resources {
        cpu    = 2000
        memory = 3072
      }

      kill_timeout = "15s"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
