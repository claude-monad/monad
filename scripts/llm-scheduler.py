#!/usr/bin/env python3
"""llm-scheduler — "Nomad for LLMs": a capacity-aware placement + overload governor.

The cluster's #1 operational rule (owner directive 2026-06-03): **never overload a node.**
A tiny node (oraclebox1: 2 GHz / 5.8 GiB) must not carry the LLM-agent load while a giant
(death-star: 80 cores / 157 GiB) sits idle. This module is the single placement authority and
the overload watchdog. All agent dispatch (assistants, fleet builders, ad-hoc sessions) should
ask `place` where to run, and the periodic `govern` pass flags/prevents overload.

It reads LIVE node load from the Nomad API and a tunable policy from the Nomad var
`cluster/capacity` (the brain's knob — engines per node + caps + headroom thresholds).

Usage:
  llm-scheduler.py report                      # load table + overload flags
  llm-scheduler.py place --engine codex|claude|auto --mem 512   # -> best node name, or QUEUE
  llm-scheduler.py govern [--shed]             # one watchdog pass; --shed stops excess on hot nodes
  llm-scheduler.py policy                       # print effective per-node policy

Env: NOMAD_ADDR (required).
"""
import json, os, sys, argparse, urllib.request, subprocess, time

NOMAD = os.environ.get("NOMAD_ADDR", "http://100.75.75.39:4646")

# --- defaults if cluster/capacity var is absent. The brain edits the var to tune. ---
# engines: which LLM engines are usable on the node. max_agents: hard cap on concurrent
# LLM-agent allocs. cpu_pct/mem_pct: refuse placement above this allocation fraction.
DEFAULT_POLICY = {
    "death-star":  {"engines": ["codex"],            "max_agents": 24, "cpu_pct": 80, "mem_pct": 80},
    "bigo-server": {"engines": ["codex"],            "max_agents": 8,  "cpu_pct": 75, "mem_pct": 75},
    "V1410-1":     {"engines": ["codex"],            "max_agents": 6,  "cpu_pct": 75, "mem_pct": 75},
    "claudebox":   {"engines": ["codex"],            "max_agents": 5,  "cpu_pct": 75, "mem_pct": 75},
    # oraclebox1 is the ONLY claude-credentialed node but is the smallest box: protect it.
    # Reserve it for claude work (concierge/assistants/RC) at a low cap; keep codex off it.
    "oraclebox1":  {"engines": ["claude"],           "max_agents": 4,  "cpu_pct": 70, "mem_pct": 70},
}
# Jobs that are LLM agents (count toward max_agents / are sheddable). Substring match on JobID.
AGENT_JOBS = ("assistant", "fleet-builder", "concierge", "remote-control", "rc-session",
              "math-researcher", "math-quick-compute", "math-reviewer", "math-formalizer",
              "lrc-", "agent-")
# Jobs the governor may force-stop to relieve a hot node. ONLY ephemeral builders / ad-hoc
# agents — NEVER persistent user-facing sessions (concierge/assistant/remote-control count
# toward the cap so a full node refuses NEW work, but they are never killed) and NEVER the
# control plane. If a node is over cap purely from persistent sessions, the governor flags it
# and placement refuses new work — it does not kill what the owner is using.
SHEDDABLE = ("fleet-builder", "agent-builder", "agent-compute", "agent-research")


def api(path, timeout=15, retries=2):
    # Retry once on a transient blip — death-star (the routing target) is across the tailnet and
    # occasionally slow; skipping it would defeat the point of routing work there.
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(NOMAD.rstrip("/") + path, timeout=timeout) as r:
                return json.load(r)
        except Exception:
            if attempt == retries:
                raise
            time.sleep(0.5)


def load_policy():
    try:
        out = subprocess.run(["nomad", "var", "get", "-out=json", "cluster/capacity"],
                             capture_output=True, text=True, timeout=15,
                             env={**os.environ, "NOMAD_ADDR": NOMAD})
        if out.returncode == 0:
            items = json.loads(out.stdout).get("Items", {})
            pol = json.loads(items.get("policy", "{}"))
            if pol:
                return pol
    except Exception:
        pass
    return DEFAULT_POLICY


def node_load():
    """Per-node: total/allocated cpu+mem, running-agent count, status."""
    nodes = {}
    for n in api("/v1/nodes"):
        if n.get("Status") != "ready":
            continue
        nid, name = n["ID"], n["Name"]
        # Tolerate a slow/unreachable node: skip it rather than crash the whole pass (this runs
        # every 5 min as a job — one hung node must not take the governor down).
        try:
            d = api(f"/v1/node/{nid}")
            allocs = api(f"/v1/node/{nid}/allocations")
        except Exception as e:
            print(f"# warn: skipping {name} ({e})", file=sys.stderr)
            continue
        nr = d.get("NodeResources", {})
        tot_cpu = nr.get("Cpu", {}).get("CpuShares", 0) or nr.get("Processors", {}).get("Topology", {}).get("TotalCompute", 0)
        tot_mem = nr.get("Memory", {}).get("MemoryMB", 0)
        a_cpu = a_mem = agents = 0
        for al in allocs:
            if al.get("ClientStatus") != "running":
                continue
            ar = al.get("AllocatedResources", {}) or {}
            for t in (ar.get("Tasks") or {}).values():
                a_cpu += (t.get("Cpu") or {}).get("CpuShares", 0)
                a_mem += (t.get("Memory") or {}).get("MemoryMB", 0)
            if any(s in al.get("JobID", "") for s in AGENT_JOBS):
                agents += 1
        nodes[name] = {"id": nid, "tot_cpu": tot_cpu, "a_cpu": a_cpu,
                       "tot_mem": tot_mem, "a_mem": a_mem, "agents": agents}
    return nodes


def pct(a, t):
    return (100.0 * a / t) if t else 0.0


def evaluate():
    pol = load_policy()
    nodes = node_load()
    rows = []
    for name, ld in nodes.items():
        p = pol.get(name, {"engines": [], "max_agents": 0, "cpu_pct": 75, "mem_pct": 75})
        cp, mp = pct(ld["a_cpu"], ld["tot_cpu"]), pct(ld["a_mem"], ld["tot_mem"])
        # Resource overload is always real; agent-count overload only where a cap is set
        # (nodes absent from policy have cap 0 = "not a placement target", not "overloaded").
        over = (cp > p["cpu_pct"] or mp > p["mem_pct"]
                or (p["max_agents"] > 0 and ld["agents"] > p["max_agents"]))
        rows.append({"name": name, **ld, **p, "cpu_used": cp, "mem_used": mp, "over": over})
    return sorted(rows, key=lambda r: r["mem_used"])


def cmd_report(_):
    rows = evaluate()
    print(f"{'NODE':<13}{'CPU':>14}{'MEM':>16}{'AGENTS':>9}  ENGINES        STATE")
    for r in rows:
        cpu = f"{r['cpu_used']:.0f}%/{r['cpu_pct']}%"
        mem = f"{r['mem_used']:.0f}%/{r['mem_pct']}% ({r['tot_mem']//1024}G)"
        ag = f"{r['agents']}/{r['max_agents']}"
        state = "🔴 OVERLOAD" if r["over"] else ("🟡 busy" if r["mem_used"] > r["mem_pct"]*0.7 else "🟢 ok")
        print(f"{r['name']:<13}{cpu:>14}{mem:>16}{ag:>9}  {','.join(r['engines']) or '-':<14} {state}")
    hot = [r["name"] for r in rows if r["over"]]
    if hot:
        print(f"\nOVERLOADED: {', '.join(hot)} — placement will avoid these; run `govern --shed` to relieve.")


def cmd_policy(_):
    print(json.dumps(load_policy(), indent=2))


def score(r, mem):
    """Lower is better: prefer most free memory headroom (absolute) then lowest cpu%."""
    free_mem = r["tot_mem"] - r["a_mem"]
    return (-free_mem, r["cpu_used"])


def cmd_place(a):
    rows = evaluate()
    want = a.engine
    cands = []
    for r in rows:
        if r["over"]:
            continue
        if r["a_mem"] + a.mem > r["tot_mem"] * (r["mem_pct"] / 100.0):
            continue
        if r["agents"] >= r["max_agents"]:
            continue
        engines = r["engines"]
        if want == "auto":
            if not engines:
                continue
        elif want not in engines:
            continue
        cands.append(r)
    if not cands:
        # Backpressure: tell the caller to queue rather than pile onto a hot node.
        print("QUEUE")
        return 3
    best = sorted(cands, key=lambda r: score(r, a.mem))[0]
    # When engine=auto, also surface which engine to use on the chosen node.
    eng = a.engine if a.engine != "auto" else best["engines"][0]
    print(best["name"] if a.quiet else f"{best['name']} {eng}")
    return 0


def cmd_govern(a):
    rows = evaluate()
    hot = [r for r in rows if r["over"]]
    if not hot:
        print("govern: all nodes within capacity 🟢")
        return 0
    for r in hot:
        print(f"govern: 🔴 {r['name']} over capacity "
              f"(cpu {r['cpu_used']:.0f}%/{r['cpu_pct']}%, mem {r['mem_used']:.0f}%/{r['mem_pct']}%, "
              f"agents {r['agents']}/{r['max_agents']})")
    if not a.shed:
        print("govern: report-only (pass --shed to stop sheddable excess on hot nodes)")
        return 0
    # Shed: on each hot node, stop the most-recently-started sheddable agent allocs until
    # under cap. Conservative — only AGENT_JOBS not in PROTECTED, and never the last one.
    for r in hot:
        allocs = api(f"/v1/node/{r['id']}/allocations")
        sheddable = sorted(
            [al for al in allocs if al.get("ClientStatus") == "running"
             and any(s in al.get("JobID", "") for s in SHEDDABLE)],
            key=lambda al: al.get("CreateTime", 0), reverse=True)
        need = max(r["agents"] - r["max_agents"], 0)
        for al in sheddable[:need]:
            jid = al["JobID"]
            print(f"govern: shedding {jid} on {r['name']} (over cap)")
            subprocess.run(["nomad", "alloc", "stop", al["ID"]],
                           env={**os.environ, "NOMAD_ADDR": NOMAD},
                           capture_output=True, text=True, timeout=30)
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("report").set_defaults(fn=cmd_report)
    sub.add_parser("policy").set_defaults(fn=cmd_policy)
    p = sub.add_parser("place"); p.set_defaults(fn=cmd_place)
    p.add_argument("--engine", default="auto", choices=["auto", "codex", "claude"])
    p.add_argument("--mem", type=int, default=512)
    p.add_argument("--quiet", action="store_true")
    g = sub.add_parser("govern"); g.set_defaults(fn=cmd_govern)
    g.add_argument("--shed", action="store_true")
    args = ap.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
