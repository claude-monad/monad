#!/usr/bin/env bash
# engines.sh — the cluster's agent-engine abstraction (sourceable library).
#
# Monad runs LLM agents to do work. There are two interchangeable engines:
#   * claude  — Anthropic Claude Code CLI (`claude`)
#   * codex   — OpenAI Codex CLI (`codex`)
#
# Everything that launches an agent (dispatch, node-doctor, the conductor, research
# jobs) should go through here instead of hard-coding one CLI, so the cluster brain is
# free to launch either type and load can spread across independent rate-limit pools.
#
# Source this file, then use:
#   engine_available <engine>          -> 0 if installed, else 1
#   engine_authed    <engine>          -> 0 if logged in, else 1
#   engine_ready     <engine>          -> available AND authed
#   engines_ready                      -> echoes the list of ready engines
#   engine_pick      [preferred]       -> echoes one ready engine (policy below)
#   engine_exec_argv <engine> <cwd> <lastmsg_file?>  -> prints the argv for a headless
#                                                        one-shot run (prompt is fed via
#                                                        the caller as the final arg)
# The actual run wrapper lives in run-agent.sh.

# ── selection policy ──────────────────────────────────────────────────────────
# Order of preference when "auto" is requested and no explicit engine is pinned.
# Override per-call with MONAD_ENGINE=claude|codex, or globally via the env.
: "${MONAD_ENGINE_PREFERENCE:=claude codex}"

engine_bin() { case "$1" in claude) echo claude ;; codex) echo codex ;; *) return 1 ;; esac; }

engine_available() {
  local b; b="$(engine_bin "$1")" || return 1
  command -v "$b" >/dev/null 2>&1
}

# Authed = credentials present. We do NOT spend a token probing on every call.
engine_authed() {
  case "$1" in
    claude) [ -f "${CLAUDE_HOME:-$HOME/.claude}/.credentials.json" ] ;;
    codex)  [ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ] ;;
    *) return 1 ;;
  esac
}

engine_ready() { engine_available "$1" && engine_authed "$1"; }

engines_ready() {
  local e out=""
  for e in claude codex; do engine_ready "$e" && out="$out $e"; done
  echo "${out# }"
}

# engine_pick [preferred]: pick a ready engine. If 'preferred' is given and ready, use
# it; else fall back through MONAD_ENGINE_PREFERENCE; else first ready engine.
engine_pick() {
  local pref="${1:-}"
  [ -n "$pref" ] && [ "$pref" != auto ] && { engine_ready "$pref" && { echo "$pref"; return 0; }; }
  local e
  for e in $MONAD_ENGINE_PREFERENCE; do engine_ready "$e" && { echo "$e"; return 0; }; done
  for e in $(engines_ready); do echo "$e"; return 0; done
  return 1
}

# engine_exec_argv <engine> <cwd> [lastmsg_file]
# Prints the command + flags (one token per line) for a headless one-shot run that
# auto-approves and has full access (these nodes/containers are the sandbox boundary).
# The caller appends the prompt as the final argument and handles cwd/timeout.
engine_exec_argv() {
  local eng="$1" cwd="${2:-$PWD}" last="${3:-}"
  case "$eng" in
    claude)
      # claude takes its working dir from the process cwd; no per-call dir flag.
      printf '%s\n' claude --print --dangerously-skip-permissions
      ;;
    codex)
      printf '%s\n' codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -C "$cwd"
      [ -n "$last" ] && printf '%s\n' -o "$last"
      ;;
    *) return 1 ;;
  esac
}

# engine_session_argv <engine> <name>
# Persistent / remote-control "brain" session (attach from the vendor's app).
engine_session_argv() {
  local eng="$1" name="${2:-monad-agent}"
  case "$eng" in
    claude) printf '%s\n' claude remote-control --name "$name" --spawn same-dir ;;
    codex)  printf '%s\n' codex remote-control start ;;  # daemon; attach from Codex app
    *) return 1 ;;
  esac
}
