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
  priority    = 80

  parameterized {
    payload       = "optional"
    meta_required = ["name"]
    meta_optional = ["model", "effort", "node"]
  }

  # Place on any Claude-ready node (node meta IS interpolated in constraints; dispatch meta is
  # NOT, so we can't target an exact node that way). assistant.sh still asks the governor for
  # admission (refuse when all Claude nodes are at capacity) + Nomad's spread scheduler keeps
  # new assistants off the most-loaded node, so oraclebox1 no longer gets buried.
  constraint {
    attribute = "${meta.has_claude}"
    value     = "true"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
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

    # raw_exec on the host (no Docker image) — runs as the node's Claude-credentialed user via
    # rc-session-host.sh. This is what lets an assistant run on death-star/claudebox/etc., not
    # just oraclebox1, now that Claude creds + CLI are portable to every node.
    task "session" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "W=/tmp/assistant-${NOMAD_META_name}-monad; if [ -d \"$W/.git\" ]; then git -C \"$W\" fetch -q origin main && git -C \"$W\" reset --hard -q origin/main || true; else rm -rf \"$W\"; git clone -q --depth 1 https://github.com/eliott-monad/monad \"$W\"; fi; exec bash \"$W/scripts/rc-session-host.sh\""]
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
        REPO_URL   = "https://github.com/eliott-monad/monad"
        NOMAD_ADDR = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 200
        memory = 512
      }

      kill_timeout = "10s"
    }
  }
}
