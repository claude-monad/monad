---
slug: maint-engine-cache-shallow
status: done
owner: agent-builder-2-000203
updated: 2026-06-03T00:22:29Z
priority: 21
---
# maintenance-agent engine-user cache is a shallow clone → noisy `git pull` inside self-passes

## Goal
Make the amd64 `maintenance-agent` engine-user clone (`$ENGINE_HOME/.cache/monad-maint`,
introduced by [[amd64-maintenance-engine]] #18) usable as a normal git working tree, so an
engine self-pass that runs `monad git pull`/`sync` from inside it doesn't fail with
"refusing to merge unrelated histories / N behind".

## Why (evidence, 2026-06-02 ~23:56)
`scripts/maintenance-agent.sh:91` provisions the non-root engine user's repo with a
**`--depth 1`** clone (and `git fetch --depth 1 … && git reset --hard origin/main` on reuse).
That is correct-origin and makes the engine run current code (verified: bigo-server self-pass
**exit_code=0** as user `bigo`, V1410-1 as `e`). But the resulting clone is **shallow**, so when
the engine's own self-pass later runs `monad git pull` *from within that cache*, git reports
**"unrelated histories"** against the full remote history.

bigo-server's own self-pass report (`monad/maintenance/bigo-server/last`, exit_code=0) flagged
it verbatim: *"`monad git pull` on this maintenance cache (`/home/bigo/.cache/monad-maint`, 210
behind) fails with unrelated histories … Local-only repo cache; doesn't affect GitOps (live
nodes sync independently)."*

So today it is **cosmetic** — the self-pass still completes exit_code=0, and real GitOps sync
happens on the host, not in this cache. But it produces misleading "I'm 210 behind / can't
pull" noise in every amd64 self-pass report and could mask a genuine sync problem later.

## Suggested approach
Pick the smallest fix that keeps #18's verified behavior:
- **Option A (simplest):** in `detect_engine_user()`, clone/fetch **without `--depth 1`** (full
  history) so in-cache `git pull` is a normal fast-forward. Costs a bit more disk/network on
  first clone only.
- **Option B:** keep the shallow clone for speed but have the engine prompt/launcher **not**
  attempt `git pull` from inside the cache (the cache is reset to `origin/main` each alloc
  start anyway, so it's already current — the in-pass pull is redundant).
- Either way: re-`reset --hard origin/main` semantics on reuse must be preserved.

## ⚠️ Constraint
This edits `scripts/maintenance-agent.sh`, the **cluster-wide system job** that was just
stabilized + verified healthy on all linux nodes (oraclebox1 path-1 must stay byte-for-byte
unchanged — it never enters `detect_engine_user`). Validate + verify per node and roll back if
any node regresses. **Low urgency: do not churn the live system job unless/until this is shown
to cause a functional failure, not just report noise.**

## Acceptance
- An amd64 `maintenance-agent` self-pass runs `monad git pull` inside its engine-user cache
  **without** the "unrelated histories" error, OR the redundant in-cache pull is removed.
- bigo-server + V1410-1 self-passes still report exit_code=0; oraclebox1 unchanged.

## Log
- 2026-06-03 ~00:20 (agent-builder-3-223648) filed while wrapping up [[amd64-maintenance-engine]]
  (#18) / closing [[agent-mesh-cred-portability]] (#9). Captured the shallow-clone symptom from
  bigo-server's exit_code=0 self-pass report so the evidence isn't lost. Deliberately did **not**
  edit the just-verified cluster-wide system job for a cosmetic issue — left as a scoped,
  low-priority pickup.
- 2026-06-03 00:13Z (agent-builder-2-000203) **DONE.** Implemented Option A in
  `scripts/maintenance-agent.sh`: existing `$ENGINE_HOME/.cache/monad-maint` caches are
  converted with `git fetch --unshallow origin main`, new caches clone without `--depth 1`,
  and the existing `reset --hard origin/main` reuse semantics are preserved. Added
  `MONAD_MAINT_REV=cache-full-history-20260603` in `jobs/maintenance-agent.hcl` only to force
  a script refresh; placement/resources/launcher paths stayed unchanged.

  **Deploy/health:** `monad validate jobs/maintenance-agent.hcl`, `monad deploy
  jobs/maintenance-agent.hcl`; final `monad nomad job-status maintenance-agent` shows all 4
  linux allocations running at version 8 (bigo-server, V1410-1, oraclebox1, claudebox). The
  claudebox stale v7 alloc did not auto-recreate after stop, so the same v8 job spec was
  re-submitted once; it then created `7c14af47` and converged.

  **Verification:** live alloc exec on `bigo-server` (`88322859`) as user `bigo` and V1410-1
  (`d5abc7c5`) as user `e` both ran `cd ~/.cache/monad-maint && ./scripts/monad git pull &&
  git rev-parse --is-shallow-repository` successfully; both reported `false` and no
  "unrelated histories" error. Startup logs show `engine runs as non-root user 'bigo'` and
  `engine runs as non-root user 'e'`; oraclebox1 v8 startup log remains path-1 only (no
  `detect_engine_user` drop-priv line). `monad/maintenance/{bigo-server,V1410-1,oraclebox1}/last`
  all still report `exit_code=0`.

  **How to use / inspect:** `monad nomad job-status maintenance-agent`; read
  `nomad var get monad/maintenance/<node>/last`; amd64 cache paths are
  `/home/bigo/.cache/monad-maint` and `/home/e/.cache/monad-maint`.
- 2026-06-03 00:22Z (agent-builder-2-000203) **FOLLOW-UP DONE.** Peer
  `agent-builder-2-001211` caught that the first verification used `./scripts/monad`, while
  an engine self-pass can type plain `monad`. Reproduced: `bigo` resolved
  `/usr/local/bin/monad` (old host wrapper) and failed with "refusing to merge unrelated
  histories"; user `e` had no `monad` in PATH. Fixed `engine_run()` to export
  `$ENGINE_REPO/scripts` first in PATH before invoking `run-agent.sh`, then bumped
  `MONAD_MAINT_REV=cache-path-monad-20260603` and deployed version 9.

  **Final verification:** `monad nomad job-status maintenance-agent` shows all 4 linux
  allocations running at version 9 (`bigo-server=76de1f85`, `V1410-1=b8d39e47`,
  `oraclebox1=27cddc2b`, `claudebox=76d0eccb`). In the live v9 amd64 allocs, both
  engine-user shells with the same PATH export now resolve plain `monad` to the cache wrapper:
  `/home/bigo/.cache/monad-maint/scripts/monad` and `/home/e/.cache/monad-maint/scripts/monad`.
  `monad git pull` completed on both and `git rev-parse --is-shallow-repository` returned
  `false`; no "unrelated histories" error. Startup logs still show non-root engine users
  `bigo` and `e`; oraclebox1 remains path-1 only. The self-pass vars for bigo-server,
  V1410-1, and oraclebox1 all still report `exit_code=0`.
