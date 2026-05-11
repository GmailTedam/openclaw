<# .SYNOPSIS
    openclaw consolidated release script — replaces docker-release.yml,
    openclaw-npm-release.yml, plugin-npm-release.yml, plugin-clawhub-release.yml,
    docs-sync-publish.yml, control-ui-locale-refresh.yml.

    Usage:
      pwsh -File scripts/ci-local/release.ps1 -Target docker [-Push]
      pwsh -File scripts/ci-local/release.ps1 -Target npm [-Beta]
      pwsh -File scripts/ci-local/release.ps1 -Target plugins
      pwsh -File scripts/ci-local/release.ps1 -Target clawhub
      pwsh -File scripts/ci-local/release.ps1 -Target docs
      pwsh -File scripts/ci-local/release.ps1 -Target locales
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet("docker", "npm", "plugins", "clawhub", "docs", "locales")]
    [string]$Target,

    [switch]$Push,
    [switch]$Beta,
    [string]$Tag = "latest",
    [string]$Registry = "ghcr.io/gmailtedam/openclaw"
)

$ErrorActionPreference = "Stop"
Set-Location C:\Users\hgeec\github\openclaw

function Require-Env($name) {
    if (-not (Get-Item "env:$name" -ErrorAction SilentlyContinue)) {
        Write-Host "[FAIL] Required env var $name not set"; exit 1
    }
}

switch ($Target) {
    "docker" {
        # --- Docker release (replaces docker-release.yml) ---
        $version = (node -e "process.stdout.write(require('./package.json').version)")
        $defaultTag = "${Registry}:$version"
        $slimTag = "${Registry}:${version}-slim"

        Write-Host "[INFO] Building default image: $defaultTag"
        docker buildx build --platform linux/amd64 -t $defaultTag -f Dockerfile .
        Write-Host "[INFO] Building slim image: $slimTag"
        docker buildx build --platform linux/amd64 -t $slimTag -f Dockerfile.slim .

        if ($Push) {
            Require-Env "GHCR_PAT"
            echo $env:GHCR_PAT | docker login ghcr.io -u GmailTedam --password-stdin
            docker push $defaultTag
            docker push $slimTag
            Write-Host "[OK] Pushed: $defaultTag, $slimTag"
        } else {
            Write-Host "[OK] Built (not pushed): $defaultTag, $slimTag"
        }
    }

    "npm" {
        # --- npm release (replaces openclaw-npm-release.yml) ---
        Require-Env "NPM_TOKEN"
        $distTag = if ($Beta) { "beta" } else { "latest" }

        Write-Host "[INFO] Building..."
        pnpm install --frozen-lockfile
        pnpm build

        Write-Host "[INFO] Packing tarball for preflight..."
        pnpm pack --pack-destination ./dist

        Write-Host "[INFO] Publishing to npm (dist-tag: $distTag)..."
        npm publish --tag $distTag --access public
        Write-Host "[OK] Published to npm"
    }

    "plugins" {
        # --- Plugin npm release (replaces plugin-npm-release.yml) ---
        Require-Env "NPM_TOKEN"

        Write-Host "[INFO] Resolving plugin release plan..."
        pnpm install --frozen-lockfile

        $plugins = Get-ChildItem -Path plugins -Directory | Where-Object { Test-Path "$($_.FullName)/package.json" }
        foreach ($p in $plugins) {
            Write-Host "[INFO] Publishing plugin: $($p.Name)"
            Set-Location $p.FullName
            npm pack --dry-run
            npm publish --access public
            Set-Location C:\Users\hgeec\github\openclaw
        }
        Write-Host "[OK] All plugins published"
    }

    "clawhub" {
        # --- ClawHub release (replaces plugin-clawhub-release.yml) ---
        Require-Env "CLAWHUB_API_KEY"

        Write-Host "[INFO] Publishing to ClawHub..."
        bash scripts/plugin-clawhub-publish.sh --publish
        Write-Host "[OK] Published to ClawHub"
    }

    "docs" {
        # --- Docs sync (replaces docs-sync-publish.yml) ---
        Write-Host "[INFO] Syncing docs to openclaw/docs repo..."
        node scripts/docs-sync-publish.mjs
        Write-Host "[OK] Docs synced"
    }

    "locales" {
        # --- Locale refresh (replaces control-ui-locale-refresh.yml) ---
        Write-Host "[INFO] Refreshing Control UI locales..."
        $locales = @("zh-CN","ja-JP","es","pt-BR","ko","de","fr","ar","it","tr","uk","id","pl")
        foreach ($loc in $locales) {
            Write-Host "  Syncing $loc..."
            node scripts/control-ui-i18n.ts sync --locale $loc --write
        }
        Write-Host "[OK] All locales refreshed"
    }
}
