---
status: todo
owner:
updated: 2026-06-03T01:25:00Z
---

# gh-escalation-resilience

**Make `monad gh issue` degrade gracefully when the `gh` CLI is absent, so node-doctor's
"auto-file a GitHub issue on failed repair" escalation is never silently lost.**

## Problem (code-level, confirmed)

`scripts/monad` `cmd_gh()` calls `gh issue create …` / `gh issue list …` directly with
**no presence check and no fallback**. On any node where `gh` isn't installed, the command
dies with `gh: command not found` and returns non-zero. This is the same class of hidden
hard-dependency that [[mesh-msg-jq-portability]] (#32) just fixed for `jq` in `agent-msg`.

Why it matters: self-healing depends on it. CLAUDE.md's Node Doctor section says "If repair
fails, creates a GitHub issue automatically." That escalation runs `monad gh issue`. On a
gh-less node-doctor host the issue is **never created** and the failure is invisible —
exactly when visibility matters most. (Observed: `monad gh issues` returns
`gh: command not found` on at least one fleet node — the agent-builder host.)

## Acceptance criteria

1. `monad gh issue "<title>" "<body>"` on a node **without `gh`** does NOT silently fail:
   it falls back to the GitHub REST API via `curl` using a token from
   `monad secrets` (e.g. `fleet/github-token`), OR — if no token is available — emits a
   loud `logs/events.jsonl` event (source `fleet`, type `escalation`, action `gh-missing`)
   AND writes the would-be issue to a Nomad var (e.g. `fleet/pending-issues/<ts>`) so the
   escalation is durably captured, never dropped.
2. When `gh` IS present, behaviour is unchanged (fast path preserved).
3. `monad gh issues` (list) degrades the same way (API or a clear, non-crashing message).
4. Token stored via `monad secrets set fleet/github-token token=…` — **never committed**.
   The fallback must work read-only-safely (no token → capture-not-crash, per #1).
5. Single-file change to `scripts/monad` (plus the secret); reversible.

## Notes / placement

No Nomad job — a fix to the shared `monad` CLI. Verify first which roster node-doctor hosts
actually lack `gh` (cheap: check each canonical node) to size impact, but the graceful
fallback is worth shipping regardless since the current code has zero degradation path.
Mirror the approach of #32: detect-the-missing-dep, preserve the fast path, never lose the
signal.

## Log
