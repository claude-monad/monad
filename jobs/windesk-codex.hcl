// windesk-codex — codex HTTP gateway on windesk (Windows amd64, raw_exec).
//
// Starts the gateway.py text front door for codex on windesk and binds it to
// windesk's Tailscale IP (100.94.210.54:8300). Clients POST to /ask with plain
// text or JSON to get codex replies. Mirrors the Linux codex-worker for the cluster
// but adapted for Windows paths and PowerShell.
//
// Reach it (once running):
//   curl -sX POST http://100.94.210.54:8300/ask -d "What is the Lonely Runner Conjecture?"
//   curl -s http://100.94.210.54:8300/health
//
// Type: service (persistent, auto-restarts).

job "windesk-codex" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 60

  constraint {
    attribute = "${node.unique.name}"
    value     = "windesk"
  }

  group "gateway" {
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

    network {
      mode = "host"
      port "http" {
        static = 8300
      }
    }

    task "gateway" {
      driver = "raw_exec"

      config {
        command = "powershell.exe"
        args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", <<-PS
          $ErrorActionPreference = "Continue"
          function Log($m) { Write-Host "[windesk-codex $(Get-Date -Format 'HH:mm:ss')] $m" }

          # Find monad repo
          $monad = $null
          foreach ($p in @("$env:USERPROFILE\monad", "C:\Users\Eliott\monad", "C:\monad")) {
            if (Test-Path "$p\codex-worker\gateway.py") {
              $monad = $p; break
            }
          }
          if (-not $monad) { Log "monad repo not found"; exit 1 }
          Log "monad: $monad"

          # Resolve codex binary
          $codex = $null
          foreach ($c in @("codex", "$env:APPDATA\npm\codex.cmd", "$env:USERPROFILE\AppData\Roaming\npm\codex.cmd")) {
            try { $r = Get-Command $c -ErrorAction Stop; $codex = $c; break } catch {}
          }
          if (-not $codex) { Log "codex not found in PATH; is @openai/codex installed?"; exit 1 }
          Log "codex: $codex"

          # Resolve Python
          $py = $null
          foreach ($p in @("python", "python3", "py")) {
            try { Get-Command $p -ErrorAction Stop | Out-Null; $py = $p; break } catch {}
          }
          if (-not $py) { Log "python not found"; exit 1 }

          # Bind to Tailscale IP
          $tsip = "100.94.210.54"
          try {
            $out = & tailscale ip -4 2>&1
            if ($LASTEXITCODE -eq 0 -and $out -match "\d+\.\d+\.\d+\.\d+") {
              $tsip = ($out -split "`n")[0].Trim()
            }
          } catch {}
          Log "binding to $tsip:8300"

          $env:CODEX_BIND    = $tsip
          $env:CODEX_PORT    = "8300"
          $env:CODEX_WORKDIR = $monad
          $env:CODEX_SANDBOX = "bypass"
          $env:CODEX_BIN     = $codex
          $env:PATH          = "$env:USERPROFILE\AppData\Roaming\npm;$env:PATH"

          Log "starting gateway.py"
          & $py "$monad\codex-worker\gateway.py"
        PS
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
