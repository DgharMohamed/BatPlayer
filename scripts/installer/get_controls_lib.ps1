# Shared control-enumeration helpers for driver scripts (dotted into scripts).
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class GC2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint rel);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[GC2]::SetProcessDPIAware() | Out-Null

function Get-Controls {
    param([string]$procName)
    $p = Get-Process -Name $procName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return $null }
    $outer = $p.MainWindowHandle
    if ($outer -eq [IntPtr]::Zero) { return $null }
    $result = @()
    $h = $outer
    while ($h -ne [IntPtr]::Zero) {
        $cls = New-Object System.Text.StringBuilder 64
        [void][GC2]::GetClassName($h, $cls, 64)
        $txt = New-Object System.Text.StringBuilder 256
        [void][GC2]::GetWindowText($h, $txt, 256)
        $r = New-Object GC2+RECT
        [void][GC2]::GetWindowRect($h, [ref]$r)
        $result += [PSCustomObject]@{ h = $h; cls = $cls.ToString(); txt = $txt.ToString(); vis = [GC2]::IsWindowVisible($h); L = $r.L; T = $r.T; R = $r.R; B = $r.B }
        $child = [GC2]::GetWindow($h, 5)
        if ($child -ne [IntPtr]::Zero) {
            $h2 = $child
            while ($h2 -ne [IntPtr]::Zero) {
                $cls2 = New-Object System.Text.StringBuilder 64
                [void][GC2]::GetClassName($h2, $cls2, 64)
                $txt2 = New-Object System.Text.StringBuilder 256
                [void][GC2]::GetWindowText($h2, $txt2, 256)
                $r2 = New-Object GC2+RECT
                [void][GC2]::GetWindowRect($h2, [ref]$r2)
                $result += [PSCustomObject]@{ h = $h2; cls = $cls2.ToString(); txt = $txt2.ToString(); vis = [GC2]::IsWindowVisible($h2); L = $r2.L; T = $r2.T; R = $r2.R; B = $r2.B }
                $h2 = [GC2]::GetWindow($h2, 2)
            }
        }
        $h = [GC2]::GetWindow($h, 2)
    }
    return $result
}
