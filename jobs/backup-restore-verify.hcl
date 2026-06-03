# backup-restore-verify — standing, low-noise proof that the cluster's backups
# actually RESTORE. The fleet makes three keystone backups on bigo-server:
#   - postgres-backup (#8): /opt/monad-postgres-backups/<db>-<stamp>.sql.gz  (gzip plain SQL)
#   - registry-backup (#27): /opt/monad-registry-backups/registry-<stamp>.tar.gz (gzip tar)
#   - nomad-vars-backup (#36): /opt/monad-vars-backups/nomad-vars-<stamp>.json.gz (gzip JSONL)
# Freshness/size is watched by backup-health-monitor (#28). This is the RECOVERY side:
# a backup you have never restored is not a backup. Each run test-restores the LATEST of
# each into a DISPOSABLE target and verifies integrity, writing one verdict var.
#
# READ-ONLY w.r.t. live data: it never touches the live DB, the live registry store, the live
# vars, or the backup archives themselves. Postgres is restored into a throwaway in-container
# postgres (initdb in /tmp, unix-socket only, no TCP); the registry tar is extracted to a temp
# dir (with a free-space preflight so a test-restore can never fill bigo-server's disk) and
# the temp dir is removed; the vars dump is replayed into a throwaway nomad var path
# (restore-test/vars-verify/probe) that this job creates and always purges. Result -> Nomad
# var fleet/backup-restore-verify.
#
# Quiet by design: overwrites the single var each run; a status transition is captured in the
# var (prev_status + changed_at), mirroring jobs/registry-health.hcl.
#
# NOTE: the embedded scripts avoid ${...} brace sequences because Nomad HCL2 would treat them
# as interpolation inside the heredoc; use $VAR / $(...) throughout.
job "backup-restore-verify" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    # Daily at 06:30 UTC — after postgres-backup (04:00) and registry-backup (05:30) so the
    # "latest" archive each run tests is that morning's fresh backup.
    crons            = ["30 6 * * *"]
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  # The backup dirs live on bigo-server's host disk, so the verifier must run there to read
  # them. docker (for the throwaway postgres) is available there — the backup jobs use it.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "backup-restore-verify" {
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
        PG_BACKUP_DIR   = "/opt/monad-postgres-backups"
        REG_BACKUP_DIR  = "/opt/monad-registry-backups"
        VARS_BACKUP_DIR = "/opt/monad-vars-backups"
        PG_IMAGE        = "postgres:16-alpine"
        # require this much free space (KiB) beyond the archive size before extracting the
        # registry tar, so a test-restore never fills the disk registry-health guards (1 GiB).
        EXTRACT_SAFETY_KB = "1048576"
        NOMAD_ADDR        = "http://100.75.75.39:4646"
      }

      config {
        command = "/bin/bash"
        args    = ["local/probe.sh"]
      }

      # Script run INSIDE the throwaway postgres container to perform a real restore.
      template {
        destination = "local/pgverify.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/sh
# Runs inside PG_IMAGE. Restores /dump.sql.gz into a fresh throwaway postgres (initdb in
# /tmp, unix socket only) and prints "TABLES=<n>" (user-table count) on success. Any restore
# error (ON_ERROR_STOP) or startup failure exits non-zero so the caller marks it a failure.
set -eu
export PGDATA=/tmp/pgdata
mkdir -p "$PGDATA"
chown -R postgres "$PGDATA" /tmp 2>/dev/null || true
su postgres -c "initdb -D '$PGDATA' -A trust -U postgres" >/tmp/initdb.log 2>&1
# listen on a unix socket in /tmp only (listen_addresses empty => no TCP), port unused by anyone
su postgres -c "pg_ctl -D '$PGDATA' -o '-k /tmp -p 5499 -c listen_addresses=' -w -t 60 start" >/tmp/pgstart.log 2>&1
su postgres -c "createdb -h /tmp -p 5499 -U postgres verifydb"
gunzip -c /dump.sql.gz | su postgres -c "psql -h /tmp -p 5499 -U postgres -d verifydb -v ON_ERROR_STOP=1 -q" >/tmp/restore.log 2>&1
TABLES=$(su postgres -c "psql -h /tmp -p 5499 -U postgres -d verifydb -tAc \"select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema')\"" 2>/dev/null | tr -d '[:space:]')
su postgres -c "pg_ctl -D '$PGDATA' -w stop" >/dev/null 2>&1 || true
echo "TABLES=$TABLES"
SCRIPT
      }

      # Helper for the vars dump round-trip. Never prints secret values — only counts and a
      # sha256 of the chosen entry's Items, so nothing sensitive lands in logs or argv.
      #   count                 : stdin=JSONL dump -> "COUNT=<n>" (exit!=0 if 0/invalid)
      #   makespec <path> <file>: stdin=JSONL dump -> write a put-spec at <file> with Path
      #                           rewritten to <path>, keeping a real entry's Items; prints
      #                           "SRC=<orig path>" and "SHA=<sha256 of canonical Items>"
      #   sha                   : stdin=`nomad var get -out=json` -> "SHA=<sha256 of Items>"
      template {
        destination = "local/varshelper.py"
        perms       = "755"
        data        = <<-SCRIPT
#!/usr/bin/env python3
import hashlib, json, sys

def canon_sha(items):
    canon = json.dumps(items or {}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()

cmd = sys.argv[1] if len(sys.argv) > 1 else ""

if cmd == "count":
    n = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        if "Path" not in obj:
            print("BADLINE", file=sys.stderr); sys.exit(2)
        n += 1
    print("COUNT=%d" % n)
    sys.exit(0 if n > 0 else 1)

if cmd == "makespec":
    newpath, specfile = sys.argv[2], sys.argv[3]
    chosen = None
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        if obj.get("Items"):
            chosen = obj
            break
    if not chosen:
        print("NOITEMS", file=sys.stderr); sys.exit(1)
    items = chosen["Items"]
    spec = {"Namespace": "default", "Path": newpath, "Items": items}
    with open(specfile, "w") as f:
        json.dump(spec, f)
    print("SRC=%s" % chosen.get("Path", "?"))
    print("SHA=%s" % canon_sha(items))
    sys.exit(0)

if cmd == "sha":
    obj = json.load(sys.stdin)
    print("SHA=%s" % canon_sha(obj.get("Items")))
    sys.exit(0)

print("usage: varshelper.py count|makespec|sha", file=sys.stderr)
sys.exit(2)
SCRIPT
      }

      template {
        destination = "local/probe.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# Restore-verify the latest pg + registry backups -> Nomad var fleet/backup-restore-verify.
set -uo pipefail

HVAR="fleet/backup-restore-verify"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

prev="$(nomad var get -item=status "$HVAR" 2>/dev/null || echo '')"
prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
changed_at="$(nomad var get -item=changed_at "$HVAR" 2>/dev/null || echo '')"

# rank: healthy < unknown < warn  (worst wins for the overall verdict)
rank() { case "$1" in healthy) echo 0;; unknown) echo 1;; warn) echo 2;; *) echo 1;; esac; }

# ---------------------------------------------------------------- postgres restore-verify
pg_status="unknown"; pg_detail="no pg backup found"; pg_backup=""; pg_tables=""; pg_mode="none"
pg_latest="$(ls -1t "$PG_BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)"
if [ -n "$pg_latest" ]; then
  pg_backup="$(basename "$pg_latest")"
  if ! gunzip -t "$pg_latest" 2>/dev/null; then
    pg_status="warn"; pg_detail="gzip integrity check FAILED (corrupt/truncated dump)"
  elif ! gunzip -c "$pg_latest" 2>/dev/null | tail -c 400 | grep -q 'PostgreSQL database dump complete'; then
    pg_status="warn"; pg_detail="missing dump-complete footer (dump likely truncated)"
  else
    pg_status="healthy"; pg_mode="shallow"; pg_detail="gzip ok + dump-complete footer present"
    # Deep restore when docker is reachable: actually load the dump and count tables.
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      out="$(timeout 300 docker run --rm \
        -v "$pg_latest":/dump.sql.gz:ro \
        -v "$NOMAD_TASK_DIR/pgverify.sh":/pgverify.sh:ro \
        "$PG_IMAGE" sh /pgverify.sh 2>&1)"; rc=$?
      if [ "$rc" -eq 0 ]; then
        # rc=0 means psql restored the whole dump under ON_ERROR_STOP=1 (a truncated/corrupt
        # dump would have errored out non-zero, or failed the gzip/footer checks above). So a
        # clean restore is recoverable regardless of table count — 0 tables just means the
        # source DB is empty (the shared fleet DB is provisioned but coordination uses Nomad
        # vars). Table count is informational, not a failure criterion.
        pg_tables="$(printf '%s' "$out" | sed -n 's/^TABLES=//p' | tail -1)"
        [ -n "$pg_tables" ] || pg_tables="0"
        pg_status="healthy"; pg_mode="deep"
        if [ "$pg_tables" -gt 0 ] 2>/dev/null; then
          pg_detail="restored ok: $pg_tables user tables"
        else
          pg_detail="restored ok: 0 user tables (source DB is empty)"
        fi
      else
        pg_status="warn"; pg_mode="deep"
        pg_detail="restore FAILED rc=$rc: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 160)"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------- registry restore-verify
reg_status="unknown"; reg_detail="no registry backup found"; reg_backup=""; reg_repos=""; reg_blobs=""
reg_latest="$(ls -1t "$REG_BACKUP_DIR"/registry-*.tar.gz 2>/dev/null | head -1)"
if [ -n "$reg_latest" ]; then
  reg_backup="$(basename "$reg_latest")"
  if ! gunzip -t "$reg_latest" 2>/dev/null; then
    reg_status="warn"; reg_detail="gzip integrity check FAILED (corrupt/truncated archive)"
  elif ! tar -tzf "$reg_latest" >/dev/null 2>&1; then
    reg_status="warn"; reg_detail="archive is not a listable tar"
  else
    # free-space preflight before extracting (registry archives can be large)
    arch_kb="$(du -k "$reg_latest" 2>/dev/null | awk '{print $1}')"
    free_kb="$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
    need_kb="$(( arch_kb + EXTRACT_SAFETY_KB ))"
    if [ -n "$free_kb" ] && [ "$free_kb" -lt "$need_kb" ] 2>/dev/null; then
      reg_status="unknown"
      reg_detail="gzip+tar ok; skipped extract (free ${free_kb}KiB < need ${need_kb}KiB)"
    else
      work="$(mktemp -d /tmp/brv-reg.XXXXXX)"
      if tar -xzf "$reg_latest" -C "$work" 2>/dev/null; then
        repos_dir="$work/docker/registry/v2/repositories"
        blobs_dir="$work/docker/registry/v2/blobs/sha256"
        reg_repos="$(find "$repos_dir" -type d -name _manifests 2>/dev/null | wc -l | tr -d ' ')"
        checked=0; bad=0
        for data in $(find "$blobs_dir" -type f -name data 2>/dev/null | head -3); do
          dgst="$(basename "$(dirname "$data")")"
          actual="$(sha256sum "$data" 2>/dev/null | awk '{print $1}')"
          checked=$((checked + 1))
          [ "$actual" = "$dgst" ] || bad=$((bad + 1))
        done
        reg_blobs="$checked"
        rr="$reg_repos"; [ -n "$rr" ] || rr=0
        if [ "$bad" -gt 0 ]; then
          reg_status="warn"; reg_detail="blob sha256 MISMATCH on $bad/$checked sampled blobs (corrupt store)"
        elif [ "$rr" -eq 0 ] 2>/dev/null; then
          reg_status="warn"; reg_detail="archive extracts but has 0 repositories"
        else
          reg_status="healthy"; reg_detail="extracted ok: $reg_repos repos, $checked/$checked sampled blobs verified"
        fi
      else
        reg_status="warn"; reg_detail="tar extraction failed despite listing ok"
      fi
      rm -rf "$work" 2>/dev/null || true
    fi
  fi
fi

# ---------------------------------------------------------------- vars restore-verify
# Round-trip the latest nomad-vars-backup dump (#36): parse it (shallow), then replay one
# real entry into a throwaway nomad var path, read it back, sha-compare its Items, and purge.
vars_status="unknown"; vars_detail="no vars backup found"; vars_backup=""; vars_count=""; vars_mode="none"
vars_probe_path="restore-test/vars-verify/probe"
vars_latest="$(ls -1t "$VARS_BACKUP_DIR"/nomad-vars-*.json.gz 2>/dev/null | head -1)"
if [ -n "$vars_latest" ]; then
  vars_backup="$(basename "$vars_latest")"
  if ! gunzip -t "$vars_latest" 2>/dev/null; then
    vars_status="warn"; vars_detail="gzip integrity check FAILED (corrupt/truncated dump)"
  else
    # shallow: every JSONL line parses as a {Path,Items} object and there is >=1 var
    cnt_out="$(gunzip -c "$vars_latest" 2>/dev/null | python3 "$NOMAD_TASK_DIR/varshelper.py" count 2>/dev/null)"; cnt_rc=$?
    vars_count="$(printf '%s' "$cnt_out" | sed -n 's/^COUNT=//p' | tail -1)"
    if [ "$cnt_rc" -ne 0 ] || [ -z "$vars_count" ]; then
      vars_status="warn"; vars_detail="dump failed JSONL parse / zero variables"
    else
      vars_status="healthy"; vars_mode="shallow"; vars_detail="gzip ok + $vars_count vars parse"
      # deep: real put -> get -> sha-compare -> purge round-trip (proves the spec replays)
      specfile="$(mktemp /tmp/brv-vars.XXXXXX.json)"
      mk_out="$(gunzip -c "$vars_latest" 2>/dev/null | python3 "$NOMAD_TASK_DIR/varshelper.py" makespec "$vars_probe_path" "$specfile" 2>/dev/null)"; mk_rc=$?
      exp_sha="$(printf '%s' "$mk_out" | sed -n 's/^SHA=//p' | tail -1)"
      if [ "$mk_rc" -ne 0 ] || [ -z "$exp_sha" ]; then
        vars_status="warn"; vars_mode="deep"; vars_detail="no replayable entry with items in dump"
      elif nomad var put -force -in=json @"$specfile" >/dev/null 2>&1; then
        got_sha="$(nomad var get -out=json "$vars_probe_path" 2>/dev/null | python3 "$NOMAD_TASK_DIR/varshelper.py" sha 2>/dev/null | sed -n 's/^SHA=//p' | tail -1)"
        # always purge the throwaway var, regardless of the compare outcome
        nomad var purge "$vars_probe_path" >/dev/null 2>&1 || true
        gd="$got_sha"; [ -n "$gd" ] || gd="none"
        if [ -n "$got_sha" ] && [ "$got_sha" = "$exp_sha" ]; then
          vars_status="healthy"; vars_mode="deep"; vars_detail="restored ok: $vars_count vars, round-trip sha match"
        else
          vars_status="warn"; vars_mode="deep"; vars_detail="round-trip sha MISMATCH (got=$gd want=$exp_sha)"
        fi
      else
        vars_status="warn"; vars_mode="deep"; vars_detail="nomad var put -in=json of dump entry FAILED (spec not replayable)"
        nomad var purge "$vars_probe_path" >/dev/null 2>&1 || true
      fi
      rm -f "$specfile" 2>/dev/null || true
    fi
  fi
fi

# ---------------------------------------------------------------- overall verdict
status="$pg_status"
[ "$(rank "$reg_status")" -gt "$(rank "$status")" ] && status="$reg_status"
[ "$(rank "$vars_status")" -gt "$(rank "$status")" ] && status="$vars_status"
detail="pg($pg_status): $pg_detail | registry($reg_status): $reg_detail | vars($vars_status): $vars_detail"

ca="$changed_at"; trans="(none)"
if [ "$prev" != "$status" ]; then ca="$now"; trans="$prevlabel->$status"; fi
[ -n "$ca" ] || ca="$now"

nomad var put -force "$HVAR" \
  status="$status" detail="$detail" \
  pg_status="$pg_status" pg_detail="$pg_detail" pg_backup="$pg_backup" pg_tables="$pg_tables" pg_mode="$pg_mode" \
  registry_status="$reg_status" registry_detail="$reg_detail" registry_backup="$reg_backup" \
  registry_repos="$reg_repos" registry_blobs_checked="$reg_blobs" \
  vars_status="$vars_status" vars_detail="$vars_detail" vars_backup="$vars_backup" \
  vars_count="$vars_count" vars_mode="$vars_mode" \
  prev_status="$prevlabel" changed_at="$ca" ts="$now" >/dev/null 2>&1 \
  || { echo "[backup-restore-verify] WARN: nomad var put failed"; }

echo "[backup-restore-verify] status=$status pg=$pg_status($pg_mode) registry=$reg_status vars=$vars_status($vars_mode) transition=$trans"
echo "[backup-restore-verify] detail: $detail"
exit 0
SCRIPT
      }

      resources {
        cpu    = 500
        memory = 512
      }

      kill_timeout = "30s"
    }
  }
}
