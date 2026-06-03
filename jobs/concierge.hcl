# concierge — the owner's always-on, weak/cheap front-door LLM.
#
# A persistent named Claude remote-control session (haiku) the owner chats with in the Claude
# app. Handles quick questions directly and, mainly, spins up / tears down purpose-built
# assistants (scripts/assistant.sh). Its role is assistants/concierge/CLAUDE.md.
#
# Effort is brain-controllable: set the Nomad var concierge/config (model=… or effort=…) and
# restart this job, or just `nomad job dispatch`/`monad deploy` after editing. Default: haiku.

job "concierge" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 80

  # raw_exec on a Claude-ready Linux host (no Docker image) — runs as the node's
  # Claude-credentialed user. has_claude (node meta) ensures creds+CLI are present.
  constraint {
    attribute = "${meta.has_claude}"
    value     = "true"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "concierge" {
    count = 1
    reschedule {
      attempts       = 0
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }
    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    network { mode = "host" }

    # raw_exec: clone monad fresh, then rc-session-host.sh runs rc-session.sh as the host's
    # Claude-credentialed user. No node-local Docker image → runs on any Claude-ready node.
    task "concierge" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "W=/tmp/concierge-monad; if [ -d \"$W/.git\" ]; then git -C \"$W\" fetch -q origin main && git -C \"$W\" reset --hard -q origin/main || true; else rm -rf \"$W\"; git clone -q --depth 1 https://github.com/eliott-monad/monad \"$W\"; fi; exec bash \"$W/scripts/rc-session-host.sh\""]
      }

      # GH token (for assistant.sh git push) + brain-controllable model/effort override.
      template {
        data        = <<-EOT
          GH_TOKEN={{ with nomadVar "secret/fleet" }}{{ .github_token }}{{ end }}
          {{ with nomadVar "concierge/config" }}RC_MODEL={{ .model }}
          RC_EFFORT={{ .effort }}{{ end }}
        EOT
        destination = "secrets/c.env"
        env         = true
      }

      env {
        RC_NAME    = "concierge"
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
