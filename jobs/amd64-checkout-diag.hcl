# amd64-checkout-diag — READ-ONLY diagnostic of the credentialed host monad
# checkouts on the amd64 agent nodes. It captures exactly what is dirty/stale/
# divergent so the checkout blocker in
# fleet/projects/amd64-agent-checkout-sync.md can be resolved safely.
#
# It NEVER writes the working tree: only git status, git diff, git log, and a
# non-mutating `git fetch` of refs. The full report is both logged AND written
# to the Nomad variable fleet/checkout-diag/<node> so it survives alloc GC and
# the bigo-server alloc-log 404 that has blocked prior builders.
job "amd64-checkout-diag" {
  datacenters = ["dc1"]
  type        = "batch"

  group "v1410" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "V1410-1"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "diag" {
      driver = "raw_exec"

      env {
        NODE_LABEL  = "V1410-1"
        TARGET_USER = "e"
        TARGET_REPO = "/home/e/monad"
        NOMAD_ADDR  = "http://100.75.75.39:4646"
      }

      config {
        command = "/bin/bash"
        args    = ["local/diag.sh"]
      }

      template {
        destination = "local/diag.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only: no working-tree mutation
set -uo pipefail

REPORT="local/report.txt"
: > "$REPORT"

log() { printf '[diag:%s] %s\n' "$NODE_LABEL" "$*"; }
fail() { printf '[diag:%s] FAIL: %s\n' "$NODE_LABEL" "$*" >&2; exit 1; }

[ -n "$TARGET_USER" ] || fail "TARGET_USER empty"
[ -n "$TARGET_REPO" ] || fail "TARGET_REPO empty"
getent passwd "$TARGET_USER" >/dev/null || fail "missing user $TARGET_USER"
[ -d "$TARGET_REPO/.git" ] || fail "missing git checkout at $TARGET_REPO"

repo_q="$(printf '%q' "$TARGET_REPO")"

as_user() {
  local cmd="$1"
  if [ "$(id -un)" = "$TARGET_USER" ]; then
    bash -lc "$cmd"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n -H -u "$TARGET_USER" bash -lc "$cmd"
  else
    su - "$TARGET_USER" -c "bash -lc $(printf '%q' "$cmd")"
  fi
}

run_diag() {
  local uid branch head origin counts status mods
  uid="$(id -u "$TARGET_USER" 2>/dev/null || echo '?')"
  log "===== $TARGET_REPO  (user=$TARGET_USER uid=$uid) ====="

  branch="$(as_user "cd $repo_q && git rev-parse --abbrev-ref HEAD" 2>/dev/null || echo '?')"
  head="$(as_user "cd $repo_q && git rev-parse HEAD" 2>/dev/null || echo '?')"
  log "branch=$branch head=$head"

  log "remotes:"
  as_user "cd $repo_q && git remote -v" 2>/dev/null || true

  as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null \
    && log "fetched origin/main" || log "WARN: git fetch failed (offline/wrong remote?)"

  origin="$(as_user "cd $repo_q && git rev-parse origin/main" 2>/dev/null || echo '?')"
  log "origin/main=$origin"
  counts="$(as_user "cd $repo_q && git rev-list --left-right --count HEAD...origin/main" 2>/dev/null || echo '? ?')"
  log "ahead/behind (HEAD...origin/main) = $counts"

  log "----- git status --porcelain -----"
  status="$(as_user "cd $repo_q && git status --porcelain" 2>/dev/null || true)"
  if [ -z "$status" ]; then
    log "(clean working tree)"
  else
    printf '%s\n' "$status"
    log "dirty file count: $(printf '%s\n' "$status" | grep -c . || true)"
  fi

  log "----- tracked changes vs HEAD: git diff --stat -----"
  as_user "cd $repo_q && git diff --stat" 2>/dev/null || true

  log "----- per-file: local-modified files vs origin/main -----"
  mods="$(printf '%s\n' "$status" | awk '$1 ~ /[MARCD]/ {print $2}')"
  if [ -n "$mods" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if as_user "cd $repo_q && git diff --quiet origin/main -- $(printf '%q' "$f")" 2>/dev/null; then
        log "  SAME-AS-ORIGIN  $f"
      else
        log "  DIVERGES        $f"
      fi
    done <<< "$mods"
  else
    log "  (no tracked modifications)"
  fi

  log "----- untracked files (ff pull would NOT touch these) -----"
  as_user "cd $repo_q && git ls-files --others --exclude-standard" 2>/dev/null | sed 's/^/  ?? /' || true

  log "----- key files present in checkout? -----"
  for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
    if as_user "test -f $repo_q/$f" 2>/dev/null; then
      log "  PRESENT  $f"
    else
      log "  MISSING  $f"
    fi
  done

  log "===== DIAG DONE for $TARGET_REPO ====="
}

# Capture the full report to a file (and surface it in alloc logs via tee).
run_diag 2>&1 | tee "$REPORT"

# Persist durably to a Nomad var so it survives alloc GC / log-retrieval 404s.
if command -v nomad >/dev/null 2>&1; then
  if nomad var put -force "fleet/checkout-diag/$NODE_LABEL" report=@"$REPORT" >/dev/null 2>&1; then
    log "persisted report to nomad var fleet/checkout-diag/$NODE_LABEL"
  else
    log "WARN: could not write nomad var (logs still have the report)"
  fi
else
  log "WARN: nomad CLI not on PATH; report only in logs"
fi
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "20s"
    }
  }

  group "bigo" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "bigo-server"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "diag" {
      driver = "raw_exec"

      env {
        NODE_LABEL  = "bigo-server"
        TARGET_USER = "bigo"
        TARGET_REPO = "/home/bigo/monad"
        NOMAD_ADDR  = "http://100.75.75.39:4646"
      }

      config {
        command = "/bin/bash"
        args    = ["local/diag.sh"]
      }

      template {
        destination = "local/diag.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only: no working-tree mutation
set -uo pipefail

REPORT="local/report.txt"
: > "$REPORT"

log() { printf '[diag:%s] %s\n' "$NODE_LABEL" "$*"; }
fail() { printf '[diag:%s] FAIL: %s\n' "$NODE_LABEL" "$*" >&2; exit 1; }

[ -n "$TARGET_USER" ] || fail "TARGET_USER empty"
[ -n "$TARGET_REPO" ] || fail "TARGET_REPO empty"
getent passwd "$TARGET_USER" >/dev/null || fail "missing user $TARGET_USER"
[ -d "$TARGET_REPO/.git" ] || fail "missing git checkout at $TARGET_REPO"

repo_q="$(printf '%q' "$TARGET_REPO")"

as_user() {
  local cmd="$1"
  if [ "$(id -un)" = "$TARGET_USER" ]; then
    bash -lc "$cmd"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n -H -u "$TARGET_USER" bash -lc "$cmd"
  else
    su - "$TARGET_USER" -c "bash -lc $(printf '%q' "$cmd")"
  fi
}

run_diag() {
  local uid branch head origin counts status mods
  uid="$(id -u "$TARGET_USER" 2>/dev/null || echo '?')"
  log "===== $TARGET_REPO  (user=$TARGET_USER uid=$uid) ====="

  branch="$(as_user "cd $repo_q && git rev-parse --abbrev-ref HEAD" 2>/dev/null || echo '?')"
  head="$(as_user "cd $repo_q && git rev-parse HEAD" 2>/dev/null || echo '?')"
  log "branch=$branch head=$head"

  log "remotes:"
  as_user "cd $repo_q && git remote -v" 2>/dev/null || true

  as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null \
    && log "fetched origin/main" || log "WARN: git fetch failed (offline/wrong remote?)"

  origin="$(as_user "cd $repo_q && git rev-parse origin/main" 2>/dev/null || echo '?')"
  log "origin/main=$origin"
  counts="$(as_user "cd $repo_q && git rev-list --left-right --count HEAD...origin/main" 2>/dev/null || echo '? ?')"
  log "ahead/behind (HEAD...origin/main) = $counts"

  log "----- git status --porcelain -----"
  status="$(as_user "cd $repo_q && git status --porcelain" 2>/dev/null || true)"
  if [ -z "$status" ]; then
    log "(clean working tree)"
  else
    printf '%s\n' "$status"
    log "dirty file count: $(printf '%s\n' "$status" | grep -c . || true)"
  fi

  log "----- tracked changes vs HEAD: git diff --stat -----"
  as_user "cd $repo_q && git diff --stat" 2>/dev/null || true

  log "----- per-file: local-modified files vs origin/main -----"
  mods="$(printf '%s\n' "$status" | awk '$1 ~ /[MARCD]/ {print $2}')"
  if [ -n "$mods" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if as_user "cd $repo_q && git diff --quiet origin/main -- $(printf '%q' "$f")" 2>/dev/null; then
        log "  SAME-AS-ORIGIN  $f"
      else
        log "  DIVERGES        $f"
      fi
    done <<< "$mods"
  else
    log "  (no tracked modifications)"
  fi

  log "----- untracked files (ff pull would NOT touch these) -----"
  as_user "cd $repo_q && git ls-files --others --exclude-standard" 2>/dev/null | sed 's/^/  ?? /' || true

  log "----- key files present in checkout? -----"
  for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
    if as_user "test -f $repo_q/$f" 2>/dev/null; then
      log "  PRESENT  $f"
    else
      log "  MISSING  $f"
    fi
  done

  log "===== DIAG DONE for $TARGET_REPO ====="
}

run_diag 2>&1 | tee "$REPORT"

if command -v nomad >/dev/null 2>&1; then
  if nomad var put -force "fleet/checkout-diag/$NODE_LABEL" report=@"$REPORT" >/dev/null 2>&1; then
    log "persisted report to nomad var fleet/checkout-diag/$NODE_LABEL"
  else
    log "WARN: could not write nomad var (logs still have the report)"
  fi
else
  log "WARN: nomad CLI not on PATH; report only in logs"
fi
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
