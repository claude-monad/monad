#!/bin/bash
# cluster-uptime-check.sh — measure cluster connectivity and Nomad health
# Runs periodically on the server node. Logs to logs/cluster-uptime.jsonl
# and maintains a rolling summary in logs/cluster-uptime-summary.json.
set -uo pipefail

MONAD_DIR="${MONAD_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
UPTIME_LOG="$MONAD_DIR/logs/cluster-uptime.jsonl"
UPTIME_SUMMARY="$MONAD_DIR/logs/cluster-uptime-summary.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Detect Nomad address
if [ -z "${NOMAD_ADDR:-}" ]; then
  MY_IP=$(grep -oP 'bind_addr\s*=\s*"\K[^"]+' /etc/nomad.d/nomad.hcl 2>/dev/null || echo "127.0.0.1")
  NOMAD_ADDR="http://${MY_IP}:4646"
fi
export NOMAD_ADDR

# All known nodes
declare -A NODES
NODES=(
  [windesk]="100.94.210.54"
  [v1410-1]="100.75.75.39"
  [oraclebox1]="100.125.210.126"
  [claudebox]="100.87.219.108"
  [eliotts-mac-mini]="100.113.252.45"
  [death-star]="100.96.31.66"
)

mkdir -p "$(dirname "$UPTIME_LOG")"

# Measure each node
results="[]"
ts_up=0
total=${#NODES[@]}

for node in "${!NODES[@]}"; do
  ip="${NODES[$node]}"

  # Tailscale ping
  ping_out=$(tailscale ping --c 1 --timeout 5s "$ip" 2>&1 || true)
  if echo "$ping_out" | grep -q "pong"; then
    reachable=true
    ts_up=$((ts_up + 1))
    latency=$(echo "$ping_out" | grep -oP 'in \K[0-9]+' | head -1)
    latency="${latency:-0}ms"
  else
    reachable=false
    latency="n/a"
  fi

  # Nomad status for this node
  nomad_status=$(nomad node status -json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    for n in nodes:
        if n.get('Address') == '$ip':
            print(n.get('Status', 'unknown'))
            break
    else:
        print('not-registered')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

  results=$(python3 -c "
import json
r = json.loads('$results'.replace(\"'\", '\"'))
r.append({
    'node': '$node',
    'ip': '$ip',
    'tailscale_reachable': $reachable,
    'latency': '$latency',
    'nomad_status': '$nomad_status'
})
print(json.dumps(r))
" 2>/dev/null || echo "$results")
done

nomad_ready=$(echo "$results" | python3 -c "import sys,json; print(sum(1 for n in json.load(sys.stdin) if n.get('nomad_status')=='ready'))" 2>/dev/null || echo 0)

# Compute percentages
conn_pct=$(python3 -c "print(round($ts_up / $total * 100, 1))")
cluster_pct=$(python3 -c "print(round($nomad_ready / $total * 100, 1))")

# Write event
event=$(python3 -c "
import json
print(json.dumps({
    'timestamp': '$TIMESTAMP',
    'total_nodes': $total,
    'tailscale_up': $ts_up,
    'nomad_ready': $nomad_ready,
    'connectivity_pct': $conn_pct,
    'cluster_pct': $cluster_pct,
    'nodes': $results
}))
" 2>/dev/null)
echo "$event" >> "$UPTIME_LOG"

# Update rolling summary (last 144 entries = ~24h at 10-min intervals)
tail -144 "$UPTIME_LOG" | python3 -c "
import sys, json

entries = []
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            entries.append(json.loads(line))
        except:
            pass

if not entries:
    sys.exit(0)

total_checks = len(entries)
avg_conn = sum(e.get('connectivity_pct', 0) for e in entries) / total_checks
avg_cluster = sum(e.get('cluster_pct', 0) for e in entries) / total_checks

node_up = {}
for e in entries:
    for n in e.get('nodes', []):
        name = n['node']
        if name not in node_up:
            node_up[name] = {'ts_up': 0, 'nomad_up': 0, 'total': 0}
        node_up[name]['total'] += 1
        if n.get('tailscale_reachable'):
            node_up[name]['ts_up'] += 1
        if n.get('nomad_status') == 'ready':
            node_up[name]['nomad_up'] += 1

per_node = {}
for name, c in node_up.items():
    per_node[name] = {
        'tailscale_uptime_pct': round(c['ts_up'] / c['total'] * 100, 1),
        'nomad_uptime_pct': round(c['nomad_up'] / c['total'] * 100, 1),
        'checks': c['total']
    }

summary = {
    'last_updated': entries[-1]['timestamp'],
    'window': f'{total_checks} checks (~{total_checks * 10} min)',
    'avg_connectivity_pct': round(avg_conn, 1),
    'avg_cluster_pct': round(avg_cluster, 1),
    'latest': entries[-1],
    'per_node_24h': per_node
}
with open('$UPTIME_SUMMARY', 'w') as f:
    json.dump(summary, f, indent=2)
" 2>/dev/null

# Print summary
echo "=== Cluster Uptime Check: $TIMESTAMP ==="
echo "  Tailscale reachable: $ts_up / $total ($conn_pct%)"
echo "  Nomad ready:         $nomad_ready / $total ($cluster_pct%)"
echo "$results" | python3 -c "
import sys, json
for n in json.load(sys.stdin):
    icon = 'OK' if n.get('tailscale_reachable') else 'XX'
    print(f\"  [{icon}] {n['node']:20s}  nomad={n.get('nomad_status','?'):15s}  latency={n.get('latency','?')}\")
" 2>/dev/null
