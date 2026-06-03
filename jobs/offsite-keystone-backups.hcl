# offsite-keystone-backups — mirror the three KEYSTONE backups off-node.
#
# The keystone backups all write ONLY to bigo-server's local disk, next to the live
# data they protect:
#   - postgres-backup    -> /opt/monad-postgres-backups   (live: /opt/monad-postgres)
#   - registry-backup    -> /opt/monad-registry-backups   (live: /opt/monad-registry)
#   - nomad-vars-backup  -> /opt/monad-vars-backups        (live: Raft on this node)
# A bigo-server disk loss / node death therefore destroys the live data AND its only
# backups at once. This job mirrors each local backup dir off-node to the existing
# MinIO object store on death-star (100.96.31.66:9000, bucket `backups`, the same store
# backup-mac-mini / backup-windesk already use) so an off-node recovery copy exists.
#
# READ-ONLY w.r.t. the source: it only reads /opt/monad-*-backups and PUSHES copies.
# Per-category empty-source GUARD: a missing/empty local dir is SKIPPED (its remote copy
# is left untouched) so a transient empty local dir can never wipe the off-node copy via
# `mc mirror --remove`. MinIO creds come from the nomad var `nomad/jobs/minio-storage`
# (never hardcoded). Publishes a compact verdict to the Nomad var fleet/offsite-backup,
# which fleet-health-rollup folds in as the `offsite-backup` component.
#
# NOTE: heredoc avoids ${...} brace expansions (Nomad HCL2 would treat them as
# interpolation); use $VAR throughout.
job "offsite-keystone-backups" {
  datacenters = ["dc1"]
  type        = "batch"

  # Daily, after all three keystone backups are fresh (postgres 04:00, registry 05:30,
  # vars 06:00) and the restore-verify (06:30) has run. 07:10 UTC leaves headroom.
  periodic {
    crons            = ["10 7 * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # Pin to bigo-server: that is where the /opt/monad-*-backups dirs live; raw_exec runs
  # as root there and reads them directly (no docker bind mounts needed).
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "offsite" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "mirror" {
      driver = "raw_exec"

      env {
        MINIO_URL     = "http://100.96.31.66:9000"
        ALIAS         = "monad-offsite"
        REMOTE_PREFIX = "backups/keystone"
        # offsite freshness warning: daily backups should have a <36h-old newest copy
        WARN_AGE_S    = "129600"
        NOMAD_ADDR    = "http://100.75.75.39:4646"
        MC_CONFIG_DIR = "local/.mc"
      }

      config {
        command = "/bin/bash"
        args    = ["local/mirror.sh"]
      }

      template {
        destination = "local/mirror.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# Mirror the three keystone backup dirs off-node to MinIO -> fleet/offsite-backup.
set -uo pipefail

HVAR="fleet/offsite-backup"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
nowepoch="$(date -u +%s)"
MC="local/mc"
export MC_CONFIG_DIR="$MC_CONFIG_DIR"

# --- transition helper: read prev status so we can stamp changed_at ---
prev="$(nomad var get -item=status "$HVAR" 2>/dev/null || echo '')"
prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
changed_at="$(nomad var get -item=changed_at "$HVAR" 2>/dev/null || echo '')"

# per-category results (filled by process_cat)
PG_C=0;  PG_B=0;  PG_A=-1;  PG_S="unknown"
REG_C=0; REG_B=0; REG_A=-1; REG_S="unknown"
V_C=0;   V_B=0;   V_A=-1;   V_S="unknown"
DETAIL=""

put_and_exit() {
  # $1 = overall status
  local st="$1"
  local ca="$changed_at"
  if [ "$prev" != "$st" ]; then ca="$now"; fi
  [ -n "$ca" ] || ca="$now"
  nomad var put -force "$HVAR" \
    status="$st" detail="$DETAIL" \
    postgres_count="$PG_C"  postgres_bytes="$PG_B"  postgres_newest_age_s="$PG_A"  postgres_status="$PG_S" \
    registry_count="$REG_C" registry_bytes="$REG_B" registry_newest_age_s="$REG_A" registry_status="$REG_S" \
    vars_count="$V_C"       vars_bytes="$V_B"       vars_newest_age_s="$V_A"       vars_status="$V_S" \
    remote="$MINIO_URL/$REMOTE_PREFIX" \
    prev_status="$prevlabel" changed_at="$ca" ts="$now" >/dev/null 2>&1 \
    || echo "[offsite] WARN: nomad var put failed"
  echo "[offsite] status=$st $DETAIL"
  exit 0
}

# rank/worst helpers (healthy < unknown < warn < critical)
rankof() { case "$1" in healthy) echo 0;; unknown) echo 1;; warn) echo 2;; critical) echo 3;; *) echo 1;; esac; }
worst() { if [ "$(rankof "$1")" -ge "$(rankof "$2")" ]; then echo "$1"; else echo "$2"; fi; }

command -v curl >/dev/null 2>&1 || { DETAIL="no curl on host"; put_and_exit "unknown"; }

# --- MinIO reachability ---
if ! curl -fsS --max-time 10 "$MINIO_URL/minio/health/live" >/dev/null 2>&1; then
  DETAIL="MinIO unreachable at $MINIO_URL"; put_and_exit "unknown"
fi

# --- credentials from the nomad var (never committed) ---
MUSER="$(nomad var get -item=MINIO_ROOT_USER nomad/jobs/minio-storage 2>/dev/null || echo '')"
MPASS="$(nomad var get -item=MINIO_ROOT_PASSWORD nomad/jobs/minio-storage 2>/dev/null || echo '')"
if [ -z "$MUSER" ] || [ -z "$MPASS" ]; then
  DETAIL="MinIO creds unavailable (nomad/jobs/minio-storage)"; put_and_exit "unknown"
fi

# --- mc client ---
if [ ! -x "$MC" ]; then
  if ! curl -fsSL --max-time 180 https://dl.min.io/client/mc/release/linux-amd64/mc -o "$MC"; then
    DETAIL="mc download failed"; put_and_exit "unknown"
  fi
  chmod +x "$MC"
fi
mkdir -p "$MC_CONFIG_DIR"
if ! "$MC" alias set "$ALIAS" "$MINIO_URL" "$MUSER" "$MPASS" >/dev/null 2>&1; then
  DETAIL="mc alias set failed"; put_and_exit "unknown"
fi

# count/bytes/newest-epoch of regular files directly under a dir
local_count() { [ -d "$1" ] && find "$1" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ' || echo 0; }
local_bytes() { [ -d "$1" ] && du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0; }
local_newest() { [ -d "$1" ] && find "$1" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -1 | cut -d. -f1 || echo ''; }

# process_cat NAME DIR -> sets globals via the caller-provided prefix through stdout:
# echoes "count bytes age status"
process_cat() {
  local name="$1" dir="$2"
  local cnt bytes newest age status note
  cnt="$(local_count "$dir")"; [ -n "$cnt" ] || cnt=0
  bytes="$(local_bytes "$dir")"; [ -n "$bytes" ] || bytes=0
  if [ "$cnt" -eq 0 ]; then
    # GUARD: empty/missing local dir -> skip mirror entirely so --remove can't wipe remote
    echo "[offsite] $name: no local backups in $dir -> SKIP (remote left untouched)" >&2
    echo "0 0 -1 warn"
    return
  fi
  newest="$(local_newest "$dir")"; [ -n "$newest" ] || newest=0
  age=$(( nowepoch - newest ))
  echo "[offsite] $name: mirroring $cnt file(s) ($bytes B, newest ${age}s old) -> $ALIAS/$REMOTE_PREFIX/$name/" >&2
  if "$MC" mirror --overwrite --remove "$dir/" "$ALIAS/$REMOTE_PREFIX/$name/" >&2 2>&1; then
    status="healthy"
    if [ "$age" -gt "$WARN_AGE_S" ] 2>/dev/null; then status="warn"; fi   # offsite copy exists but upstream backup is stale
  else
    status="warn"
    echo "[offsite] $name: mc mirror FAILED" >&2
  fi
  echo "$cnt $bytes $age $status"
}

read PG_C PG_B PG_A PG_S  <<< "$(process_cat postgres /opt/monad-postgres-backups)"
read REG_C REG_B REG_A REG_S <<< "$(process_cat registry /opt/monad-registry-backups)"
read V_C V_B V_A V_S      <<< "$(process_cat vars     /opt/monad-vars-backups)"

OVERALL="healthy"
OVERALL="$(worst "$OVERALL" "$PG_S")"
OVERALL="$(worst "$OVERALL" "$REG_S")"
OVERALL="$(worst "$OVERALL" "$V_S")"

DETAIL="$(printf 'postgres=%s(%s) registry=%s(%s) vars=%s(%s) -> %s' \
  "$PG_S" "$PG_C" "$REG_S" "$REG_C" "$V_S" "$V_C" "$MINIO_URL/$REMOTE_PREFIX")"

put_and_exit "$OVERALL"
SCRIPT
      }

      resources {
        cpu    = 500
        memory = 512
      }

      kill_timeout = "120s"
    }
  }
}
