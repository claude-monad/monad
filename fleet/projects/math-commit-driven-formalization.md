---
slug: math-commit-driven-formalization
status: done
owner: bigo-server
updated: 2026-06-03
priority: 2
---
# Commit-driven Lean formalization: every math commit feeds an automated Codex formalizer

> **Implemented 2026-06-03 (bigo-server).** Built concurrently with this project doc; see
> `meta/FORMALIZATION-POLICY.md` and commit "delegate formalization to commit-triggered codex
> work". Delivered: `jobs/formalize-watch.hcl` + `scripts/formalize-watch.sh` (poll math HEAD,
> advance `fleet/formalizer-cursor`, write `monad/formalize/inbox`, force `math-formalizer` or
> defer to an active session); `math-formalizer` switched to codex on `has_codex` nodes with
> `MONAD_CODEX_EFFORT=high`; `engines.sh` honors `MONAD_CODEX_EFFORT` (opt-in, fleet default
> unchanged); `scripts/prompts/formalizer.md` gains the dual mandate (formalize + mine
> implications/extensions/connections, scratch in math-lean `exploration/`, forward new
> results + court cases to the informal repo). Reconciled to this spec's var name
> (`fleet/formalizer-cursor`) and math-lean scratch location.
> **Follow-on (not done here):** fold a `formalizer-lag` signal (cursor vs math HEAD) into
> `fleet/health-summary`.

**Owner request (2026-06-03).** We have a separate, Lean-specific repo
(`eliott-monad/math-lean`). **Delegate formalization to automated Codex work** and make it
**event-driven on the informal math repo** so the Lean repo is *always up to date* — not just
swept every 4h by the periodic `math-formalizer`.

## What the owner asked for
1. **Trigger on every commit to the informal math repo** (`eliottcassidy2000/math`): when a
   new commit lands, **either spawn a formalization job** for it **or, if a formalizer session
   is already active, send it a message** saying *what has arrived* (which results/theorems/
   files changed). The goal is that `math-lean` continuously tracks the math repo.
2. **Codex engine at MAX thinking/reasoning effort** for these agents.
3. The agents must treat the **mathematics as equally important as the formalization**: while
   formalizing, actively consider the **mathematical implications, extensions, and the
   connections between results** — don't mechanically transcribe.
4. They should **keep their own thoughts, tests, and ideas in their own (Lean) repo**
   (`math-lean` — a scratch/exploration area for notes, experiments, conjectures, failed/partial
   attempts), so the exploration is durable and shared.
5. Expect this to **produce new theorems of its own** — results the Codex agents discover while
   formalizing/extending. Those new results should themselves be fed back and formalized (and,
   per the existing loop, raised as court cases in the informal repo when they reconcile or
   contradict it).

## How it should work (suggested design — adjust with peers)
- **Commit watcher → dispatch.** A small standing/periodic job (lean, read-only on the math
  repo) polls `eliottcassidy2000/math` HEAD (the cluster has no webhook ingress; poll the
  GitHub API or `git ls-remote`, persist last-seen SHA in a Nomad var e.g.
  `fleet/formalizer-cursor`). On a new commit, diff `HEAD~n..HEAD` for changed
  results/theorems and **enqueue a formalization unit** describing exactly what arrived.
  - **If a formalizer is already running** (active `math-formalizer` alloc, or a standing mesh
    "formalizer brain" session): **message it** the arrival via the agent mesh
    (`agent-msg send <peer> "<commit sha>: <changed results>"`) / the math repo's
    `agents/processor.py --send`, so the running session picks it up instead of double-work.
  - **Else spawn** a Codex formalizer dispatch for that unit (a `claude-task`/dispatch job,
    engine-pinned to codex). Keep `prohibit_overlap`-style guards so concurrent commits don't
    stampede; coalesce bursts.
- **Codex at max effort.** Run the engine as codex with **highest reasoning effort**:
  `codex exec -c model_reasoning_effort="high"` (wire it through `meta/agent/engines.sh`
  `engine_exec_argv` / `run-agent.sh`, e.g. an opt-in `MONAD_CODEX_EFFORT=high` the job sets;
  don't change the cluster default for *other* agents). These formalizer jobs should set
  engine=codex explicitly (job `-meta engine=codex`) regardless of the cluster default.
- **Prompt (extend `scripts/prompts/formalizer.md`).** Keep the existing sorry-free Lean 4 +
  Mathlib mandate and the court-case feedback loop, and **add** an explicit charge to: weigh
  the mathematical implications/extensions and cross-result connections as it formalizes;
  record its reasoning, experiments, and conjectures in a scratch area of `math-lean`
  (e.g. `exploration/` or `notes/`); and **open/forward any genuinely new theorem** it proves
  back into the pipeline (formalize it too) and to the informal repo via a court case.
- **Always-up-to-date guarantee.** The periodic `math-formalizer` (jobs/math-formalizer.hcl)
  stays as the safety-net sweep; the new watcher makes the common case *immediate*. The cursor
  var makes "is math-lean caught up to math?" answerable, and is a natural health component
  (fold a `formalizer-lag` signal into `fleet/health-summary` so a stalled pipeline is visible).

## Acceptance
- A new commit to `eliottcassidy2000/math` reliably results, within minutes, in **either** a
  spawned Codex formalization dispatch **or** a mesh/processor message to an active formalizer —
  verifiable from a test commit (or a recent real one) advancing `fleet/formalizer-cursor` and
  a corresponding dispatch/alloc or mesh message.
- The formalizer dispatch runs **codex at max reasoning effort** (job meta engine=codex +
  effort=high), and the formalizer prompt includes the math-implications/exploration/new-theorem
  charge above, writing exploration notes into `math-lean`.
- Committed (watcher code + any job in `jobs/`, prompt + engine changes, README/notes), the
  pipeline's address/cursor advertised as a Nomad var, peers told. Decide placement of the
  watcher with peers (needs `gh`/network to the math repo + ability to dispatch).

## Notes / constraints
- **Engine-effort change must be opt-in** — don't raise reasoning effort (or cost) for the
  whole fleet; scope `effort=high` to these formalizer jobs.
- Read-only on the informal math repo from the watcher's side (it only *reads* commits and
  *dispatches*); formalization writes land in `math-lean` and, via court cases, back to math.
- Builds on the existing pieces: `jobs/math-formalizer.hcl`, `scripts/formalizer-session.sh`,
  `scripts/prompts/formalizer.md`, the math-lean `sync-candidates.sh`, the agent mesh
  (`agent-msg`) + the math repo's `agents/processor.py`. Reuse, don't reinvent.
