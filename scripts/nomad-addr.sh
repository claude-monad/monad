#!/usr/bin/env bash
# nomad-addr.sh — resolve NOMAD_ADDR to a Nomad server that is actually reachable.
#
# Source this, then call resolve_nomad_addr. It exports NOMAD_ADDR.
#
# Why this exists: the server set is {v1410-1, claudebox} (+ oraclebox1 as a client/
# former voter). Whichever one is down still answers TCP nowhere, and every `nomad`
# CLI call against a dead server blocks ~30s before failing. node-doctor and the
# maintenance-agent make several such calls per pass, so a dead default turned every
# self-pass into a timeout (rc=1). Pointing at a *live* server does not restore quorum,
# but it fails in ~5s with an honest "No cluster leader" instead of hanging.
#
# An explicitly-set NOMAD_ADDR still wins whenever it is reachable — this only falls
# through when the configured server does not answer, so callers (and job env blocks)
# keep control without being able to wedge the cluster's own maintenance loop.

# Candidate servers, in preference order: intended leader first, then the rest.
NOMAD_ADDR_CANDIDATES="${NOMAD_ADDR_CANDIDATES:-100.75.75.39 100.87.219.108 100.125.210.126}"

# TCP-connect probe. Deliberately not an HTTP probe: with no Raft leader the HTTP API
# takes ~5s to answer, while a TCP connect to a live agent returns in milliseconds and
# to a dead one fails fast. We want reachability here, not health.
_nomad_addr_reachable() {
    local host="$1" port="${2:-4646}"
    timeout 2 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null
}

resolve_nomad_addr() {
    local configured="${NOMAD_ADDR:-}"

    if [ -n "$configured" ]; then
        local hostport="${configured#*://}"
        hostport="${hostport%%/*}"
        local host="${hostport%%:*}"
        local port="${hostport##*:}"
        [ "$port" = "$host" ] && port=4646
        if _nomad_addr_reachable "$host" "$port"; then
            export NOMAD_ADDR="$configured"
            return 0
        fi
    fi

    local cand
    for cand in $NOMAD_ADDR_CANDIDATES; do
        if _nomad_addr_reachable "$cand"; then
            export NOMAD_ADDR="http://${cand}:4646"
            [ -n "$configured" ] && [ "$NOMAD_ADDR" != "$configured" ] && \
                echo "[nomad-addr] ${configured} unreachable — using ${NOMAD_ADDR}" >&2
            return 0
        fi
    done

    # Nothing answered. Keep whatever was configured (or the first candidate) so the
    # caller's own error handling reports a real failure rather than an empty address.
    export NOMAD_ADDR="${configured:-http://${NOMAD_ADDR_CANDIDATES%% *}:4646}"
    return 1
}
