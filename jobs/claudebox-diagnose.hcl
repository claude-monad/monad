# claudebox-diagnose — delegate claudebox diagnosis to windesk (its LAN neighbor).
#
# claudebox (100.87.219.108) is unreachable over Tailscale (relay only, rx 0), so the
# control plane cannot probe it directly. windesk shares claudebox's LAN, so we run the
# probe THERE. It discovers claudebox's LAN address from Tailscale peer endpoints, tests
# reachability + key ports, and publishes the result to the Nomad variable
# `claudebox-diag/last` (raw_exec stdout is NOT captured on Windows, so the variable is the
# channel the control plane reads).
#
# Run:    monad deploy jobs/claudebox-diagnose.hcl
# Read:   nomad var get claudebox-diag/last        (keys: reachable, findings, node, stamp)
# Re-run: nomad job run jobs/claudebox-diagnose.hcl

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
          $TS_IP = "100.87.219.108"
          $NAME  = "claudebox"
          $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
          # Accumulate findings into a single top-level string (no helper fn — function
          # scope did not mutate the outer collection on this host). " || " separates lines.
          $F = "diag from $env:COMPUTERNAME for $NAME tailscale=$TS_IP at $stamp"

          # --- 1. Tailscale's view of claudebox (peer endpoints reveal LAN addrs) ---
          $lan = @()
          $ts  = & tailscale status --json 2>$null | ConvertFrom-Json
          $F  += " || backend=" + $ts.BackendState
          $peer = $ts.Peer.PSObject.Properties.Value | Where-Object { $_.HostName -eq $NAME -or $_.TailscaleIPs -contains $TS_IP }
          if ($peer) {
            $F += " || peer Online=" + $peer.Online + " Relay=" + $peer.Relay + " CurAddr=" + $peer.CurAddr + " LastSeen=" + $peer.LastSeen
            foreach ($a in @($peer.CurAddr) + @($peer.Addrs)) {
              if ($a) {
                $ip = ($a -split ":")[0]
                if ($ip -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' -and $lan -notcontains $ip) { $lan += $ip }
              }
            }
          } else { $F += " || peer NOT FOUND among tailscale peers" }

          # --- 2. Hostname resolution on the LAN (mDNS / NetBIOS / DNS) ---
          foreach ($n in @($NAME, "$NAME.local")) {
            $rec = Resolve-DnsName $n -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress }
            foreach ($r in $rec) {
              $F += " || resolve $n=" + $r.IPAddress
              if ($r.IPAddress -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' -and $lan -notcontains $r.IPAddress) { $lan += $r.IPAddress }
            }
          }
          $F += " || LAN candidates: " + ($lan -join ",")

          # --- 3. Probe each address (tailscale IP + LAN candidates) ---
          $targets   = @($TS_IP) + $lan | Select-Object -Unique
          $reachable = $false
          foreach ($t in $targets) {
            $ping = Test-Connection -ComputerName $t -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($ping) { $reachable = $true }
            $ports = ""
            foreach ($p in @(22, 4646, 4647)) {
              $tc = Test-NetConnection -ComputerName $t -Port $p -WarningAction SilentlyContinue
              $ports += "${p}:" + $(if ($tc.TcpTestSucceeded) { "open" } else { "x" }) + " "
            }
            $F += " || $t icmp=" + $(if ($ping) { "UP" } else { "down" }) + " ports[$ports]"
          }

          # --- 4. Verdict ---
          if ($reachable) {
            $F += " || VERDICT: claudebox REACHABLE from windesk. Revive: stop old agent, clear stale standalone Raft (mv ~/nomad/data ~/nomad/data.standalone.bak), then claudebox-server.sh start (now a JOIN config). See cluster/desired-servers.md."
          } else {
            $F += " || VERDICT: claudebox NOT reachable from windesk on any address. Likely powered off / off the LAN / Tailscale down. Needs physical or out-of-band check."
          }

          # --- 5. Publish to a Nomad variable (the reliable central channel) ---
          & nomad var put -force "claudebox-diag/last" "stamp=$stamp" "node=$env:COMPUTERNAME" "reachable=$reachable" "findings=$F" 2>&1 | Out-Null
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
