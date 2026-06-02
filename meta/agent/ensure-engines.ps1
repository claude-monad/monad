# ensure-engines.ps1 — Windows port of ensure-engines.sh.
#
# Make this (Windows) node able to run agent jobs with BOTH engines (claude + codex),
# and advertise which engines are READY via dynamic Nomad node metadata so the cluster
# brain can schedule either type here. Idempotent and scheduled-task / cron-safe.
#
#   has_claude / has_codex   -> "true" only if the CLI is installed AND logged in
#   agent_engines            -> comma list of ready engines (e.g. "claude,codex")
#
# It will try to INSTALL a missing CLI, but it cannot log you in — auth is a human,
# once-per-machine step (`claude`, `codex login`). Missing auth is a warning, not a
# failure, so a half-ready node still advertises what it can do.
#
# Mirrors meta/agent/engines.sh detection exactly:
#   claude authed = %USERPROFILE%\.claude\.credentials.json exists
#   codex  authed = %USERPROFILE%\.codex\auth.json exists
#
# Run:  powershell -ExecutionPolicy Bypass -File meta\agent\ensure-engines.ps1

$ErrorActionPreference = "Continue"

function Log  ($m) { Write-Host "[ensure-engines] $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "[ensure-engines] $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

$HOMEDIR = $env:USERPROFILE
$CLAUDE_HOME = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOMEDIR ".claude" }
$CODEX_HOME  = if ($env:CODEX_HOME)  { $env:CODEX_HOME }  else { Join-Path $HOMEDIR ".codex" }

# ── install (best-effort; install only, never logs in) ──────────────────────────
function Install-Claude {
  if (Have claude) { return }
  Log "installing claude CLI…"
  try { Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression }
  catch { Warn "claude install failed — install Claude Code manually, then run 'claude' to log in." }
}
function Install-Codex {
  if (Have codex) { return }
  Log "installing codex CLI…"
  if (Have npm) {
    try { npm install -g @openai/codex 2>$null } catch { Warn "codex npm install failed." }
  } elseif (Have scoop) {
    try { scoop install codex 2>$null } catch { Warn "codex scoop install failed." }
  } else {
    Warn "no npm/scoop to install codex — install @openai/codex manually, then 'codex login'."
  }
}
Install-Claude
Install-Codex

# ── detect (available AND authed), mirroring engines.sh ─────────────────────────
function Engine-Available ($e) { switch ($e) { "claude" { Have claude } "codex" { Have codex } default { $false } } }
function Engine-Authed ($e) {
  switch ($e) {
    "claude" { Test-Path (Join-Path $CLAUDE_HOME ".credentials.json") }
    "codex"  { Test-Path (Join-Path $CODEX_HOME  "auth.json") }
    default  { $false }
  }
}

$ready = @{}
$summary = ""
$readyList = @()
foreach ($e in @("claude","codex")) {
  if (Engine-Available $e) {
    if (Engine-Authed $e) {
      $ready[$e] = "true"; $readyList += $e; $summary += " $e=ready"
    } else {
      $ready[$e] = "false"; $summary += " $e=installed-NOT-logged-in"
      $cmd = if ($e -eq "codex") { "codex login" } else { "claude" }
      Warn "$e is installed but not logged in on this node — run '$cmd' once."
    }
  } else {
    $ready[$e] = "false"; $summary += " $e=absent"
  }
}
Log "engine status:$summary"
$enginesCsv = ($readyList -join ",")

# ── advertise via dynamic node metadata (no nomad restart; ~10s to propagate) ──
if (-not $env:NOMAD_ADDR) {
  $tip = $null
  try { $tip = (tailscale ip -4 2>$null | Select-Object -First 1) } catch {}
  if (-not $tip) { $tip = "127.0.0.1" }
  $env:NOMAD_ADDR = "http://${tip}:4646"
}
$applied = $false
if (Have nomad) {
  try {
    nomad node meta apply "has_claude=$($ready['claude'])" "has_codex=$($ready['codex'])" "agent_engines=$(if($enginesCsv){$enginesCsv}else{'none'})" *> $null
    if ($LASTEXITCODE -eq 0) {
      Log "advertised dynamic node meta: has_claude=$($ready['claude']) has_codex=$($ready['codex']) agent_engines=$(if($enginesCsv){$enginesCsv}else{'none'}) (via $env:NOMAD_ADDR)"
      $applied = $true
    }
  } catch {}
}
if (-not $applied) {
  Warn "could not apply dynamic node meta (is the local nomad client up at $env:NOMAD_ADDR?) — engines still usable, just not advertised."
}

if (-not $enginesCsv) {
  Warn "no ready engine on this node yet (install + log in to claude and/or codex)."
}
exit 0
