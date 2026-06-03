job "remote-control" {
  datacenters = ["dc1"]
  type        = "system"

  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }
  # Exclude Windows (no bash)
  constraint {
    attribute = "${attr.kernel.name}"
    operator  = "!="
    value     = "windows"
  }

  group "session" {
    restart {
      attempts = 3
      interval = "30m"
      delay    = "60s"
      mode     = "delay"
    }

    task "remote" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-c", <<-EOC
          for u in e bigo ubuntu eliott
          do
            h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6 || true)"
            [ -n "$h" ] || continue
            [ -f "$h/.claude/.credentials.json" ] || continue
            su - "$u" -c "command -v claude >/dev/null 2>&1" 2>/dev/null || continue
            REPO=""
            for r in "$h/monad" "$h/Documents/monad" "$h/.cache/monad-rc"
            do
              [ -f "$r/CLAUDE.md" ] && REPO="$r"
            done
            if [ -z "$REPO" ]
            then
              REPO="$h/.cache/monad-rc"
              su - "$u" -c "git clone --depth 1 https://github.com/eliott-monad/monad '$REPO'" 2>/dev/null || true
            fi
            [ -f "$REPO/CLAUDE.md" ] || REPO="$h"
            echo "[remote-control] Starting as $u from $REPO"
            exec su - "$u" -c "cd '$REPO' && exec claude remote-control --name 'maint-$(hostname)' --permission-mode bypassPermissions --spawn same-dir"
          done
          echo "[remote-control] No claude user found, idling"
          while true
          do
            sleep 3600
          done
        EOC
        ]
      }

      env {
        NOMAD_ADDR = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 100
        memory = 256
      }

      kill_timeout = "10s"
    }
  }
}
