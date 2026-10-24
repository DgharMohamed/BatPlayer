param([string]$Action = "dump")  # dump | click-finish
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WD2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint rel);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[WD2]::SetProcessDPIAware() | Out-Null

function Dump-Tree($node, $depth) {
    while ($node -ne [IntPtr]::Zero) {
        $cls = New-Object System.Text.StringBuilder 64
        [void][WD2]::GetClassName($node, $cls, 64)
        $txt = New-Object System.Text.StringBuilder 160
        [void][WD2]::GetWindowText($node, $txt, 160)
        $r = New-Object WD2+RECT
        [void][WD2]::GetWindowRect($node, [ref]$r)
        $vis = [WD2]::IsWindowVisible($node)
        $id = [WD2]::GetDlgCtrlID($node)
        $pad = ' ' * ($depth * 2)
        "$pad CLS=$($cls.ToString()) ID=$id VIS=$vis TXT=[$($txt.ToString())] RECT=$($r.L),$($r.T),$($r.R),$($r.B)"
        $grand = [WD2]::GetWindow($node, 5)
        if ($grand -ne [IntPtr]::Zero) { Dump-Tree $grand ($depth + 1) }
        $node = [WD2]::GetWindow($node, 2)
    }
}

$p = Get-Process -Name "BatPlayer_Setup" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output "NO PROCESS"; exit 1 }
"outer: $($p.MainWindowHandle)"
Dump-Tree $p.MainWindowHandle 0
