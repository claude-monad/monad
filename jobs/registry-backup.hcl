job "registry-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  # Daily backup of the keystone shared registry (see jobs/registry.hcl). Runs on the
  # same node as the registry store so it can read the bind-mount directly and write
  # archives to local disk. Offset from postgres-backup (04:00) to avoid disk-IO overlap.
  periodic {
    crons            = ["30 5 * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to bigo-server: that is where the registry's bind-mount /opt/monad-registry lives
  # and where we keep the backup directory. Docker driver required for the busybox image.
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

    task "tar-registry" {
      driver = "docker"

      config {
        image        = "busybox:1.36"
        network_mode = "host"

        # Read-only mount of the live registry store, plus a backups dir this job owns
        # (separate from the live store). The :ro guarantees the job can never write to
        # or corrupt the registry's data.
        volumes = [
          "/opt/monad-registry:/registry:ro",
          "/opt/monad-registry-backups:/backups",
        ]

        command = "/bin/sh"
        args    = ["-c", "exec /local/backup.sh"]
      }

      template {
        destination = "local/backup.sh"
        perms       = "755"
        data        = <<-EOT
#!/bin/sh
# Archive the registry blob store to a timestamped, gzip'd tarball, verify it, then
# prune our own old archives. Restore with (registry stopped):
#   tar -xzf <archive>.tar.gz -C /opt/monad-registry
set -eu

RETENTION_KEEP=2          # number of most-recent archives to keep (was 3; bigo-server disk sits ~92%, each archive ~1.4G)
# Free-space preflight: refuse to write unless free space comfortably exceeds the live
# store size. Same-host backups share bigo-server's disk with the registry itself (the
# disk registry-health guards), so a backup must NEVER be allowed to fill it and break
# cluster-wide pulls. Require free >= store_size * SAFETY_FACTOR.
SAFETY_FACTOR=2

STORE_KB="$(du -sk /registry 2>/dev/null | awk '{print $1}')"
FREE_KB="$(df -Pk /backups | awk 'NR==2 {print $4}')"
NEED_KB="$(( STORE_KB * SAFETY_FACTOR ))"

echo "[registry-backup] store=${STORE_KB}KB free=${FREE_KB}KB need>=${NEED_KB}KB (safety x${SAFETY_FACTOR})"
if [ "$FREE_KB" -lt "$NEED_KB" ]; then
  # Skip without failing: a too-tight disk is a warning, not a job failure. The next
  # prune below still runs so headroom can recover for the next cycle.
  echo "[registry-backup] SKIP: insufficient free space for a safe archive; pruning old archives only" >&2
  ls -1t /backups/registry-*.tar.gz 2>/dev/null | tail -n +$((RETENTION_KEEP + 1)) | while read -r f; do
    echo "[registry-backup] prune ${f}"; rm -f "$f"
  done
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/backups/registry-${STAMP}.tar.gz"
TMP="${OUT}.partial"

echo "[registry-backup] archiving /registry -> ${OUT}"
# -C /registry . captures docker/registry/v2/{blobs,repositories}. Registry blobs are
# already-compressed layers so gzip mostly just frames them; that's fine.
tar -czf "$TMP" -C /registry .

# Verify the archive is a valid, listable gzip tar before we trust it / prune anything.
if ! tar -tzf "$TMP" >/dev/null 2>&1; then
  echo "[registry-backup] FAIL: archive failed tar -tzf verification" >&2
  rm -f "$TMP"
  exit 1
fi

SIZE="$(wc -c < "$TMP")"
if [ "$SIZE" -lt 100 ]; then
  echo "[registry-backup] FAIL: archive suspiciously small (${SIZE} bytes)" >&2
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$OUT"
echo "[registry-backup] wrote ${SIZE} bytes, archive verified"

echo "[registry-backup] pruning archives beyond the ${RETENTION_KEEP} most recent"
ls -1t /backups/registry-*.tar.gz 2>/dev/null | tail -n +$((RETENTION_KEEP + 1)) | while read -r f; do
  echo "[registry-backup] prune ${f}"; rm -f "$f"
done

echo "[registry-backup] current archives:"
ls -lh /backups 2>/dev/null || true
echo "[registry-backup] done"
EOT
      }

      resources {
        cpu    = 400
        memory = 256
      }
    }
  }
}
