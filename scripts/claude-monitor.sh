#!/usr/bin/env bash
# Monitor the owner-facing Claude/Codex sessions and take only scheduler-safe recovery steps.
set -uo pipefail

export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
REPO="${MONAD_REPO_DIR:-/home/e/monad}"
LOG_DIR="${MONAD_LOG_DIR:-$REPO/logs}"
LOG="$LOG_DIR/claude-monitor.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"
}

job_running_allocs() {
  nomad job status "$1" 2>/dev/null | awk '
    /^Allocations/ { in_allocs=1; next }
    in_allocs && NF >= 6 && $5 == "run" && $6 == "running" { n++ }
    END { print n + 0 }
  '
}

node_status() {
  nomad node status 2>/dev/null | awk -v node="$1" '$4 == node { print $NF; found=1 } END { if (!found) print "missing" }'
}

run_job_if_present() {
  job="$1"
  spec="$2"
  if [ -f "$spec" ]; then
    log "$job: running nomad job run -detach $spec"
    nomad job run -detach "$spec" >>"$LOG" 2>&1 || log "$job: job run failed"
  else
    log "$job: cannot run, spec missing: $spec"
  fi
}

restart_or_redeploy() {
  job="$1"
  spec="$2"
  running="$(job_running_allocs "$job")"
  if [ "$running" -gt 0 ]; then
    log "$job: ok ($running running allocation(s))"
    return 0
  fi
  log "$job: no running allocations"
  run_job_if_present "$job" "$spec"
}

check_codex_tui() {
  restart_or_redeploy codex-tui "$REPO/jobs/codex-tui.hcl"
}

check_oracle_pinned_claude() {
  job="$1"
  spec="$2"
  running="$(job_running_allocs "$job")"
  if [ "$running" -gt 0 ]; then
    log "$job: ok ($running running allocation(s))"
    return 0
  fi

  oracle="$(node_status oraclebox1)"
  if [ "$oracle" != "ready" ]; then
    log "$job: blocked; oraclebox1 client is $oracle, so restarting would not place"
    return 0
  fi

  log "$job: oraclebox1 ready but no running allocations; redeploying"
  run_job_if_present "$job" "$spec"
}

check_leonhard() {
  if ! nomad var get assistants/leonhard >/dev/null 2>&1; then
    log "leonhard: registry var missing; not auto-creating without owner intent"
    return 0
  fi

  job="$(nomad var get -item=job assistants/leonhard 2>/dev/null || true)"
  if [ -z "$job" ]; then
    log "leonhard: registry has no job id"
    return 0
  fi

  running="$(job_running_allocs "$job")"
  if [ "$running" -gt 0 ]; then
    log "leonhard: ok ($job, $running running allocation(s))"
    return 0
  fi

  oracle="$(node_status oraclebox1)"
  if [ "$oracle" != "ready" ]; then
    log "leonhard: blocked; $job is pinned through assistant to oraclebox1, currently $oracle"
    return 0
  fi

  log "leonhard: oraclebox1 ready but $job has no running allocations; rescheduling"
  nomad job restart -yes -reschedule "$job" >>"$LOG" 2>&1 || log "leonhard: reschedule failed for $job"
}

main() {
  log "monitor pass start"
  check_codex_tui
  check_oracle_pinned_claude cluster-conductor "$REPO/jobs/cluster-conductor.hcl"
  check_oracle_pinned_claude concierge "$REPO/jobs/concierge.hcl"
  check_leonhard
  log "monitor pass complete"
}

main "$@"
