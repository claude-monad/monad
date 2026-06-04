---
slug: dashboard-research-frontier-status
status: todo
owner: ""
updated: 2026-06-04
priority: 1
---
# Research frontier status dashboard

## Goal
Add a dashboard section that tracks the cluster's most important mathematical progress
markers: key theorems, lemmas, conjectures, ideas, and research directions. The panel should
make the research frontier legible at a glance for the owner and for working agents.

This is not just a static list. Agents managing the cluster should be creative about keeping
the frontier current, comparable, and useful: summarize the live state, link to evidence, and
separate proven facts from conjectural or computational evidence.

## Required content
- Each item records its kind: theorem, lemma, conjecture, idea, direction, computation,
  proof candidate, or obstruction.
- Each item records its status: proven, formally verified, proof candidate, partial,
  computationally supported, disproven, blocked, speculative, or unknown.
- Each item records the furthest computation reached, with exact parameters and where the
  artifact lives.
- For each current best proof candidate, show the status of its pieces: dependencies, known
  lemmas, missing lemmas, fragile steps, computations required, formalization status, and
  reviewer/court status where applicable.
- Each item includes a brief "bleeding edge" note: what angles are actively being tried now,
  which agents are working them, and what would count as the next meaningful advance.
- Every claim links to a source when possible: math repo paths, session-log entries,
  theorem IDs, court cases, Nomad vars, compute outputs, Lean files, or assistant notes.

## Seed frontier examples
The initial tracked set should include, at minimum:
- `H=21` impossibility / tournament Hamiltonian-path-count frontier.
- `LRC n=14`, including current endpoint-blocker, quotient/tiling, and computation state.
- Unit distance problem `n=21`.
- `A000568` and related OEIS/computation frontier items.
- Schanuel's conjecture connections.
- Twin primes and Goldbach directions, when the cluster has actionable angles or useful
  cross-links rather than generic encyclopedia summaries.

Agents should add and retire entries as the frontier changes. The dashboard should prefer
honest, high-signal uncertainty over optimistic prose.

## Implementation guidance
- Prefer a structured backing source that agents can update safely, such as a JSON/YAML file
  in this repo, a Nomad var namespace, or a small Postgres table. The dashboard can then render
  the latest version without hardcoding research status in `server.py`.
- Include timestamps, last-updated-by, confidence/evidence level, and stale-data warnings.
- Make entries compact in the main dashboard, with expandable detail for proof-candidate
  piece status and bleeding-edge notes.
- Consider auto-harvesting from the math repo's session log, theorem/court indexes, and
  formalization candidates, but allow human/agent curation so the important markers remain
  visible even when their source artifacts are scattered.

## Acceptance
- The live dashboard shows a "Research frontier" or equivalent section with the fields above.
- Initial seed entries exist for the examples listed here, even if some are marked unknown or
  speculative pending source review.
- Agents have a documented update path and can refresh entries without editing dashboard code.
- Stale entries are visibly marked so the owner can tell what has and has not been updated.

## Log
**2026-06-04 - Codex - TODO created from owner request.** The owner wants the dashboard to
track statuses of key theorems, lemmas, conjectures, ideas, and directions, including proof
piece status, furthest computation, and active bleeding-edge angles. This project turns that
mandate into a first-class fleet task.
