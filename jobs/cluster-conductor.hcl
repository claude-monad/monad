# cluster-conductor — the singular, always-on Claude instance for the whole cluster.
#
# One brain, two front doors:
#   * Tailscale text gateway   — POST http://<oraclebox1-tailnet-ip>:8200/ask
#   * Remote-control session   — appears in the Claude app (claude.ai/code) under the
#                                account; the owner attaches from desktop or phone.
#
# Runs in a container (docker driver) on oraclebox1, where the account credentials
# live. Host networking so the gateway binds the node's Tailscale address and the
# nomad/tailscale CLIs reach the mesh. Credentials, the monad repo, the tailscale
# socket, and the host nomad/tailscale binaries are mounted in (image stays lean).
job "cluster-conductor" {
  datacenters = ["dc1"]
  type        = "service"

  # Pin to oraclebox1 — the always-on Oracle box that holds the Claude credentials.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "conductor" {
    count = 1

    restart {
      attempts = 5
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    network {
      mode = "host"
    }

    service {
      name     = "cluster-conductor"
      provider = "nomad"
      port     = "8200"

      check {
        type     = "http"
        protocol = "http"
        port     = "8200"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "conductor" {
      driver = "docker"

      config {
        image        = "ghcr.io/eliott-monad/monad-conductor:latest"
        network_mode = "host"
        # GHCR pull auth — templated from the encrypted Nomad variable so the
        # package can stay private (no committed credentials).
        auth {
          username = "eliottcassidy2000"
          password = "${GHCR_TOKEN}"
        }
        # mounts: creds (rw for token refresh), repo, tailscale socket + host CLIs
        volumes = [
          "/home/ubuntu/.claude:/home/ubuntu/.claude",
          "/home/ubuntu/.claude.json:/home/ubuntu/.claude.json",
          "/home/ubuntu/monad:/work",
          "/var/run/tailscale:/var/run/tailscale",
          "/usr/bin/nomad:/host/bin/nomad:ro",
          "/usr/bin/tailscale:/host/bin/tailscale:ro",
        ]
      }

      # GitOps push token + GHCR pull token, templated from an encrypted Nomad var.
      template {
        data        = <<-EOH
          GH_TOKEN={{ with nomadVar "secret/conductor" }}{{ .github_token }}{{ end }}
          GHCR_TOKEN={{ with nomadVar "secret/conductor" }}{{ .ghcr_token }}{{ end }}
        EOH
        destination = "secrets/conductor.env"
        env         = true
      }

      env {
        NOMAD_ADDR        = "http://100.125.210.126:4646"
        CONDUCTOR_WORKDIR = "/work"
        CONDUCTOR_PORT    = "8200"
        MONAD_REPO_DIR    = "/work"
        # ENABLE_REMOTE_CONTROL=1 keeps the app-facing session alive (default)
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
