# Compiles the welcome-only NSIS preview, launches it, captures a window
# screenshot, and terminates it - so installer UI edits can be verified
# visually without running the real installer. With -ExePath, skips the
# compile and screenshots an existing exe (e.g. the real installer).
param(
    [string]$ExePath = "",
    [string]$OutPng = "",
    [switch]$KeepRunning
)
$ErrorActionPreference = "Stop"

$makensis = Join-Path $env:LOCALAPPDATA 'tauri\NSIS\makensis.exe'
$temp = [System.IO.Path]::GetTempPath()
if ($OutPng -eq "") { $OutPng = Join-Path $temp 'batplayer-welcome-preview.png' }

$exe = $ExePath
if ($exe -eq "") {
    $exe = Join-Path $temp 'batplayer-welcome-preview.exe'
    $icons = Join-Path (Split-Path $PSScriptRoot -Parent) 'src-tauri\icons'
    & $makensis /V2 "/DBATPLAYER_ICONS=$icons" "/DBATPLAYER_OUT=$exe" (Join-Path $PSScriptRoot 'welcome-preview.nsi') | Select-Object -Last 4
    if ($LASTEXITCODE -ne 0) { throw "makensis failed" }
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int z, uint f);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@
Add-Type -AssemblyName System.Drawing
[Win]::SetProcessDPIAware() | Out-Null

$process = Start-Process $exe -PassThru
try {
    $process.WaitForInputIdle(5000) | Out-Null
    # Let the custom page paint, fonts settle, and the image extract land.
    Start-Sleep -Milliseconds 1200
    $process.Refresh()
    $hwnd = $process.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { throw "no main window" }

    # Pin the window topmost and park it on-screen so nothing overlaps it.
    [Win]::SetWindowPos($hwnd, [IntPtr](-1), 80, 60, 0, 0, 0x0041) | Out-Null  # NOSIZE|SHOWWINDOW|TOPMOST
    Start-Sleep -Milliseconds 700

    $rect = New-Object Win+RECT
    [Win]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $width = $rect.R - $rect.L
    $height = $rect.B - $rect.T

    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $g.GetHdc()
    # 2 = PW_RENDERFULLCONTENT (DWM-composited content, fonts included)
    [Win]::PrintWindow($hwnd, $hdc, 2) | Out-Null
    $g.ReleaseHdc($hdc)
    $g.Dispose()
    $bitmap.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    "captured ${width}x${height} -> $OutPng"
} finally {
    if (-not $KeepRunning) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
}
