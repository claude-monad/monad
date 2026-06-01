# claudebox-diagnose — delegate claudebox diagnosis to windesk (its LAN neighbor).
#
# claudebox (100.87.219.108) is unreachable over Tailscale (relay only, rx 0), so the
# control plane on oraclebox1 cannot probe it directly. windesk shares claudebox's LAN, so
# we run the probe THERE. This is diagnosis-first: it discovers claudebox's LAN address from
# Tailscale peer endpoints, tests reachability + key ports, writes a report into the repo
# (logs/claudebox-diag/) and to alloc logs, and prints the recommended revival commands.
#
# Run:    monad deploy jobs/claudebox-diagnose.hcl    (or: nomad job run jobs/claudebox-diagnose.hcl)
# Read:   nomad alloc logs <alloc>   /   logs/claudebox-diag/*-windesk.txt (after sync)
# Re-run: nomad job run jobs/claudebox-diagnose.hcl   (batch — re-dispatches a fresh probe)

job "claudebox-diagnose" {
  datacenters = ["dc1"]
  type        = "batch"

  # Pin to windesk specifically — it is the node on claudebox's LAN.
  constraint {
    attribute = "${node.unique.name}"
    value     = "windesk"
  }

  group "diag" {
    count = 1

    restart {
      attempts = 1
      interval = "5m"
      delay    = "30s"
      mode     = "fail"
    }

    task "probe" {
      driver = "raw_exec"

      template {
        destination = "local/diagnose.ps1"
        data        = <<-SCRIPT
          $ErrorActionPreference = "SilentlyContinue"
          $TS_IP   = "100.87.219.108"
          $NAME    = "claudebox"
          $REPO    = $env:MONAD_REPO_DIR; if (-not $REPO) { $REPO = "C:/Users/Eliott/monad" }
          $stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
          $report  = New-Object System.Collections.ArrayList
          function R($m) { $ts = Get-Date -Format "HH:mm:ss"; $line = "[$ts] $m"; Write-Output $line; [void]$report.Add($line) }

          R "=== claudebox diagnosis from windesk ($env:COMPUTERNAME) ==="
          R "target: $NAME tailscale=$TS_IP"

          # --- 1. Tailscale's view of claudebox (peer endpoints reveal LAN addrs) ---
          $lanCandidates = New-Object System.Collections.ArrayList
          try {
            $ts = & tailscale status --json 2>$null | ConvertFrom-Json
            R "windesk tailscale backend: $($ts.BackendState)"
            $peer = $ts.Peer.PSObject.Properties.Value | Where-Object { $_.HostName -eq $NAME -or $_.TailscaleIPs -contains $TS_IP }
            if ($peer) {
              R "claudebox peer: Online=$($peer.Online) Relay=$($peer.Relay) CurAddr=$($peer.CurAddr) LastSeen=$($peer.LastSeen)"
              foreach ($a in @($peer.CurAddr) + @($peer.Addrs)) {
                if ($a) {
                  $ip = ($a -split ":")[0]
                  if ($ip -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)') {
                    if (-not $lanCandidates.Contains($ip)) { [void]$lanCandidates.Add($ip) }
                  }
                }
              }
            } else { R "WARN: claudebox not found among tailscale peers" }
          } catch { R "WARN: could not parse tailscale status: $_" }
          R "LAN candidate IPs from tailscale endpoints: $($lanCandidates -join ', ')"

          # --- 2. Hostname resolution on the LAN (mDNS / NetBIOS / DNS) ---
          foreach ($n in @($NAME, "$NAME.local")) {
            $r = Resolve-DnsName $n -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress }
            foreach ($rec in $r) {
              R "resolved $n -> $($rec.IPAddress)"
              if ($rec.IPAddress -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' -and -not $lanCandidates.Contains($rec.IPAddress)) {
                [void]$lanCandidates.Add($rec.IPAddress)
              }
            }
          }

          # --- 3. Tailscale-level reachability ---
          R "--- tailscale ping ---"
          $tp = & tailscale ping --c 2 --timeout 3s $NAME 2>&1 | Select-Object -First 4
          foreach ($l in $tp) { R "  $l" }

          # --- 4. Probe every reachable address (tailscale IP + LAN candidates) ---
          $targets = @($TS_IP) + $lanCandidates | Select-Object -Unique
          foreach ($t in $targets) {
            R "--- probing $t ---"
            $ping = Test-Connection -ComputerName $t -Count 2 -Quiet -ErrorAction SilentlyContinue
            R "  icmp: $(if ($ping) {'UP'} else {'no reply'})"
            foreach ($p in @(22, 4646, 4647, 4648)) {
              $tc = Test-NetConnection -ComputerName $t -Port $p -WarningAction SilentlyContinue
              R "  tcp/${p}: $(if ($tc.TcpTestSucceeded) {'OPEN'} else {'closed/filtered'})"
            }
          }

          # --- 5. Verdict + recommended revival ---
          R "=== verdict ==="
          if ($targets | Where-Object { Test-Connection $_ -Count 1 -Quiet -ErrorAction SilentlyContinue }) {
            R "claudebox IS reachable from windesk on at least one address (see above)."
            R "Revival (run on claudebox): tailscale up ; then ~/monad/scripts/claudebox-server.sh start"
            R "Then clear stale standalone Raft first: mv ~/nomad/data ~/nomad/data.standalone.bak"
            R "See cluster/desired-servers.md for the full join procedure."
          } else {
            R "claudebox NOT reachable from windesk on any tested address."
            R "Likely powered off / off the LAN / Tailscale down. Needs physical or out-of-band check."
          }

          R "=== diagnosis complete ==="

          # --- 6. Publish the report through reliable channels ---
          # Primary: a Nomad variable the control plane can read centrally with
          #   `nomad var get -item=report claudebox-diag/last`
          # (raw_exec stdout is not captured on Windows, and windesk often can't push git).
          $text = $report -join "`n"
          try {
            $tmp = Join-Path $env:NOMAD_TASK_DIR "report.txt"; if (-not $env:NOMAD_TASK_DIR) { $tmp = "local/report.txt" }
            $text | Out-File -FilePath $tmp -Encoding utf8
            & nomad var put -force "claudebox-diag/last" "stamp=$stamp" "node=$env:COMPUTERNAME" "report=@$tmp" 2>&1 | Out-Null
          } catch {}
          # Secondary (best-effort): commit into the repo for GitOps history.
          try {
            $dir = Join-Path $REPO "logs/claudebox-diag"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $text | Out-File -FilePath (Join-Path $dir "$stamp-windesk.txt") -Encoding utf8
            Push-Location $REPO
            & git add "logs/claudebox-diag/$stamp-windesk.txt" 2>$null
            & git -c user.name="windesk" -c user.email="windesk@monad" commit -m "claudebox-diagnose: report from windesk $stamp" 2>$null
            & git pull --ff-only 2>$null; & git push 2>$null
            Pop-Location
          } catch {}
        SCRIPT
      }

      config {
        command = "powershell.exe"
        args    = ["-ExecutionPolicy", "Bypass", "-File", "local/diagnose.ps1"]
      }

      env {
        MONAD_REPO_DIR = "C:/Users/Eliott/monad"
        NOMAD_ADDR     = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
