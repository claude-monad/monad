#!/usr/bin/env bash
# math-engine-test.sh — autonomous capability test (scheduled cluster task).
#
# Runs ONE small autonomous math session with each engine — claude AND codex — via the
# engine abstraction (meta/agent/run-agent.sh), then reports how both went BACK TO THE
# CLUSTER: Nomad vars `math-engine-test/{claude,codex,last}` (readable fleet-wide) plus a
# clear report block on stdout (alloc logs). Invoked by jobs/math-engine-test.hcl
# (Nomad periodic), run as the engine-credentialed user so claude/codex auth is in place.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
RA="$REPO/meta/agent/run-agent.sh"
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"

PROMPT='You are an autonomous math research agent in the monad cluster (subjects: tournaments / the Lonely Runner Conjecture / OEIS sequences). Do ONE small, self-contained piece of original mathematics: form a concrete question, optionally run a quick Python check to test it, and state a specific finding. Keep the whole reply under 8 lines. End with exactly two lines: a line "RESULT: <one-sentence finding>" then a line "SESSION-OK".'

US=$'\037'   # unit separator for safe rc/summary split

run_one() {
  local eng="$1" out rc sum
  echo "[math-engine-test] running $eng session (as $(whoami))…" >&2
  out="$(timeout 540 bash "$RA" --engine "$eng" --quiet --timeout 480 "$PROMPT" 2>&1)"; rc=$?
  # one-line, trimmed summary (last ~500 chars of the final message)
  sum="$(printf '%s' "$out" | tr '\n\t' '  ' | tr -s ' ')"
  sum="${sum: -500}"
  [ -n "$sum" ] || sum="(no output)"
  nomad var put -force "math-engine-test/$eng" \
    engine="$eng" rc="$rc" finished="$(date -u +%FT%TZ)" summary="$sum" >/dev/null 2>&1 || true
  printf '%s%s%s' "$rc" "$US" "$sum"
}

C="$(run_one claude)"; CRC="${C%%${US}*}"; CSUM="${C#*${US}}"
X="$(run_one codex)";  XRC="${X%%${US}*}"; XSUM="${X#*${US}}"
TS="$(date -u +%FT%TZ)"

nomad var put -force "math-engine-test/last" \
  ts="$TS" node="$(hostname)" \
  claude_rc="$CRC" claude_summary="$CSUM" \
  codex_rc="$XRC" codex_summary="$XSUM" >/dev/null 2>&1 || true

echo "===MATH-ENGINE-TEST-REPORT ${TS} on $(hostname)==="
echo "CLAUDE  rc=${CRC} :: ${CSUM}"
echo "CODEX   rc=${XRC} :: ${XSUM}"
echo "===END-REPORT==="

# Succeed only if BOTH engines completed cleanly (rc 0 and no timeout=124).
{ [ "$CRC" = 0 ] && [ "$XRC" = 0 ]; } && exit 0 || exit 1
