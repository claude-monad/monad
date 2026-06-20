# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_1703
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding
- Git cannot fast-forward — may have conflicts or diverged history

## Warnings

- Git has        5 uncommitted changes

## Sweep note

- Local Nomad client answers `NOMAD_ADDR=http://127.0.0.1:4646 nomad agent-info`; normal status checks fail because the cluster has no leader.
- `ensure-engines.sh` reports `claude=ready` and `codex=ready`, and advertised `agent_engines=claude,codex`.
- Auto-repair helper produced no output after startup and was stopped; quorum recovery was escalated via existing tasks `t-0147` and `t-0148`.
