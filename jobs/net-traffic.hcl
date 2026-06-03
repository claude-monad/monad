# net-traffic — per-node tailnet tx/rx publisher for the dashboard cluster graph.
#
# READ-ONLY: each node runs `tailscale status --json` (its LOCAL view) and records,
# per peer, the cumulative TxBytes/RxBytes counters into the Nomad var
# fleet/net-traffic/<node>. The cluster-dashboard reads every such var and assembles
# a pairwise traffic matrix to orient the cluster "tournament" (one directed edge per
# node pair, pointing from whichever node sent more to the other; weight = volume).
#
# Why a SYSTEM job: tailscale tx/rx is only visible from the local node's own view, so
# this must run on every node it measures (a central periodic job can't see it). One
# node's view of a peer already carries BOTH directions (tx = self→peer, rx = peer→self),
# so even a single publisher yields edges; with every node publishing the matrix is
# cross-checked. Constrained to linux + raw_exec (windesk/mac-mini still appear as graph
# vertices, just without traffic edges).
#
# The embedded probe is Python and contains no ${...} sequences, so Nomad HCL2 does not
# try to interpolate it. The single env interpolation ${node.unique.name} keys the var.
job "net-traffic" {
  datacenters = ["dc1"]
  type        = "system"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
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
        NOMAD_ADDR = "http://127.0.0.1:4646"
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
# read-only per-node tailnet tx/rx publisher -> Nomad var fleet/net-traffic/<node>
import json, os, subprocess, datetime, time

NODE = os.environ.get("NODE_NAME", "?")
VAR = "fleet/net-traffic/" + NODE
INTERVAL = int(os.environ.get("INTERVAL", "60") or "60")

def ts_json():
    for cmd in (["tailscale", "status", "--json"],
                ["sudo", "-n", "tailscale", "status", "--json"]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            if r.returncode == 0 and r.stdout.strip():
                return json.loads(r.stdout)
        except Exception:
            continue
    return None

def publish():
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    st = ts_json()
    if not st:
        print("[net-traffic] %s: tailscale status unavailable" % NODE, flush=True)
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
    args = ["nomad", "var", "put", "-force", VAR,
            "node=" + NODE,
            "ip=" + self_ip,
            "host=" + (me.get("HostName", "") or ""),
            "peer_count=" + str(len(peers)),
            "ts=" + now,
            "peers_json=" + peers_json]
    r = subprocess.run(args, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        print("[net-traffic] %s: var put failed: %s" % (NODE, r.stderr.strip()), flush=True)
    else:
        print("[net-traffic] %s: published %d peers" % (NODE, len(peers)), flush=True)

print("[net-traffic] %s: starting (interval %ds)" % (NODE, INTERVAL), flush=True)
while True:
    try:
        publish()
    except Exception as e:
        print("[net-traffic] %s: error %s" % (NODE, e), flush=True)
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
