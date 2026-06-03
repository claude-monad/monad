// windesk-tsnet-sidecar — gives windesk its own tsnet node on the Tailnet.
//
// Runs as a persistent service on windesk. The sidecar joins the Tailnet as
// "agent-windesk" and exposes two HTTP APIs:
//
//   MESH  (on Tailnet IP, port 8472) — peers POST /msg to reach this node
//   LOCAL (127.0.0.1:8473) — local agents call /peers, /send, /recv, /whoami
//
// The sidecar binary is pre-compiled for Windows (amd64) and lives in the repo
// at meta/agent/mesh/sidecar/bin/sidecar-windows-amd64.exe. The job does a git
// pull first so windesk always runs the latest binary.
//
// TS_AUTHKEY comes from the Nomad variable secret/agent-mesh.tailscale_authkey.

job "windesk-tsnet-sidecar" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 60

  constraint {
    attribute = "${node.unique.name}"
    value     = "windesk"
  }

  group "sidecar" {
    count = 1

    reschedule {
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = true
    }

    restart {
      attempts = 5
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    task "sidecar" {
      driver = "raw_exec"

      config {
        command = "powershell.exe"
        args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", <<-PS
          $ErrorActionPreference = "Stop"
          function Log($m) { Write-Host "[windesk-tsnet $(Get-Date -Format 'HH:mm:ss')] $m" }

          # Find monad repo (check for scripts/monad or codex-worker — anything that shows the repo)
          $monad = $null
          foreach ($p in @("$env:USERPROFILE\monad", "C:\Users\Eliott\monad", "C:\monad")) {
            if ((Test-Path "$p\scripts\monad") -or (Test-Path "$p\codex-worker\gateway.py")) {
              $monad = $p; break
            }
          }
          if (-not $monad) {
            Log "monad repo not found (tried USERPROFILE\monad, C:\Users\Eliott\monad, C:\monad)"
            exit 1
          }
          Log "monad repo: $monad"

          # Pull latest (to get the tsnet sidecar binary if newly added)
          Push-Location $monad
          try {
            $out = git pull --ff-only 2>&1
            Log "git pull: $($out -join ' ')"
          } catch { Log "git pull skipped: $_" }
          Pop-Location

          $bin = "$monad\meta\agent\mesh\sidecar\bin\sidecar-windows-amd64.exe"
          if (-not (Test-Path $bin)) {
            Log "sidecar binary not found at $bin after git pull — was the commit pushed?"
            exit 1
          }

          Log "starting tsnet sidecar as agent-windesk (mesh :8472, local :8473)"
          $env:AGENT_NAME   = "agent-windesk"
          $env:MESH_PORT    = "8472"
          $env:LOCAL_PORT   = "8473"
          $env:TS_STATE_DIR = "$monad\.tsnet\agent-windesk"
          New-Item -ItemType Directory -Force -Path $env:TS_STATE_DIR | Out-Null

          & $bin
        PS
        ]
      }

      template {
        destination = "secrets/mesh.env"
        env         = true
        data        = <<-TMPL
          TS_AUTHKEY={{ with nomadVar "secret/agent-mesh" }}{{ .tailscale_authkey }}{{ end }}
        TMPL
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
