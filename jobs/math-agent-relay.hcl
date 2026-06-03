// math-agent-relay: tsnet IPC relay for the math research agent network.
//
// Runs as a system job on every node that has a math agent identity (windesk, mac-mini).
// Each instance advertises as `math-relay-<machine-id>` on the Tailnet and exposes:
//   POST /send          — accept a message (also writes to agents/<id>/inbox/ in the math repo)
//   GET  /messages      — list pending messages
//   POST /messages/{id}/read — mark a message read
//
// The binary is compiled from monad/meta/tsnet-relay/ and placed at the standard tool path.
// Build on each machine: cd ~/monad/meta/tsnet-relay && go build -o ~/monad/bin/math-agent-relay .
// OR let fleet-builder build it from the Dockerfile in meta/tsnet-relay/.

job "math-agent-relay" {
  datacenters = ["dc1"]
  type        = "system"

  // Only run on nodes that have joined as math research agents.
  // Tag your Nomad client with: meta { math_agent = "true" }
  constraint {
    attribute = "${meta.math_agent}"
    value     = "true"
  }

  group "relay" {
    task "relay" {
      driver = "raw_exec"

      config {
        // The binary is placed by the bootstrap or fleet-builder.
        // Falls back to go run for development.
        command = "/bin/bash"
        args    = ["-c", <<-CMD
          set -e
          BIN=""
          for p in $HOME/monad/bin/math-agent-relay /usr/local/bin/math-agent-relay; do
            [ -x "$p" ] && BIN=$p && break
          done
          if [ -z "$BIN" ]; then
            # development fallback: go run from the source
            for u in ubuntu bigo e eliott; do
              home=$(getent passwd $u 2>/dev/null | cut -d: -f6)
              [ -n "$home" ] || continue
              src="$home/monad/meta/tsnet-relay"
              [ -d "$src" ] || continue
              BIN="go run $src/."
              break
            done
          fi
          [ -n "$BIN" ] || { echo "math-agent-relay binary not found"; exit 1; }

          # Resolve machine ID and repo root
          MACHINE_ID=""
          REPO_ROOT=""
          for u in ubuntu bigo e eliott; do
            home=$(getent passwd $u 2>/dev/null | cut -d: -f6)
            [ -n "$home" ] || continue
            for repo in $home/monad/../math $home/Documents/GitHub/math; do
              [ -f "$repo/.machine-id" ] || continue
              MACHINE_ID=$(cat "$repo/.machine-id" | tr -d '[:space:]')
              REPO_ROOT="$repo"
              break 2
            done
          done

          [ -n "$MACHINE_ID" ] || { echo "could not find .machine-id"; exit 1; }

          exec $BIN --machine "$MACHINE_ID" --repo "$REPO_ROOT" --port 7373
        CMD
        ]
      }

      env {
        // TS_AUTHKEY is injected from a Nomad variable.
        // Set it once: nomad var put nomad/jobs/math-agent-relay ts_authkey=<your-key>
        TS_AUTHKEY = "${NOMAD_VAR_ts_authkey}"
      }

      resources {
        cpu    = 100
        memory = 128
      }

      // Restart indefinitely — this is a persistent relay.
      restart {
        attempts = 0
        mode     = "delay"
        delay    = "15s"
        interval = "1h"
      }
    }
  }
}
