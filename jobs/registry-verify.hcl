job "registry-verify" {
  datacenters = ["dc1"]
  type        = "batch"

  # Run on a DIFFERENT node than the registry host (bigo-server) to prove the
  # registry is usable cross-node over the tailnet. V1410-1: amd64, ample disk.
  constraint {
    attribute = "${node.unique.name}"
    value     = "V1410-1"
  }

  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "verify" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "verify" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/verify.sh"]
      }

      # JSON edit kept in its own file so there is no nested heredoc inside the HCL.
      # Heredoc is flush-left (plain <<) so Python sees no leading indentation.
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
        destination = "local/verify.sh"
        perms       = "755"
        data        = <<SCRIPT
#!/bin/bash
set -uo pipefail
ADDR="100.78.218.70:5000"
IMG="$ADDR/registry-verify:alpine"
echo "=== registry-verify on $(hostname) -> $ADDR ==="

# 1. trust the shared registry (live reload, no container restart)
python3 local/trust.py "$ADDR"
systemctl reload docker 2>/dev/null || kill -HUP "$(pidof dockerd)" 2>/dev/null || true
sleep 2

# 2. seed: pull a tiny public image, retag, push over the tailnet
echo "--- seeding $IMG ---"
docker pull alpine:latest || { echo "FAIL: cannot pull alpine from docker hub"; exit 1; }
docker tag alpine:latest "$IMG"
docker push "$IMG" || { echo "FAIL: push to shared registry"; exit 1; }

# 3. drop the local copy, then pull it back FROM the shared registry
echo "--- pulling back from shared registry ---"
docker rmi "$IMG" >/dev/null 2>&1 || true
if docker pull "$IMG"; then
  echo "VERIFY-OK: pulled $IMG from the shared registry over the tailnet"
else
  echo "FAIL: could not pull $IMG from shared registry"
  exit 1
fi
docker rmi "$IMG" >/dev/null 2>&1 || true
echo "=== registry-verify done ==="
SCRIPT
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
