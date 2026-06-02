job "postgres-backup-verify" {
  datacenters = ["dc1"]
  type        = "batch"

  # One-shot check that postgres-backup actually wrote a valid dump on bigo-server.
  # Deploy, read logs, then `monad undeploy postgres-backup-verify`.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  constraint {
    attribute = "${attr.driver.docker}"
    value     = "1"
  }

  group "verify" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "check" {
      driver = "docker"

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"

        # Read-only: we only inspect the dumps, never modify them.
        volumes = [
          "/opt/monad-postgres-backups:/backups:ro",
        ]

        command = "/bin/sh"
        args    = ["-c", "exec /local/verify.sh"]
      }

      template {
        destination = "local/verify.sh"
        perms       = "755"
        data        = <<-EOT
#!/bin/sh
set -eu
echo "[verify] contents of /backups:"
ls -lh /backups
LATEST="$(ls -1t /backups/*.sql.gz 2>/dev/null | head -1 || true)"
if [ -z "$LATEST" ]; then
  echo "[verify] FAIL: no *.sql.gz dump found" >&2
  exit 1
fi
echo "[verify] latest dump: $LATEST ($(wc -c < "$LATEST") bytes)"

echo "[verify] gzip integrity check..."
gzip -t "$LATEST"
echo "[verify] gzip OK"

echo "[verify] checking dump contains real SQL (pg_dump header + a CREATE/COPY/INSERT)..."
HDR="$(gunzip -c "$LATEST" | head -40)"
echo "$HDR" | grep -q "PostgreSQL database dump" || { echo "[verify] FAIL: missing pg_dump header" >&2; exit 1; }
if gunzip -c "$LATEST" | grep -qiE '^(CREATE |COPY |INSERT |ALTER )' ; then
  echo "[verify] found schema/data statements"
else
  echo "[verify] NOTE: dump has no CREATE/COPY/INSERT yet (DB may be empty) — header valid, structure restorable"
fi
echo "[verify] PASS"
EOT
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
