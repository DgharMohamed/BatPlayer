# Compiles the production NSIS template (src-tauri/nsis/installer.nsi) by splicing
# Tauri's placeholder values out of the bundler's last-generated staged installer.nsi.
# Compiles in-place in the staging dir so ${__FILEDIR__}\..\..\..\.. still resolves to src-tauri.
$ErrorActionPreference = 'Stop'
$repo     = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # scripts/installer -> repo root
$templatePath = "$repo\src-tauri\nsis\installer.nsi"
$staging  = "$repo\src-tauri\target\release\nsis\x64"
$stagedPath = "$staging\installer.nsi"
$makensis = Join-Path $env:LOCALAPPDATA 'tauri\NSIS\makensis.exe'

$enc = [System.Text.UTF8Encoding]::new($false)   # UTF-8 WITHOUT BOM
$template = [System.IO.File]::ReadAllText($templatePath, $enc)
$staged   = [System.IO.File]::ReadAllText($stagedPath, $enc)

# --- 1) splice expanded language_slots {{#each language_files}} ... {{/each}} block ---
$langLines = ([regex]::Matches($staged, '(?m)!\s*include\s+"[A-Za-z]:[^"]*\.nsh"') |
              ForEach-Object { $_.Value.TrimEnd() })
if ($langLines.Count -eq 0) { throw 'No absolute-path language includes found in staged file' }
Write-Host "Language includes from staged: $($langLines -join ' | ')"
$body = [regex]::Replace($template,
    '(?s)\{\{#each language_files\}\}.*?\{\{/each\}\}',
    { param($m) ($langLines -join "`r`n") })

# --- 2) splice scalar {{token}} values into !define lines ---
$n = 0
$body = [regex]::Replace($body,
    '(?m)!\s*define\s+(\w+)\s+"\{\{([^}]+)\}\}"',
    [System.Text.RegularExpressions.MatchEvaluator]{
      param($m)
      $name = $m.Groups[1].Value
      $sm = [regex]::Match($staged, '(?m)!\s*define\s+' + [regex]::Escape($name) + '\s+"([^"]*)"')
      if (-not $sm.Success) { throw "Staged file has no define for $name" }
      $script:n++
      return '!define ' + $name + ' "' + $sm.Groups[1].Value + '"'
    })
if ($script:n -lt 20) { throw "Only $script:n scalar tokens spliced - something is off" }

if ([regex]::IsMatch($body, '\{\{')) {
  foreach ($m in [regex]::Matches($body, '.*\{\{[^}]*\}\}.*')) { Write-Host "LEFTOVER: $($m.Value)" }
  throw 'Leftover placeholder tokens after splice'
}

# --- 3) backup staged file, write spliced file ---
# CRITICAL: makensis compiles Unicode scripts as ACP unless a UTF-8 BOM is present
# (Tauri's bundler writes the staged installer.nsi WITH BOM). The repo template file
# itself stays BOM-less; only this compile artifact gets the BOM.
# Keep a pristine copy of the bundler's output while it still holds placeholder
# tokens; this run overwrites the staged file with spliced values.
if ($staged.Contains('{{')) { Copy-Item $stagedPath "$staging\installer.pre-splice.nsi" -Force }
$bomEnc = [System.Text.UTF8Encoding]::new($true)   # UTF-8 WITH BOM
[System.IO.File]::WriteAllText($stagedPath, $body, $bomEnc)
$check = [System.IO.File]::ReadAllBytes($stagedPath)
$hasBom = ($check.Length -ge 3 -and $check[0] -eq 0xEF -and $check[1] -eq 0xBB -and $check[2] -eq 0xBF)
if (-not $hasBom) { throw 'Spliced file lost its BOM!' }
Write-Host ("Spliced file written: {0} bytes, BOM={1}" -f $check.Length, $hasBom)

# --- 4) compile ---
if (Test-Path "$staging\nsis-output.exe") { Remove-Item "$staging\nsis-output.exe" -Force }
Push-Location $staging
try {
  & $makensis 'installer.nsi'
  $code = $LASTEXITCODE
} finally { Pop-Location }
if ($code -ne 0) { throw "makensis failed with exit code $code" }

$out = Get-Item "$staging\nsis-output.exe" -ErrorAction Stop
Write-Host "SUCCESS: $($out.FullName) ($('{0:N1} MB' -f ($out.Length / 1MB)))"
