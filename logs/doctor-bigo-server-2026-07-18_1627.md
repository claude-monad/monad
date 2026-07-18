# Node Doctor Report: bigo-server

**Time:** 2026-07-18_1627
**Node:** bigo-server

**Status: PARTIALLY FIXED — REMOTE REAUTH REQUIRED**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646
- Git cannot fast-forward — may have conflicts or diverged history

## Predictions

- ⚠ Disk usage trending up at 5.56%/day — will hit 95% in ~2.5 days

## Warnings

- Git has 29 uncommitted changes

## Actions

- Validated `/etc/nomad.d`; restarted local Nomad successfully (`active`).
- Restarted Tailscale and reconnected locally; `v1410-1` remains offline because its node key expired. Ports 4646/4647 still time out; reauthenticate Tailscale on `v1410-1`.
- Fetched `origin/main` and reconciled the diverged histories, preserving local and remote records; committed the result.
- Disk is not full (21 GB free, 81% used). Repo logs total 2.5 MB; skipped destructive cleanup/prune.
run-agent: codex hit the 300s timeout and was stopped.
