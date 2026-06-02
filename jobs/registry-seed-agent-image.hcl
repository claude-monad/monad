job "registry-seed-agent-image" {
  datacenters = ["dc1"]
  type        = "batch"

  # Must run on oraclebox1: that's where the current monad-agent-mesh image lives
  # (its localhost:5000) and where docker is confirmed. One-shot stopgap to seed the
  # shared registry so agent-mesh.hcl can flip off localhost:5000 without breaking.
  # Superseded the moment the multiarch build pushes the same tag.
  constraint {
    attribute = "${node.unique.name}"
    value     = "oraclebox1"
  }

  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "seed" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "seed" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/seed.sh"]
      }

      template {
        destination = "local/trust.py"
        perms       = "644"
        data        = <<PY
import json, os, sys
addr = sys.argv[1]; path = "/etc/docker/daemon.json"
d = {}
if os.path.exists(path):
    try:
        d = json.load(open(path)) or {}
    except Exception:
        d = {}
lst = d.get("insecure-registries") or []
if addr not in lst:
    lst.append(addr)
    d["insecure-registries"] = lst
    json.dump(d, open(path, "w"), indent=2)
    print("ADDED")
else:
    print("ALREADY-TRUSTED")
PY
      }

      template {
        destination = "local/seed.sh"
        perms       = "755"
        data        = <<SCRIPT
#!/bin/bash
set -uo pipefail
ADDR="100.78.218.70:5000"
SRC="localhost:5000/monad-agent-mesh:latest"
DST="$ADDR/monad-agent-mesh:latest"
echo "=== seed agent image on $(hostname): $SRC -> $DST ==="

# 1. trust the shared registry on this node (live reload, no container restart)
python3 local/trust.py "$ADDR"
systemctl reload docker 2>/dev/null || kill -HUP "$(pidof dockerd)" 2>/dev/null || true
sleep 2

# 2. pull the current node-local image, retag, push to the shared registry
docker pull "$SRC" || { echo "FAIL: $SRC not present in localhost:5000"; exit 1; }
docker tag "$SRC" "$DST"
docker push "$DST" || { echo "FAIL: push to shared registry"; exit 1; }
echo "SEED-OK: $DST is now in the shared registry"
echo "=== seed done ==="
SCRIPT
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
