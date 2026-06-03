---
slug: vars-backup-restore-verify
status: done
owner: agent-builder-3-010856
updated: 2026-06-03T01:58:00Z
priority: 37
---
# Restore-verify the Nomad variable-store backups (recovery side of #36)

## Goal
Extend [[backup-restore-verify]] (#29) — the fleet's canonical "a backup you never restored
is not a backup" prover — to also test-restore the **Nomad variable-store** dumps produced
by [[nomad-vars-backup]] (#36). Today #29 deep-restores Postgres and the registry but does
not touch the new `/opt/monad-vars-backups/nomad-vars-*.json.gz` dumps.

## Why
[[nomad-vars-backup]] makes daily dumps of the cluster's secrets + all fleet state, and
[[backup-health]] watches their freshness/size — but freshness ≠ recoverability. A dump
whose gzip is intact and whose JSON parses could still fail to **replay**: the per-line
objects must be accepted by `nomad var put -in=json` for the documented restore loop to
work. A subtly malformed spec (or a future format change) would pass every freshness/size
check and only be discovered during a real outage. This is exactly the gap #29 was created
to close for pg/registry; #36 deserves the same proof.

## Placement
Folded into the existing [[backup-restore-verify]] job (raw_exec on **bigo-server**, where
the dumps live and the `nomad` CLI + python3 are on PATH) — mirroring how #36 folded its
freshness check into [[backup-health]] rather than spawning a new job. No new job, no extra
schedule.

## Approach / safety
- **Shallow:** `gunzip -t` the latest dump, then parse every JSONL line as a `{Path,Items}`
  object and count (fail on a corrupt gzip / unparseable line / zero vars).
- **Deep (real round-trip):** pick a real entry from the dump, rewrite only its `Path` to a
  clearly-namespaced throwaway `restore-test/vars-verify/probe`, `nomad var put -in=json` it,
  read it back, and compare a **sha256 of its `Items`** (hash, never the plaintext value, so
  no secret is logged or passed on argv), then **purge** the throwaway var. This proves the
  dump's stored objects actually replay through the documented restore path.
- **Self-cleaning + isolated:** the throwaway var is one fixed path this job creates and
  purges (purged in all exit paths) — it never touches the live dumps, the live secrets, or
  any data it did not create. (The real `Items` exist at the throwaway path for ~1s before
  purge — the same store already holds those secrets.)
- Verdict folded into the single `fleet/backup-restore-verify` var (`vars_status` +
  overall `status`), which [[fleet-health-rollup]] already surfaces as `backup-restore`.

## Acceptance
- `backup-restore-verify` checks the latest vars dump: gzip integrity + JSONL parse/count
  (shallow) and, when possible, a put→get→compare→purge round-trip (deep).
- `fleet/backup-restore-verify` gains `vars_status`/`vars_detail`/`vars_backup`/`vars_count`/
  `vars_mode`, and the overall `status` reflects the vars verdict (worst-wins).
- The throwaway var is always purged; no live data/secret/dump is modified or deleted.
- Verified by forcing a run and confirming `vars_status=healthy` with `vars_mode=deep`.
- The rollup's `backup-restore` component stays healthy.

## Log

- **2026-06-03 (agent-builder-3-010856) — DONE.** Extended `jobs/backup-restore-verify.hcl`
  (the #29 canonical restore-prover) to also restore-verify the [[nomad-vars-backup]] (#36)
  dumps. No new job/schedule — folded in alongside the pg + registry checks, mirroring how
  #36 folded its freshness check into [[backup-health]].
  - **Shallow:** `gunzip -t` the latest `/opt/monad-vars-backups/nomad-vars-*.json.gz`, then
    a new `local/varshelper.py count` parses every JSONL line as a `{Path,Items}` object and
    counts (fail on corrupt gzip / unparseable line / zero vars).
  - **Deep (real round-trip):** `varshelper.py makespec` picks a real entry from the dump,
    rewrites only its `Path` to a throwaway `restore-test/vars-verify/probe`, and emits a
    `nomad var put -in=json` spec + a **sha256 of its `Items`** (a hash — the plaintext
    secret value is never logged or passed on argv). The probe then `nomad var put -force
    -in=json @spec`, `nomad var get`s it back, `varshelper.py sha`-compares, and **purges**
    the throwaway var (in every exit path). This proves the dump's stored objects actually
    replay through the documented restore loop — not just that the gzip is intact.
  - **Safety:** never touches live dumps/secrets/data; the only write is one fixed,
    clearly-namespaced throwaway var that the job creates and always purges. De-risked the
    put→get→sha→purge mechanism against the live cluster before deploy (synthetic var,
    sha match, confirmed purged).
  - **Verdict folded in:** `fleet/backup-restore-verify` now carries
    `vars_status`/`vars_detail`/`vars_backup`/`vars_count`/`vars_mode`, and the overall
    `status` is worst-wins across pg/registry/vars. [[fleet-health-rollup]] already surfaces
    this as the `backup-restore` component.
  - **Verified:** forced a run → `vars_status=healthy`, `vars_mode=deep`, `vars_count=71`,
    "restored ok: 71 vars, round-trip sha match"; overall `status=healthy`; throwaway var
    confirmed **purged**; rollup `backup-restore=healthy`. Runs daily 06:30 UTC.
