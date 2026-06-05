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

  # Unix nodes with raw_exec (the bash agent script). Windows agents come later.
  constraint {
    attribute = "${attr.kernel.name}"
    operator  = "regexp"
    value     = "^(linux|darwin)$"
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
        # Find the user whose home has the monad checkout (that user is logged in to the
        # engines) and exec the agent as them. Nomad runs as root here, so we su to the
        # credentialed user — this fixes both the repo path and engine-credential location.
        # Falls back to running directly if we're already a non-root user with the repo.
        args = ["-c", <<-EOC
          # If raw_exec already runs as a credentialed user, prefer that user's checkout.
          if [ "$(id -u)" != 0 ]; then
            for repo in "$HOME/monad" "$HOME/Documents/monad"; do
              [ -f "$repo/scripts/maintenance-agent.sh" ] || continue
              if [ -d "$repo/.git" ] &&
                 git -C "$repo" diff --quiet 2>/dev/null &&
                 git -C "$repo" diff --cached --quiet 2>/dev/null; then
                git -C "$repo" pull --ff-only origin main >/dev/null 2>&1 || true
              fi
              exec bash "$repo/scripts/maintenance-agent.sh"
            done
          fi
          # 1) Prefer a credentialed user's host checkout (that user is logged in to the
          #    engines). Run as them so engine creds + repo path both line up.
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
            if [ -z "$home" ] && [ "$u" = e ]; then home="/Users/e"; fi
            if [ -z "$home" ] && [ "$u" = eliott ]; then home="/Users/eliott"; fi
            [ -n "$home" ] || continue
            for repo in "$home/monad" "$home/Documents/monad"; do
              [ -f "$repo/scripts/maintenance-agent.sh" ] || continue
              if [ -d "$repo/.git" ] &&
                 git -C "$repo" diff --quiet 2>/dev/null &&
                 git -C "$repo" diff --cached --quiet 2>/dev/null; then
                git -C "$repo" pull --ff-only origin main >/dev/null 2>&1 || true
              fi
              if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then
                exec su - "$u" -c "exec bash '$repo/scripts/maintenance-agent.sh'"
              else
                exec bash "$repo/scripts/maintenance-agent.sh"
              fi
            done
          done
          # 2) Portable fallback (e.g. amd64 nodes with no host checkout): clone a fresh repo
          #    into this alloc's task dir and run from there. Needs only git + network. Engine
          #    creds may be absent, but the agent still attaches to the mesh (mesh-attach runs
          #    before the engine check) and can drain delegated tasks. Reversible: lives with
          #    the alloc, removed on stop. See fleet/projects/amd64-maintenance-mesh.md.
          # Bare $NOMAD_TASK_DIR (no braces) so neither HCL nor Nomad's runtime arg
          # interpolation touches it — bash expands the env var Nomad sets for raw_exec.
          WORK="$NOMAD_TASK_DIR/monad"
          [ -n "$NOMAD_TASK_DIR" ] || WORK="/tmp/maint-monad"
          if command -v git >/dev/null 2>&1; then
            [ -f "$WORK/scripts/maintenance-agent.sh" ] || { rm -rf "$WORK"; \
              git clone --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || true; }
            if [ -f "$WORK/scripts/maintenance-agent.sh" ]; then
              echo "maintenance-agent: using alloc-local clone at $WORK" >&2
              exec bash "$WORK/scripts/maintenance-agent.sh"
            fi
          fi
          echo "maintenance-agent: no monad checkout found and clone failed; idling" >&2
          while true; do sleep 180; done
        EOC
        ]
      }

      env {
        MAINT_INTERVAL = "1800"   # self-maintenance pass cadence (s)
        POLL           = "60"     # delegated-queue poll cadence (s)
        SELF_TIMEOUT   = "900"    # self-pass wall-clock budget; oraclebox1 Codex hit 600s
        MONAD_ENGINE   = "auto"   # claude|codex|auto
        NOMAD_ADDR     = "http://100.75.75.39:4646"
        NODE_NAME      = "${node.unique.name}"
        MONAD_MAINT_REV = "self-timeout-20260603" # bump for script-only refreshes
      }

      # Mostly an idle poller (60s sleep loop); LLM self-passes burst above this
      # reservation since raw_exec doesn't hard-cap CPU. Kept modest so the standing
      # agent always fits on busy nodes (e.g. oraclebox1 also runs conductor/foreman/
      # dashboard/postgres/registry + transient fleet-builders).
      resources {
        cpu    = 100
        memory = 256
      }

      kill_timeout = "15s"
    }
  }
}
