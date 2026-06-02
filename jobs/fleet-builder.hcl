# fleet-builder — a mesh agent that builds the cluster's backlog projects.
#
# Like a mesh agent, but host-networked + nomad-capable so it can actually deploy workloads
# and reach the Nomad API + the tailnet. Runs the "builder" role (meta/agent/prompts/builder.md):
# claim a backlog project, coordinate placement on the mesh, build it via GitOps, repeat.
#
# Launch one:  nomad job dispatch -meta agent_name=agent-builder-1 -meta engine=codex fleet-builder
# (the foreman, scripts/fleet-foreman.sh, keeps a few running.)

job "fleet-builder" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_optional = ["agent_name", "engine", "role", "timeout"]
  }

  # Where the image registry, engine creds, and docker live. Expands once shared-registry +
  # multiarch images exist (then builders can run on any node).
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "builder" {
    count = 1
    restart {
      attempts = 0
      mode     = "fail"
    }

    task "builder" {
      driver = "docker"

      config {
        image        = "localhost:5000/monad-agent-mesh:latest"
        network_mode = "host"   # reach the tailnet (mesh + nomad API) and the local registry
        volumes = [
          "/home/ubuntu/.claude:/home/ubuntu/.claude",
          "/home/ubuntu/.claude.json:/home/ubuntu/.claude.json",
          "/home/ubuntu/.codex:/home/ubuntu/.codex",
          "/home/ubuntu/monad:/work",
          "/usr/bin/nomad:/usr/local/bin/nomad:ro",
        ]
      }

      template {
        data        = <<-EOT
          TS_AUTHKEY={{ with nomadVar "secret/agent-mesh" }}{{ .tailscale_authkey }}{{ end }}
          GH_TOKEN={{ with nomadVar "secret/fleet" }}{{ .github_token }}{{ end }}
        EOT
        destination = "secrets/builder.env"
        env         = true
      }

      env {
        AGENT_NAME    = "${NOMAD_META_agent_name}"
        ROLE          = "builder"
        MONAD_ENGINE  = "${NOMAD_META_engine}"
        AGENT_TIMEOUT = "2700"
        NOMAD_ADDR    = "http://100.125.210.126:4646"   # oraclebox1's local server (host net)
        RUN_AGENT     = "/work/meta/agent/run-agent.sh"
        PATH          = "/work/scripts:/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        GIT_AUTHOR_NAME  = "monad-fleet"
        GIT_AUTHOR_EMAIL = "fleet@monad.cluster"
        GIT_COMMITTER_NAME  = "monad-fleet"
        GIT_COMMITTER_EMAIL = "fleet@monad.cluster"
      }

      resources {
        cpu    = 2000
        memory = 2048
      }

      kill_timeout = "20s"
    }
  }
}
