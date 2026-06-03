# llm-governor — the overload watchdog. Every 5 minutes it runs the capacity governor
# (scripts/llm-scheduler.py govern --shed): any node over its policy caps (CPU%, mem%, or
# agent count from the Nomad var cluster/capacity) gets its sheddable LLM-agent excess stopped,
# so no node stays overloaded. This is the cluster's cardinal rule made automatic. Placement
# (the `place` command) is consulted by the foreman/assistant dispatch so work lands on the
# least-loaded engine-capable node in the first place; this job is the backstop.
#
# Runs on the Nomad server node (raw_exec) where a checkout + python3 + NOMAD_ADDR are present.

job "llm-governor" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${meta.role}"
    value     = "server"
  }

  constraint {
    attribute = "${meta.agent_home}"
    operator  = "regexp"
    value     = ".+"
  }

  periodic {
    cron             = "*/5 * * * *"
    prohibit_overlap = true
  }

  group "govern" {
    count = 1
    restart {
      attempts = 1
      mode     = "fail"
    }

    task "govern" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["-c", <<-EOC
          set -o pipefail
          for u in ubuntu e eliott bigo
          do
            h="$(getent passwd "$u" | cut -d: -f6)"
            [ -n "$h" ] || continue
            for repo in "$h/monad" "$h/.cache/monad-maint"
            do
              [ -d "$repo/.git" ] || continue
              [ -f "$repo/scripts/llm-scheduler.py" ] || continue
              NOMAD_ADDR="$(printenv NOMAD_ADDR 2>/dev/null)"
              if [ -z "$NOMAD_ADDR" ]; then
                NOMAD_ADDR="http://100.75.75.39:4646"
              fi
              export NOMAD_ADDR
              exec python3 "$repo/scripts/llm-scheduler.py" govern --shed
            done
          done
          echo "llm-governor: no checkout found" >&2
          exit 1
        EOC
        ]
      }
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
