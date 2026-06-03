# PROPOSAL / RFC — verifiable master results DB + persistent shared graph model

**Status:** open proposal (owner-directed 2026-06-03, posted by claudebox). This is a *thinking
prompt for the whole cluster*, not a finished spec — agents are invited to critique, refine, and
prototype the first slices. See "Open questions" and "First concrete steps".

**Owner's ask (verbatim intent):**
1. Store the results of computations in a **master database**, where each result is *shown to be
   the output of an exact program* — e.g. by **hashing the program together with its output** — so
   it is **easily verifiable that any result in the DB is at least the output of a specific thing**.
2. Build **persistent shared models of nodes / edges / actions**, and **native ways to explore
   tournament structure as a process**.

Both map cleanly onto infra the cluster already runs — and they **unify** (see §C).

---

## A. Verifiable master results database (provenance ledger)

**The claim we want every row to make:** *"output O is what program P produced in environment E on
input I"* — and we want that claim to be **cheaply checkable by anyone**, ideally re-derivable.

### Content-addressing scheme
The verifiable identity of a result is a small tuple of hashes:

| field | definition | why |
|-------|-----------|-----|
| `program_hash` | `sha256(canonical(program source))` | pins the *exact* code |
| `env_hash` | the **pinned toolchain image digest** (`ghcr.io/eliott-monad/compute@sha256:…`) | pins the *exact* environment — this is what makes "a specific thing" real; we already run code in pinned images via `meta/execution/run-in-toolchain.sh` |
| `input_hash` | `sha256(canonical(inputs/args))` | pins the data/parameters |
| `claim_hash` | `sha256(program_hash ‖ env_hash ‖ input_hash)` | the **derivation id** — addresses "this exact computation" |
| `output_hash` | `sha256(output bytes)` | addresses the result |

A row binds `claim_hash → output_hash` plus provenance metadata (who/when/which node, wall time,
exit code, engine). This is essentially Nix-derivation / content-addressed-store semantics — but
grounded in our existing pinned compute image, so it's reproducible by construction.

**"Easily verifiable" then means two tiers:**
- **Tier 1 (cheap, always):** recompute `program_hash`/`input_hash` from the linked source+args and
  check `claim_hash`; confirm `sha256(stored output) == output_hash`. Proves *integrity* — the row
  hasn't been tampered with and names a specific program.
- **Tier 2 (re-derivation, on demand / sampled):** actually **re-run** P in image E on I inside
  `run-in-toolchain.sh`, hash the output, and assert it equals `output_hash`. Proves
  *reproducibility*. A periodic **`results-verify`** job (mirror of the existing
  `postgres-verify.hcl`) re-derives a random sample and flags any mismatch → the result is either
  reproducible, or it's flagged non-deterministic/wrong (itself a useful signal).

### Storage (build on what exists)
- **Index:** a `results` schema in the shared **`fleet` Postgres** (per the schema-per-app convention
  in this README). Immutable, append-only, deduped on `claim_hash` (`ON CONFLICT DO NOTHING`) — the
  same pattern as `health_snapshots`. Sketch:
  ```sql
  CREATE SCHEMA IF NOT EXISTS results;
  CREATE TABLE IF NOT EXISTS results.derivation (
    claim_hash   text PRIMARY KEY,         -- sha256(program‖env‖input)
    program_hash text NOT NULL,
    env_hash     text NOT NULL,            -- pinned image digest
    input_hash   text NOT NULL,
    program_ref  text,                     -- git path@commit or blob key for the source
    args         jsonb,
    created_at   timestamptz DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS results.output (
    claim_hash   text REFERENCES results.derivation,
    output_hash  text NOT NULL,
    output_ref   text,                     -- MinIO key (large) or inline (small)
    bytes        bigint, rc int, wall_ms bigint,
    node text, engine text, produced_at timestamptz DEFAULT now(),
    verified     text DEFAULT 'tier1',     -- tier1 | reproduced | MISMATCH
    PRIMARY KEY (claim_hash, output_hash)
  );
  ```
- **Blobs:** large outputs go to **MinIO** (`jobs/minio-storage.hcl`) keyed by `output_hash`
  (content-addressed → natural dedup); small outputs inline in Postgres.
- **Source of truth stays git** for *code*; the DB stores *derivations + outputs + provenance*, and
  references code by `path@commit` so a row always points back to an auditable program.

### Seed / first consumer
The math repo already emits `05-knowledge/results/*.out` from `04-computation/*.py` (see the math
CLAUDE.md). That's the natural **first ingestion source**: wrap a run so producing a `.out`
*also* writes a `results.derivation`+`output` row. A `monad results put|get|verify` helper (thin
wrapper over `run-in-toolchain.sh` + psql/MinIO) is the obvious interface.

---

## B. Persistent shared graph model — nodes / edges / actions, exploration as a process

A persistent, **shared**, **explorable** structure where the unit of work is *applying an action*:

- **nodes** — entities: vertices, whole tournaments, structures (orbits/perspectives, hypotheses,
  invariants, sequences).
- **edges** — relations: arcs, isomorphism, "is-a-flip-of", refinement, "perspective-of",
  "extends/implies".
- **actions** — the *process generators* / morphisms: arc-flip, automorphism, sieve/dilation,
  complement, the `⟨2⟩`-doubling and `⟨−1⟩`-reflection maps. Applying an action to a node yields
  another node — exploration is **walking the action graph**, persistently and collaboratively.

This is the computational substrate for the research line we're already on (see the LRC
"perspective = vertex-orbit under the automorphism group", and the S593/S596 "see everything as
orbits of group actions on Z/n; rigidity = orbit type" framing): **an orbit is literally a connected
component of the action subgraph**; "exploration as a process" is orbit-closure made executable.
The math repo's `00-navigation/CONCEPT-MAP.md` and `05-knowledge/COMPLETE_INVARIANT_CATALOG.md` are
the **informal precursors** — this proposal makes them a live, queryable, multi-agent graph.

### Backend options (decide later)
- **Lowest friction:** plain `nodes` / `edges` / `actions` tables in the same `fleet` Postgres
  (adjacency + JSONB attrs). Good enough for millions of nodes, no new service.
- **Native graph:** the **Apache AGE** extension on the existing Postgres (openCypher over the same
  DB) if/when traversal queries get heavy — keeps one backend.
- Keep nodes **content-addressed** too (a tournament → a canonical hash of its arc set), so the graph
  and the results DB share identities.

---

## C. The unification (why these are one system)

Each **action application is a computation**. So an *edge in the graph is produced by a derivation in
the results DB*: `node_A --action(P,E,I)--> node_B` is exactly a `results` row whose program computed
`node_B` from `node_A`. That gives us a **self-documenting, verifiable, ever-growing shared map**:
every node and edge is backed by a reproducible, hash-pinned computation; the exploration *process*
is what writes the ledger; the ledger is *why* you can trust the map. Provenance (A) and exploration
(B) are the write-path and the read-model of the same thing.

---

## Open questions (please poke holes)
- **Canonicalization:** how to canonicalize "the program" (single script vs repo subtree + entrypoint
  + args) and inputs so hashes are stable across formatting/noise? Is `program_ref = path@commit`
  enough, or do we hash the file bytes?
- **Nondeterminism:** RNG seeds, wall-time, float/ordering, parallelism. Policy: require seeded/pure
  programs for Tier-2 reproducibility; otherwise store as Tier-1 "attested, not reproducible" and
  record the seed in `args`.
- **Trust:** do we want signatures (per-node key) on rows, or is content-addressing + sampled
  re-derivation enough? (Re-derivation is stronger than a signature for *correctness*.)
- **Graph backend:** plain tables now vs AGE later — and node identity (content hash vs surrogate id).
- **Write contention / claims:** how do many agents extend the graph without stampede (reuse the
  `cluster-memory.sh` claim pattern? per-frontier-node claims?).
- **Relation to git:** git stays source-of-truth for code; DB owns derivations/outputs/graph. Where's
  the boundary for *results* that are currently committed as `.out` files?

## First concrete steps (small, hand-off-able — claim one and prototype)
1. **`results` schema + `monad results put|get|verify`** — thinnest end-to-end slice: run a math
   `04-computation/*.py` through `run-in-toolchain.sh`, write the derivation+output rows, store blob
   in MinIO, verify Tier-1. Register the schema in this README's table.
2. **`results-verify` periodic job** — sample N rows, Tier-2 re-derive, mark `reproduced|MISMATCH`.
3. **`graph` schema (nodes/edges/actions)** seeded from `COMPLETE_INVARIANT_CATALOG.md` /
   `CONCEPT-MAP.md`, with a `monad graph add-node|add-edge|apply-action|neighbors` CLI; one worked
   example: enumerate small tournaments, apply arc-flip actions, record the orbit components.
4. Write up findings back as new tasks; if a result resists Tier-2 verification, that's a court case
   in the math repo.

*Reply / extend via `cluster-msg`, or claim a step with a task (`meta/coordination/task.sh emit`).*
