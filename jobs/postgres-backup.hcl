job "postgres-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  # Daily backup of the shared Postgres (see jobs/postgres.hcl). Runs on the same
  # node as the DB so it can pg_dump over loopback and store dumps on local disk.
  periodic {
    crons            = ["0 4 * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to bigo-server: that is where the postgres DB and its bind-mount live, and
  # where we keep the backup directory. Docker driver required for the postgres image.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  constraint {
    attribute = "${attr.driver.docker}"
    value     = "1"
  }

  group "backup" {
    count = 1

    restart {
      attempts = 2
      interval = "30m"
      delay    = "30s"
      mode     = "fail"
    }

    task "pg-dump" {
      driver = "docker"

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"

        # Backups land on bigo-server's host disk, in a directory this job owns
        # (separate from the live DB bind-mount /opt/monad-postgres).
        volumes = [
          "/opt/monad-postgres-backups:/backups",
        ]

        command = "/bin/sh"
        args    = ["-c", "exec /local/backup.sh"]
      }

      # Connection + credentials from the encrypted Nomad variable (never hardcoded).
      # network_mode=host means the local postgres is reachable on 127.0.0.1:5432.
      template {
        data        = <<-EOT
{{ with nomadVar "nomad/jobs/postgres" }}
PGHOST=127.0.0.1
PGPORT=5432
PGUSER={{ .POSTGRES_USER }}
PGPASSWORD={{ .POSTGRES_PASSWORD }}
PGDATABASE={{ .POSTGRES_DB }}
{{ end }}
EOT
        destination = "secrets/pg.env"
        env         = true
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<-EOT
#!/bin/sh
# Dump the shared DB to a timestamped, gzip'd plain-SQL file, then prune our own
# dumps older than the retention window. Restore with:  gunzip -c <f> | psql ...
set -eu
RETENTION_DAYS=14
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/backups/${PGDATABASE}-${STAMP}.sql.gz"
TMP="${OUT}.partial"

echo "[pg-backup] dumping ${PGDATABASE}@${PGHOST}:${PGPORT} -> ${OUT}"
# --no-owner/--no-acl keep the dump portable across role names.
pg_dump --no-owner --no-acl | gzip -c > "$TMP"
mv "$TMP" "$OUT"

SIZE="$(wc -c < "$OUT")"
if [ "$SIZE" -lt 100 ]; then
  echo "[pg-backup] FAIL: dump suspiciously small (${SIZE} bytes)" >&2
  exit 1
fi
echo "[pg-backup] wrote ${SIZE} bytes"

echo "[pg-backup] pruning ${PGDATABASE}-*.sql.gz older than ${RETENTION_DAYS}d"
find /backups -maxdepth 1 -name "${PGDATABASE}-*.sql.gz" -type f -mtime +${RETENTION_DAYS} -print -delete || true

echo "[pg-backup] current backups:"
ls -lh /backups || true
echo "[pg-backup] done"
EOT
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
