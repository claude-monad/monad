# storage-mount.ps1 — Mount death-star cluster storage on Windows via SMB.
#
# Usage:
#   .\storage-mount.ps1 mount           # Map Z: drive to cluster storage
#   .\storage-mount.ps1 unmount         # Remove Z: drive mapping
#   .\storage-mount.ps1 status          # Show storage status
#   .\storage-mount.ps1 setup-s3        # Install and configure MinIO client
#
# All traffic runs over Tailscale — no port forwarding needed.

param(
    [Parameter(Position=0)]
    [ValidateSet("mount", "unmount", "status", "setup-s3", "help")]
    [string]$Command = "help",

    [string]$DriveLetter = "Z"
)

$StorageIP = "100.96.31.66"
$StorageHost = "death-star"
$ShareName = "public"
$MinioURL = "http://${StorageIP}:9000"
$MinioConsole = "http://${StorageIP}:9001"
$UNCPath = "\\${StorageIP}\${ShareName}"

function Write-Ok { param([string]$msg); Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Err { param([string]$msg); Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Step { param([string]$msg); Write-Host "`n==> $msg" -ForegroundColor Cyan }

function Test-Tailscale {
    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        Write-Err "Tailscale not installed. Get it at https://tailscale.com/download"
        return $false
    }
    try {
        $ip = tailscale ip -4 2>$null
        if ($ip) {
            Write-Ok "Tailscale connected ($ip)"
            return $true
        }
    } catch {}
    Write-Err "Tailscale not connected. Run: tailscale up"
    return $false
}

function Test-StorageReachable {
    try {
        $r = Invoke-WebRequest -Uri "$MinioURL/minio/health/live" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            Write-Ok "Storage node reachable ($StorageHost / $StorageIP)"
            return $true
        }
    } catch {}
    Write-Err "Cannot reach storage node at $StorageIP. Is death-star online?"
    return $false
}

function Invoke-Mount {
    Write-Step "Mounting cluster storage"
    if (-not (Test-Tailscale)) { return }
    if (-not (Test-StorageReachable)) { return }

    # Check if already mapped
    $existing = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Ok "Drive ${DriveLetter}: already mapped to $($existing.Root)"
        return
    }

    Write-Step "Mapping ${DriveLetter}: → ${UNCPath}"
    try {
        net use "${DriveLetter}:" "$UNCPath" /persistent:yes 2>$null
        Write-Ok "Mapped ${DriveLetter}: to ${UNCPath}"
        Write-Host ""
        Write-Host "  Access storage at ${DriveLetter}:\"
        Write-Host "  This mapping persists across reboots."
    } catch {
        # Try without persistence
        net use "${DriveLetter}:" "$UNCPath" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Mapped ${DriveLetter}: to ${UNCPath} (non-persistent)"
        } else {
            Write-Err "Failed to map drive. Try manually: net use ${DriveLetter}: ${UNCPath}"
        }
    }
}

function Invoke-Unmount {
    Write-Step "Unmounting cluster storage"
    $existing = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if ($existing) {
        net use "${DriveLetter}:" /delete /yes 2>$null
        Write-Ok "Unmapped ${DriveLetter}:"
    } else {
        Write-Host "  Drive ${DriveLetter}: is not currently mapped"
    }
}

function Invoke-Status {
    Write-Step "Cluster Storage Status"
    Write-Host "  Storage node:  $StorageHost ($StorageIP)"
    Write-Host "  SMB share:     $UNCPath"
    Write-Host "  S3 endpoint:   $MinioURL"
    Write-Host "  S3 console:    $MinioConsole"
    Write-Host ""

    Test-StorageReachable | Out-Null

    $existing = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Ok "Mounted as ${DriveLetter}:"
        $free = [math]::Round($existing.Free / 1TB, 1)
        $used = [math]::Round($existing.Used / 1TB, 1)
        Write-Host "     Used: ${used}TB  Free: ${free}TB"
    } else {
        Write-Host "  SMB not mounted (run: .\storage-mount.ps1 mount)"
    }

    # Check mc
    if (Get-Command mc -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  S3 Buckets:"
        mc ls monad/ 2>$null | ForEach-Object { Write-Host "    $_" }
    }
}

function Invoke-SetupS3 {
    Write-Step "Setting up S3 (MinIO) client"

    if (-not (Get-Command mc -ErrorAction SilentlyContinue)) {
        Write-Host "  Installing MinIO client (mc)..."
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            scoop install minio-client
        } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            choco install minio-client -y
        } else {
            $mcPath = "$env:USERPROFILE\mc.exe"
            Invoke-WebRequest -Uri "https://dl.min.io/client/mc/release/windows-amd64/mc.exe" -OutFile $mcPath
            Write-Host "  Downloaded to $mcPath — add to PATH or move to a directory in PATH"
        }
    } else {
        Write-Ok "mc already installed"
    }

    Write-Host ""
    Write-Host "  Configure with:"
    Write-Host "    mc alias set monad $MinioURL <user> <password>"
    Write-Host ""
    Write-Host "  Get credentials from any cluster node:"
    Write-Host "    set NOMAD_ADDR=http://100.75.75.39:4646"
    Write-Host "    nomad var get nomad/jobs/minio-storage"
}

function Show-Help {
    Write-Host @"

storage-mount.ps1 — Mount or access death-star cluster storage (Windows)

Commands:
  mount       Map drive letter to cluster storage via SMB
  unmount     Remove drive mapping
  status      Show storage status and capacity
  setup-s3    Install and configure MinIO S3 client

Parameters:
  -DriveLetter   Drive letter to use (default: Z)

Examples:
  .\storage-mount.ps1 mount
  .\storage-mount.ps1 mount -DriveLetter M
  .\storage-mount.ps1 status

Universal S3 access:
  mc alias set monad http://100.96.31.66:9000 <user> <pass>
  mc cp localfile.txt monad/bucket-name/
"@
}

switch ($Command) {
    "mount"    { Invoke-Mount }
    "unmount"  { Invoke-Unmount }
    "status"   { Invoke-Status }
    "setup-s3" { Invoke-SetupS3 }
    "help"     { Show-Help }
}
