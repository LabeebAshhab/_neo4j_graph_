<#
    KGN4j - install and run NeoDash from source with Node.js.

    Usage (PowerShell, from the project root):
        .\scripts\setup-neodash.ps1            # install if needed, then run
        .\scripts\setup-neodash.ps1 -Reinstall # wipe node_modules and reinstall

    NeoDash ends up in  .\neodash  (git-ignored). It serves on
    http://localhost:3000 and connects to your local Neo4j over Bolt.
#>
param(
    [switch]$Reinstall,
    [string]$NeodashDir = (Join-Path $PSScriptRoot '..\neodash'),
    [string]$Repo = 'https://github.com/neo4j-labs/neodash.git'
)

$ErrorActionPreference = 'Stop'
$NeodashDir = [System.IO.Path]::GetFullPath($NeodashDir)

function Require-Cmd($name, $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "$name was not found on PATH. $hint"
    }
}

Require-Cmd node 'Install Node.js LTS from https://nodejs.org (18.x or 20.x recommended).'
Require-Cmd npm  'npm ships with Node.js.'
Require-Cmd git  'Install Git from https://git-scm.com/download/win.'

Write-Host "node $(node --version) / npm $(npm --version)" -ForegroundColor Cyan

if ($Reinstall -and (Test-Path $NeodashDir)) {
    Write-Host "Removing $NeodashDir ..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $NeodashDir
}

if (-not (Test-Path $NeodashDir)) {
    Write-Host "Cloning NeoDash into $NeodashDir ..." -ForegroundColor Cyan
    git clone --depth 1 $Repo $NeodashDir
}

Push-Location $NeodashDir
try {
    # KGN4j patches, applied in this order (the second builds on the first):
    #   kgn4j-neodash.patch        graph re-layout/fit + pin-all-after-layout,
    #                              and a table "rows per page on load" setting
    #   kgn4j-suspect-graph.patch  a second node caption drawn outside the
    #                              node, node shapes, fixed positions from
    #                              pin_x / pin_y, zoom-to-what-you-opened (Suspect Network)
    #   kgn4j-hires-image.patch    camera buttons save the image at up to 3x
    #                              resolution instead of screen resolution
    # Every setting is opt-in per card, so dashboards that do not set them
    # behave exactly as stock NeoDash. Each patch is applied once; skipped
    # if already in place.
    foreach ($Name in @('kgn4j-neodash.patch', 'kgn4j-suspect-graph.patch', 'kgn4j-hires-image.patch')) {
        $Patch = Join-Path $PSScriptRoot "..\neodash-patches\$Name"
        if (-not (Test-Path $Patch)) { continue }
        # With ErrorActionPreference=Stop, Windows PowerShell turns git's
        # stderr into a terminating error even with 2>$null, so relax it
        # around the checks and rely on the exit codes instead.
        $ErrorActionPreference = 'Continue'
        git apply --check $Patch 2>&1 | Out-Null
        $CanApply = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = 'Stop'
        # Not applicable forward means it is already in place. A reverse
        # check is not reliable here: a later patch edits the same lines,
        # so an earlier patch no longer reverses cleanly once it is applied.
        if ($CanApply) {
            Write-Host "Applying $Name ..." -ForegroundColor Cyan
            git apply $Patch
            if ($LASTEXITCODE -ne 0) { throw "Could not apply neodash-patches\$Name." }
        }
    }

    if (-not (Test-Path (Join-Path $NeodashDir 'node_modules'))) {
        Write-Host 'Installing dependencies (this takes a few minutes) ...' -ForegroundColor Cyan
        # NeoDash pins some peer deps loosely; --legacy-peer-deps avoids
        # npm 7+ refusing the tree on a clean machine.
        npm install --legacy-peer-deps
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }
    }

    Write-Host ''
    Write-Host 'Starting NeoDash on http://localhost:3000' -ForegroundColor Green
    Write-Host 'Leave this window open. Ctrl+C stops the server.' -ForegroundColor Green
    Write-Host ''

    # NeoDash's package.json "dev" script is  `yarn webpack-dev-server ...`,
    # so `npm run dev` fails with "yarn is not recognized" on a machine that
    # only has npm. webpack-dev-server is installed locally either way, so
    # call it directly when yarn is absent - same server, same port.
    if (Get-Command yarn -ErrorAction SilentlyContinue) {
        npm run dev
    } else {
        Write-Host 'yarn not found - running webpack-dev-server directly.' -ForegroundColor Yellow
        npx webpack-dev-server --mode development
    }
}
finally {
    Pop-Location
}
