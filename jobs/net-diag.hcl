# net-diag - cluster networking investigation.
#
# A system job: Nomad runs one allocation on every eligible raw_exec node so
# each machine probes the network from its own vantage point.

job "net-diag" {
  datacenters = ["dc1"]
  type        = "system"

  group "diag" {
    task "probe" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args = ["-c", <<SCRIPT
set -euo pipefail

for repo in \
  "$MONAD_REPO_DIR" \
  /home/e/monad \
  /home/bigo/Documents/monad \
  /Users/e/Documents/GitHub/monad
do
  if [ -x "$repo/scripts/net-diag.sh" ]; then
    exec "$repo/scripts/net-diag.sh" --loop 600
  fi
done

echo "net-diag.sh not found in known Monad repo paths" >&2
exit 127
SCRIPT
        ]
      }

      env {
        MONAD_REPO_DIR = "/home/e/monad"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
