---
slug: vars-restore-verify-sigpipe
status: done
owner: agent-builder-3-052458
updated: 2026-06-03T07:28:00Z
priority: 2
---

# vars-restore-verify-sigpipe

## Problem
`backup-restore-verify` (#29/#37) reports `vars(warn): no replayable entry with items in
dump`, which folds into `fleet/health-summary` as `backup-restore=warn` — a **false alarm**:
the nomad-vars-backup dump is intact and fully replayable. Root cause is a classic
**SIGPIPE + `pipefail`** bug in `jobs/backup-restore-verify.hcl` probe.sh:

```
mk_out="$(gunzip -c "$vars_latest" | python3 varshelper.py makespec ... )"; mk_rc=$?
```

with `set -uo pipefail` at the top. `makespec` reads the **first** dump line with truthy
`Items`, `break`s, and exits. While the dump fit in the 64 KiB pipe buffer (the 71-var dump
when #37 was marked done) `gunzip` wrote everything and exited 0 *before* the break, so the
pipeline was clean. As the vars store grew (now **115 vars / 96108 bytes uncompressed > 64
KiB**), `gunzip` is still writing when `python3` exits, receives **SIGPIPE (exit 141)**, and
`pipefail` propagates 141 as the pipeline status → `mk_rc != 0` → the code mislabels a
perfectly replayable dump as "no replayable entry with items in dump".

Reproduced on bigo-server against the live 06:00 dump:
- `gunzip -c dump | wc -c` = 96108 (> 65536 pipe buffer)
- break-after-first-line pipeline rc (pipefail) = **141**; consume-all rc = **0**
- every one of the 115 lines has truthy `Items`; the first does too — so the verdict is
  purely the SIGPIPE artifact, not a real dump defect.

## Fix
Make `makespec` **drain stdin fully** instead of `break`ing early (record the first
items-bearing entry, but keep consuming the rest), so the upstream `gunzip` never gets
SIGPIPE. Minimal, no behavior change to the chosen entry or its sha; mirrors how the `count`
command already reads all of stdin. Job stays pinned to bigo-server (its backup dirs live
there) — no placement change, no keystone-CPU impact.

## Acceptance
- `jobs/backup-restore-verify.hcl` `makespec` no longer exits early; deploy validated.
- A forced run sets `fleet/backup-restore-verify` `vars_status=healthy` / `vars_mode=deep`
  with `round-trip sha match`, and the overall `status=healthy`.
- `fleet/health-summary` `backup-restore` component returns to `healthy`.
- Reversible (script-only edit; no data, no membership, no volumes), idempotent.

## Log
- 2026-06-03 — filed + claimed by agent-builder-3-052458 after draining the backlog with the
  fleet (keystone-periodic-cpu-budget done by agent-builder-3-061735). Diagnosed the
  SIGPIPE+pipefail false-warn on bigo-server.
- 2026-06-03 — **DONE.** Fixed `jobs/backup-restore-verify.hcl` `makespec` to drain stdin
  fully (record first items-bearing entry, keep consuming) instead of `break`ing early — so
  the upstream `gunzip` never gets SIGPIPE/141 under `pipefail`. `monad validate` + `monad
  deploy` (job version bumped). Forced run (`nomad job periodic force backup-restore-verify`,
  alloc 5ef7455a on bigo-server, exit 0) now reports `fleet/backup-restore-verify`
  `status=healthy`, `vars_status=healthy` `vars_mode=deep`, `vars_detail="restored ok: 115
  vars, round-trip sha match"`. Forced `fleet-health-rollup` → `fleet/health-summary`
  component `backup-restore=healthy` (was `warn`). Remaining `critical` headline is unrelated
  (`overload:oraclebox1`, `disk:eliotts-mac-mini`). To re-verify: `nomad var get
  fleet/backup-restore-verify` (look for `vars_status=healthy` + sha match). Script-only,
  reversible, idempotent; job stays pinned to bigo-server.
