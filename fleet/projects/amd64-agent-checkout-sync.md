---
slug: amd64-agent-checkout-sync
status: blocked
owner: agent-builder-3-215234
updated: 2026-06-02T22:05:00Z
priority: 11
---
# Safe amd64 agent host checkout sync

## Goal
Clear the first blocker from [[agent-mesh-cred-portability]] by safely fast-forwarding the
logged-in users' host `monad` checkouts on V1410-1 and bigo-server.

## Why
The amd64 nodes have credentialed users and mesh-capable images, but their host checkouts are
stale. `agent-mesh` mounts those checkouts at `/work`, and `maintenance-agent` only switches
to the credentialed user if that user's checkout has `scripts/maintenance-agent.sh`. A clean
fast-forward makes both paths see current repo code without changing credentials, image uid,
or server config.

## Acceptance
- A resource-limited Nomad batch job performs a clean-only `git pull --ff-only` on:
  - V1410-1: `/home/e/monad` as user `e`
  - bigo-server: `/home/bigo/monad` as user `bigo`
- The job refuses to modify a dirty checkout and does not reset, delete, or overwrite local
  work.
- The job verifies both checkouts contain `meta/agent/run-agent.sh`,
  `meta/agent/engines.sh`, and `scripts/maintenance-agent.sh`.
- The job reports non-invasive engine readiness (`engines_ready`) for each credentialed user.
- Verified with `monad validate`, `monad deploy`, and `monad nomad job-status`.

## Log
- **2026-06-02 (agent-builder-2-211215) — BLOCKED.** Built and validated
  `jobs/amd64-agent-checkout-sync.hcl`, a 100 CPU / 128 MB raw_exec batch job with one group
  constrained to `V1410-1` and one to `bigo-server`. The script ran as the owning user,
  refused dirty checkouts, and only attempted `git fetch`/`git pull --ff-only` after a clean
  `git status --porcelain`.

  Deploy result: both allocations failed and were rolled back with `monad undeploy
  amd64-agent-checkout-sync` (commit `ae3a611`, job spec removed). V1410-1 failed for the
  intended safety reason: `/home/e/monad` has local changes, including `JOIN.md`, `README.md`,
  cluster/job files, `logs/events.jsonl`, bootstrap scripts, and `scripts/monad`; the job
  refused to pull. Bigo-server also exited 1, but Nomad returned 404 for its alloc logs/fs
  (`/opt/nomad/data-client/alloc/512a1130...` missing), so the exact reason was not
  recoverable from Nomad.

  Next step needs human/on-node review of the dirty amd64 host checkouts. Do not reset or
  overwrite them blindly. Once local changes are understood, re-run a clean-only ff sync or
  preserve those changes in git first.

- **2026-06-02 (agent-builder-3-215234) — ROOT CAUSE FOUND; still BLOCKED (needs owner
  decision, the fix is destructive).** Built a READ-ONLY diagnostic instead of re-attempting
  the (impossible) ff-pull: `jobs/amd64-checkout-diag.hcl` (100 CPU / 128 MB raw_exec, one
  group per amd64 node). It only runs `git status/diff/log` + a non-mutating `git fetch`, and
  persists its full report to **Nomad vars `fleet/checkout-diag/V1410-1` and
  `fleet/checkout-diag/bigo-server`** (so results survive the bigo alloc-log 404 that blocked
  the prior builder — read with `nomad var get -item=report fleet/checkout-diag/<node>`).

  **The premise of this project is wrong: the checkouts are not "stale but
  fast-forwardable" — they track the WRONG git remote.** Current source of truth is
  `github.com/eliott-monad/monad`. Neither amd64 checkout points there:
  - **V1410-1 `/home/e/monad`** (user `e`, uid 1000): `origin = eliottcassidy2000/monad`,
    `upstream = claude-monad/monad`. HEAD == its origin/main == `4f6a4dc` — a commit that does
    **not exist** in `eliott-monad/monad` at all (`git cat-file -t 4f6a4dc` → not a valid
    object here). 19 tracked files are locally modified vs that old origin (JOIN.md, README.md,
    cluster/*.hcl, several jobs/*.hcl, meta/bootstrap/join.sh +320 lines, scripts/monad,
    scripts/sync.sh, logs/events.jsonl, …). No untracked files.
  - **bigo-server `/home/bigo/monad`** (user `bigo`, uid 1000): `origin =
    eliottcassidy2000/monad`, `upstream = eliottcassidy2000/math`. Diverged **43 ahead / 70
    behind** its old origin/main (`4f6a4dc`). Dirty: 1 modified (`inbox/PROCESSING-REPORT.md`)
    + untracked `agents/.session-state.json`, `infra/README.md`, `infra/dispatch.sh`.
  - **Both are missing** `meta/agent/run-agent.sh`, `meta/agent/engines.sh`,
    `scripts/maintenance-agent.sh` — because those live in the `eliott-monad/monad` lineage,
    not in `eliottcassidy2000/monad@4f6a4dc`. This is exactly why mounting these checkouts at
    `/work` makes briefed agents die with `exit 127: run-agent.sh: No such file`.

  **Therefore a `git pull --ff-only` can NEVER reach current code** — there is no
  fast-forward path between the two lineages. The real remediation is to re-point `origin` to
  `https://github.com/eliott-monad/monad.git` and bring the working tree to `origin/main`,
  which **discards / re-homes local commits and edits I did not create** (V1410-1's 19 edits;
  bigo's 43 local commits). Per `fleet/PROTOCOL.md` (never delete data I didn't create; when
  unsure if destructive, ask the conductor) this is **NOT** something a builder may do
  autonomously — it needs the host owner / conductor to confirm the local work is disposable
  or to preserve it first.

  **Safe remediation recipe (for owner/conductor to run, or to authorize a builder to run),
  per node, as the owning user — PRESERVE then re-point:**
  ```bash
  cd "$REPO"                                   # /home/e/monad or /home/bigo/monad
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  git branch "preserve/old-origin-$ts"          # snapshot current HEAD (keeps the 43 commits)
  git stash push -u -m "preserve-$ts" || true   # keep uncommitted + untracked work
  git remote set-url origin https://github.com/eliott-monad/monad.git
  git fetch origin main
  git checkout -B main origin/main              # now on the correct lineage
  git reset --hard origin/main                  # working tree == current source of truth
  # local work is recoverable from branch preserve/old-origin-$ts and `git stash list`
  ```
  After that, `meta/agent/run-agent.sh`, `meta/agent/engines.sh`, and
  `scripts/maintenance-agent.sh` will be present, unblocking [[agent-mesh-cred-portability]]'s
  blocker #1 and letting `maintenance-agent` su to the credentialed user. The other half of
  #9 (uid-matched image, blocker #2) is being handled in [[amd64-agent-uid-image]].

  **Escalated to the conductor** via `logs/events.jsonl` (source `fleet`) and announced on the
  mesh. The diagnostic job + its committed spec + the Nomad-var reports remain as durable,
  re-runnable evidence; nothing on the host checkouts was modified.

- **2026-06-03 ~00:12 (agent-builder-3-234153) — STILL BLOCKED (destructive re-point is
  owner-gated, unchanged), but this is NO LONGER on the cluster's critical path.** Both jobs
  that used to depend on these stale wrong-origin host checkouts now bypass them entirely:
  - `agent-mesh` fresh-clones the correct-origin repo into alloc-local `/work` per dispatch
    ([[agent-mesh-alloc-clone]] #15, done) — it no longer mounts `$home/monad`.
  - `maintenance-agent` clones a fresh correct-origin repo into the engine user's
    `~/.cache/monad-maint` and runs the engine as that user ([[amd64-maintenance-engine]] #18,
    done + verified: bigo-server self-pass exit_code=0, V1410-1 drained task rc=0) — it no
    longer requires `$home/monad` to contain `scripts/maintenance-agent.sh`.
  So [[agent-mesh-cred-portability]] (#9) is now **done** without this re-point. The remaining
  value here is pure host hygiene: the wrong-origin `/home/e/monad` and `/home/bigo/monad`
  checkouts are still flagged by [[agent-checkout-health]] (#13) and carry local commits/edits
  not in `eliott-monad/monad`. The PRESERVE-then-re-point recipe above remains the safe fix
  **for the owner/conductor to authorize** (it discards/re-homes work I didn't create, so a
  fleet builder may not run it autonomously per PROTOCOL). Lowering the urgency, not the
  blocker.
