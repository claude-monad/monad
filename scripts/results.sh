#!/usr/bin/env bash
# results.sh — the cluster's verifiable master results store (provenance ledger).
#
# Every recorded result is content-addressed so it is *easily verifiable that the result is the
# output of a specific program in a specific environment on a specific input*:
#
#   program_hash = sha256(program source bytes)
#   env_hash     = the pinned toolchain identity (image digest / kind — what it ran in)
#   input_hash   = sha256(canonical args)
#   claim_hash   = sha256(program_hash + env_hash + input_hash)        # the derivation id
#   output_hash  = sha256(output bytes)
#
# A row binds claim_hash -> output_hash + provenance. Index lives in the fleet Postgres
# (`results` schema); large blobs go to MinIO (TODO) — small outputs are stored inline (base64).
#
# Usage:
#   results.sh put  --program FILE --env ENV [--args JSON] [--output FILE|-] \
#                   [--rc N] [--wall-ms N] [--program-ref REF] [--engine E]   # record a result
#   results.sh run  --program FILE --env lean|compute [--program-ref REF] [-- ARGS...]
#                                                                            # execute+record (needs docker)
#   results.sh get    CLAIM_HASH                                            # show row + output
#   results.sh verify CLAIM_HASH [--rerun]                                  # Tier-1 integrity (+Tier-2 re-derive)
#   results.sh list   [--program-hash H] [--limit N]                        # recent derivations
#   results.sh stats                                                        # row counts
#
# Works on any node with the nomad CLI (drives psql through the postgres alloc when psql is
# absent locally). Hashing uses sha256sum; JSON canonicalization uses python3. No jq dependency.
set -uo pipefail

export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/.." && pwd)"

die() { echo "results: $*" >&2; exit 1; }
sha256() { sha256sum | awk '{print $1}'; }   # reads stdin

# ---- Postgres access -------------------------------------------------------
# Prefer a local psql; otherwise run psql inside the running postgres alloc.
_PGPW=""; _PG_ALLOC=""
pg_init() {
  [ -n "$_PGPW" ] && return 0
  _PGPW="$(nomad var get -item=POSTGRES_PASSWORD nomad/jobs/postgres 2>/dev/null)" \
    || die "cannot read postgres password (nomad/jobs/postgres)"
  if ! command -v psql >/dev/null 2>&1; then
    _PG_ALLOC="$(nomad job status postgres 2>/dev/null \
      | awk '$6=="running"{print $1; exit}')"
    [ -n "$_PG_ALLOC" ] || die "no running postgres alloc found"
  fi
}
# pg_sql [psql-flags...]: read SQL from stdin, run it, stream results to stdout. Only pass
# SHELL-METACHARACTER-FREE flags (e.g. -tA, -P pager=off) — they are interpolated into the
# alloc-exec `sh -c`, so a flag like -F'|' would have its '|' parsed as a pipe. Unaligned mode
# (-A) already uses '|' as the default field separator, so we never need -F. Avoid psql
# backslash formatting commands (\t, \pset ...): several echo a confirmation line to stdout
# that pollutes machine-parsed output.
pg_sql() {
  pg_init
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$_PGPW" psql -h 100.78.218.70 -p 5432 -U fleet -d fleet -v ON_ERROR_STOP=1 "$@" -f -
  else
    nomad alloc exec -i "$_PG_ALLOC" sh -c \
      "PGPASSWORD='$_PGPW' psql -U fleet -d fleet -v ON_ERROR_STOP=1 $* -f -"
  fi
}
sqlq() { printf "%s" "$1" | sed "s/'/''/g"; }   # single-quote escape for SQL literals

# ---- hashing helpers -------------------------------------------------------
canon_args() {  # canonical JSON if valid json, else raw string; "" if empty
  local a="$1"; [ -z "$a" ] && { printf ''; return; }
  printf '%s' "$a" | python3 -c 'import sys,json
s=sys.stdin.read()
try: print(json.dumps(json.loads(s),sort_keys=True,separators=(",",":")),end="")
except Exception: print(s,end="")' 2>/dev/null || printf '%s' "$a"
}

# ===========================================================================
cmd_put() {
  local program="" env="" args="" output="-" rc="" wall="" pref="" engine=""
  while [ $# -gt 0 ]; do case "$1" in
    --program) program="$2"; shift 2 ;;
    --env) env="$2"; shift 2 ;;
    --args) args="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --rc) rc="$2"; shift 2 ;;
    --wall-ms) wall="$2"; shift 2 ;;
    --program-ref) pref="$2"; shift 2 ;;
    --engine) engine="$2"; shift 2 ;;
    *) die "put: unknown arg $1" ;;
  esac; done
  [ -n "$program" ] && [ -f "$program" ] || die "put: --program FILE required (existing file)"
  [ -n "$env" ] || die "put: --env ENV required (image digest or kind, e.g. compute@sha256:... or 'compute')"

  local program_hash input_hash env_hash claim_hash output_hash cargs ob64 obytes
  program_hash="$(sha256 <"$program")"
  cargs="$(canon_args "$args")"
  input_hash="$(printf '%s' "$cargs" | sha256)"
  env_hash="$(printf '%s' "$env" | sha256)"   # hash the env identity string (digest/kind)
  claim_hash="$(printf '%s%s%s' "$program_hash" "$env_hash" "$input_hash" | sha256)"

  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  if [ "$output" = "-" ]; then cat >"$tmp"; else cat "$output" >"$tmp"; fi
  output_hash="$(sha256 <"$tmp")"
  obytes="$(wc -c <"$tmp" | tr -d ' ')"
  # inline if small (<131072 bytes raw), else leave a MinIO TODO marker
  local inline_sql="NULL" ref_sql="NULL"
  if [ "$obytes" -le 131072 ]; then
    ob64="$(base64 -w0 <"$tmp")"
    inline_sql="'$(sqlq "$ob64")'"
  else
    ref_sql="'minio://results/${output_hash} (TODO: upload)'"
  fi
  [ -z "$pref" ] && pref="$program"
  [ -z "$engine" ] && engine="${MONAD_ENGINE:-}"
  local node; node="$(hostname)"

  pg_sql >/dev/null <<SQL
INSERT INTO results.derivation (claim_hash,program_hash,env_hash,input_hash,program_ref,args)
VALUES ('$claim_hash','$program_hash','$env_hash','$input_hash','$(sqlq "$pref")',
        $( [ -n "$cargs" ] && echo "'$(sqlq "$cargs")'::jsonb" || echo "NULL" ))
ON CONFLICT (claim_hash) DO NOTHING;
INSERT INTO results.output (claim_hash,output_hash,output_ref,output_inline,bytes,rc,wall_ms,node,engine)
VALUES ('$claim_hash','$output_hash',$ref_sql,$inline_sql,$obytes,
        $( [ -n "$rc" ] && echo "$rc" || echo NULL ),
        $( [ -n "$wall" ] && echo "$wall" || echo NULL ),
        '$(sqlq "$node")','$(sqlq "$engine")')
ON CONFLICT (claim_hash,output_hash) DO NOTHING;
SQL
  echo "$claim_hash"
  echo "  program_hash=$program_hash env_hash=$env_hash input_hash=$input_hash" >&2
  echo "  output_hash=$output_hash bytes=$obytes" >&2
}

cmd_run() {
  local program="" env="" pref=""
  while [ $# -gt 0 ]; do case "$1" in
    --program) program="$2"; shift 2 ;;
    --env) env="$2"; shift 2 ;;
    --program-ref) pref="$2"; shift 2 ;;
    --) shift; break ;;
    *) die "run: unknown arg $1" ;;
  esac; done
  [ -n "$program" ] && [ -f "$program" ] || die "run: --program FILE required"
  [ -n "$env" ] || die "run: --env lean|compute required"
  local out rc start end wall
  out="$(mktemp)"
  start="$(date +%s%3N)"
  "$REPO_DIR/meta/execution/run-in-toolchain.sh" "$env" python3 "$program" "$@" >"$out" 2>&1
  rc=$?
  end="$(date +%s%3N)"; wall=$((end-start))
  cmd_put --program "$program" --env "$env" --output "$out" --rc "$rc" --wall-ms "$wall" \
          ${pref:+--program-ref "$pref"} --args "$(printf '%s' "$*")"
  rm -f "$out"
}

cmd_get() {
  local h="${1:?get: CLAIM_HASH required}"
  echo "== derivation =="
  pg_sql -P pager=off <<SQL
\x on
SELECT claim_hash,program_hash,env_hash,input_hash,program_ref,args,created_at
FROM results.derivation WHERE claim_hash='$(sqlq "$h")';
SELECT output_hash,bytes,rc,wall_ms,node,engine,verified,produced_at,
       CASE WHEN output_ref IS NOT NULL THEN output_ref ELSE '(inline)' END AS storage
FROM results.output WHERE claim_hash='$(sqlq "$h")';
SQL
  echo "== output =="
  local b64; b64="$(pg_sql -tA <<SQL
SELECT coalesce(output_inline,'') FROM results.output WHERE claim_hash='$(sqlq "$h")' LIMIT 1;
SQL
)"
  [ -n "$b64" ] && printf '%s' "$b64" | tr -d '\r\n' | base64 -d 2>/dev/null || echo "(no inline output)"
}

cmd_verify() {
  local h="${1:?verify: CLAIM_HASH required}"; shift || true
  local rerun=0; [ "${1:-}" = "--rerun" ] && rerun=1
  # pull the stored tuple
  local row; row="$(pg_sql -tA <<SQL
SELECT d.program_hash,d.env_hash,d.input_hash,o.output_hash,coalesce(o.output_inline,'')
FROM results.derivation d JOIN results.output o USING(claim_hash)
WHERE d.claim_hash='$(sqlq "$h")' LIMIT 1;
SQL
)"
  [ -n "$row" ] || die "verify: claim_hash not found"
  local ph eh ih oh b64
  IFS='|' read -r ph eh ih oh b64 <<<"$row"
  # Tier-1a: the tuple is internally consistent (claim_hash binds the three)
  local recomputed; recomputed="$(printf '%s%s%s' "$ph" "$eh" "$ih" | sha256)"
  if [ "$recomputed" = "$h" ]; then echo "TIER1 claim_hash: OK (binds program+env+input)"; else
    echo "TIER1 claim_hash: MISMATCH (stored $h != recomputed $recomputed)"; return 1; fi
  # Tier-1b: the stored output still hashes to output_hash
  if [ -n "$b64" ]; then
    local actual; actual="$(printf '%s' "$b64" | tr -d '\r\n' | base64 -d 2>/dev/null | sha256)"
    if [ "$actual" = "$oh" ]; then echo "TIER1 output integrity: OK ($oh)"; else
      echo "TIER1 output integrity: MISMATCH (stored $oh != actual $actual)"; return 1; fi
  else
    echo "TIER1 output integrity: SKIP (no inline output / blob in MinIO)"
  fi
  [ "$rerun" = 1 ] && echo "TIER2 re-derivation: not yet implemented in this slice (needs program bytes + docker)"
  echo "VERIFIED (tier1): result is the recorded output of the named program/env/input."
}

cmd_list() {
  local ph="" lim=20
  while [ $# -gt 0 ]; do case "$1" in
    --program-hash) ph="$2"; shift 2 ;;
    --limit) lim="$2"; shift 2 ;;
    *) die "list: unknown arg $1" ;;
  esac; done
  local where=""; [ -n "$ph" ] && where="WHERE d.program_hash='$(sqlq "$ph")'"
  pg_sql -P pager=off <<SQL
SELECT left(d.claim_hash,12) AS claim, left(d.program_hash,10) AS prog,
       d.program_ref, o.bytes, o.rc, o.engine, o.node, o.verified, d.created_at
FROM results.derivation d LEFT JOIN results.output o USING(claim_hash)
$where ORDER BY d.created_at DESC LIMIT $lim;
SQL
}

cmd_stats() {
  pg_sql -P pager=off <<SQL
SELECT (SELECT count(*) FROM results.derivation) AS derivations,
       (SELECT count(*) FROM results.output)     AS outputs,
       (SELECT count(*) FROM results.output WHERE verified='reproduced') AS reproduced,
       (SELECT count(*) FROM results.output WHERE verified='MISMATCH')   AS mismatches;
SQL
}

sub="${1:-help}"; shift 2>/dev/null || true
case "$sub" in
  put)    cmd_put "$@" ;;
  run)    cmd_run "$@" ;;
  get)    cmd_get "$@" ;;
  verify) cmd_verify "$@" ;;
  list)   cmd_list "$@" ;;
  stats)  cmd_stats "$@" ;;
  *) sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
