# amd64-checkout-diag — READ-ONLY diagnostic of the credentialed host monad
# checkouts on the amd64 agent nodes. It captures exactly what is dirty/stale
# so the dirty-checkout blocker in fleet/projects/amd64-agent-checkout-sync.md
# can be resolved safely. It NEVER writes the working tree: only git status,
# git diff, git log, and a non-mutating `git fetch` of refs.
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

uid="$(id -u "$TARGET_USER" 2>/dev/null || echo '?')"
log "===== $TARGET_REPO  (user=$TARGET_USER uid=$uid) ====="

branch="$(as_user "cd $repo_q && git rev-parse --abbrev-ref HEAD" 2>/dev/null || echo '?')"
head="$(as_user "cd $repo_q && git rev-parse HEAD" 2>/dev/null || echo '?')"
log "branch=$branch head=$head"

# Non-mutating fetch of remote refs (does NOT touch the working tree).
as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null \
  && log "fetched origin/main" || log "WARN: git fetch failed (offline?)"

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
  nfiles="$(printf '%s\n' "$status" | grep -c . || true)"
  log "dirty file count: $nfiles"
fi

log "----- tracked changes vs HEAD: git diff --stat -----"
as_user "cd $repo_q && git diff --stat" 2>/dev/null || true

log "----- staged changes vs HEAD: git diff --cached --stat -----"
as_user "cd $repo_q && git diff --cached --stat" 2>/dev/null || true

# For each tracked, modified file: does the LOCAL version already match origin/main?
# (If yes, the local edit is just origin content not yet pulled -> safe.)
log "----- per-file: local-modified files vs origin/main -----"
mods="$(printf '%s\n' "$status" | awk '$1 ~ /[MARCD]/ {print $2}')"
if [ -n "$mods" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if as_user "cd $repo_q && git diff --quiet origin/main -- $(printf '%q' "$f")" 2>/dev/null; then
      log "  SAME-AS-ORIGIN  $f   (local edit already equals origin/main)"
    else
      log "  DIVERGES        $f   (local content differs from origin/main)"
    fi
  done <<< "$mods"
else
  log "  (no tracked modifications)"
fi

log "----- untracked files (would NOT be touched by ff pull) -----"
as_user "cd $repo_q && git ls-files --others --exclude-standard" 2>/dev/null | sed 's/^/  ?? /' || true

log "----- key files present in checkout? -----"
for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  if as_user "test -f $repo_q/$f" 2>/dev/null; then
    log "  PRESENT  $f"
  else
    log "  MISSING  $f"
  fi
done

log "----- engine readiness (read-only) -----"
engines="$(as_user "cd $repo_q && . meta/agent/engines.sh >/dev/null 2>&1 && engines_ready" 2>/dev/null || true)"
[ -n "$engines" ] || engines="none/unknown"
log "  engines_ready=$engines"

log "===== DIAG DONE for $TARGET_REPO ====="
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

uid="$(id -u "$TARGET_USER" 2>/dev/null || echo '?')"
log "===== $TARGET_REPO  (user=$TARGET_USER uid=$uid) ====="

branch="$(as_user "cd $repo_q && git rev-parse --abbrev-ref HEAD" 2>/dev/null || echo '?')"
head="$(as_user "cd $repo_q && git rev-parse HEAD" 2>/dev/null || echo '?')"
log "branch=$branch head=$head"

as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null \
  && log "fetched origin/main" || log "WARN: git fetch failed (offline?)"

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
  nfiles="$(printf '%s\n' "$status" | grep -c . || true)"
  log "dirty file count: $nfiles"
fi

log "----- tracked changes vs HEAD: git diff --stat -----"
as_user "cd $repo_q && git diff --stat" 2>/dev/null || true

log "----- staged changes vs HEAD: git diff --cached --stat -----"
as_user "cd $repo_q && git diff --cached --stat" 2>/dev/null || true

log "----- per-file: local-modified files vs origin/main -----"
mods="$(printf '%s\n' "$status" | awk '$1 ~ /[MARCD]/ {print $2}')"
if [ -n "$mods" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if as_user "cd $repo_q && git diff --quiet origin/main -- $(printf '%q' "$f")" 2>/dev/null; then
      log "  SAME-AS-ORIGIN  $f   (local edit already equals origin/main)"
    else
      log "  DIVERGES        $f   (local content differs from origin/main)"
    fi
  done <<< "$mods"
else
  log "  (no tracked modifications)"
fi

log "----- untracked files (would NOT be touched by ff pull) -----"
as_user "cd $repo_q && git ls-files --others --exclude-standard" 2>/dev/null | sed 's/^/  ?? /' || true

log "----- key files present in checkout? -----"
for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  if as_user "test -f $repo_q/$f" 2>/dev/null; then
    log "  PRESENT  $f"
  else
    log "  MISSING  $f"
  fi
done

log "----- engine readiness (read-only) -----"
engines="$(as_user "cd $repo_q && . meta/agent/engines.sh >/dev/null 2>&1 && engines_ready" 2>/dev/null || true)"
[ -n "$engines" ] || engines="none/unknown"
log "  engines_ready=$engines"

log "===== DIAG DONE for $TARGET_REPO ====="
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
