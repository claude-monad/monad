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
          set -uo pipefail
          for u in ubuntu e eliott bigo; do
            h="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$h" ] || continue
            [ -d "$h/monad/.git" ] || continue
            su - "$u" -c "cd '$h/monad' && git fetch -q origin main && git reset --hard origin/main -q" 2>/dev/null || true
            export NOMAD_ADDR="$${NOMAD_ADDR:-http://100.75.75.39:4646}"
            exec python3 "$h/monad/scripts/llm-scheduler.py" govern --shed
          done
          echo "llm-governor: no checkout found" >&2; exit 1
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
