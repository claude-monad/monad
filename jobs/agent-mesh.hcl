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

  # Repo code at /work now comes from a FRESH per-alloc clone of the correct origin
  # (https://github.com/eliott-monad/monad), NOT a host bind-mount — exactly like
  # jobs/fleet-builder.hcl. This removes the dependency on the host's `$agent_home/monad`
  # checkout, which on the amd64 nodes tracks the WRONG remote (eliottcassidy2000/monad@4f6a4dc,
  # missing meta/agent/run-agent.sh → briefed agents died exit 127) and can't be fast-forwarded.
  # See fleet/projects/agent-mesh-alloc-clone.md (the non-destructive alternative to #11).
  #
  # Cred mounts (.claude/.claude.json/.codex) STILL derive from the dynamic node meta
  # `agent_home`, set per node with:  nomad node meta apply -node-id <id> agent_home=<path>
  # Wired: oraclebox1=/home/ubuntu, V1410-1=/home/e, bigo-server=/home/bigo.
  #
  # Placement is gated on `agent_mesh_ready=true`. With the per-alloc clone + the per-uid image
  # (agent_uid meta, see amd64-agent-uid-image), the amd64 blockers are cleared, so amd64 nodes
  # can be flipped on:  nomad node meta apply -node-id <id> agent_mesh_ready=true.
  # Tracked in fleet/projects/agent-mesh-cred-portability.md + agent-mesh-alloc-clone.md.
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
        # trust it via scripts/ensure-registry-trust.sh. Multi-arch manifest (amd64+arm64).
        # Per-uid tag selected by node meta `agent_uid` so the in-image `ubuntu` user matches
        # the host's credentialed user uid → host-mounted mode-600 creds stay readable. Tags
        # built by `agent-mesh-image-build` (-meta uid=/gid=/tag=uid<N>); `latest` stays uid1001.
        # Set per node: nomad node meta apply -node-id <id> agent_uid=<uid>
        # Wired: oraclebox1=1001, V1410-1=1000. See fleet/projects/amd64-agent-uid-image.md.
        image        = "100.78.218.70:5000/monad-agent-mesh:uid${meta.agent_uid}"
        network_mode = "bridge"
        # FRESH per-alloc working tree: clone the correct-origin repo into the image's
        # /work (pre-created + chowned to ubuntu in the Dockerfile) if it isn't already a
        # git checkout, then hand off to the image's normal agent entrypoint. Mirrors
        # jobs/fleet-builder.hcl — no host monad mount, so a stale/wrong-origin host checkout
        # can't break briefed agents. The clone is anonymous (public repo).
        entrypoint = ["/bin/bash", "-c",
          "set -e; if [ ! -e /work/.git ]; then echo '[agent-mesh] cloning fresh working tree'; git clone --depth 50 \"$REPO_URL\" /work; fi; exec /usr/local/bin/agent-entrypoint"]
        # Cred sources derive from the node's wired cred home (meta.agent_home); targets stay
        # at the image's /home/ubuntu so the in-container claude/codex find creds regardless of
        # which host user owns them.
        volumes = [
          "${meta.agent_home}/.claude:/home/ubuntu/.claude",
          "${meta.agent_home}/.claude.json:/home/ubuntu/.claude.json",
          "${meta.agent_home}/.codex:/home/ubuntu/.codex",
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
        REPO_URL      = "https://github.com/eliott-monad/monad"   # cloned fresh into /work
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      kill_timeout = "15s"
    }
  }
}
