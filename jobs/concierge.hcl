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

  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
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

    task "concierge" {
      driver = "docker"

      config {
        image      = "localhost:5000/monad-agent-mesh:latest"
        network_mode = "host"
        entrypoint = ["/bin/bash", "-c",
          "set -e; [ -e /work/.git ] || git clone --depth 50 \"$REPO_URL\" /work; exec bash /work/scripts/rc-session.sh"]
        volumes = [
          "/home/ubuntu/.claude:/home/ubuntu/.claude",
          "/home/ubuntu/.claude.json:/home/ubuntu/.claude.json",
          "/usr/bin/nomad:/usr/local/bin/nomad:ro",
        ]
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
        RC_CWD     = "/work/assistants/concierge"
        REPO_URL   = "https://github.com/eliott-monad/monad"
        NOMAD_ADDR = "http://100.125.210.126:4646"
        PATH       = "/work/scripts:/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      }

      resources {
        cpu    = 200
        memory = 512
      }

      kill_timeout = "10s"
    }
  }
}
