# agent-mesh — run a containerized agent that is its own node on the Tailscale agent mesh.
#
# Each alloc joins the tailnet as agent-<name> (own IP + mailbox via the tsnet sidecar) and
# runs claude or codex with a briefing on how to message peers (`agent-msg`). With no prompt
# it idles as a persistent, reachable peer. Agents discover + coordinate with each other over
# Tailscale to sort out problems.
#
# Build the image first:  meta/agent/mesh/build-image.sh   (image: monad-agent-mesh)
# Launch a mesh agent:
#   nomad job dispatch -meta agent_name=agent-helper -meta prompt="…task…" -meta engine=codex agent-mesh
# Launch an idle peer:
#   nomad job dispatch -meta agent_name=agent-idle agent-mesh

job "agent-mesh" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_optional = ["agent_name", "prompt", "engine", "timeout"]
  }

  # Pinned to oraclebox1 — NOT for arch reasons anymore (the image is now a multi-arch
  # amd64+arm64 manifest, verified to pull+run on amd64), but because the volume mounts below
  # hard-code the /home/ubuntu engine-cred layout, which today only oraclebox1 has. Generalizing
  # this briefed job to amd64 nodes (bigo-server, v1410-1) needs a node-portable cred path
  # (their Claude creds live outside /home/ubuntu) — tracked as a follow-up. The amd64 image is
  # already proven via jobs/agent-mesh-verify.hcl (an idle peer with no cred mounts).
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "agent" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "agent" {
      driver = "docker"

      config {
        # Pulled from the shared cluster registry (jobs/registry.hcl, Nomad var
        # infra/registry = 100.78.218.70:5000). build-image.sh pushes here; nodes
        # trust it via scripts/ensure-registry-trust.sh. Now a multi-arch manifest
        # (amd64+arm64), so the oraclebox1 pin is gone — see the constraints above.
        image        = "100.78.218.70:5000/monad-agent-mesh:latest"
        network_mode = "bridge"
        volumes = [
          "/home/ubuntu/.claude:/home/ubuntu/.claude",
          "/home/ubuntu/.claude.json:/home/ubuntu/.claude.json",
          "/home/ubuntu/.codex:/home/ubuntu/.codex",
          "/home/ubuntu/monad:/work",
        ]
      }

      # Tailscale auth key (reusable + ephemeral) from the encrypted Nomad variable.
      template {
        data        = "TS_AUTHKEY={{ with nomadVar \"secret/agent-mesh\" }}{{ .tailscale_authkey }}{{ end }}"
        destination = "secrets/mesh.env"
        env         = true
      }

      env {
        AGENT_NAME    = "${NOMAD_META_agent_name}"
        PROMPT        = "${NOMAD_META_prompt}"
        MONAD_ENGINE  = "${NOMAD_META_engine}"
        AGENT_TIMEOUT = "${NOMAD_META_timeout}"
        RUN_AGENT     = "/work/meta/agent/run-agent.sh"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      kill_timeout = "15s"
    }
  }
}
