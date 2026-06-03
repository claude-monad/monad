job "account-manager" {
  datacenters = ["dc1"]
  type        = "system"

  # Linux nodes — clone monad repo to get the script, then run it
  group "linux" {
    constraint {
      attribute = "${attr.kernel.name}"
      value     = "linux"
    }

    network {
      port "http" {
        static = 7700
      }
    }

    service {
      name     = "account-manager"
      port     = "http"
      provider = "nomad"
    }

    task "server" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", <<EOT
# Use a fresh alloc-local clone so Linux nodes do not run stale host checkouts.
REPO="$NOMAD_TASK_DIR/monad"
rm -rf "$REPO"
git clone --depth 1 https://github.com/eliott-monad/monad "$REPO" >/dev/null \
  || { echo "[account-manager] clone failed; falling back to raw script"; mkdir -p /tmp/monad-am; curl -fsSL https://raw.githubusercontent.com/eliott-monad/monad/main/scripts/account-manager.py -o /tmp/monad-am/account-manager.py; REPO="/tmp/monad-am"; }
SCRIPT="$REPO/scripts/account-manager.py"
if [ ! -f "$SCRIPT" ]; then
  SCRIPT="$REPO/account-manager.py"
fi
exec python3 "$SCRIPT"
EOT
        ]
      }

      env {
        ACCOUNT_MANAGER_PORT        = "${NOMAD_PORT_http}"
        ACCOUNT_MANAGER_CLEAN_STALE = "1"
        NOMAD_ADDR                  = "http://100.87.219.108:4646"
        HOME                        = "/root"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }

  # Windows nodes — use local path (windesk has the repo cloned)
  group "windows" {
    constraint {
      attribute = "${attr.kernel.name}"
      value     = "windows"
    }

    network {
      port "http" {
        static = 7700
      }
    }

    service {
      name     = "account-manager"
      port     = "http"
      provider = "nomad"
    }

    task "server" {
      driver = "raw_exec"

      config {
        command = "python3"
        args    = ["C:\\Users\\Eliott\\monad\\scripts\\account-manager.py"]
      }

      env {
        ACCOUNT_MANAGER_PORT = "${NOMAD_PORT_http}"
        NOMAD_ADDR           = "http://100.87.219.108:4646"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
