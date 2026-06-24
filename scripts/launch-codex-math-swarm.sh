#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_AGENT="$REPO_DIR/meta/agent/run-agent.sh"
AGENT_MSG="$REPO_DIR/meta/agent/mesh/agent-msg.sh"

USER_NAME="$(id -un)"
USER_HOME="${USER_HOME:-$(getent passwd "$USER_NAME" | cut -d: -f6)}"
[ -n "$USER_HOME" ] || USER_HOME="$HOME"

NODE_NAME="${NODE_NAME:-$(hostname 2>/dev/null || echo unknown)}"
ROLE_NAME="${ROLE_NAME:-bigo-codex-creative}"
AGENT_NAME="${AGENT_NAME:-agent-$ROLE_NAME}"
BASE_DIR="${SWARM_BASE_DIR:-$USER_HOME/.cache/monad-swarm/$ROLE_NAME}"
WORKSPACE="$BASE_DIR/math"
LOG_DIR="$BASE_DIR/logs"
NOTES_DIR="$BASE_DIR/notes"
STATE_DIR="$BASE_DIR/state"
TOOLS_DIR="$BASE_DIR/bin"
PIDFILE="$STATE_DIR/agent.pid"

MATH_REPO_SOURCE="${MATH_REPO_SOURCE:-}"
[ -n "$MATH_REPO_SOURCE" ] || {
  for candidate in "$USER_HOME/math" "$USER_HOME/Documents/math"; do
    [ -d "$candidate/.git" ] && { MATH_REPO_SOURCE="$candidate"; break; }
  done
}
[ -n "$MATH_REPO_SOURCE" ] || MATH_REPO_SOURCE="https://github.com/eliottcassidy2000/math.git"
CLONE_DEPTH="${SWARM_CLONE_DEPTH:-50}"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-2400}"
SLEEP_SECONDS="${SWARM_SLEEP_SECONDS:-1200}"
NICE_LEVEL="${SWARM_NICE_LEVEL:-10}"
CYCLE_LIMIT="${SWARM_CYCLES:-0}"

export PATH="/snap/bin:/snap/codex/current/bin:$USER_HOME/claude-monad-runtime/bin:$USER_HOME/.local/bin:$USER_HOME/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export MONAD_ENGINE=codex
export MONAD_CODEX_EFFORT="${MONAD_CODEX_EFFORT:-high}"
export AGENT_NAME

mkdir -p "$LOG_DIR" "$NOTES_DIR" "$STATE_DIR" "$TOOLS_DIR"

cat > "$TOOLS_DIR/agent-msg" <<EOF
#!/usr/bin/env bash
exec "$AGENT_MSG" "\$@"
EOF
chmod +x "$TOOLS_DIR/agent-msg"
export PATH="$TOOLS_DIR:$PATH"

log() {
  printf '[codex-swarm] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

ensure_single_instance() {
  if [ -f "$PIDFILE" ]; then
    local old_pid
    old_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      log "already running as pid=$old_pid"
      exit 0
    fi
  fi
  printf '%s\n' "$$" > "$PIDFILE"
}

cleanup() {
  if [ -f "$PIDFILE" ] && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$PIDFILE"
  fi
}
trap cleanup EXIT INT TERM

ensure_workspace() {
  if [ ! -d "$WORKSPACE/.git" ]; then
    rm -rf "$WORKSPACE"
    log "cloning math workspace from $MATH_REPO_SOURCE"
    git clone --depth="$CLONE_DEPTH" "$MATH_REPO_SOURCE" "$WORKSPACE" >/dev/null 2>&1
    return
  fi
  log "updating math workspace"
  git -C "$WORKSPACE" pull --ff-only >/dev/null 2>&1 || true
}

mesh_register() {
  bash "$AGENT_MSG" register >/dev/null 2>&1 || true
}

mesh_send() {
  local msg="$1"
  bash "$AGENT_MSG" send all "$msg" >/dev/null 2>&1 || true
}

write_prompt() {
  local prompt_file="$1" note_file="$2" peers inbox msg_bin
  msg_bin="$TOOLS_DIR/agent-msg"
  peers="$(bash "$AGENT_MSG" peers 2>/dev/null || echo '[]')"
  inbox="$(bash "$AGENT_MSG" recv --wait 1 2>/dev/null || echo '[]')"
  cat > "$prompt_file" <<EOF
You are $AGENT_NAME, a Codex-based autonomous math swarm agent running on node $NODE_NAME.

Mission:
- Prioritize creativity, meta abstraction, and generating new leads for peers.
- Work broadly across tournament analysis, Triune values, number theory, representation
  theory, invariants, conjectures, obstructions, examples, formalization leads, and synthesis.
- Leave behind crisp fragments that other agents can pick up quickly.

Hard operating rules:
- Work in this isolated clone only. Do not push or commit.
- Keep computations lightweight and reversible on this 4-core node.
- Use shell/Python freely for short checks, examples, and falsification attempts.
- Write a compact markdown note to $note_file with sections:
  # Thread
  # Evidence
  # Messages Sent
  # Next Leads

IPC is mandatory. Use agent-msg repeatedly:
1. Immediately run:
   $msg_bin register
   $msg_bin peers
   $msg_bin recv --wait 1
2. Send one compact opening fragment to all peers with your initial lead.
3. Midway through the session, run agent-msg recv --wait 5 and either reply to a peer or
   send a fresh conjecture/example/obstruction/question.
4. Before ending, run agent-msg recv --wait 1 and send one compact wrap-up to all peers.
5. Keep each mesh message under 450 characters. Use $msg_bin explicitly if plain agent-msg is
   not on PATH. If $msg_bin send all fails, enumerate peers from $msg_bin peers and
   direct-message them instead.

Current peer snapshot:
$peers

Current inbox snapshot:
$inbox

Suggested session shape:
1. Skim a small amount of repo context to choose a fertile thread.
2. Pick one thread that looks likely to produce a concrete claim, obstruction, or example.
3. Do one or two short computations or derivations to sharpen it.
4. Share compact idea-dense updates with peers as required above.
5. End with a short stdout summary and the note at $note_file.

Favor outputs like:
- a sharpened conjecture
- a clean obstruction or counterexample pattern
- a reusable invariant
- a formalization lead
- a question that cleanly splits into subproblems
EOF
}

run_cycle() {
  local ts prompt_file note_file log_file rc summary
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  prompt_file="$STATE_DIR/prompt-$ts.txt"
  note_file="$NOTES_DIR/$ts.md"
  log_file="$LOG_DIR/$ts.log"

  ensure_workspace
  mesh_register
  mesh_send "startup $NODE_NAME $ts: creative codex cycle starting. Focus: compact leads, obstructions, examples, or n=14 hard-set fragments. Reply with any near-critical speed-set notes."
  write_prompt "$prompt_file" "$note_file"

  log "starting cycle ts=$ts log=$log_file"
  if nice -n "$NICE_LEVEL" bash "$RUN_AGENT" --engine codex --cwd "$WORKSPACE" --timeout "$AGENT_TIMEOUT" "@$prompt_file" >"$log_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  summary="$(tail -n 20 "$log_file" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | cut -c1-700)"
  printf 'ts=%s\nrc=%s\nlog=%s\nnote=%s\nsummary=%s\n' \
    "$ts" "$rc" "$log_file" "$note_file" "${summary:-"(no summary)"}" > "$STATE_DIR/last-run.txt"
  printf '%s\n' "${summary:-"(no summary)"}" > "$STATE_DIR/last-summary.txt"
  mesh_send "summary $NODE_NAME $ts rc=$rc: ${summary:-"(no summary)"}"
  log "finished cycle ts=$ts rc=$rc"
  rm -f "$prompt_file"
}

main() {
  local cycle=0
  ensure_single_instance
  log "launching $AGENT_NAME on $NODE_NAME"
  while :; do
    cycle=$((cycle + 1))
    run_cycle
    if [ "$CYCLE_LIMIT" -gt 0 ] && [ "$cycle" -ge "$CYCLE_LIMIT" ]; then
      log "cycle limit reached ($CYCLE_LIMIT)"
      break
    fi
    sleep "$SLEEP_SECONDS"
  done
}

main "$@"
