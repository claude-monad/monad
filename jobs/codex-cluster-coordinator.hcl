# codex-cluster-coordinator — standing containerized Codex control-plane agent.
#
# Replaces the old Claude-only conductor path for cluster coordination. This service runs the
# Codex HTTP gateway in a container so it is always reachable from this repo without manually
# starting a Claude session in the checkout.

job "codex-cluster-coordinator" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 75

  constraint {
    attribute = "${meta.agent_mesh_ready}"
    value     = "true"
  }
  constraint {
    attribute = "${meta.has_codex}"
    value     = "true"
  }

  group "coordinator" {
    count = 1

    spread {
      attribute = "${node.unique.name}"
      weight    = 100
    }

    reschedule {
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }

    restart {
      attempts = 5
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    network {
      mode = "host"
      port "http" {
        static = 8310
      }
    }

    task "agent" {
      driver = "docker"

      config {
        image        = "100.78.218.70:5000/monad-agent-mesh:uid${meta.agent_uid}"
        network_mode = "host"
        entrypoint = ["/bin/bash", "-c",
          "set -e; if [ ! -e /work/.git ]; then git clone --depth 50 \"$REPO_URL\" /work; fi; exec python3 /work/codex-worker/gateway.py"]
        volumes = [
          "${meta.agent_home}/.claude:/home/ubuntu/.claude",
          "${meta.agent_home}/.claude.json:/home/ubuntu/.claude.json",
          "${meta.agent_home}/.codex:/home/ubuntu/.codex",
        ]
      }

      env {
        REPO_URL        = "https://github.com/eliott-monad/monad"
        CODEX_BIND      = "0.0.0.0"
        CODEX_PORT      = "8310"
        CODEX_WORKDIR   = "/work"
        CODEX_SANDBOX   = "bypass"
        CODEX_TIMEOUT   = "900"
        CODEX_PREAMBLE  = "/work/codex-worker/cluster-coordinator.md"
        ENABLE_INTERACTIVE = "0"
      }

      resources {
        cpu    = 750
        memory = 1024
      }

      service {
        name     = "codex-cluster-coordinator"
        port     = "http"
        provider = "nomad"
        check {
          type     = "http"
          path     = "/health"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }
  }
}
