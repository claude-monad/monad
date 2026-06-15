# codex-cluster-coordinator — standing containerized Codex control-plane agent.
#
# Replaces the old Claude-only conductor path for cluster coordination. This agent lives in the
# existing monad-agent-mesh container image, stays online as a reactive mesh peer, and can be
# reached from this repo via scripts/codex-coordinator.sh without manually starting a Claude
# session in the checkout.

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

    task "agent" {
      driver = "docker"

      config {
        image        = "100.78.218.70:5000/monad-agent-mesh:uid${meta.agent_uid}"
        network_mode = "bridge"
        entrypoint = ["/bin/bash", "-c",
          "set -e; if [ ! -e /work/.git ]; then git clone --depth 50 \"$REPO_URL\" /work; fi; exec bash /work/meta/agent/mesh/mesh-agent-loop.sh"]
        volumes = [
          "${meta.agent_home}/.claude:/home/ubuntu/.claude",
          "${meta.agent_home}/.claude.json:/home/ubuntu/.claude.json",
          "${meta.agent_home}/.codex:/home/ubuntu/.codex",
        ]
      }

      template {
        data        = "TS_AUTHKEY={{ with nomadVar \"secret/agent-mesh\" }}{{ .tailscale_authkey }}{{ end }}"
        destination = "secrets/mesh.env"
        env         = true
      }

      env {
        AGENT_NAME   = "agent-cluster-coordinator"
        MONAD_ENGINE = "codex"
        REPO_URL     = "https://github.com/eliott-monad/monad"
        AGENT_ROLE   = <<-EOT
          You are the Monad cluster's standing Codex coordinator. Your top priority is to help operate the cluster through Codex only, not Claude. Focus on coordinating GitOps sync, deployment changes, Codex math exploration, Codex formalization, and safe cluster edits. Reply concisely, ask for evidence when needed, and prefer actionable steps that can be executed from the monad repo.
        EOT
      }

      resources {
        cpu    = 750
        memory = 1024
      }
    }
  }
}
