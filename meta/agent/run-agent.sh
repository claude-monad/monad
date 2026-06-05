#!/usr/bin/env bash
# run-agent.sh — launch ONE agent task on this node, with either engine, identically.
#
# This is the single front door for "run an LLM agent". It replaces hard-coded
# `claude --print ...` / `codex exec ...` call sites so the cluster brain can pick the
# engine freely and load spreads across independent rate-limit pools.
#
# Usage:
#   run-agent.sh [opts] <prompt | @file | -(stdin)>
#
# Options:
#   --engine claude|codex|auto   engine to use (default: auto → engine_pick)
#   --mode   exec|session        one-shot headless (default) or persistent remote-control
#   --name   NAME                session name (session mode)
#   --cwd    DIR                 working directory for the agent (default: $PWD)
#   --timeout SEC                hard wall-clock cap for exec mode (default 2700, 0=none)
#   --quiet                      emit only the agent's final message (normalized)
#   --print-engine               print the chosen engine to stderr before running
#
# Env: MONAD_ENGINE (=engine), MONAD_ENGINE_PREFERENCE, CLAUDE_HOME, CODEX_HOME,
#      MONAD_CODEX_EFFORT (minimal|low|medium|high — codex reasoning depth; agents
#      that need to think hard, e.g. formalization, set this to "high").
# Exit code is the agent's exit code (124 = timed out).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/engines.sh"

ENGINE="${MONAD_ENGINE:-auto}"
MODE="exec"; NAME="monad-agent"; CWD="$PWD"; TIMEOUT="2700"; QUIET=0; PRINTENG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2 ;;
    --mode)   MODE="$2"; shift 2 ;;
    --name)   NAME="$2"; shift 2 ;;
    --cwd)    CWD="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --quiet)  QUIET=1; shift ;;
    --print-engine) PRINTENG=1; shift ;;
    --) shift; break ;;
    -*) echo "run-agent: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

PROMPT_SRC="${1:-}"
[ -z "$PROMPT_SRC" ] && { echo "run-agent: prompt required (string | @file | -)" >&2; exit 2; }
if [ "$PROMPT_SRC" = "-" ]; then PROMPT="$(cat)"
elif [ "${PROMPT_SRC:0:1}" = "@" ]; then PROMPT="$(cat "${PROMPT_SRC:1}")"
else PROMPT="$PROMPT_SRC"; fi

# Resolve engine.
CHOSEN="$(engine_pick "$ENGINE")" || {
  echo "run-agent: no ready engine (need an installed + logged-in claude or codex)." >&2
  echo "           ready engines: '$(engines_ready)'  requested: '$ENGINE'" >&2
  exit 3
}
[ "$PRINTENG" = 1 ] && echo "run-agent: engine=$CHOSEN mode=$MODE cwd=$CWD" >&2

cd "$CWD" 2>/dev/null || { echo "run-agent: cannot cd to $CWD" >&2; exit 2; }

if [ "$MODE" = "session" ]; then
  ARGV=()
  while IFS= read -r arg; do ARGV+=("$arg"); done < <(engine_session_argv "$CHOSEN" "$NAME")
  exec "${ARGV[@]}"
fi

# exec mode
LAST=""; [ "$QUIET" = 1 ] && [ "$CHOSEN" = codex ] && LAST="$(mktemp)"
ARGV=()
while IFS= read -r arg; do ARGV+=("$arg"); done < <(engine_exec_argv "$CHOSEN" "$CWD" "$LAST")

run() {
  if [ "$TIMEOUT" = 0 ]; then
    "${ARGV[@]}" "$PROMPT"
  elif command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM "$TIMEOUT" "${ARGV[@]}" "$PROMPT"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout --signal=TERM "$TIMEOUT" "${ARGV[@]}" "$PROMPT"
  else
    "${ARGV[@]}" "$PROMPT"
  fi
}

if [ "$QUIET" = 1 ]; then
  if [ "$CHOSEN" = codex ]; then
    run >/dev/null 2>&1; rc=$?
    [ -n "$LAST" ] && [ -s "$LAST" ] && cat "$LAST"
    [ -n "$LAST" ] && rm -f "$LAST"
  else
    # claude --print already emits only the final message on stdout
    run; rc=$?
  fi
else
  run; rc=$?
fi
[ "${rc:-0}" = 124 ] && echo "run-agent: $CHOSEN hit the ${TIMEOUT}s timeout and was stopped." >&2
exit "${rc:-0}"
