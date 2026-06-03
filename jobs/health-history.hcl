# health-history — persist fleet/health-summary snapshots into the shared Postgres
# (jobs/postgres.hcl, 100.78.218.70:5432, db `fleet`) as a queryable health time-series.
#
# Motivated by fleet/projects/health-history.md: the fleet's health signal is rich but
# point-in-time — every monitor var is overwritten each run, so "how long has oraclebox1
# been saturated?" / "when did service:gateway last flap?" are unanswerable. Meanwhile the
# shared Postgres the fleet built "for shared state & coordination" sits empty (0 user
# tables). This job is its first real consumer: every 15 min it reads fleet/health-summary
# and inserts ONE immutable snapshot row into table health_snapshots, deduped on the
# snapshot's own `ts` so an unchanged rollup is not double-stored.
#
# Design notes:
#  - Reuses the postgres:16-alpine image already cached on bigo-server (no new pull on its
#    near-full disk); has psql + busybox wget.
#  - The fleet/health-summary var is non-secret and read at runtime via the Nomad HTTP API
#    (anonymous reads are open here). The Postgres password is injected via a Nomad template
#    (nomadVar) as an env var, so it never appears in this spec, in git, or in logs.
#  - All scalar columns are derived IN SQL from the inserted JSONB (j->>'...'), so there is
#    no brittle shell JSON parsing (no jq/python needed in the container).
#  - Idempotent: snapshot_ts is UNIQUE, INSERT ... ON CONFLICT DO NOTHING.
#
# NOTE: avoid ${...} brace expansions in the script heredoc — Nomad HCL2 would treat them as
# interpolation. Use $VAR throughout.
job "health-history" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/15 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to bigo-server: co-located with shared-postgres (lowest-latency writes), already has
  # the postgres:16-alpine image cached, and keeps this periodic OFF the saturated oraclebox1
  # keystone voter.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "health-history" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "snapshot" {
      driver = "docker"

      env {
        NOMAD_ADDR  = "http://100.125.210.126:4646"
        SUMMARY_VAR = "fleet/health-summary"
        PGHOST      = "100.78.218.70"
        PGPORT      = "5432"
        PGDATABASE  = "fleet"
        PGUSER      = "fleet"
        # Retention: prune snapshots older than this each run, so the table can't grow
        # unbounded on bigo-server's near-full disk. 180d ≈ 17k rows max (a few MB) —
        # ample for trend analysis. Set empty/0 to disable.
        RETENTION_DAYS = "180"
      }

      config {
        image   = "postgres:16-alpine"
        command = "/bin/bash"
        args    = ["/local/snapshot.sh"]
        # Nomad's docker driver auto-mounts the task dirs (/local, /secrets, /alloc), so
        # /local/snapshot.sh and the rendered secrets/pg.env env are available without an
        # explicit volume (an explicit local:/local would be a "Duplicate mount point").
      }

      # Postgres password -> env var, rendered from the Nomad var store (never in git/logs).
      template {
        destination = "secrets/pg.env"
        env         = true
        change_mode = "noop"
        data        = <<-EOF
PGPASSWORD={{ with nomadVar "nomad/jobs/postgres" }}{{ .POSTGRES_PASSWORD }}{{ end }}
EOF
      }

      template {
        destination = "local/snapshot.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# Snapshot fleet/health-summary -> Postgres health_snapshots (idempotent on snapshot_ts).
set -uo pipefail

# 1) Fetch the current health-summary var as JSON (non-secret; anonymous API read).
if ! wget -q -T 10 -O /local/summary.json "$NOMAD_ADDR/v1/var/$SUMMARY_VAR"; then
  echo "[health-history] ERROR: could not fetch $SUMMARY_VAR from $NOMAD_ADDR"
  exit 1
fi
if [ ! -s /local/summary.json ]; then
  echo "[health-history] ERROR: empty response for $SUMMARY_VAR"
  exit 1
fi

# 2) Ensure schema, then insert one row. All scalar columns are derived in SQL from the
#    var's Items object (j), so no shell JSON parsing is needed. ON CONFLICT keeps it
#    idempotent across overlapping runs / unchanged rollups.
psql -v ON_ERROR_STOP=1 --no-psqlrc <<'SQL'
CREATE TABLE IF NOT EXISTS health_snapshots (
  id              BIGSERIAL PRIMARY KEY,
  snapshot_ts     TIMESTAMPTZ UNIQUE,
  ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  status          TEXT,
  raw_status      TEXT,
  component_count INT,
  components      TEXT,
  detail          TEXT,
  foreman         TEXT,
  full_json       JSONB
);
SQL

# Load the API response, extract its Items object, and insert. :'doc' safely quotes the
# whole JSON document as a literal; ->'Items' is the flat string map of the var.
psql -v ON_ERROR_STOP=1 --no-psqlrc \
  --set=doc="$(cat /local/summary.json)" <<'SQL'
WITH src AS (
  SELECT ((:'doc')::jsonb -> 'Items') AS j
)
INSERT INTO health_snapshots
  (snapshot_ts, status, raw_status, component_count, components, detail, foreman, full_json)
SELECT
  NULLIF(j->>'ts','')::timestamptz,
  j->>'status',
  j->>'raw_status',
  NULLIF(j->>'component_count','')::int,
  j->>'components',
  j->>'detail',
  j->>'foreman',
  j
FROM src
WHERE j ? 'ts'
ON CONFLICT (snapshot_ts) DO NOTHING;
SQL

rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[health-history] ERROR: insert failed rc=$rc"
  exit "$rc"
fi

# 3) Retention prune (keep the table bounded; safe — only deletes our own old snapshots).
if [ -n "$RETENTION_DAYS" ] && [ "$RETENTION_DAYS" != "0" ]; then
  pruned="$(psql -At -v ON_ERROR_STOP=1 --no-psqlrc \
    -c "WITH d AS (DELETE FROM health_snapshots WHERE snapshot_ts < now() - interval '$RETENTION_DAYS days' RETURNING 1) SELECT count(*) FROM d;" 2>/dev/null || echo '?')"
  echo "[health-history] retention: pruned $pruned rows older than $RETENTION_DAYS days"
fi

# Report current depth (no secrets).
psql -At --no-psqlrc -c \
  "SELECT 'rows='||count(*)||' latest='||COALESCE(max(snapshot_ts)::text,'none') FROM health_snapshots;" \
  | sed 's/^/[health-history] /'
echo "[health-history] ok"
exit 0
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 96
      }

      kill_timeout = "20s"
    }
  }
}
