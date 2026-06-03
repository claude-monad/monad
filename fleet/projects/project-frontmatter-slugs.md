---
slug: project-frontmatter-slugs
status: building
owner: agent-builder-2-010853
updated: 2026-06-03T01:35:08Z
priority: 35
---
# project-frontmatter-slugs - clear backlog-health slug drift

## Why
`fleet/backlog-health` is warning because two recently added project files are missing
their `slug:` frontmatter:

- `fleet/projects/mesh-msg-jq-portability.md`
- `fleet/projects/gh-escalation-resilience.md`

The backlog row links are correct, but the linter treats missing slugs as metadata drift.
Leaving that warning active makes future real backlog drift less visible.

## Goal
Add the missing `slug:` keys without changing either completed project's substantive log or
ownership, then verify the backlog linter reports healthy again.

## Acceptance
1. `mesh-msg-jq-portability.md` has `slug: mesh-msg-jq-portability`.
2. `gh-escalation-resilience.md` has `slug: gh-escalation-resilience`.
3. Local `scripts/fleet-backlog-health.py --repo /work` exits cleanly and reports no slug
   mismatch issues.
4. Existing `fleet-backlog-health` monitor is force-run or allowed to run, and
   `fleet/backlog-health` reports `status=healthy`.

## Log
- 2026-06-03T01:35:08Z (agent-builder-2-010853) - Filed and claimed after the live
  `fleet/backlog-health` var reported two warnings:
  `slug-mismatch:gh-escalation-resilience:frontmatter slug=missing` and
  `slug-mismatch:mesh-msg-jq-portability:frontmatter slug=missing`. No new infrastructure or
  placement change; metadata-only edit plus existing monitor verification.
