#!/usr/bin/env bash
# cred-sync — make Claude + Codex credentials portable so EITHER engine can run on EVERY node.
#
# The problem: Claude Code / Codex auth is a per-machine human login (no API key). Creds only
# lived on the nodes someone logged into, trapping Claude work on oraclebox1. This distributes
# the logged-in creds through an ENCRYPTED Nomad var store so any node can run any engine.
#
# Auth is OAuth (accessToken + refreshToken + expiresAt). We DON'T run a central refresh broker;
# instead "newest token wins": each node periodically reconciles its local creds with the var —
# if the var copy is fresher (later expiry) it installs it; if the LOCAL copy is fresher (the
# local CLI just refreshed) it writes that back to the var. The freshest valid token always
# propagates, which tolerates refresh-token rotation without a single point of failure.
#
# Store layout (Nomad vars, encrypted at rest):
#   secret/creds/claude/<account>   item credentials_b64  (base64 of ~/.claude/.credentials.json)
#   secret/creds/codex/<account>    item auth_b64         (base64 of ~/.codex/auth.json)
#   secret/creds/index              items claude_accounts, codex_accounts (csv)
#
# Usage:
#   cred-sync.sh harvest <claude|codex> [account] [--home DIR]   # local creds -> var (seed/refresh)
#   cred-sync.sh install <claude|codex> [account] [--user U]     # var -> local (newest-wins)
#   cred-sync.sh reconcile [account] [--user U]                  # both engines, newest-wins + writeback
#   cred-sync.sh sync [--interval N] [account] [--user U]        # reconcile in a loop
#   cred-sync.sh list                                            # what's in the store
set -uo pipefail

: "${NOMAD_ADDR:=http://100.75.75.39:4646}"; export NOMAD_ADDR
DEFAULT_ACCOUNT="${CRED_ACCOUNT:-shared}"
log() { echo "[cred-sync $(date '+%H:%M:%S')] $*"; }
die() { echo "cred-sync: $*" >&2; exit 1; }

# --- locate a user's home + the cred file paths ---
user_home() { getent passwd "$1" 2>/dev/null | cut -d: -f6; }

# Find a home that already has creds for an engine (for harvest auto-detect).
find_cred_home() {
  local engine="$1" rel u h
  rel=$([ "$engine" = claude ] && echo ".claude/.credentials.json" || echo ".codex/auth.json")
  for u in "$USER" e ubuntu bigo eliott; do
    h="$(user_home "$u")"; [ -n "$h" ] || continue
    [ -f "$h/$rel" ] && { echo "$h"; return 0; }
  done
  return 1
}

cred_path() { # <engine> <home>
  [ "$1" = claude ] && echo "$2/.claude/.credentials.json" || echo "$2/.codex/auth.json"
}

# Expiry (epoch seconds) of a creds file, for newest-wins comparison. Missing/unknown -> 0.
expiry_of() { # <engine> <file>
  local engine="$1" f="$2"; [ -f "$f" ] || { echo 0; return; }
  if [ "$engine" = claude ]; then
    python3 -c "import json,sys; print(int(json.load(open('$f')).get('claudeAiOauth',{}).get('expiresAt',0)//1000))" 2>/dev/null || echo 0
  else
    # codex: tokens.expiry varies by version; fall back to file mtime if no explicit field.
    python3 -c "
import json,os
d=json.load(open('$f'))
t=d.get('tokens',{}) or {}
for k in ('expires_at','expiry','exp'):
    v=t.get(k) or d.get(k)
    if v: print(int(float(v))); raise SystemExit
print(int(os.path.getmtime('$f')))" 2>/dev/null || echo 0
  fi
}

var_expiry() { # <engine> <account>  -> expiry of the stored copy (via a temp decode)
  local engine="$1" acct="$2" item tmp e
  item=$([ "$engine" = claude ] && echo credentials_b64 || echo auth_b64)
  tmp="$(mktemp)"
  if nomad var get -item="$item" "secret/creds/$engine/$acct" 2>/dev/null | base64 -d > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    e="$(expiry_of "$engine" "$tmp")"
  else e=0; fi
  rm -f "$tmp"; echo "${e:-0}"
}

add_to_index() { # <engine> <account>
  # `nomad var put -force PATH k=v` replaces the WHOLE var, so we must rewrite BOTH engine
  # lists every time or one clobbers the other. Read current values, update the relevant one.
  local engine="$1" acct="$2" cl co
  cl="$(nomad var get -item=claude_accounts secret/creds/index 2>/dev/null)"
  co="$(nomad var get -item=codex_accounts secret/creds/index 2>/dev/null)"
  if [ "$engine" = claude ]; then case ",$cl," in *",$acct,"*) :;; *) cl="${cl:+$cl,}$acct";; esac
  else case ",$co," in *",$acct,"*) :;; *) co="${co:+$co,}$acct";; esac; fi
  nomad var put -force secret/creds/index "claude_accounts=$cl" "codex_accounts=$co" >/dev/null 2>&1
}

cmd_harvest() {
  local engine="$1" acct="${2:-$DEFAULT_ACCOUNT}" home="" item key
  shift; [ "${1:-}" = "--home" ] && { home="$2"; }
  [ "$engine" = claude ] || [ "$engine" = codex ] || die "engine must be claude|codex"
  [ -n "$home" ] || home="$(find_cred_home "$engine")" || die "no $engine creds found locally to harvest"
  local f; f="$(cred_path "$engine" "$home")"
  [ -f "$f" ] || die "no creds at $f"
  item=$([ "$engine" = claude ] && echo credentials_b64 || echo auth_b64)
  base64 -w0 "$f" > /tmp/.cs.$$ 2>/dev/null || base64 "$f" | tr -d '\n' > /tmp/.cs.$$
  nomad var put -force "secret/creds/$engine/$acct" "$item=@/tmp/.cs.$$" >/dev/null 2>&1 \
    && log "harvested $engine ($acct) from $f -> secret/creds/$engine/$acct (expiry $(expiry_of "$engine" "$f"))" \
    || die "nomad var put failed"
  rm -f /tmp/.cs.$$
  add_to_index "$engine" "$acct"
}

# Write the var's copy into a user's home if the var is fresher; if local is fresher, write back.
reconcile_engine() { # <engine> <account> <user>
  local engine="$1" acct="$2" u="$3" home rel f item le ve
  home="$(user_home "$u")"; [ -n "$home" ] || { log "no home for user $u"; return 1; }
  f="$(cred_path "$engine" "$home")"
  item=$([ "$engine" = claude ] && echo credentials_b64 || echo auth_b64)
  le="$(expiry_of "$engine" "$f")"; ve="$(var_expiry "$engine" "$acct")"
  if [ "$ve" -eq 0 ] && [ "$le" -eq 0 ]; then log "$engine/$acct: nothing in store or locally"; return 1; fi
  if [ "$ve" -gt "$le" ]; then
    # var is fresher -> install it locally
    mkdir -p "$(dirname "$f")"; chmod 700 "$(dirname "$f")" 2>/dev/null || true
    [ -f "$f" ] && cp -p "$f" "$f.bak-$(date +%s)" 2>/dev/null || true
    nomad var get -item="$item" "secret/creds/$engine/$acct" 2>/dev/null | base64 -d > "$f.tmp" 2>/dev/null
    if [ -s "$f.tmp" ]; then
      mv "$f.tmp" "$f"; chmod 600 "$f"; chown "$u:$(id -gn "$u" 2>/dev/null || echo "$u")" "$f" 2>/dev/null || true
      log "$engine/$acct: installed var copy for $u (var expiry $ve > local $le)"
    else rm -f "$f.tmp"; log "$engine/$acct: var decode empty — skipped"; fi
  elif [ "$le" -gt "$ve" ]; then
    # local is fresher (CLI refreshed) -> write back so other nodes adopt it
    base64 -w0 "$f" > /tmp/.cs.$$ 2>/dev/null || base64 "$f" | tr -d '\n' > /tmp/.cs.$$
    nomad var put -force "secret/creds/$engine/$acct" "$item=@/tmp/.cs.$$" >/dev/null 2>&1 \
      && log "$engine/$acct: wrote back fresher local token for $u (local $le > var $ve)"
    rm -f /tmp/.cs.$$
    add_to_index "$engine" "$acct"
  else
    log "$engine/$acct: in sync for $u (expiry $le)"
  fi
}

cmd_install()   { local e="$1" a="${2:-$DEFAULT_ACCOUNT}" u="${CRED_USER:-$USER}"; [ "${3:-}" = "--user" ] && u="$4"; reconcile_engine "$e" "$a" "$u"; }
cmd_reconcile() { local a="${1:-$DEFAULT_ACCOUNT}" u="${CRED_USER:-$USER}"; [ "${2:-}" = "--user" ] && u="$3"; reconcile_engine claude "$a" "$u"; reconcile_engine codex "$a" "$u"; }

cmd_sync() {
  local interval=120 a="$DEFAULT_ACCOUNT" u="${CRED_USER:-$USER}"
  while [ $# -gt 0 ]; do case "$1" in
    --interval) interval="$2"; shift 2;; --user) u="$2"; shift 2;; *) a="$1"; shift;;
  esac; done
  log "sync loop: account=$a user=$u every ${interval}s (newest-wins both engines)"
  while true; do CRED_USER="$u" cmd_reconcile "$a" --user "$u"; sleep "$interval"; done
}

cmd_list() {
  echo "claude accounts: $(nomad var get -item=claude_accounts secret/creds/index 2>/dev/null || echo '(none)')"
  echo "codex accounts:  $(nomad var get -item=codex_accounts secret/creds/index 2>/dev/null || echo '(none)')"
}

case "${1:-}" in
  harvest)   shift; cmd_harvest "$@";;
  install)   shift; cmd_install "$@";;
  reconcile) shift; cmd_reconcile "$@";;
  sync)      shift; cmd_sync "$@";;
  list)      cmd_list;;
  *) echo "usage: cred-sync.sh {harvest|install|reconcile|sync|list} …" >&2; exit 1;;
esac
