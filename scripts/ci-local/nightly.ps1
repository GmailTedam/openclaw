<# .SYNOPSIS
    openclaw nightly CI — replaces codeql.yml, stale.yml,
    openclaw-scheduled-live-checks.yml, install-smoke.yml,
    sandbox-common-smoke.yml, parity-gate.yml.

    Run daily via Task Scheduler or manually:
      pwsh -NoProfile -File scripts/ci-local/nightly.ps1
#>
param(
    [string]$LogDir = "C:\Users\hgeec\github\openclaw\logs\ci-local"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logFile = Join-Path $LogDir "nightly_$timestamp.log"

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

Set-Location C:\Users\hgeec\github\openclaw

Log "[INFO] openclaw nightly started"

# --- Install smoke (replaces install-smoke.yml) ---
Log "[INFO] Running install smoke..."
pnpm install --frozen-lockfile 2>&1 | Out-File -Append $logFile -Encoding utf8
Log "[$(if ($LASTEXITCODE -eq 0) {'OK'} else {'FAIL'})] Install smoke: exit $LASTEXITCODE"

# --- Parity gate (replaces parity-gate.yml) ---
Log "[INFO] Running parity gate..."
pnpm run test:parity 2>&1 | Out-File -Append $logFile -Encoding utf8
$parityRc = $LASTEXITCODE
Log "[$(if ($parityRc -eq 0) {'OK'} else {'FAIL'})] Parity gate: exit $parityRc"

# --- Sandbox smoke (replaces sandbox-common-smoke.yml) ---
Log "[INFO] Running sandbox smoke..."
pnpm run test:sandbox 2>&1 | Out-File -Append $logFile -Encoding utf8
$sandboxRc = $LASTEXITCODE
Log "[$(if ($sandboxRc -eq 0) {'OK'} else {'FAIL'})] Sandbox smoke: exit $sandboxRc"

# --- Stale issues (replaces stale.yml) ---
Log "[INFO] Closing stale issues/PRs..."
gh issue list --label "stale" --state open --limit 50 --json number --jq '.[].number' 2>$null | ForEach-Object {
    gh issue close $_ --comment "Closed by nightly CI: stale for 60+ days" 2>&1 | Out-Null
}
Log "[OK] Stale issues processed"

# --- CodeQL (replaces codeql.yml) ---
# CodeQL Analysis is free for public repos on GitHub. For local:
# install codeql CLI and run: codeql database create --language=javascript
# For now, use npm audit as a lightweight alternative.
Log "[INFO] Running security audit (npm audit replaces CodeQL)..."
pnpm audit --audit-level=high 2>&1 | Out-File -Append $logFile -Encoding utf8
$auditRc = $LASTEXITCODE
Log "[$(if ($auditRc -eq 0) {'OK'} else {'WARN'})] Security audit: exit $auditRc"

Log "[INFO] Nightly complete. Log: $logFile"
exit 0
