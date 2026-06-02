# amd64-agent-checkout-sync — one-shot safe sync for credentialed amd64 host
# monad checkouts. This clears the stale-repo blocker from
# fleet/projects/agent-mesh-cred-portability.md without touching creds,
# deleting files, or resetting local work.
job "amd64-agent-checkout-sync" {
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

    task "sync" {
      driver = "raw_exec"

      env {
        NODE_LABEL  = "V1410-1"
        TARGET_USER = "e"
        TARGET_REPO = "/home/e/monad"
      }

      config {
        command = "/bin/bash"
        args    = ["local/sync-checkout.sh"]
      }

      template {
        destination = "local/sync-checkout.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
set -euo pipefail

log() { printf '[checkout-sync:%s] %s\n' "$NODE_LABEL" "$*"; }
fail() { printf '[checkout-sync:%s] FAIL: %s\n' "$NODE_LABEL" "$*" >&2; exit 1; }

[ -n "$TARGET_USER" ] || fail "TARGET_USER is empty"
[ -n "$TARGET_REPO" ] || fail "TARGET_REPO is empty"
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

log "checking $TARGET_REPO as $TARGET_USER"
branch="$(as_user "cd $repo_q && git rev-parse --abbrev-ref HEAD")"
[ "$branch" = "main" ] || fail "$TARGET_REPO is on branch $branch, not main"

dirty="$(as_user "cd $repo_q && git status --porcelain")"
if [ -n "$dirty" ]; then
  printf '%s\n' "$dirty" >&2
  fail "$TARGET_REPO has local changes; refusing to pull"
fi

before="$(as_user "cd $repo_q && git rev-parse HEAD")"
log "clean checkout at $before; fetching origin/main"
as_user "cd $repo_q && git fetch origin main --quiet"
as_user "cd $repo_q && git pull --ff-only origin main"
after="$(as_user "cd $repo_q && git rev-parse HEAD")"

for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  as_user "test -f $repo_q/$f" || fail "missing $TARGET_REPO/$f after sync"
done

engines="$(as_user "cd $repo_q && . meta/agent/engines.sh && engines_ready" || true)"
[ -n "$engines" ] || engines="none"
log "CHECKOUT_SYNC_OK before=$before after=$after engines=$engines"
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "30s"
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

    task "sync" {
      driver = "raw_exec"

      env {
        NODE_LABEL  = "bigo-server"
        TARGET_USER = "bigo"
        TARGET_REPO = "/home/bigo/monad"
      }

      config {
        command = "/bin/bash"
        args    = ["local/sync-checkout.sh"]
      }

      template {
        destination = "local/sync-checkout.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
set -euo pipefail

log() { printf '[checkout-sync:%s] %s\n' "$NODE_LABEL" "$*"; }
fail() { printf '[checkout-sync:%s] FAIL: %s\n' "$NODE_LABEL" "$*" >&2; exit 1; }

[ -n "$TARGET_USER" ] || fail "TARGET_USER is empty"
[ -n "$TARGET_REPO" ] || fail "TARGET_REPO is empty"
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

log "checking $TARGET_REPO as $TARGET_USER"
branch="$(as_user "cd $repo_q && git rev-parse --abbrev-ref HEAD")"
[ "$branch" = "main" ] || fail "$TARGET_REPO is on branch $branch, not main"

dirty="$(as_user "cd $repo_q && git status --porcelain")"
if [ -n "$dirty" ]; then
  printf '%s\n' "$dirty" >&2
  fail "$TARGET_REPO has local changes; refusing to pull"
fi

before="$(as_user "cd $repo_q && git rev-parse HEAD")"
log "clean checkout at $before; fetching origin/main"
as_user "cd $repo_q && git fetch origin main --quiet"
as_user "cd $repo_q && git pull --ff-only origin main"
after="$(as_user "cd $repo_q && git rev-parse HEAD")"

for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  as_user "test -f $repo_q/$f" || fail "missing $TARGET_REPO/$f after sync"
done

engines="$(as_user "cd $repo_q && . meta/agent/engines.sh && engines_ready" || true)"
[ -n "$engines" ] || engines="none"
log "CHECKOUT_SYNC_OK before=$before after=$after engines=$engines"
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "30s"
    }
  }
}
