# Formalization Policy — codex keeps math-lean in lockstep with the math repo

**Status:** active (2026-06-03). Supersedes the old "formalizer runs every 4h on the Pro
Claude account" model.

## Decision

Lean formalization lives in its **own repo** (`eliott-monad/math-lean`), separate from the
informal research repo (`eliottcassidy2000/math`). Because it is a distinct, self-contained
workstream, we **delegate it to automated codex work**, running at **maximum reasoning
effort**, and we drive it off the math repo's commit stream so math-lean is *always* up to
date — never waiting on a human or a slow cron.

Two rules define the policy:

1. **Every commit to the informal math repo triggers formalization.** A watcher detects when
   the math repo's `main` moves and makes sure formalization work is spawned — or, if a
   formalizer is already running, leaves the new arrivals in a durable inbox so the active
   session picks them up. Either way, what arrived is communicated to the worker.

2. **The codex formalizer has a dual mandate, both equally important:**
   - **Formalize** — turn newly-arrived informal results into sorry-free Lean 4 proofs in
     math-lean, keeping the build green.
   - **Think** — genuinely mine the mathematics it touches: implications, extensions,
     generalizations, and *connections between* results. It keeps this thinking (notes,
     conjectures, computational tests, ideas) in a scratch `exploration/` area of its **own
     repo, math-lean**, so the work is durable and shared. Genuinely new results are then
     forwarded to the informal math repo (and a contradiction opens a court case) — where they
     become formalization candidates themselves, so the loop feeds itself.

## Mechanism (where it lives)

| Piece | File | Role |
|-------|------|------|
| Commit watcher | `jobs/formalize-watch.hcl` → `scripts/formalize-watch.sh` | Server-side periodic (every 10 min). `git ls-remote` the math repo; on a moved HEAD, record the new commits to the `monad/formalize/inbox` Nomad var and force an immediate `math-formalizer` run (or note that one is already active). Advances the `fleet/formalizer-cursor` watermark. |
| Formalizer job | `jobs/math-formalizer.hcl` | Periodic safety-net (every 4h) + the job the watcher forces. Constrained to a **codex-ready node** (`meta.has_codex = true`); sets `MONAD_ENGINE=codex`, `MONAD_CODEX_EFFORT=high`. |
| Session launcher | `scripts/formalizer-session.sh` | Clones math-lean, injects the inbox ("just arrived") into the prompt, runs the agent via `meta/agent/run-agent.sh --engine codex` at high effort. |
| Agent prompt | `scripts/prompts/formalizer.md` | The dual-mandate instructions. |
| Engine support | `meta/agent/engines.sh` | codex exec argv now honors `MONAD_CODEX_EFFORT` (`minimal\|low\|medium\|high`). |

### State / coordination vars
- `fleet/formalizer-cursor` — `last_sha`: the math-repo commit the watcher has processed.
  Makes "is math-lean caught up to math?" answerable, and is the natural input to a
  `formalizer-lag` health signal (a follow-on for `fleet/health-summary`).
- `monad/formalize/inbox` — `since`, `head`, `count`, `arrived`, `commits`: what most recently
  landed. This is how a commit "communicates to the active job what has arrived."

### Self-correcting by design
The trigger is best-effort; the **authoritative** queue is still `candidates/` in math-lean,
refilled by the repo's `sync-candidates.sh` at the start of every session. So a missed trigger
only delays formalization to the next 4h pass — it never drops a result.

## Why codex (not Claude) for this
codex has an independent rate-limit pool, so heavy formalization + exploration sessions never
compete with the Max/Pro **Claude** research/compute/reviewer agents for quota. See
`meta/agent/README.md` for the engine abstraction.

## Operating notes
- Requires at least one node advertising `has_codex=true` with codex authed (currently
  `oraclebox1`; `bigo-server`'s codex is currently broken — missing the linux-x64 binary).
- To watch it work: `monad events` (sources `formalize-watch`, `math-formalizer`) and
  `nomad var get monad/formalize/inbox`.
