job "backup-windesk" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "windesk"
  }

  group "backup" {
    task "copy-all" {
      driver = "raw_exec"

      config {
        command = "powershell.exe"
        args    = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", <<-SCRIPT
          $ErrorActionPreference = "Continue"
          $SIP = "100.96.31.66"
          $u = $env:USERPROFILE
          $Log = "$env:TEMP\monad-backup.log"

          function Log($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $line = "[$ts] $msg"
            Write-Output $line
            Add-Content -Path $Log -Value $line
          }

          # Map drive
          net use Y: /delete /yes 2>$null
          net use Y: "\\$SIP\media" /user:monad monad /persistent:no 2>$null
          if (-not (Test-Path "Y:\")) {
            Log "ERROR: Cannot map Y: to \\$SIP\media"
            exit 1
          }
          Log "=== WINDESK DEEP BACKUP ==="
          Log "Mapped X: successfully"

          $base = "Y:\backups\windesk"
          New-Item -ItemType Directory -Force -Path $base | Out-Null

          # Helper: robocopy with logging
          function Backup($src, $dest, $extra) {
            if (Test-Path $src) {
              $sz = (Get-ChildItem -Path $src -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
              Log "  $([math]::Round($sz/1GB,2)) GB  $src -> $dest"
              New-Item -ItemType Directory -Force -Path $dest | Out-Null
              if ($extra) {
                robocopy $src $dest /E /Z /MT:4 /R:1 /W:2 /NP /NDL /NFL @($extra) 2>$null
              } else {
                robocopy $src $dest /E /Z /MT:4 /R:1 /W:2 /NP /NDL /NFL 2>$null
              }
            } else {
              Log "  SKIP (not found): $src"
            }
          }

          # === Downloads (everything, not just media) ===
          Log ""
          Log "=== DOWNLOADS ==="
          Backup "$u\Downloads" "$base\downloads"

          # === Dotfiles / configs ===
          Log ""
          Log "=== CONFIGS & DOTFILES ==="
          # SSH
          Backup "$u\.ssh" "$base\dotfiles\ssh"
          # Git config
          if (Test-Path "$u\.gitconfig") {
            Copy-Item "$u\.gitconfig" "$base\dotfiles\" -Force
            Log "  .gitconfig copied"
          }
          # Claude config
          Backup "$u\.claude" "$base\dotfiles\claude"
          # Codex config
          Backup "$u\.codex" "$base\dotfiles\codex"
          # General .config
          Backup "$u\.config" "$base\dotfiles\config"

          # === VS Code settings ===
          Log ""
          Log "=== VS CODE ==="
          Backup "$u\AppData\Roaming\Code\User" "$base\vscode"

          # === OBS Studio (scenes, profiles, configs) ===
          Log ""
          Log "=== OBS STUDIO ==="
          Backup "$u\AppData\Roaming\obs-studio" "$base\obs-studio"

          # === Browser bookmarks & profiles ===
          Log ""
          Log "=== BROWSERS ==="
          # Chrome - just bookmarks and key profile data, not cache
          $chromeProfile = "$u\AppData\Local\Google\Chrome\User Data\Default"
          if (Test-Path $chromeProfile) {
            New-Item -ItemType Directory -Force -Path "$base\browsers\chrome" | Out-Null
            foreach ($f in @("Bookmarks", "Bookmarks.bak", "Preferences", "Login Data", "History", "Favicons", "Top Sites", "Shortcuts")) {
              $fp = Join-Path $chromeProfile $f
              if (Test-Path $fp) { Copy-Item $fp "$base\browsers\chrome\" -Force }
            }
            Log "  Chrome profile data copied"
          }
          # Firefox - full profiles (includes bookmarks db, passwords, etc)
          Backup "$u\AppData\Roaming\Mozilla\Firefox\Profiles" "$base\browsers\firefox"
          # Edge bookmarks
          $edgeProfile = "$u\AppData\Local\Microsoft\Edge\User Data\Default"
          if (Test-Path $edgeProfile) {
            New-Item -ItemType Directory -Force -Path "$base\browsers\edge" | Out-Null
            foreach ($f in @("Bookmarks", "Bookmarks.bak", "Preferences", "History", "Favicons")) {
              $fp = Join-Path $edgeProfile $f
              if (Test-Path $fp) { Copy-Item $fp "$base\browsers\edge\" -Force }
            }
            Log "  Edge profile data copied"
          }

          # === ELAN data ===
          Log ""
          Log "=== ELAN ==="
          Backup "$u\.elan" "$base\elan"

          # === Math repo ===
          Log ""
          Log "=== MATH REPO ==="
          Backup "$u\math" "$base\math"

          # === Scoop (package state) ===
          Log ""
          Log "=== SCOOP ==="
          Backup "$u\scoop" "$base\scoop"

          # === Saved Games ===
          Log ""
          Log "=== SAVED GAMES ==="
          Backup "$u\Saved Games" "$base\saved-games"

          # === Desktop ===
          Log ""
          Log "=== DESKTOP ==="
          Backup "$u\Desktop" "$base\desktop"

          # === Summary ===
          Log ""
          Log "=== BACKUP SUMMARY ==="
          $total = (Get-ChildItem -Path $base -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
          Log "Total backed up: $([math]::Round($total/1GB,2)) GB"
          Get-ChildItem -Path $base -Directory | ForEach-Object {
            $sz = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Log "  $([math]::Round($sz/1GB,2)) GB  $($_.Name)"
          }
          Log ""
          Log "=== DONE ==="

          net use Y: /delete /yes 2>$null
        SCRIPT
        ]
      }

      resources {
        cpu    = 500
        memory = 256
      }

      kill_timeout = "30s"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
