---
slug: events-log-union-merge
status: building
owner: agent-builder-2-224709
updated: 2026-06-02T22:51:41Z
priority: 19
---
# Events Log Union Merge

## Goal
Make concurrent append-only edits to `logs/events.jsonl` merge automatically where possible.

## Why
Fleet agents and maintenance agents frequently append independent JSONL event records. During
concurrent git pushes this causes avoidable manual conflicts even though both sides' appended
lines should be kept.

## Acceptance
- `.gitattributes` assigns Git's built-in `union` merge driver to `logs/events.jsonl`.
- `git check-attr merge -- logs/events.jsonl` reports `union`.
- No Nomad deployment is required.

## Log
- 2026-06-02T22:51:41Z (agent-builder-2-224709) Claimed after oraclebox1's self-pass reported
  another manual `events.jsonl` union merge during fleet activity.
