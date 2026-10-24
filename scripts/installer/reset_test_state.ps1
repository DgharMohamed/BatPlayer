# Resets the machine to a clean state for installer tests.
# Kills processes, runs the silent uninstaller if present, removes test leftovers.
$ErrorActionPreference = 'SilentlyContinue'
Get-Process -Name 'BatPlayer_Setup','batplayer' | Stop-Process -Force
Start-Sleep -Milliseconds 600

$dir = "$env:LOCALAPPDATA\BatPlayer"
if (Test-Path "$dir\uninstall.exe") {
    Start-Process "$dir\uninstall.exe" -ArgumentList '/S', "_?=$dir" -Wait
    Start-Sleep -Seconds 2
}

Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BatPlayer' -Recurse -Force
Remove-Item 'HKCU:\Software\BatSoft' -Recurse -Force
Remove-Item 'HKCU:\Software\BatPlayer' -Recurse -Force
Remove-Item $dir -Recurse -Force
Remove-Item "$env:APPDATA\com.batplayer.app" -Recurse -Force
Remove-Item "$env:LOCALAPPDATA\com.batplayer.app" -Recurse -Force

"== state after reset =="
"install dir   : $(Test-Path "$env:LOCALAPPDATA\BatPlayer")"
"uninst key    : $(Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BatPlayer')"
"BatSoft       : $(Test-Path 'HKCU:\Software\BatSoft')"
"setup running : $($null -ne (Get-Process -Name BatPlayer_Setup))"
"app running   : $($null -ne (Get-Process -Name batplayer))"
