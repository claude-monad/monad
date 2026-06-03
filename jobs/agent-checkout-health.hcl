# agent-checkout-health — standing, low-noise monitor of the host monad
# checkout on each agent node. READ-ONLY: it only runs git status/rev-parse/
# rev-list + a non-mutating `git fetch`, and records a compact health verdict
# to the Nomad var fleet/checkout-health/<node>.
#
# Motivated by fleet/projects/agent-checkout-health.md: V1410-1 and bigo-server
# silently ran checkouts of the WRONG repo (eliottcassidy2000/monad, missing the
# meta/agent/* tree) for an unknown period, breaking every briefed/maintenance
# agent on them. This turns that silent failure into a queryable signal.
#
# Quiet by design: the per-node var is overwritten each run (no log spam) and a
# transition is captured in the var itself (prev_status + changed_at). The
# monitor script is delivered via a Nomad template, so it does NOT depend on the
# host checkout being correct — it can correctly report an unhealthy node.
#
# NOTE: script bodies avoid ${...} brace expansions because Nomad HCL2 would
# interpret them as interpolation inside the heredoc.
job "agent-checkout-health" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */6 * * *"]
    prohibit_overlap = true
  }

  group "oraclebox1" {
    count = 1

    constraint {
      attribute = "${node.unique.name}"
      value     = "oraclebox1"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
    reschedule {
      attempts = 0
    }

    task "health" {
      driver = "raw_exec"

      env {
        NODE_LABEL    = "oraclebox1"
        TARGET_USER   = "ubuntu"
        TARGET_REPO   = "/home/ubuntu/monad"
        EXPECT_ORIGIN = "eliott-monad/monad"
        NOMAD_ADDR    = "http://100.75.75.39:4646"
      }

      config {
        command = "/bin/bash"
        args    = ["local/health.sh"]
      }

      template {
        destination = "local/health.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only checkout health probe -> Nomad var fleet/checkout-health/<node>
set -uo pipefail

HVAR="fleet/checkout-health/$NODE_LABEL"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_unknown() {
  nomad var put -force "$HVAR" node="$NODE_LABEL" status="unknown" \
    detail="$1" ts="$now" >/dev/null 2>&1 || true
  echo "[checkout-health:$NODE_LABEL] status=unknown detail=$1"
  exit 0
}

getent passwd "$TARGET_USER" >/dev/null 2>&1 || emit_unknown "missing user $TARGET_USER"
[ -d "$TARGET_REPO/.git" ] || emit_unknown "no git checkout at $TARGET_REPO"

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

head="$(as_user "cd $repo_q && git rev-parse --short HEAD" 2>/dev/null || echo '?')"
origin="$(as_user "cd $repo_q && git remote get-url origin" 2>/dev/null || echo '?')"
as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null || true
counts="$(as_user "cd $repo_q && git rev-list --left-right --count HEAD...origin/main" 2>/dev/null || echo '? ?')"
ahead="$(echo "$counts" | awk '{print $1}')"
behind="$(echo "$counts" | awk '{print $2}')"
dirty="$(as_user "cd $repo_q && git status --porcelain" 2>/dev/null | grep -c . || echo '?')"

origin_ok=false
case "$origin" in *"$EXPECT_ORIGIN"*) origin_ok=true ;; esac

key_files_ok=true
for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  as_user "test -f $repo_q/$f" 2>/dev/null || key_files_ok=false
done

status="unhealthy"
if [ "$origin_ok" = true ] && [ "$key_files_ok" = true ]; then status="healthy"; fi

prev="$(nomad var get -item=status "$HVAR" 2>/dev/null || echo '')"
prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
changed_at="$(nomad var get -item=changed_at "$HVAR" 2>/dev/null || echo '')"
transition="(none)"
if [ "$prev" != "$status" ]; then
  changed_at="$now"
  transition="$prevlabel->$status"
fi
[ -n "$changed_at" ] || changed_at="$now"

nomad var put -force "$HVAR" \
  node="$NODE_LABEL" status="$status" origin_ok="$origin_ok" key_files_ok="$key_files_ok" \
  origin="$origin" head="$head" ahead="$ahead" behind="$behind" dirty="$dirty" \
  prev_status="$prevlabel" changed_at="$changed_at" ts="$now" >/dev/null 2>&1 \
  || { echo "[checkout-health:$NODE_LABEL] WARN: nomad var put failed"; exit 0; }

echo "[checkout-health:$NODE_LABEL] status=$status origin_ok=$origin_ok key_files_ok=$key_files_ok ahead=$ahead behind=$behind dirty=$dirty transition=$transition"
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 64
      }

      kill_timeout = "20s"
    }
  }

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

    task "health" {
      driver = "raw_exec"

      env {
        NODE_LABEL    = "V1410-1"
        TARGET_USER   = "e"
        TARGET_REPO   = "/home/e/monad"
        EXPECT_ORIGIN = "eliott-monad/monad"
        NOMAD_ADDR    = "http://100.75.75.39:4646"
      }

      config {
        command = "/bin/bash"
        args    = ["local/health.sh"]
      }

      template {
        destination = "local/health.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only checkout health probe -> Nomad var fleet/checkout-health/<node>
set -uo pipefail

HVAR="fleet/checkout-health/$NODE_LABEL"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_unknown() {
  nomad var put -force "$HVAR" node="$NODE_LABEL" status="unknown" \
    detail="$1" ts="$now" >/dev/null 2>&1 || true
  echo "[checkout-health:$NODE_LABEL] status=unknown detail=$1"
  exit 0
}

getent passwd "$TARGET_USER" >/dev/null 2>&1 || emit_unknown "missing user $TARGET_USER"
[ -d "$TARGET_REPO/.git" ] || emit_unknown "no git checkout at $TARGET_REPO"

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

head="$(as_user "cd $repo_q && git rev-parse --short HEAD" 2>/dev/null || echo '?')"
origin="$(as_user "cd $repo_q && git remote get-url origin" 2>/dev/null || echo '?')"
as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null || true
counts="$(as_user "cd $repo_q && git rev-list --left-right --count HEAD...origin/main" 2>/dev/null || echo '? ?')"
ahead="$(echo "$counts" | awk '{print $1}')"
behind="$(echo "$counts" | awk '{print $2}')"
dirty="$(as_user "cd $repo_q && git status --porcelain" 2>/dev/null | grep -c . || echo '?')"

origin_ok=false
case "$origin" in *"$EXPECT_ORIGIN"*) origin_ok=true ;; esac

key_files_ok=true
for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  as_user "test -f $repo_q/$f" 2>/dev/null || key_files_ok=false
done

status="unhealthy"
if [ "$origin_ok" = true ] && [ "$key_files_ok" = true ]; then status="healthy"; fi

prev="$(nomad var get -item=status "$HVAR" 2>/dev/null || echo '')"
prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
changed_at="$(nomad var get -item=changed_at "$HVAR" 2>/dev/null || echo '')"
transition="(none)"
if [ "$prev" != "$status" ]; then
  changed_at="$now"
  transition="$prevlabel->$status"
fi
[ -n "$changed_at" ] || changed_at="$now"

nomad var put -force "$HVAR" \
  node="$NODE_LABEL" status="$status" origin_ok="$origin_ok" key_files_ok="$key_files_ok" \
  origin="$origin" head="$head" ahead="$ahead" behind="$behind" dirty="$dirty" \
  prev_status="$prevlabel" changed_at="$changed_at" ts="$now" >/dev/null 2>&1 \
  || { echo "[checkout-health:$NODE_LABEL] WARN: nomad var put failed"; exit 0; }

echo "[checkout-health:$NODE_LABEL] status=$status origin_ok=$origin_ok key_files_ok=$key_files_ok ahead=$ahead behind=$behind dirty=$dirty transition=$transition"
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 64
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

    task "health" {
      driver = "raw_exec"

      env {
        NODE_LABEL    = "bigo-server"
        TARGET_USER   = "bigo"
        TARGET_REPO   = "/home/bigo/monad"
        EXPECT_ORIGIN = "eliott-monad/monad"
        NOMAD_ADDR    = "http://100.75.75.39:4646"
      }

      config {
        command = "/bin/bash"
        args    = ["local/health.sh"]
      }

      template {
        destination = "local/health.sh"
        perms       = "755"
        data        = <<-SCRIPT
#!/bin/bash
# read-only checkout health probe -> Nomad var fleet/checkout-health/<node>
set -uo pipefail

HVAR="fleet/checkout-health/$NODE_LABEL"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_unknown() {
  nomad var put -force "$HVAR" node="$NODE_LABEL" status="unknown" \
    detail="$1" ts="$now" >/dev/null 2>&1 || true
  echo "[checkout-health:$NODE_LABEL] status=unknown detail=$1"
  exit 0
}

getent passwd "$TARGET_USER" >/dev/null 2>&1 || emit_unknown "missing user $TARGET_USER"
[ -d "$TARGET_REPO/.git" ] || emit_unknown "no git checkout at $TARGET_REPO"

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

head="$(as_user "cd $repo_q && git rev-parse --short HEAD" 2>/dev/null || echo '?')"
origin="$(as_user "cd $repo_q && git remote get-url origin" 2>/dev/null || echo '?')"
as_user "cd $repo_q && git fetch origin main --quiet" 2>/dev/null || true
counts="$(as_user "cd $repo_q && git rev-list --left-right --count HEAD...origin/main" 2>/dev/null || echo '? ?')"
ahead="$(echo "$counts" | awk '{print $1}')"
behind="$(echo "$counts" | awk '{print $2}')"
dirty="$(as_user "cd $repo_q && git status --porcelain" 2>/dev/null | grep -c . || echo '?')"

origin_ok=false
case "$origin" in *"$EXPECT_ORIGIN"*) origin_ok=true ;; esac

key_files_ok=true
for f in meta/agent/run-agent.sh meta/agent/engines.sh scripts/maintenance-agent.sh; do
  as_user "test -f $repo_q/$f" 2>/dev/null || key_files_ok=false
done

status="unhealthy"
if [ "$origin_ok" = true ] && [ "$key_files_ok" = true ]; then status="healthy"; fi

prev="$(nomad var get -item=status "$HVAR" 2>/dev/null || echo '')"
prevlabel="$prev"; [ -n "$prevlabel" ] || prevlabel="none"
changed_at="$(nomad var get -item=changed_at "$HVAR" 2>/dev/null || echo '')"
transition="(none)"
if [ "$prev" != "$status" ]; then
  changed_at="$now"
  transition="$prevlabel->$status"
fi
[ -n "$changed_at" ] || changed_at="$now"

nomad var put -force "$HVAR" \
  node="$NODE_LABEL" status="$status" origin_ok="$origin_ok" key_files_ok="$key_files_ok" \
  origin="$origin" head="$head" ahead="$ahead" behind="$behind" dirty="$dirty" \
  prev_status="$prevlabel" changed_at="$changed_at" ts="$now" >/dev/null 2>&1 \
  || { echo "[checkout-health:$NODE_LABEL] WARN: nomad var put failed"; exit 0; }

echo "[checkout-health:$NODE_LABEL] status=$status origin_ok=$origin_ok key_files_ok=$key_files_ok ahead=$ahead behind=$behind dirty=$dirty transition=$transition"
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 64
      }

      kill_timeout = "20s"
    }
  }
}
