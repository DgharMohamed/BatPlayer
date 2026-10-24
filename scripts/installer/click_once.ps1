# One-shot: wait for a control by text on the live installer, bring window to top, real-click it.
param(
    [string]$ProcName = "BatPlayer_Setup",
    [string]$Text,
    [int]$TimeoutSec = 30,
    [string[]]$CtlClass = @('Static','Button')
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CO {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hpos, uint f);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
'@
[CO]::SetProcessDPIAware() | Out-Null
. "$PSScriptRoot\get_controls_lib.ps1"

function Find-Ctl2 {
    param([string]$name, [string]$text)
    $list = Get-Controls $name
    if (-not $list) { return $null }
    foreach ($c in $list) { if ($c.vis -and ($CtlClass -contains $c.cls) -and $c.txt.Trim() -eq $text) { return $c } }
    return $null
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$ctl = $null
while ((Get-Date) -lt $deadline) {
    $ctl = Find-Ctl2 $ProcName $Text
    if ($ctl) { break }
    Start-Sleep -Milliseconds 300
}
if (-not $ctl) { Write-Output "NOT FOUND: '$Text'"; exit 2 }
$x = [int](($ctl.L + $ctl.R) / 2); $y = [int](($ctl.T + $ctl.B) / 2)
$p = Get-Process -Name $ProcName | Select-Object -First 1
$null = [CO]::SetWindowPos($p.MainWindowHandle, [IntPtr]0, 0, 0, 0, 0, 0x1 -bor 0x2 -bor 0x10)
$null = [CO]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 300
# re-resolve rect after bring-to-top (window may have moved)
$ctl = Find-Ctl2 $ProcName $Text
$x = [int](($ctl.L + $ctl.R) / 2); $y = [int](($ctl.T + $ctl.B) / 2)
$null = [CO]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 150
[CO]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[CO]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
$still = Find-Ctl2 $ProcName $Text
Write-Output ("clicked '{0}' at {1},{2} - still visible: {3}" -f $Text, $x, $y, ($null -ne $still))
