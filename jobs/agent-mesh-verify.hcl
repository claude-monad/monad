# agent-mesh-verify — proof that the multi-arch monad-agent-mesh image runs on an amd64 node.
#
# Runs the shared-registry image as an *idle* mesh peer (no PROMPT → entrypoint just starts the
# tsnet sidecar and waits), with NO engine-cred volume mounts, pinned to an amd64 node. If the
# alloc runs and `agent-msg peers` shows "agent-mesh-verify", the amd64 manifest pulled + ran +
# joined the tailnet. This is a throwaway verification (deploy → confirm peer → undeploy); it
# deliberately mounts nothing so it depends only on the image + the mesh authkey.
#
#   monad deploy jobs/agent-mesh-verify.hcl
#   agent-msg peers          # expect agent-mesh-verify to appear
#   monad undeploy agent-mesh-verify

job "agent-mesh-verify" {
  datacenters = ["dc1"]
  type        = "batch"

  # v1410-1 is amd64 and trusts the insecure shared registry — a clean amd64 proof target.
  constraint {
    attribute = "${node.unique.name}"
    value     = "V1410-1"
  }

  group "verify" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "agent" {
      driver = "docker"

      config {
        image        = "100.78.218.70:5000/monad-agent-mesh:latest"
        network_mode = "bridge"
      }

      # Tailscale auth key (reusable + ephemeral) from the encrypted Nomad variable.
      template {
        data        = "TS_AUTHKEY={{ with nomadVar \"secret/agent-mesh\" }}{{ .tailscale_authkey }}{{ end }}"
        destination = "secrets/mesh.env"
        env         = true
      }

      env {
        AGENT_NAME = "agent-mesh-verify"
        # no PROMPT → idle peer (no engine creds needed)
      }

      resources {
        cpu    = 256
        memory = 256
      }

      kill_timeout = "15s"
    }
  }
}
