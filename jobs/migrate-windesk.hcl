job "migrate-windesk" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "windesk"
  }

  group "migrate" {
    task "copy-media" {
      driver = "raw_exec"

      config {
        command = "powershell.exe"
        args    = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", <<-SCRIPT
          $ErrorActionPreference = "Continue"
          $StorageIP = "100.96.31.66"
          $SharePath = "\\$StorageIP\public\media"
          $UserDir = $env:USERPROFILE
          $LogFile = "$env:TEMP\monad-migration.log"

          function Log($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $line = "[$ts] $msg"
            Write-Output $line
            Add-Content -Path $LogFile -Value $line
          }

          Log "=== WINDESK MEDIA MIGRATION ==="
          Log "Source: $UserDir"
          Log "Destination: $SharePath"
          Log ""

          # Map drive with cluster credentials
          net use X: /delete /yes 2>$null
          Log "Mapping X: to \\$StorageIP\media ..."
          $r = net use X: "\\$StorageIP\media" /user:monad monad /persistent:no 2>&1
          Log $r
          if (-not (Test-Path "X:\")) {
            Log "Trying guest on public share..."
            $r = net use X: "\\$StorageIP\public" /user:guest "" /persistent:no 2>&1
            Log $r
            if (-not (Test-Path "X:\")) {
              Log "ERROR: Cannot mount share. Aborting."
              exit 1
            }
            $SharePath = "X:\media"
          } else {
            $SharePath = "X:\"
          }
          Log "SMB share accessible at $SharePath"

          # --- Videos ---
          Log ""
          Log "=== MIGRATING VIDEOS ==="

          # Drone footage
          $droneSrc = "$UserDir\Documents\Videos\Random outdoor musings"
          if (Test-Path $droneSrc) {
            $dest = "$SharePath\videos\drone"
            Log "Drone footage: $droneSrc -> $dest"
            robocopy $droneSrc $dest /E /Z /MT:4 /R:2 /W:5 /NP /LOG+:$LogFile /TEE 2>$null
          }

          # Favorites (recorded streams/sessions)
          $favSrc = "$UserDir\Favorites"
          if (Test-Path $favSrc) {
            $dest = "$SharePath\videos\recordings"
            Log "Recorded sessions: $favSrc -> $dest"
            $vids = Get-ChildItem -Path $favSrc -Include "*.mkv","*.mp4","*.mov","*.avi" -Recurse -File -ErrorAction SilentlyContinue
            foreach ($v in $vids) {
              $destFile = Join-Path $dest $v.Name
              if (-not (Test-Path $destFile)) {
                Log "  Copying: $($v.Name) ($([math]::Round($v.Length/1GB,2)) GB)"
                Copy-Item -Path $v.FullName -Destination $dest -Force
              } else {
                Log "  Skip (exists): $($v.Name)"
              }
            }
          }

          # NVIDIA game clips
          $nvSrc = "$UserDir\Videos\NVIDIA"
          if (Test-Path $nvSrc) {
            $dest = "$SharePath\game-clips"
            Log "Game clips: $nvSrc -> $dest"
            robocopy $nvSrc $dest /E /Z /MT:4 /R:2 /W:5 /NP /LOG+:$LogFile /TEE 2>$null
          }

          # General videos
          $vidSrc = "$UserDir\Videos"
          if (Test-Path $vidSrc) {
            $dest = "$SharePath\videos\windesk"
            Log "General videos: $vidSrc -> $dest"
            robocopy $vidSrc $dest /E /Z /MT:4 /R:2 /W:5 /NP /XD "NVIDIA" /LOG+:$LogFile /TEE 2>$null
          }

          # --- Photos ---
          Log ""
          Log "=== MIGRATING PHOTOS ==="
          $picSrc = "$UserDir\Pictures"
          if (Test-Path $picSrc) {
            $dest = "$SharePath\photos\windesk"
            Log "Photos: $picSrc -> $dest"
            robocopy $picSrc $dest /E /Z /MT:4 /R:2 /W:5 /NP /LOG+:$LogFile /TEE 2>$null
          }

          # --- Documents ---
          Log ""
          Log "=== MIGRATING DOCUMENTS ==="
          $docSrc = "$UserDir\Documents"
          if (Test-Path $docSrc) {
            $dest = "$SharePath\documents"
            Log "Documents: $docSrc -> $dest"
            # Skip Videos subfolder (already handled) and large temp files
            robocopy $docSrc "$dest\windesk" /E /Z /MT:4 /R:2 /W:5 /NP /XD Videos /LOG+:$LogFile /TEE 2>$null
          }

          # --- Downloads (large media only) ---
          Log ""
          Log "=== MIGRATING LARGE DOWNLOADS ==="
          $dlSrc = "$UserDir\Downloads"
          if (Test-Path $dlSrc) {
            $dest = "$SharePath\downloads"
            $large = Get-ChildItem -Path $dlSrc -Include "*.mp4","*.mov","*.mkv","*.avi","*.iso","*.dmg" -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 50MB }
            foreach ($f in $large) {
              $destFile = Join-Path $dest $f.Name
              if (-not (Test-Path $destFile)) {
                Log "  Copying: $($f.Name) ($([math]::Round($f.Length/1GB,2)) GB)"
                Copy-Item -Path $f.FullName -Destination $dest -Force
              } else {
                Log "  Skip (exists): $($f.Name)"
              }
            }
          }

          # --- Summary ---
          Log ""
          Log "=== MIGRATION SUMMARY ==="
          $totalDest = (Get-ChildItem -Path $SharePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
          Log "Total data on death-star media share: $([math]::Round($totalDest/1GB,2)) GB"
          Log ""
          Log "=== MIGRATION COMPLETE ==="

          # Cleanup
          Log "Unmapping X: drive"
          net use X: /delete /yes 2>$null
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
