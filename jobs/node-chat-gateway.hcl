# node-chat-gateway — a per-node chat gateway so the dashboard can talk to a Claude
# instance ON this node. Same contract as the conductor (conductor/gateway.py):
#   POST http://<node-tailnet-ip>:8201/ask {"text": "..."} -> {"reply": "..."}
# with per-gateway conversation continuity. Lightweight raw_exec (no docker): the node
# already has claude + python + the repo, and the nomad client runs as the engine user.
#
# Pinned to claudebox here; clone this stanza (change the constraint + name) to add a
# chattable brain on any other node that has a logged-in claude.
job "node-chat-gateway" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.unique.name}"
    value     = "claudebox"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "gateway" {
    count = 1

    # Host networking so the gateway binds the node's Tailscale interface.
    network {
      mode = "host"
      port "ask" {
        static = 8201
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    task "gateway" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<SCRIPT
#!/bin/bash
set -uo pipefail
# Use the node's own checkout if present (has the logged-in engine + CONDUCTOR.md);
# else clone fresh. gateway.py drives `claude` with conversation continuity.
REPO="$HOME/monad"
[ -d "$REPO/.git" ] || REPO="$NOMAD_TASK_DIR/monad"
if [ ! -d "$REPO/.git" ]; then
  git clone --depth 1 https://github.com/eliott-monad/monad "$REPO" || { echo "clone failed"; exit 1; }
fi
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin"
export CONDUCTOR_BIND="0.0.0.0"
export CONDUCTOR_PORT="8201"
export CONDUCTOR_WORKDIR="$REPO"
export CONDUCTOR_SYSPROMPT="$REPO/conductor/CONDUCTOR.md"
export CONDUCTOR_SESSION="$NOMAD_TASK_DIR/.session-id"
export NOMAD_ADDR="$${NOMAD_ADDR:-http://100.75.75.39:4646}"
echo "[node-chat-gateway] binding $CONDUCTOR_BIND:$CONDUCTOR_PORT (repo=$REPO)"
exec python3 "$REPO/conductor/gateway.py"
SCRIPT
      }

      env {
        NOMAD_ADDR = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      service {
        name     = "node-chat-gateway-claudebox"
        port     = "ask"
        provider = "nomad"

        check {
          type     = "http"
          path     = "/health"
          port     = "ask"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
