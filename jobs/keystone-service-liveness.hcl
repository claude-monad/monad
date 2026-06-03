# keystone-service-liveness — standing, low-noise LIVENESS probe of the fleet's own
# keystone services: the cluster dashboard (jobs/cluster-dashboard.hcl,
# 100.78.218.70:8088) and shared-postgres (jobs/postgres.hcl, 100.78.218.70:5432).
# READ-ONLY: an HTTP GET of the dashboard /api/state and a TCP connect to postgres
# :5432. No writes to either service, no credentials. It records a compact per-service
# verdict to Nomad vars fleet/service-health/<svc>.
#
# Motivated by fleet/projects/keystone-service-liveness.md: fleet-health-rollup already
# aggregates raft/registry/backup/backup-restore/checkout/maintenance, but the fleet's
# OWN services have no liveness check in that single signal. The dashboard (the human
# window into the fleet) dying is invisible; shared-postgres dying only surfaces hours
# later via backup-health staleness. The registry is intentionally NOT probed here — it
# is already covered by jobs/registry-health.hcl (avoid double-counting). The rollup
# globs fleet/service-health/ so each appears as a service:<svc> component, individually
# ack-able via fleet/health-ack.
#
# Quiet by design: each var is overwritten per run (no log/commit spam) and a status
# transition is captured in the var itself (prev_status + changed_at), mirroring
# jobs/registry-health.hcl.
#
# NOTE: script body avoids ${...} brace expansions because Nomad HCL2 would interpret
# them as interpolation inside the heredoc; use $VAR throughout.
job "keystone-service-liveness" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/10 * * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to oraclebox1: the stable voter that hosts the rollup + the other fleet
  # monitors and can reach the keystone services over the tailnet. Same placement as
  # fleet-health-rollup / raft-quorum-health.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  group "keystone-service-liveness" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "probe" {
      driver = "raw_exec"

      env {
        NOMAD_ADDR     = "http://100.125.210.126:4646"
        DASHBOARD_URL  = "http://100.78.218.70:8088/api/state"
        POSTGRES_HOST  = "100.78.218.70"
        POSTGRES_PORT  = "5432"
        PROBE_TIMEOUT  = "8"
      }

      config {
        command = "/bin/bash"
        args    = ["local/probe.sh"]
      }

      template {
        destination = "local/probe.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only keystone service liveness probe -> Nomad vars fleet/service-health/<svc>
set -uo pipefail

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TMO="$PROBE_TIMEOUT"

# put_svc <svc> <status> <detail>
# overwrites fleet/service-health/<svc>, stamping changed_at on a status transition.
put_svc() {
  local svc="$1" st="$2" det="$3"
  local hvar="fleet/service-health/$svc"
  local prev prevlabel ca trans
  prev="$(nomad var get -item=status "$hvar" 2>/dev/null || echo '')"
  prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
  ca="$(nomad var get -item=changed_at "$hvar" 2>/dev/null || echo '')"
  trans="(none)"
  if [ "$prev" != "$st" ]; then ca="$now"; trans="$prevlabel->$st"; fi
  [ -n "$ca" ] || ca="$now"
  nomad var put -force "$hvar" \
    status="$st" detail="$det" \
    prev_status="$prevlabel" changed_at="$ca" ts="$now" >/dev/null 2>&1 \
    || { echo "[svc-liveness] WARN: nomad var put failed for $svc"; return 0; }
  echo "[svc-liveness] $svc status=$st transition=$trans detail=$det"
}

# --- dashboard: HTTP GET /api/state, expect 200 + a JSON-ish body ---
if command -v curl >/dev/null 2>&1; then
  code="$(curl -s -o local/dash.body -w '%%{http_code}' --max-time "$TMO" "$DASHBOARD_URL" 2>/dev/null || echo '000')"
  if [ "$code" = "200" ]; then
    # sanity: body should look like JSON (starts with { or [) so a 200 error page is caught
    first="$(head -c 1 local/dash.body 2>/dev/null)"
    if [ "$first" = "{" ] || [ "$first" = "[" ]; then
      put_svc "dashboard" "healthy" "HTTP 200 from /api/state, JSON body"
    else
      put_svc "dashboard" "warn" "HTTP 200 but non-JSON body (first char='$first')"
    fi
  else
    put_svc "dashboard" "warn" "dashboard unreachable: HTTP $code from /api/state"
  fi
else
  put_svc "dashboard" "unknown" "no curl on host"
fi

# --- postgres: TCP connect to :5432 (liveness; deeper integrity is backup-restore-verify) ---
if timeout "$TMO" bash -c "cat < /dev/null > /dev/tcp/$POSTGRES_HOST/$POSTGRES_PORT" 2>/dev/null; then
  put_svc "postgres" "healthy" "TCP $POSTGRES_HOST:$POSTGRES_PORT accepting connections"
else
  put_svc "postgres" "warn" "TCP $POSTGRES_HOST:$POSTGRES_PORT refused/unreachable"
fi

exit 0
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "20s"
    }
  }
}
