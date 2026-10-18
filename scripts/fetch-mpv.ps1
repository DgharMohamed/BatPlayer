# Downloads the libmpv development package (dll + headers) for Windows and
# vendors the pieces BatPlayer's build needs into src-tauri/mpv/.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts/fetch-mpv.ps1

$ErrorActionPreference = "Stop"

$libmpvVersion = "20261011-git-accb7b2821"
$arch = "x86_64"
$url = "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-$arch-$libmpvVersion.7z/download"
$temp = Join-Path $env:TEMP "batplayer-mpv-dev"
$out = "$PSScriptRoot\..\src-tauri\mpv"

New-Item -ItemType Directory -Force -Path $temp | Out-Null
New-Item -ItemType Directory -Force -Path $out | Out-Null

$archive = Join-Path $temp "mpv-dev.7z"
if (-not (Test-Path $archive)) {
  Write-Output "downloading $url"
  # sourceforge /download redirects to a mirror; follow it
  curl.exe -sL -o $archive $url
}

$sevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $sevenZip)) { throw "7-Zip not found at $sevenZip" }
& $sevenZip x -y "-o$temp" $archive | Out-Null

$extracted = Get-ChildItem -Path $temp -Recurse -Filter "libmpv-2.dll" | Select-Object -First 1
if (-not $extracted) { throw "libmpv-2.dll not found in the archive" }

Copy-Item $extracted.FullName (Join-Path $out "libmpv-2.dll") -Force
Write-Output ("vendored " + (Join-Path $out "libmpv-2.dll"))

# Generate the MSVC import library from the DLL exports (the archive only
# ships a GNU-style import library).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -products "*" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw "Visual Studio C++ tools not found" }
$tools = Get-ChildItem "$vsPath\VC\Tools\MSVC" | Sort-Object Name -Descending | Select-Object -First 1
$dumpbin = "$vsPath\VC\Tools\MSVC\$($tools.Name)\bin\Hostx64\x64\dumpbin.exe"
$libexe = "$vsPath\VC\Tools\MSVC\$($tools.Name)\bin\Hostx64\x64\lib.exe"

$exports = & $dumpbin /exports $extracted.FullName |
  Where-Object { $_ -match "^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)$" } |
  ForEach-Object { ($_ -replace "^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+", "").Trim() }

$def = Join-Path $out "mpv.def"
"LIBRARY libmpv-2.dll" | Set-Content $def -Encoding ASCII
"EXPORTS" | Add-Content $def -Encoding ASCII
$exports | ForEach-Object { "  $_" | Add-Content $def -Encoding ASCII }
& $libexe "/def:$def" /machine:x64 "/out:$(Join-Path $out 'mpv.lib')" | Out-Null
Write-Output ("generated mpv.lib with " + $exports.Count + " exports")
