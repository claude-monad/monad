# mesh-relay — the reliable real-time message bus for inter-LLM comms (replaces flaky
# ephemeral-tsnet P2P delivery). Runs on the always-up leader v1410-1, reachable by every node
# over the hosts' regular Tailscale at http://100.75.75.39:8477. agent-msg.sh talks to it;
# long-poll /recv gives real-time delivery. Address is advertised in the var infra/mesh-relay.

job "mesh-relay" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 80

  constraint {
    attribute = "${node.unique.name}"
    value     = "V1410-1"
  }

  group "relay" {
    count = 1
    reschedule {
      delay          = "10s"
      delay_function = "exponential"
      max_delay      = "1m"
      unlimited      = true
    }
    restart {
      attempts = 5
      interval = "5m"
      delay    = "10s"
      mode     = "delay"
    }

    network {
      mode = "host"
      port "relay" {
        static = 8477
      }
    }

    task "server" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args    = ["local/run.sh"]
      }

      template {
        destination = "local/run.sh"
        perms       = "755"
        data        = <<-SCRIPT
          #!/bin/bash
          set -uo pipefail
          W=/tmp/mesh-relay-monad
          if [ ! -d "$W/.git" ]; then
            rm -rf "$W"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$W"
          else
            git -C "$W" fetch -q origin main && git -C "$W" reset --hard -q origin/main || true
          fi
          export MESH_RELAY_PORT=8477
          exec python3 "$W/meta/agent/mesh/relay.py"
        SCRIPT
      }

      resources {
        cpu    = 150
        memory = 128
      }

      service {
        name     = "mesh-relay"
        port     = "relay"
        provider = "nomad"
        check {
          type     = "http"
          path     = "/health"
          interval = "20s"
          timeout  = "4s"
        }
      }
    }
  }
}
