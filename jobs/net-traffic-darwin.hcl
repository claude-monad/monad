# net-traffic-darwin — per-node tailnet tx/rx publisher for macOS (darwin) nodes.
#
# Companion to jobs/net-traffic.hcl (which is constrained kernel.name=linux). The cluster
# graph renders a directed tournament over the reachable nodes but reported complete=false
# because only the 5 linux nodes published net-traffic: a node only ever sees its OWN tx/rx
# to each peer, so the one pair between the two non-publishers (windesk <-> eliotts-mac-mini)
# was undeterminable. Running a publisher on the darwin node makes that pair observable and
# completes the 7-vertex tournament (21 edges).
#
# READ-ONLY: runs `tailscale status --json` (local view) and records, per peer, the
# cumulative TxBytes/RxBytes into the Nomad var fleet/net-traffic/<node> using the EXACT
# same schema the dashboard already parses (node, ip, host, peer_count, ts, peers_json) —
# so no dashboard / server.py change is needed.
#
# The embedded probe is Python (macOS ships /usr/bin/python3) and contains no ${...}
# sequences, so Nomad HCL2 does not interpolate it. The single env interpolation
# ${node.unique.name} keys the var.
job "net-traffic-darwin" {
  datacenters = ["dc1"]
  type        = "system"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "darwin"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "publish" {
    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "probe" {
      driver = "raw_exec"

      env {
        NODE_NAME  = "${node.unique.name}"
        # Write via the live Nomad leader's HTTP API over the tailnet (the local agent may
        # not listen on 127.0.0.1:4646); var writes forward to the leader.
        NOMAD_ADDR = "http://100.75.75.39:4646"
        INTERVAL   = "60"
      }

      config {
        command = "/usr/bin/env"
        args    = ["python3", "local/netpub.py"]
      }

      template {
        destination = "local/netpub.py"
        perms       = "755"
        data        = <<-SCRIPT
#!/usr/bin/env python3
# read-only per-node (macOS) tailnet tx/rx publisher -> Nomad var fleet/net-traffic/<node>
import json, os, subprocess, datetime, time

NODE = os.environ.get("NODE_NAME", "?")
VAR = "fleet/net-traffic/" + NODE
INTERVAL = int(os.environ.get("INTERVAL", "60") or "60")

# macOS: the tailscale CLI may live in /usr/local/bin or inside the app bundle, and is
# often not on the raw_exec PATH. Try the likely locations (plain + sudo -n).
TS_BINS = [
    "tailscale",
    "/usr/local/bin/tailscale",
    "/opt/homebrew/bin/tailscale",
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    "/Applications/Tailscale.app/Contents/MacOS/tailscale",
]

def ts_json():
    for b in TS_BINS:
        for cmd in ([b, "status", "--json"], ["sudo", "-n", b, "status", "--json"]):
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
                if r.returncode == 0 and r.stdout.strip():
                    return json.loads(r.stdout)
            except Exception:
                continue
    return None

def nomad_bin():
    for b in ("nomad", "/usr/local/bin/nomad", "/opt/homebrew/bin/nomad"):
        try:
            r = subprocess.run([b, "version"], capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                return b
        except Exception:
            continue
    return "nomad"

NOMAD = nomad_bin()

def publish():
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    st = ts_json()
    if not st:
        print("[net-traffic-darwin] %s: tailscale status unavailable" % NODE, flush=True)
        return
    me = st.get("Self") or {}
    self_ip = (me.get("TailscaleIPs") or ["?"])[0]
    peers = {}
    for p in (st.get("Peer") or {}).values():
        ips = p.get("TailscaleIPs") or []
        if not ips:
            continue
        peers[ips[0]] = {
            "host": p.get("HostName", ""),
            "tx": int(p.get("TxBytes") or 0),
            "rx": int(p.get("RxBytes") or 0),
            "online": bool(p.get("Online", False)),
        }
    peers_json = json.dumps(peers, separators=(",", ":"))
    args = [NOMAD, "var", "put", "-force", VAR,
            "node=" + NODE,
            "ip=" + self_ip,
            "host=" + (me.get("HostName", "") or ""),
            "peer_count=" + str(len(peers)),
            "ts=" + now,
            "peers_json=" + peers_json]
    r = subprocess.run(args, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        print("[net-traffic-darwin] %s: var put failed: %s" % (NODE, r.stderr.strip()), flush=True)
    else:
        print("[net-traffic-darwin] %s: published %d peers" % (NODE, len(peers)), flush=True)

print("[net-traffic-darwin] %s: starting (interval %ds, nomad=%s)" % (NODE, INTERVAL, NOMAD), flush=True)
while True:
    try:
        publish()
    except Exception as e:
        print("[net-traffic-darwin] %s: error %s" % (NODE, e), flush=True)
    time.sleep(INTERVAL)
SCRIPT
      }

      resources {
        cpu    = 50
        memory = 64
      }

      kill_timeout = "10s"
    }
  }
}
