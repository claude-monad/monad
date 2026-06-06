#!/usr/bin/env bash
# math-campaign.sh — keep a BUNCH of Claude explorer sessions running on a focused, long-running
# research campaign (e.g. the signed-LRC push). Reads the campaign brief from a Nomad var and
# tops up math-explore sessions to TARGET concurrent, governor-admitted, each with a distinct
# angle so they don't duplicate. Run periodically (jobs/math-campaign.hcl) until the campaign's
# `active` is set false — that's how it "spends a long time" without manual nudging.
#
# Coexists with math-explore-watch (commit-driven): both feed the math-explore job and both
# count the shared running total, so concurrency stays bounded. Cost: TARGET concurrent deep
# Claude sessions on the single Max account — keep TARGET modest; the governor caps by capacity.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"; export NOMAD_ADDR

CAMPAIGN_VAR="${CAMPAIGN_VAR:-monad/campaign/signed-lrc}"
EXPLORE_JOB="${EXPLORE_JOB:-math-explore}"
TARGET="${TARGET:-4}"          # desired concurrent explorers on this campaign
PER_PASS="${PER_PASS:-3}"      # max to launch in one top-up pass
log() { echo "[campaign $(date '+%H:%M:%S')] $*"; }

active="$(nomad var get -item=active "$CAMPAIGN_VAR" 2>/dev/null || true)"
[ "$active" = "true" ] || { log "campaign $CAMPAIGN_VAR inactive — nothing to do"; exit 0; }
seed="$(nomad var get -item=seed "$CAMPAIGN_VAR" 2>/dev/null || true)"
[ -n "$seed" ] || { log "no seed in $CAMPAIGN_VAR"; exit 0; }

ANGLES=(
  " YOUR ANGLE: exhaustive small-n (n=2..6) — enumerate sign-reversal patterns, rigorously find the optimal gap at each, tabulate which patterns beat 3n."
  " YOUR ANGLE: the 2D-realizable group spectrum between the triangular lattice (kappa=6) and the CM field — characterize norm-1 layers and exactly where they beat 3n at moderate n."
  " YOUR ANGLE: structural reduction — how signed-LRC witnesses/bounds transfer to the regular LRC; what does a signed counterexample or tight configuration imply for the unsigned problem?"
  " YOUR ANGLE: counterexample / extremal hunting at moderate n with creative sign patterns; try to refute or sharpen the standing signed-LRC hypotheses with computation."
  " YOUR ANGLE: cross-domain — CM fields, norm forms, the formal group F(x,y), Krawtchouk; develop a connection the recent signed-LRC work suggests into a concrete result."
)

running="$(nomad job status "$EXPLORE_JOB" 2>/dev/null | grep -cE '\brunning\b' || echo 0)"
want=$(( TARGET - running ))
if [ "$want" -lt 1 ]; then log "$running explorer(s) running (target $TARGET) — no top-up"; exit 0; fi
[ "$want" -gt "$PER_PASS" ] && want="$PER_PASS"
log "topping up: $running running, launching up to $want (target $TARGET)"

spawned=0
off=$(( RANDOM % ${#ANGLES[@]} ))   # random start, then rotate — distinct angles within a pass
for i in $(seq 1 "$want"); do
  node="$(python3 "$REPO_DIR/scripts/llm-scheduler.py" place --engine claude --mem 1024 --quiet 2>/dev/null)"
  if [ -z "$node" ] || [ "$node" = "QUEUE" ]; then
    log "governor: no Claude capacity right now — holding ($spawned launched this pass)"; break
  fi
  angle="${ANGLES[$(( (off + i) % ${#ANGLES[@]} ))]}"
  if nomad job dispatch -detach -meta "seed=$seed" -meta "angle=$angle" "$EXPLORE_JOB" >/dev/null 2>&1; then
    log "launched explorer (governor node hint: $node)"; spawned=$((spawned+1))
  else
    log "WARN: dispatch failed"
  fi
  sleep 2
done
log "pass done: $spawned launched ($(( running + spawned ))/$TARGET running on campaign $CAMPAIGN_VAR)"
