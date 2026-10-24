# Creates a BatPlayer release and hands it to the BatSoft catalog repo.
#
#   1. `npm run tauri build` (skipped with -SkipBuild)
#   2. copies the newest `*-setup.exe` to <BatPack>\Releases\BatPlayer.exe
#      (the app name doubles as the release asset name)
#   3. writes <BatPack>\Releases\BatPlayer.json (version/sha256/size/builtAt)
#   4. unless -NoPublish: commits + pushes BatSoft's current branch;
#      its .github/workflows/publish-release.yml then verifies the SHA-256
#      and publishes the GitHub Release (tag batplayer-v<version>,
#      asset BatPlayer.exe, checksum in the notes).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\publish-release.ps1          # full release
#   powershell ... -SkipBuild -NoPublish                                          # dry run
#   powershell ... -Notes "first public build"                                    # extra notes
#
# Re-releasing an already-published version fails by design: bump the version
# in package.json, src-tauri\tauri.conf.json and src-tauri\Cargo.toml first.
param(
    [switch]$SkipBuild,
    [switch]$NoPublish,
    # The BatSoft catalog repo ("BatPack"); default: sibling of this repo.
    [string]$BatPackDir = "",
    [string]$Notes = ""
)
$ErrorActionPreference = 'Stop'

$appName = 'BatPlayer'
$repo = Split-Path $PSScriptRoot -Parent                       # ...\Projects\BatPlayer
$projects = Split-Path $repo -Parent                           # ...\Projects
if ($BatPackDir -eq "") { $BatPackDir = Join-Path $projects 'BatPack' }
if (-not (Test-Path (Join-Path $BatPackDir '.git'))) {
    throw "BatSoft repo with .git not found at '$BatPackDir' (pass -BatPackDir)"
}
$relDir = Join-Path $BatPackDir 'Releases'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)            # JSON sidecar must be plain UTF-8

Write-Host "target dir : $relDir"

# --- version -----------------------------------------------------------------
$version = (Get-Content (Join-Path $repo 'package.json') -Raw | ConvertFrom-Json).version

# --- build --------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host 'building: npm run tauri build (several minutes)...'
    Push-Location $repo
    try {
        npm run tauri build
        if ($LASTEXITCODE -ne 0) { throw 'npm run tauri build failed' }
    } finally { Pop-Location }
} else {
    Write-Host '-SkipBuild: reusing the newest existing bundle'
}

# --- locate the NSIS bundler output --------------------------------------------
$bundleDir = Join-Path $repo 'src-tauri\target\release\bundle\nsis'
$bundle = Get-ChildItem $bundleDir -Filter '*-setup.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bundle) { throw "no *-setup.exe in $bundleDir - run 'npm run tauri build' first" }
if ($bundle.Name -notlike "*_$version*") {
    Write-Warning "bundle '$($bundle.Name)' does not mention version $version (from package.json) - check for a stale version bump"
}

# --- copy into BatPack\Releases under the app name ------------------------------
New-Item -ItemType Directory -Force -Path $relDir | Out-Null
$target = Join-Path $relDir "$appName.exe"
Copy-Item $bundle.FullName $target -Force

# --- metadata sidecar (consumed by the BatSoft publish workflow) -----------------
$sha = (Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
$meta = [ordered]@{
    app     = $appName
    version = $version
    file    = "$appName.exe"
    sha256  = $sha
    size    = (Get-Item $target).Length
    builtAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    notes   = $Notes
}
[System.IO.File]::WriteAllText(
    (Join-Path $relDir "$appName.json"),
    ($meta | ConvertTo-Json),
    $utf8NoBom)

Write-Host ("placed    : {0} ({1:N1} MB, sha256 {2}...)" -f $target, ($meta.size / 1MB), $sha.Substring(0, 12))

# --- guard: same version already committed on BatSoft? ---------------------------
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$published = git -C $BatPackDir show "HEAD:Releases/$appName.json" 2>$null
$ErrorActionPreference = $prevEap
if ($published) {
    $old = (($published -join "`n") | ConvertFrom-Json).version
    if ($old -eq $version) {
        throw "$appName v$version is already released on BatSoft - bump the version everywhere first"
    }
}

# --- publish: commit + push; the workflow creates the GitHub Release --------------
if ($NoPublish) {
    Write-Host 'DRY RUN: files placed in Releases\ only - nothing committed or pushed.'
    exit 0
}

$branch = git -C $BatPackDir rev-parse --abbrev-ref HEAD
if (-not $branch) { throw 'could not resolve BatPack current branch' }
# the pipeline itself may still be uncommitted (first release on a fresh clone)
foreach ($nav in @('.github/workflows/publish-release.yml', 'Releases/README.md')) {
    if (Test-Path (Join-Path $BatPackDir ($nav -replace '/', '\'))) { git -C $BatPackDir add $nav }
}
git -C $BatPackDir add "Releases/$appName.exe" "Releases/$appName.json"
$staged = @(git -C $BatPackDir diff --cached --name-only)
if ($staged.Count -eq 0) { throw 'nothing staged in BatPack - unexpected' }
git -C $BatPackDir commit -m "release: $appName v$version"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed in BatPack' }
git -C $BatPackDir push origin $branch
if ($LASTEXITCODE -ne 0) { throw "git push origin $branch failed in BatPack" }

Write-Host ("pushed    : BatSoft/{0} - Actions creates tag 'batplayer-v{1}'" -f $branch, $version)
Write-Host 'watch     : https://github.com/DgharMohamed/BatSoft/actions'
Write-Host ("release   : https://github.com/DgharMohamed/BatSoft/releases/tag/batplayer-v{0}" -f $version)
