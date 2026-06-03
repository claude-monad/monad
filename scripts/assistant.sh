#!/usr/bin/env bash
# assistant.sh — spawn / list / remove persistent app-attachable assistant LLM sessions.
#
# The concierge (and the owner/conductor) use this to manage purpose-built assistants. Each
# assistant is a named Claude remote-control session (shows in the Claude app) with its own
# purpose (assistants/<slug>/CLAUDE.md). Assistants persist until removed. State lives in
# git (the purpose dir) + Nomad vars (assistants/<slug> = registry entry incl. its job id).
#
#   assistant.sh spawn  <slug> "<purpose>" [--model sonnet|opus|haiku] [--effort low|medium|high]
#   assistant.sh list
#   assistant.sh remove <slug>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
GIT="git -C $REPO_DIR"

die() { echo "assistant: $*" >&2; exit 1; }
slug_ok() { printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]{1,30}$'; }
# Push the repo, retrying against the fast-moving fleet (rebase onto origin, then push).
push_repo() {
  local i
  for i in 1 2 3 4 5; do
    $GIT fetch -q origin 2>/dev/null
    $GIT rebase -q origin/main 2>/dev/null || { $GIT rebase --abort 2>/dev/null; sleep 1; continue; }
    $GIT push -q origin main 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
  spawn)
    slug="${1:-}"; shift || true
    slug_ok "$slug" || die "slug must be lowercase letters/digits/-, 2-31 chars (got '$slug')"
    model="sonnet"; effort=""; purpose=""
    while [ $# -gt 0 ]; do case "$1" in
      --model) model="$2"; shift 2 ;;
      --effort) effort="$2"; shift 2 ;;
      *) purpose="${purpose:+$purpose }$1"; shift ;;
    esac; done
    [ -n "$purpose" ] || die "a purpose is required: assistant.sh spawn <slug> \"<purpose>\""
    nomad var get "assistants/$slug" >/dev/null 2>&1 && die "assistant '$slug' already exists (remove it first or pick another slug)"

    # Admission control: assistants are Claude sessions and run on the Claude node (oraclebox1,
    # the smallest box). Ask the governor before spawning — if it returns QUEUE the Claude node
    # is at capacity, and spawning anyway would overload it (the cardinal sin). Refuse instead.
    if [ "${ASSISTANT_FORCE:-}" != "1" ]; then
      place="$(python3 "$REPO_DIR/scripts/llm-scheduler.py" place --engine claude --mem 512 --quiet 2>/dev/null)"
      if [ -z "$place" ] || [ "$place" = "QUEUE" ]; then
        die "the Claude node is at capacity — refusing to spawn '$slug' (would overload it). Remove an assistant first ('assistant.sh list' / 'remove <slug>'), or set ASSISTANT_FORCE=1 to override."
      fi
    fi

    # 1) purpose dir (the assistant's personality) → commit + push so its session can clone it
    dir="$REPO_DIR/assistants/$slug"; mkdir -p "$dir"
    cat > "$dir/CLAUDE.md" <<EOF
# Assistant: $slug

$purpose

You are a persistent, purpose-built assistant in the Monad cluster, reached by the owner from
the Claude app as "$slug". Stay focused on the purpose above. You persist across the
conversation; keep useful context in this directory's files if helpful.
EOF
    $GIT add "assistants/$slug/CLAUDE.md" >/dev/null 2>&1 || true
    $GIT commit -q -m "assistant: spawn $slug" >/dev/null 2>&1 || true
        push_repo || echo "assistant: warning — push failed; session clones what is on origin" >&2

    # 2) dispatch the persistent session job
    out="$(nomad job dispatch -meta "name=$slug" -meta "model=$model" -meta "effort=$effort" assistant 2>&1)"
    jobid="$(printf '%s' "$out" | grep -oE 'Dispatched Job ID = \S+' | awk '{print $NF}')"
    [ -n "$jobid" ] || die "dispatch failed: $out"

    # 3) registry entry
    nomad var put -force "assistants/$slug" \
      slug="$slug" purpose="$purpose" model="$model" effort="$effort" \
      job="$jobid" created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
    echo "spawned assistant '$slug' (model=$model, job=$jobid)."
    echo "→ it will appear in your Claude app as '$slug' shortly. It persists until: assistant.sh remove $slug"
    ;;

  list)
    paths="$(nomad var list -out=terse assistants/ 2>/dev/null | grep '^assistants/')" || true
    [ -z "$paths" ] && { echo "(no assistants)"; exit 0; }
    printf "%-22s %-8s %s\n" "SLUG" "MODEL" "PURPOSE"
    while read -r p; do
      [ -z "$p" ] && continue
      s="$(nomad var get -item=slug "$p" 2>/dev/null)"; m="$(nomad var get -item=model "$p" 2>/dev/null)"
      pu="$(nomad var get -item=purpose "$p" 2>/dev/null)"
      printf "%-22s %-8s %s\n" "$s" "$m" "${pu:0:60}"
    done <<< "$paths"
    ;;

  remove)
    slug="${1:-}"; slug_ok "$slug" || die "usage: assistant.sh remove <slug>"
    nomad var get "assistants/$slug" >/dev/null 2>&1 || die "no such assistant '$slug'"
    job="$(nomad var get -item=job "assistants/$slug" 2>/dev/null)"
    [ -n "$job" ] && nomad job stop -purge "$job" >/dev/null 2>&1 && echo "stopped session ($job)"
    # archive the purpose dir + drop the registry entry
    if [ -d "$REPO_DIR/assistants/$slug" ]; then
      $GIT rm -r -q "assistants/$slug" >/dev/null 2>&1 || rm -rf "$REPO_DIR/assistants/$slug"
      $GIT commit -q -m "assistant: remove $slug" >/dev/null 2>&1 || true
          push_repo || true
    fi
    nomad var purge "assistants/$slug" >/dev/null 2>&1 || true
    echo "removed assistant '$slug'."
    ;;

  *) echo "usage: assistant.sh {spawn <slug> \"<purpose>\" [--model M] | list | remove <slug>}" >&2; exit 2 ;;
esac
