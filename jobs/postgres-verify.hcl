job "postgres-verify" {
  datacenters = ["dc1"]
  type        = "batch"

  # Connect from a DIFFERENT node than the DB host (bigo-server) to prove cross-node
  # reachability over the tailnet.
  constraint {
    attribute = "${node.unique.name}"
    value     = "V1410-1"
  }

  group "verify" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "psql" {
      driver = "docker"

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        command      = "psql"
        args         = ["-c", "SELECT 1 AS ok, now(), version();"]
      }

      template {
        data        = <<-EOT
PGHOST=100.78.218.70
PGPORT=5432
{{ with nomadVar "nomad/jobs/postgres" }}
PGUSER={{ .POSTGRES_USER }}
PGPASSWORD={{ .POSTGRES_PASSWORD }}
PGDATABASE={{ .POSTGRES_DB }}
{{ end }}
EOT
        destination = "secrets/pg.env"
        env         = true
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
