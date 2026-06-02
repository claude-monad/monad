# registry-health — standing, low-noise monitor of the shared container
# registry (jobs/registry.hcl, 100.78.218.70:5000 on bigo-server) and its
# on-disk store /opt/monad-registry. READ-ONLY: it only curls the local /v2/
# API, `du`s the store, and `df`s the filesystem, then records a compact verdict
# to the Nomad var fleet/registry-health.
#
# Motivated by fleet/projects/registry-health.md: the registry is now the single
# source of every cluster image (multi-arch agent-mesh, the uid1000/uid1001
# variants, seeds) but nothing watches it. A registry whose disk fills breaks
# pulls cluster-wide; the registry job itself was pinned to bigo-server *because*
# of that risk. This turns "is the registry filling up?" into a queryable signal
# and extends the cluster's disk-health mandate to the registry bind-mount.
#
# Quiet by design: the single var fleet/registry-health is overwritten each run
# (no log/commit spam) and a status transition is captured in the var itself
# (prev_status + changed_at), mirroring jobs/agent-checkout-health.hcl.
#
# NOTE: script body avoids ${...} brace expansions because Nomad HCL2 would
# interpret them as interpolation inside the heredoc; use $VAR throughout.
job "registry-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */6 * * *"]
    prohibit_overlap = true
  }

  # The registry and its /opt/monad-registry bind-mount live on bigo-server, so
  # the probe must run there to see the store on disk.
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "registry-health" {
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
        REGISTRY_URL = "http://localhost:5000"
        STORE_DIR    = "/opt/monad-registry"
        # warn when the registry filesystem dips below this many KiB free (3 GiB)
        WARN_FREE_KB = "3145728"
        # ...or when it crosses this used percentage
        WARN_USED_PCT = "90"
        NOMAD_ADDR    = "http://100.75.75.39:4646"
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
# read-only registry health probe -> Nomad var fleet/registry-health
set -uo pipefail

HVAR="fleet/registry-health"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- transition helper: read previous status so we can stamp changed_at ---
prev="$(nomad var get -item=status "$HVAR" 2>/dev/null || echo '')"
prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
changed_at="$(nomad var get -item=changed_at "$HVAR" 2>/dev/null || echo '')"

put_var() {
  # args: status detail repo_count tag_count repos store_bytes store_human disk_free_kb disk_used_pct
  local st="$1"
  local trans="(none)"
  local ca="$changed_at"
  if [ "$prev" != "$st" ]; then ca="$now"; trans="$prevlabel->$st"; fi
  [ -n "$ca" ] || ca="$now"
  nomad var put -force "$HVAR" \
    status="$st" detail="$2" \
    repo_count="$3" tag_count="$4" repos="$5" \
    store_bytes="$6" store_human="$7" \
    disk_free_kb="$8" disk_used_pct="$9" \
    prev_status="$prevlabel" changed_at="$ca" ts="$now" >/dev/null 2>&1 \
    || { echo "[registry-health] WARN: nomad var put failed"; return 0; }
  echo "[registry-health] status=$st repos=$3 tags=$4 store=$7 free_kb=$8 used=$9% transition=$trans"
}

command -v curl >/dev/null 2>&1 || { put_var "unknown" "no curl on host" "?" "?" "" "?" "?" "?" "?"; exit 0; }

# --- catalog ---
cat_json="$(curl -fsS --max-time 10 "$REGISTRY_URL/v2/_catalog" 2>/dev/null || echo '')"
if [ -z "$cat_json" ]; then
  put_var "unknown" "registry API unreachable at $REGISTRY_URL/v2/_catalog" "?" "?" "" "?" "?" "?" "?"
  exit 0
fi

# parse {"repositories":["a","b",...]} without jq
repos="$(echo "$cat_json" | tr -d '\n' | sed -n 's/.*"repositories":\[\(.*\)\].*/\1/p' | tr ',' ' ' | tr -d '"')"
repo_count=0
for r in $repos; do repo_count=$((repo_count + 1)); done

# --- per-repo tag counts ---
tag_count=0
repolist=""
for r in $repos; do
  tl="$(curl -fsS --max-time 10 "$REGISTRY_URL/v2/$r/tags/list" 2>/dev/null || echo '')"
  tags="$(echo "$tl" | tr -d '\n' | sed -n 's/.*"tags":\[\(.*\)\].*/\1/p' | tr ',' ' ' | tr -d '"')"
  n=0
  for t in $tags; do n=$((n + 1)); done
  tag_count=$((tag_count + n))
  repolist="$repolist $r=$n"
done
repolist="$(echo "$repolist" | sed 's/^ *//')"

# --- store size on disk (du; raw_exec is typically root, fall back to sudo -n) ---
store_bytes="?"
if [ -d "$STORE_DIR" ]; then
  store_bytes="$(du -sb "$STORE_DIR" 2>/dev/null | awk '{print $1}')"
  if [ -z "$store_bytes" ]; then
    store_bytes="$(sudo -n du -sb "$STORE_DIR" 2>/dev/null | awk '{print $1}')"
  fi
  [ -n "$store_bytes" ] || store_bytes="?"
fi
store_human="?"
if [ "$store_bytes" != "?" ]; then
  if command -v numfmt >/dev/null 2>&1; then
    store_human="$(numfmt --to=iec "$store_bytes" 2>/dev/null || echo '')"
  fi
  [ -n "$store_human" ] || store_human="$(printf '%sB' "$store_bytes")"
fi

# --- filesystem free space for the store ---
disk_free_kb="?"
disk_used_pct="?"
dfline="$(df -Pk "$STORE_DIR" 2>/dev/null | awk 'NR==2')"
if [ -n "$dfline" ]; then
  disk_free_kb="$(echo "$dfline" | awk '{print $4}')"
  disk_used_pct="$(echo "$dfline" | awk '{print $5}' | tr -d '%')"
fi

# --- verdict ---
status="healthy"
detail="ok"
if [ "$disk_free_kb" != "?" ] && [ "$disk_free_kb" -lt "$WARN_FREE_KB" ] 2>/dev/null; then
  status="warn"; detail="$(printf 'low free space: %sKiB < %sKiB' "$disk_free_kb" "$WARN_FREE_KB")"
fi
if [ "$disk_used_pct" != "?" ] && [ "$disk_used_pct" -ge "$WARN_USED_PCT" ] 2>/dev/null; then
  status="warn"; detail="$(printf 'filesystem %s%% used (>= %s%%)' "$disk_used_pct" "$WARN_USED_PCT")"
fi

put_var "$status" "$detail" "$repo_count" "$tag_count" "$repolist" "$store_bytes" "$store_human" "$disk_free_kb" "$disk_used_pct"
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
