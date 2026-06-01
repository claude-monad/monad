#!/usr/bin/env python3
"""Cluster uptime check — measure Tailscale + Nomad health for all known nodes."""
import json, os, subprocess, sys
from datetime import datetime, timezone

KNOWN_NODES = {
    "windesk":          "100.94.210.54",
    "v1410-1":          "100.75.75.39",
    "oraclebox1":       "100.125.210.126",
    "claudebox":        "100.87.219.108",
    "eliotts-mac-mini": "100.113.252.45",
    "death-star":       "100.96.31.66",
}

def run(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout + r.stderr, r.returncode
    except Exception:
        return "", 1

def get_nomad_nodes():
    """Query Nomad for all registered nodes."""
    out, rc = run(["nomad", "node", "status", "-json"])
    if rc != 0:
        return {}
    try:
        nodes = json.loads(out)
        return {n["Address"]: n.get("Status", "unknown") for n in nodes}
    except Exception:
        return {}

def local_ips():
    """This machine's own Tailscale IP(s). A node cannot tailscale-ping itself, so
    the node running this check must count itself reachable or it undercounts."""
    out, rc = run(["tailscale", "ip", "-4"])
    if rc != 0:
        return set()
    return {l.strip() for l in out.splitlines() if l.strip()}

def ping_node(ip, selfset=frozenset()):
    """Tailscale ping a node, return (reachable, latency_ms). The local node is
    counted reachable directly (Tailscale cannot ping the host it runs on)."""
    if ip in selfset:
        return True, "0ms (self)"
    out, rc = run(["tailscale", "ping", "--c", "1", "--timeout", "5s", ip])
    if "pong" in out:
        import re
        m = re.search(r"in (\d+)ms", out)
        latency = f"{m.group(1)}ms" if m else "unknown"
        return True, latency
    return False, "n/a"

def main():
    monad_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    log_file = os.path.join(monad_dir, "logs", "cluster-uptime.jsonl")
    summary_file = os.path.join(monad_dir, "logs", "cluster-uptime-summary.json")
    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    nomad_nodes = get_nomad_nodes()

    selfset = local_ips()
    results = []
    ts_up = 0
    for name, ip in KNOWN_NODES.items():
        reachable, latency = ping_node(ip, selfset)
        if reachable:
            ts_up += 1
        nomad_status = nomad_nodes.get(ip, "not-registered")
        results.append({
            "node": name,
            "ip": ip,
            "tailscale_reachable": reachable,
            "latency": latency,
            "nomad_status": nomad_status,
        })

    total = len(KNOWN_NODES)
    nomad_ready = sum(1 for r in results if r["nomad_status"] == "ready")
    conn_pct = round(ts_up / total * 100, 1)
    cluster_pct = round(nomad_ready / total * 100, 1)

    event = {
        "timestamp": timestamp,
        "total_nodes": total,
        "tailscale_up": ts_up,
        "nomad_ready": nomad_ready,
        "connectivity_pct": conn_pct,
        "cluster_pct": cluster_pct,
        "nodes": results,
    }

    # Append event
    with open(log_file, "a") as f:
        f.write(json.dumps(event) + "\n")

    # Rolling summary (last 144 entries ≈ 24h at 10-min intervals)
    try:
        with open(log_file) as f:
            lines = f.readlines()
        entries = []
        for line in lines[-144:]:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except Exception:
                    pass

        if entries:
            avg_conn = sum(e.get("connectivity_pct", 0) for e in entries) / len(entries)
            avg_cluster = sum(e.get("cluster_pct", 0) for e in entries) / len(entries)

            node_up = {}
            for e in entries:
                for n in e.get("nodes", []):
                    nm = n["node"]
                    if nm not in node_up:
                        node_up[nm] = {"ts_up": 0, "nomad_up": 0, "total": 0}
                    node_up[nm]["total"] += 1
                    if n.get("tailscale_reachable"):
                        node_up[nm]["ts_up"] += 1
                    if n.get("nomad_status") == "ready":
                        node_up[nm]["nomad_up"] += 1

            per_node = {}
            for nm, c in node_up.items():
                per_node[nm] = {
                    "tailscale_uptime_pct": round(c["ts_up"] / c["total"] * 100, 1),
                    "nomad_uptime_pct": round(c["nomad_up"] / c["total"] * 100, 1),
                    "checks": c["total"],
                }

            summary = {
                "last_updated": entries[-1]["timestamp"],
                "window": f"{len(entries)} checks (~{len(entries) * 10} min)",
                "avg_connectivity_pct": round(avg_conn, 1),
                "avg_cluster_pct": round(avg_cluster, 1),
                "latest": entries[-1],
                "per_node_24h": per_node,
            }
            with open(summary_file, "w") as f:
                json.dump(summary, f, indent=2)
    except Exception:
        pass

    # Print
    print(f"=== Cluster Uptime Check: {timestamp} ===")
    print(f"  Tailscale reachable: {ts_up} / {total} ({conn_pct}%)")
    print(f"  Nomad ready:         {nomad_ready} / {total} ({cluster_pct}%)")
    for r in results:
        icon = "OK" if r["tailscale_reachable"] else "XX"
        print(f"  [{icon}] {r['node']:20s}  nomad={r['nomad_status']:15s}  latency={r['latency']}")

if __name__ == "__main__":
    main()
