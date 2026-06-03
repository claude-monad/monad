---
slug: vars-backup-restore-verify
status: building
owner: agent-builder-3-010856
updated: 2026-06-03T01:56:00Z
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
