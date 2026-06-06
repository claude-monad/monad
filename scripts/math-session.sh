#!/usr/bin/env bash
# math-session.sh — Shared launcher for all math research agent sessions
#
# Usage: math-session.sh <role> [clone-depth]
#   role: researcher | compute | reviewer
#   clone-depth: git clone depth (default: 100, use 0 for full clone)
#
# Handles: repo clone, machine ID, day-of-week focus (researcher), prompt loading, cleanup
set -euo pipefail

ROLE="${1:?Usage: math-session.sh <researcher|compute|reviewer>}"
CLONE_DEPTH="${2:-100}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="$SCRIPT_DIR/prompts"
MATH_REPO="${MATH_REPO_URL:-https://github.com/eliottcassidy2000/math.git}"

# ─── Setup working directory ──────────────────────────────────────────────────

WORK_DIR="/tmp/math-${ROLE}-$$"
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone the math repo
if [ "$CLONE_DEPTH" -gt 0 ] 2>/dev/null; then
    git clone --depth="$CLONE_DEPTH" "$MATH_REPO" math
else
    git clone "$MATH_REPO" math
fi
cd math

# ─── Register agent ──────────────────────────────────────────────────────────

MACHINE_ID="monad-${ROLE}"
echo "$MACHINE_ID" > .machine-id
if [ -f agents/processor.py ]; then
    python3 agents/processor.py --register 2>/dev/null || true
fi

# ─── Build prompt ─────────────────────────────────────────────────────────────

PROMPT_FILE="$PROMPT_DIR/${ROLE}.md"
if [ "$ROLE" = "researcher" ]; then
    # Substitute day-of-week focus
    PROMPT_FILE="$PROMPT_DIR/researcher.md"
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

PROMPT=$(cat "$PROMPT_FILE")

# For researcher: substitute {{FOCUS}} with day-of-week rotation
if [ "$ROLE" = "researcher" ]; then
    DAY=$(date +%u)
    case $DAY in
        1) FOCUS="Pick the highest-priority red open question from 00-navigation/OPEN-QUESTIONS.md and attempt a proof or significant partial result" ;;
        2) FOCUS="Run computation scripts from 04-computation/ — extend known OEIS sequences, verify conjectures with new data, save ALL outputs via ./run_and_save.sh" ;;
        3) FOCUS="Review hypotheses in 05-knowledge/hypotheses/INDEX.md — pick one and try to prove or definitively refute it with computation or proof" ;;
        4) FOCUS="Read 00-navigation/TANGENTS.md and CONCEPT-MAP.md — develop the most promising cross-domain connection into a concrete result" ;;
        5) FOCUS="Engineering: build or improve a tool — check OPEN-QUESTIONS.md for engineering tasks, improve scripts in 04-computation/, or create a new visualization" ;;
        6) FOCUS="Write-up day: take a result from 05-knowledge/results/ that lacks a clean proof and write a proper theorem file for 01-canon/theorems/" ;;
        7) FOCUS="Free exploration: read CONCEPT-MAP.md and INVESTIGATION-BACKLOG.md, investigate whatever seems most promising, follow your curiosity" ;;
    esac
    PROMPT="${PROMPT//\{\{FOCUS\}\}/$FOCUS}"
fi

# Optional dispatched SEED (e.g. recent-commit context from math-explore-watch) — appended so
# the session builds on what just landed instead of starting cold.
if [ -n "${SEED:-}" ]; then
    PROMPT="$PROMPT

## Dispatched seed — recent activity to build on (explore beyond it, don't just resolve it)
$SEED"
fi

# ─── Run Claude session ──────────────────────────────────────────────────────

PROMPT_FILE="$WORK_DIR/prompt.txt"
printf '%s' "$PROMPT" > "$PROMPT_FILE"

if [ "$(id -u)" = "0" ]; then
    # Nomad raw_exec runs as root; claude refuses --dangerously-skip-permissions as root.
    # Drop to the node's Claude-credentialed user. Check creds (portable now) + claude on PATH
    # (the provisioner symlinks it to /usr/local/bin). Includes 'claude' (claudebox) + any
    # uid>=1000 user with credentials, so this works on every node, not just the old roster.
    RUN_USER=""
    for u in claude e bigo ubuntu eliott $(getent passwd | awk -F: '$3>=1000 && $3<65000 && $6 ~ /^\/home\//{print $1}'); do
        # Guard with `id` first: on a node without this user, `getent passwd <u>` exits 2 and
        # `set -o pipefail` + `set -e` would kill the whole script (was exiting code 2 here).
        id "$u" >/dev/null 2>&1 || continue
        h="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$h" ] || continue
        if [ -f "$h/.claude/.credentials.json" ]; then RUN_USER="$u"; break; fi
    done
    if [ -z "$RUN_USER" ]; then
        echo "ERROR: no user with claude credentials found" >&2
        exit 1
    fi
    echo "[math-session] dropping privileges to $RUN_USER"
    chown -R "$RUN_USER" "$WORK_DIR"
    su - "$RUN_USER" -c "export PATH=/usr/local/bin:\$HOME/.local/bin:\$HOME/.claude/local:/snap/bin:\$PATH; cd '$PWD' && claude --print --dangerously-skip-permissions \"\$(cat '$PROMPT_FILE')\""
else
    claude --print --dangerously-skip-permissions "$PROMPT"
fi
