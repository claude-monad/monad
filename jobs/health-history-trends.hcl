# health-history-trends — derive a consumable trend digest from the health time-series.
#
# health-history (jobs/health-history.hcl) snapshots fleet/health-summary into the shared
# Postgres table fleet.public.health_snapshots every 15 min. That gives the cluster a queryable
# health time-series — but nothing READS it except hand-run `nomad alloc exec <pg> psql`. This
# job is the read-side consumer: every 15 min it computes a rolling-window (default 24h) trend
# digest from health_snapshots and publishes it to the Nomad var `fleet/health-trend`, the same
# single-var surface every other fleet monitor uses (and that the dashboard can read).
#
# It is strictly READ-ONLY w.r.t. Postgres (SELECT only, no DDL/writes), so it cannot harm the
# time-series and is fully reversible (`monad undeploy health-history-trends`).
#
# Two tasks, one alloc, sharing /alloc/data:
#   * compute (docker, postgres:16-alpine, prestart): runs the digest SQL with psql, writes the
#     results to /alloc/data/*. Reuses the image already cached on bigo-server and the lowest-
#     latency loopback path to the DB. Renders the PG password from the Nomad var store.
#   * publish (raw_exec, prestart-gated): reads the files, derives the headline trend, and does
#     `nomad var put -force fleet/health-trend …` — the same raw_exec/var-put pattern as
#     registry-health and backup-health (proven to work from bigo-server's host agent).
#
# NOTE: avoid ${...} / %{...} brace forms in the heredocs (HCL2 interpolation) and {{ }} except
# in the password template (consul-template). Use $VAR / $(...) throughout the shell.
job "health-history-trends" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    # Offset off :00/:15/:30/:45 so both fleet-health-rollup and health-history (which run on
    # the quarter-hour) have already produced/snapshotted the current cycle before we read it.
    crons            = ["7,22,37,52 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to bigo-server: hosts the shared Postgres (lowest-latency read), already caches the
  # postgres:16-alpine image (no new pull on its tight disk), already runs raw_exec monitors
  # that `nomad var put`, and keeps this periodic OFF the saturated oraclebox1 keystone voter.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "trend" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    # ---- compute: read-only SQL over health_snapshots -> /alloc/data/* -------------------
    task "compute" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      env {
        PGHOST        = "100.78.218.70"
        PGPORT        = "5432"
        PGDATABASE    = "fleet"
        PGUSER        = "fleet"
        WINDOW_HOURS  = "24"
      }

      config {
        image   = "postgres:16-alpine"
        command = "/bin/bash"
        args    = ["/local/compute.sh"]
      }

      # PG password -> env, rendered from the Nomad var store (never in git/logs).
      template {
        destination = "secrets/pg.env"
        env         = true
        change_mode = "noop"
        data        = <<-EOF
PGPASSWORD={{ with nomadVar "nomad/jobs/postgres" }}{{ .POSTGRES_PASSWORD }}{{ end }}
EOF
      }

      template {
        destination = "local/compute.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# Compute the trend digest from fleet.public.health_snapshots (READ-ONLY: SELECT only).
set -uo pipefail
WIN="$WINDOW_HOURS"
mkdir -p /alloc/data

# Window-summary query: one pipe-delimited row of
#   rows | oldest | newest | span_hours | cur_status | cur_degraded | start_status | start_degraded | flaps | status_dist
cat > /local/q1.sql <<'SQL'
WITH win AS (
  SELECT * FROM health_snapshots WHERE snapshot_ts >= now() - interval 'WINWIN hours'
),
deg AS (
  SELECT w.snapshot_ts, w.status,
         (SELECT count(*) FROM unnest(string_to_array(w.components,';')) kv
            WHERE kv LIKE '%=%' AND split_part(kv,'=',2) <> 'healthy') AS ndeg
  FROM win w
),
latest   AS (SELECT * FROM deg ORDER BY snapshot_ts DESC LIMIT 1),
earliest AS (SELECT * FROM deg ORDER BY snapshot_ts ASC  LIMIT 1),
flaps AS (
  SELECT count(*) FILTER (WHERE prev IS NOT NULL AND status IS DISTINCT FROM prev) AS n
  FROM (SELECT status, lag(status) OVER (ORDER BY snapshot_ts) prev FROM win) t
),
dist AS (SELECT status, count(*) c FROM win GROUP BY status)
SELECT (SELECT count(*) FROM win),
       (SELECT min(snapshot_ts) FROM win),
       (SELECT max(snapshot_ts) FROM win),
       round(extract(epoch FROM (SELECT max(snapshot_ts)-min(snapshot_ts) FROM win))/3600.0, 2),
       (SELECT status FROM latest), (SELECT ndeg FROM latest),
       (SELECT status FROM earliest), (SELECT ndeg FROM earliest),
       (SELECT n FROM flaps),
       (SELECT string_agg(status||'='||c, ';' ORDER BY status) FROM dist);
SQL

# Per-component current-degraded-streak query (gaps-and-islands). One value:
#   comp=state(since=ISO,for=Xh);...   ordered by streak start ASC (longest-degraded first).
cat > /local/q2.sql <<'SQL'
WITH parsed AS (
  SELECT snapshot_ts, split_part(kv,'=',1) comp, split_part(kv,'=',2) state
  FROM health_snapshots, unnest(string_to_array(components,';')) kv
  WHERE snapshot_ts >= now() - interval 'WINWIN hours' AND kv LIKE '%=%'
),
lagged AS (
  SELECT comp, state, snapshot_ts,
         lag(state) OVER (PARTITION BY comp ORDER BY snapshot_ts) pstate
  FROM parsed
),
grp AS (
  SELECT comp, state, snapshot_ts,
         sum(CASE WHEN state IS DISTINCT FROM pstate THEN 1 ELSE 0 END)
             OVER (PARTITION BY comp ORDER BY snapshot_ts) g
  FROM lagged
),
mx  AS (SELECT max(snapshot_ts) m FROM parsed),
cur AS (SELECT comp, state, g FROM grp WHERE snapshot_ts = (SELECT m FROM mx)),
streak AS (
  SELECT c.comp, c.state, min(g2.snapshot_ts) since
  FROM cur c JOIN grp g2 ON g2.comp=c.comp AND g2.g=c.g
  GROUP BY c.comp, c.state
)
SELECT COALESCE(string_agg(
  comp||'='||state||'(since='||to_char(since,'YYYY-MM-DD"T"HH24:MI:SS"Z"')
       ||',for='||round(extract(epoch FROM (now()-since))/3600.0,1)||'h)',
  ';' ORDER BY since), 'none')
FROM streak WHERE state <> 'healthy';
SQL

# Inject the rolling-window size (integer hours) into the 'WINWIN hours' interval literals.
sed -i "s/WINWIN/$WIN/g" /local/q1.sql /local/q2.sql

if ! psql -v ON_ERROR_STOP=1 --no-psqlrc -At -F'|' -f /local/q1.sql > /alloc/data/summary.psv; then
  echo "[trends] ERROR: summary query failed"; exit 1
fi
if ! psql -v ON_ERROR_STOP=1 --no-psqlrc -At -f /local/q2.sql > /alloc/data/degraded.txt; then
  echo "[trends] ERROR: degraded-streak query failed"; exit 1
fi
echo "$WIN" > /alloc/data/window_hours
echo "[trends] compute ok: $(cat /alloc/data/summary.psv)"
exit 0
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 96
      }

      kill_timeout = "20s"
    }

    # ---- publish: derive trend + nomad var put fleet/health-trend ------------------------
    task "publish" {
      driver = "raw_exec"

      env {
        HVAR = "fleet/health-trend"
      }

      config {
        command = "/bin/bash"
        args    = ["local/publish.sh"]
      }

      template {
        destination = "local/publish.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# Read the compute task's output, derive the headline trend, publish fleet/health-trend.
set -uo pipefail
# raw_exec runs on the host (no chroot): reach the shared alloc dir via $NOMAD_ALLOC_DIR,
# the same directory the docker compute task sees mounted at /alloc.
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AD="$NOMAD_ALLOC_DIR"
SUM="$AD/data/summary.psv"
DEG="$AD/data/degraded.txt"
WINF="$AD/data/window_hours"

if [ ! -s "$SUM" ]; then
  nomad var put -force "$HVAR" ts="$NOW" status=warn detail="compute produced no summary" \
    || echo "[trends] WARN: var put failed"
  exit 0
fi

IFS='|' read -r ROWS OLDEST NEWEST SPAN CURS CURD STS STD FLAPS DIST < "$SUM"
WIN="$(cat "$WINF" 2>/dev/null || echo 24)"
DEGRADED="$(cat "$DEG" 2>/dev/null || echo none)"
[ -z "$DEGRADED" ] && DEGRADED=none

# longest-degraded = first ';'-separated token of the (since-ASC ordered) degraded list.
if [ "$DEGRADED" = "none" ]; then
  LONGEST=none
else
  LONGEST="$(printf '%s' "$DEGRADED" | cut -d';' -f1)"
fi

# Trend: compare current vs window-start degraded-component count.
TREND=stable
if [ -n "$CURD" ] && [ -n "$STD" ]; then
  if [ "$CURD" -lt "$STD" ] 2>/dev/null; then TREND=improving
  elif [ "$CURD" -gt "$STD" ] 2>/dev/null; then TREND=worsening
  fi
fi

# A short human detail line.
DETAIL="$TREND: now $CURS/$CURD-degraded vs start $STS/$STD over $ROWS snaps/$WIN h; flaps=$FLAPS"

nomad var put -force "$HVAR" \
  ts="$NOW" \
  status=healthy \
  window_hours="$WIN" \
  rows="$ROWS" \
  span_hours="$SPAN" \
  oldest="$OLDEST" \
  newest="$NEWEST" \
  current_status="$CURS" \
  current_degraded="$CURD" \
  start_status="$STS" \
  start_degraded="$STD" \
  trend="$TREND" \
  flaps="$FLAPS" \
  status_dist="$DIST" \
  degraded_now="$DEGRADED" \
  longest_degraded="$LONGEST" \
  detail="$DETAIL" \
  || { echo "[trends] WARN: nomad var put failed"; exit 0; }

echo "[trends] published $HVAR: $DETAIL"
exit 0
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 48
      }

      kill_timeout = "10s"
    }
  }
}
