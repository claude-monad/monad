# storage-mount-windows — make death-star's storage seamless on Windows (e.g. windesk,
# low on disk). Stores share credentials machine-wide (cmdkey) so the UNC \\death-star\public
# works without prompts, maps a persistent Z: drive, and installs a logon scheduled task so
# the drive re-appears in the user's session at sign-in.

job "storage-mount-windows" {
  datacenters = ["dc1"]
  type        = "system"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "windows"
  }

  group "mount" {
    count = 1
    restart {
      attempts = 3
      interval = "10m"
      delay    = "20s"
      mode     = "delay"
    }

    task "smb-mount" {
      driver = "raw_exec"
      config {
        command = "powershell.exe"
        args    = ["-ExecutionPolicy", "Bypass", "-File", "local/mount.ps1"]
      }
      template {
        destination = "secrets/smb.env"
        env         = true
        data        = <<-EOT
          SMB_USER={{ with nomadVar "secret/samba" }}{{ .username }}{{ end }}
          SMB_PASS={{ with nomadVar "secret/samba" }}{{ .password }}{{ end }}
        EOT
      }
      template {
        destination = "local/mount.ps1"
        data        = <<-PS
          $ip    = if ($env:STORAGE_IP) { $env:STORAGE_IP } else { "100.96.31.66" }
          $user  = if ($env:SMB_USER) { $env:SMB_USER } else { "monad" }
          $pass  = $env:SMB_PASS
          $share = "\\$ip\public"
          $drive = "Z:"
          function Log($m) { Write-Output "[storage-mount $(Get-Date -Format HH:mm:ss)] $m" }

          cmd /c "cmdkey /add:$ip /user:$user /pass:$pass" | Out-Null
          Log "stored credentials for $ip (UNC \\$ip\public usable in any session)"

          $cmd = "net use $drive $share /persistent:yes"
          cmd /c "schtasks /create /tn MonadStorageMount /tr `"cmd /c $cmd`" /sc onlogon /rl highest /f" 2>$null | Out-Null
          Log "installed logon mapping task (MonadStorageMount -> $drive)"

          while ($true) {
            if (-not (Get-PSDrive -Name Z -ErrorAction SilentlyContinue)) {
              cmd /c "net use $drive $share /user:$user $pass /persistent:yes" 2>$null | Out-Null
              Log "mapped $drive -> $share"
            }
            Start-Sleep -Seconds 120
          }
        PS
      }
      env {
        STORAGE_IP = "100.96.31.66"
      }
      resources {
        cpu    = 100
        memory = 128
      }
      kill_timeout = "10s"
    }
  }
}
