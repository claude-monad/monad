job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  # bigo-server: amd64 client with docker + disk. Kept off the Raft servers
  # (v1410-1 / oraclebox1 are voters) so a growing DB can't threaten the control
  # plane. Reachable cluster-wide at 100.78.218.70:5432 (see Nomad var infra/postgres).
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "db" {
    count = 1

    # Host networking so postgres binds the tailnet interface (not just the LAN),
    # making it reachable from other nodes. (Default bridge port-mapping would only
    # publish on bigo-server's LAN IP.)
    network {
      mode = "host"
      port "db" {
        static = 5432
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    task "postgres" {
      driver = "docker"

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"

        # Persistent data via a docker bind-mount (no Nomad host-volume / client-config
        # change needed). The postgres entrypoint initdb's + chowns this dir on first run.
        volumes = [
          "/opt/monad-postgres:/var/lib/postgresql/data",
        ]
      }

      # Credentials from an encrypted Nomad variable (never in git). Set via:
      #   monad secrets set nomad/jobs/postgres POSTGRES_USER=… POSTGRES_PASSWORD=… POSTGRES_DB=…
      template {
        data        = <<-EOT
{{ with nomadVar "nomad/jobs/postgres" }}
POSTGRES_USER={{ .POSTGRES_USER }}
POSTGRES_PASSWORD={{ .POSTGRES_PASSWORD }}
POSTGRES_DB={{ .POSTGRES_DB }}
{{ end }}
EOT
        destination = "secrets/postgres.env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name     = "postgres"
        port     = "db"
        provider = "nomad"

        check {
          type     = "tcp"
          port     = "db"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
