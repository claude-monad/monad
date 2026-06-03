#!/usr/bin/env bash
# provision-node — make THIS node able to run both engines. One pass:
#   1. pick the node's run-user (the one that owns/will own engine sessions)
#   2. unlock it if locked (so `su -`/login + sessions work) — root only
#   3. ensure both CLIs are installed, and symlink whatever binary exists (incl. snap +
#      user-local installs) into /usr/local/bin so they're on PATH for ANY shell
#   4. install the shared Claude+Codex creds from the var store (cred-sync, newest-wins)
#   5. advertise readiness via node meta (ensure-engines)
#
# Run by jobs/engine-provision.hcl (system job, every node) in a loop. Idempotent + safe:
# cred-sync only adopts a fresher token and only writes back a VALIDATED one (the single Max
# account is the owner's only cred). Env: CRED_USER (override), CRED_ACCOUNT (default max).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NOMAD_ADDR:=http://100.75.75.39:4646}"; export NOMAD_ADDR
ACCOUNT="${CRED_ACCOUNT:-max}"
log() { echo "[provision $(date '+%H:%M:%S')] $*"; }

real_users() { getent passwd | awk -F: '$3>=1000 && $3<65000 && $6 ~ /^\/home\//{print $1}'; }

pick_user() {
  [ -n "${CRED_USER:-}" ] && { echo "$CRED_USER"; return; }
  local u h
  # prefer a user that already has engine creds (the established login)
  for u in $(real_users); do
    h="$(getent passwd "$u" | cut -d: -f6)"
    [ -f "$h/.claude/.credentials.json" ] || [ -f "$h/.codex/auth.json" ] && { echo "$u"; return; }
  done
  u="$(real_users | head -1)"; [ -n "$u" ] && { echo "$u"; return; }
  echo root
}

U="$(pick_user)"; H="$(getent passwd "$U" | cut -d: -f6)"
log "node=$(hostname) target user=$U home=$H"

# 2) unlock a locked run-user so su/login + engine sessions work (the codex-ssh lesson)
if [ "$(id -u)" = 0 ] && [ "$U" != root ]; then
  pw="$(getent shadow "$U" 2>/dev/null | cut -d: -f2)"
  case "$pw" in
    '!'*|'*'|'') usermod -p '*' "$U" 2>/dev/null && log "unlocked run-user $U" ;;
  esac
fi

run_as() { # run a command as the run-user (or directly if we ARE them / root target)
  if [ "$U" = root ] || [ "$(id -un)" = "$U" ]; then bash -lc "$*"; else su - "$U" -c "$*"; fi
}

# 3) ensure CLIs installed + reachable. ensure-engines installs missing CLIs + advertises meta.
if [ -f "$HERE/ensure-engines.sh" ]; then
  run_as "NOMAD_ADDR='$NOMAD_ADDR' bash '$HERE/ensure-engines.sh'" 2>&1 | sed 's/^/  ee: /' | tail -5 || true
fi
# Symlink the best available binary into /usr/local/bin (on every shell's PATH), so an empty
# login PATH or a snap/user-local install can't hide the engine from sessions.
for eng in claude codex; do
  b=""
  for cand in "/snap/bin/$eng" "$H/.local/bin/$eng" "$H/.claude/local/$eng" "$H/bin/$eng"; do
    [ -x "$cand" ] && { b="$cand"; break; }
  done
  [ -n "$b" ] || b="$(run_as "command -v $eng" 2>/dev/null | grep -E '^/' | head -1)"
  [ -n "$b" ] || b="$(find "$H" /snap -maxdepth 6 -name "$eng" -type f -perm -u+x 2>/dev/null | head -1)"
  if [ -n "$b" ] && [ -e "$b" ]; then
    ln -sf "$b" "/usr/local/bin/$eng" 2>/dev/null && log "$eng available -> /usr/local/bin/$eng ($b)"
  else
    log "$eng: NO binary on this node (install did not yield one)"
  fi
done

# 4) install creds for the run-user (newest-wins; writeback is validated)
CRED_USER="$U" bash "$HERE/cred-sync.sh" reconcile "$ACCOUNT" --user "$U" 2>&1 | sed 's/^/  /'

# 5) re-advertise readiness (run-user context, where the creds + CLIs now are)
[ -f "$HERE/ensure-engines.sh" ] && run_as "NOMAD_ADDR='$NOMAD_ADDR' bash '$HERE/ensure-engines.sh'" >/dev/null 2>&1 || true
log "provision pass done for $U on $(hostname)"
