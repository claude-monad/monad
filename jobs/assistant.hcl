# assistant — a persistent, app-attachable, purpose-built LLM session.
#
# Dispatched by the concierge (scripts/assistant.sh spawn <slug>). Runs a named Claude
# remote-control session the owner chats with in the Claude app; the session's purpose is
# assistants/<slug>/CLAUDE.md (cloned fresh into its own /work, so sessions don't share a
# tree). Persists until removed (assistant.sh remove <slug> → nomad job stop).
#
#   nomad job dispatch -meta name=math-inspiration -meta model=sonnet assistant

job "assistant" {
  datacenters = ["dc1"]
  type        = "batch"

  parameterized {
    payload       = "optional"
    meta_required = ["name"]
    meta_optional = ["model", "effort"]
  }

  # oraclebox1 holds the Claude creds + the agent image (localhost registry). Generalizes
  # once creds are portable to other nodes (project agent-mesh-cred-portability).
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "session" {
    count = 1
    # Persistent: if the alloc/node drops, bring the session back.
    reschedule {
      attempts       = 0
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }
    restart {
      attempts = 2
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    network { mode = "host" }

    task "session" {
      driver = "docker"

      config {
        image      = "localhost:5000/monad-agent-mesh:latest"
        network_mode = "host"
        # Isolated tree: clone fresh, then run the RC session in this assistant's purpose dir.
        entrypoint = ["/bin/bash", "-c",
          "set -e; [ -e /work/.git ] || git clone --depth 50 \"$REPO_URL\" /work; exec /work/scripts/rc-session.sh"]
        volumes = [
          "/home/ubuntu/.claude:/home/ubuntu/.claude",
          "/home/ubuntu/.claude.json:/home/ubuntu/.claude.json",
          "/usr/bin/nomad:/usr/local/bin/nomad:ro",
        ]
      }

      template {
        data        = "GH_TOKEN={{ with nomadVar \"secret/fleet\" }}{{ .github_token }}{{ end }}"
        destination = "secrets/a.env"
        env         = true
      }

      env {
        RC_NAME    = "${NOMAD_META_name}"
        RC_MODEL   = "${NOMAD_META_model}"
        RC_EFFORT  = "${NOMAD_META_effort}"
        RC_CWD     = "/work/assistants/${NOMAD_META_name}"
        REPO_URL   = "https://github.com/eliott-monad/monad"
        NOMAD_ADDR = "http://100.125.210.126:4646"
        PATH       = "/work/scripts:/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      }

      resources {
        cpu    = 200
        memory = 1024
      }

      kill_timeout = "10s"
    }
  }
}
