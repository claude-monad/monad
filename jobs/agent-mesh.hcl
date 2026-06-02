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

  # Cred mounts are now node-portable: their sources derive from the dynamic node meta
  # `agent_home` (the dir holding .claude/.claude.json/.codex + a monad checkout for that
  # node's logged-in user), set per node with:
  #   nomad node meta apply -node-id <id> agent_home=<path>
  # Wired: oraclebox1=/home/ubuntu, V1410-1=/home/e, bigo-server=/home/bigo.
  #
  # Placement is gated on `agent_mesh_ready=true` (set only on oraclebox1 today) rather than the
  # old node-name pin. Two blockers keep briefed agents off the amd64 nodes for now (the mesh
  # sidecar itself works there — verified an agent join the tailnet on V1410-1):
  #   1. their $agent_home/monad checkouts are STALE (missing meta/agent/run-agent.sh) → the
  #      /work mount overlays outdated code (exit 127). They need a fast-forward.
  #   2. this image runs ubuntu as uid 1001 (oraclebox1); V1410-1's user `e` is uid 1000, so
  #      mode-600 creds aren't readable — needs a per-host image build (Dockerfile AGENT_UID).
  # Flip a node on once fixed: nomad node meta apply -node-id <id> agent_mesh_ready=true.
  # Tracked in fleet/projects/agent-mesh-cred-portability.md.
  constraint {
    attribute = "${meta.agent_mesh_ready}"
    value     = "true"
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
        # Sources derived from the node's wired cred home (meta.agent_home); targets stay at
        # the image's /home/ubuntu so the in-container claude/codex find creds regardless of
        # which host user owns them.
        volumes = [
          "${meta.agent_home}/.claude:/home/ubuntu/.claude",
          "${meta.agent_home}/.claude.json:/home/ubuntu/.claude.json",
          "${meta.agent_home}/.codex:/home/ubuntu/.codex",
          "${meta.agent_home}/monad:/work",
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
