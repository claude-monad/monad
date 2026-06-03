---
status: done
owner: agent-builder-1-010849
updated: 2026-06-03T01:30:00Z
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

- **2026-06-03 (agent-builder-1-010849)** — DONE (no-token durable-capture path). Commit `cfb6260`.
  `scripts/monad` `cmd_gh()` now guards on `command -v gh`; when gh is absent it calls a new
  `_gh_no_cli()` that, for `issue`/`pr`, writes the would-be item to Nomad var
  **`fleet/pending-issues/<utc>-<pid>`** (kind/title/body/node/created/repo) **and** emits a
  loud `escalation`/`gh-missing`/`captured` event, then returns 0 (captured, not dropped).
  `gh issues` lists pending captures. The gh-present fast path is untouched.
  - **Verified on a gh-less node (this builder alloc on oraclebox1):**
    `monad gh issue "…" "body w/ \"quote\", backslash \\, = sign"` → captured to
    `fleet/pending-issues/20260603T012243Z-1063`, exit 0; `monad secrets get` showed the body
    preserved byte-for-byte; `monad gh issues` listed the pending capture. Test var purged +
    test event line removed afterward.
  - **Acceptance**: #1 (OR branch — durable capture, never dropped) ✅, #2 (gh present
    unchanged) ✅, #3 (`issues` degrades non-crashing) ✅, #5 (single-file, reversible) ✅.
    **#4 (GitHub-API-via-token fast-fill) deferred** — no `fleet/github-token` secret exists;
    provisioning a token is an owner credential decision. Follow-up when a token is added:
    in `_gh_no_cli` issue/pr, if `fleet/github-token` exists, POST to
    `https://api.github.com/repos/eliott-monad/monad/issues` via curl before falling back to
    capture. A dashboard/health panel surfacing `fleet/pending-issues/*` would also help.
  - **How to use**: nothing changes when gh works. Where gh is missing, escalations land in
    `fleet/pending-issues/*` — file them later from any gh-capable node with
    `monad secrets get fleet/pending-issues/<id>` then `monad gh issue "<title>" "<body>"`.
