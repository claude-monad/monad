#!/usr/bin/env bash
# formalizer-session.sh — launcher for the Lean formalizer agent.
#
# Mirrors math-session.sh, but clones the Lean formalization repo (eliott-monad/math-lean)
# instead of the informal math repo, and runs the formalizer prompt. The agent pulls its own
# candidates from the informal repo via the repo's sync-candidates.sh.
#
# Policy (meta/FORMALIZATION-POLICY.md): formalization is delegated to automated *codex*
# work at MAX reasoning effort. The agent's mandate is dual — keep math-lean converging on
# the latest informal results AND think as a mathematician about the implications,
# extensions, and connections of what it formalizes, recording that exploration back in the
# informal math repo (where it becomes new formalization candidates, closing the loop).
#
# Usage: formalizer-session.sh [clone-depth]   (default depth: full, Lean repo is small)
set -uo pipefail

CLONE_DEPTH="${1:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_FILE="$SCRIPT_DIR/prompts/formalizer.md"
RUN_AGENT="$REPO_DIR/meta/agent/run-agent.sh"
LEAN_REPO="${LEAN_REPO_URL:-https://github.com/eliott-monad/math-lean.git}"

# Engine + effort: codex, thinking as hard as it can. Override via env if ever needed.
ENGINE="${MONAD_ENGINE:-codex}"
export MONAD_CODEX_EFFORT="${MONAD_CODEX_EFFORT:-high}"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR

WORK_DIR="/tmp/math-lean-formalizer-$$"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone the Lean repo (small; full clone by default)
if [ "$CLONE_DEPTH" -gt 0 ] 2>/dev/null; then
    git clone --depth="$CLONE_DEPTH" "$LEAN_REPO" math-lean
else
    git clone "$LEAN_REPO" math-lean
fi
cd math-lean

echo "monad-formalizer" > .machine-id

[ -f "$PROMPT_FILE" ] || { echo "ERROR: prompt not found: $PROMPT_FILE" >&2; exit 1; }
PROMPT="$(cat "$PROMPT_FILE")"

# Inbox: what just arrived in the informal math repo (written by formalize-watch.sh).
# This is how a commit "communicates to the active job what has arrived" — prioritize it.
INBOX="$(nomad var get -item=commits monad/formalize/inbox 2>/dev/null || true)"
if [ -n "$INBOX" ]; then
    PROMPT="$PROMPT

── JUST ARRIVED in the informal math repo (prioritize formalizing these) ──
$INBOX
──────────────────────────────────────────────────────────────────────────"
fi

if [ -x "$RUN_AGENT" ]; then
    exec "$RUN_AGENT" --engine "$ENGINE" --cwd "$WORK_DIR/math-lean" --timeout "${MONAD_TIMEOUT:-7200}" "$PROMPT"
else
    # Fallback if the engine abstraction is unavailable on this node.
    echo "WARN: $RUN_AGENT not found; falling back to claude --print" >&2
    exec claude --print --dangerously-skip-permissions "$PROMPT"
fi
