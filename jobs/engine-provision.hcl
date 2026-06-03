# engine-provision — make EVERY node able to run BOTH engines. A system job (one alloc per
# Linux node) that loops meta/agent/provision-node.sh: ensure CLIs installed + on PATH, unlock
# the run-user, and install the shared Claude+Codex creds from the encrypted var store
# (newest-token-wins). This is what turns cred portability into "claude+codex run anywhere".
#
# Safe: cred-sync only adopts a fresher token and only writes back a validated one (the single
# Max account is the owner's only cred). Inspect a node:  nomad alloc logs <alloc>

job "engine-provision" {
  datacenters = ["dc1"]
  type        = "system"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "provision" {
    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "loop" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      env {
        NOMAD_ADDR    = "http://100.75.75.39:4646"
        CRED_ACCOUNT  = "max"
        PROVISION_INT = "300"
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          W=/tmp/engine-provision-monad
          while true; do
            if [ ! -d "$W/.git" ]; then
              rm -rf "$W"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$W" 2>/dev/null || true
            else
              git -C "$W" fetch -q origin main 2>/dev/null && git -C "$W" reset --hard -q origin/main 2>/dev/null || true
            fi
            if [ -f "$W/meta/agent/provision-node.sh" ]; then
              NOMAD_ADDR="$NOMAD_ADDR" CRED_ACCOUNT="$CRED_ACCOUNT" bash "$W/meta/agent/provision-node.sh" || true
            else
              echo "provision: clone missing provision-node.sh — retrying"
            fi
            sleep "$${PROVISION_INT:-300}"
          done
        SCRIPT
      }

      resources {
        cpu    = 150
        memory = 200
      }
    }
  }
}
