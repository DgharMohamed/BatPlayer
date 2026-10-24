# Samples the installer outer window rect + show-state every 250ms; catches the
# exact moment the window goes to the minimized/parked position (-32000).
param(
    [string]$ProcName = "BatPlayer_Setup",
    [int]$TimeoutSec = 120
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class TR2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct WINDOWPLACEMENT { public int length; public int flags; public int showCmd; public POINT ptMinPosition; public POINT ptMaxPosition; public RECT rcNormalPosition; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
'@
[TR2]::SetProcessDPIAware() | Out-Null

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
while (-not $p -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200; $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $p) { Write-Output "no process"; exit 1 }

$last = ""
while ((Get-Date) -lt $deadline) {
    $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { break }
    $h = $p.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) {
        $r = New-Object TR2+RECT
        [void][TR2]::GetWindowRect($h, [ref]$r)
        $wp = New-Object TR2+WINDOWPLACEMENT
        $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf($wp)
        [void][TR2]::GetWindowPlacement($h, [ref]$wp)
        $state = switch ($wp.showCmd) { 2 { 'min' } 3 { 'max' } default { 'normal' } }
        $line = "{0:HH:mm:ss.fff} rect={1},{2},{3},{4} state={5} fg={6}" -f (Get-Date), $r.L, $r.T, $r.R, $r.B, $state, ([int]$wp.ptMinPosition.X)
        if ($line -ne $last) { Write-Output $line; $last = $line }
    } else {
        $line = "{0:HH:mm:ss.fff} NO-HWND" -f (Get-Date)
        if ($line -ne $last) { Write-Output $line; $last = $line }
    }
    Start-Sleep -Milliseconds 250
}
