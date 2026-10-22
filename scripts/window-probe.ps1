# Runtime probe for BatPlayer's window-manager responsiveness (Windows).
#
# Proves (rather than assumes) on the running app, all through Win32:
#   1. the frameless window keeps its resizable/maximizable/minimizable styles,
#   2. Tauri's invisible "drag resize" ring child exists and answers
#      WM_NCHITTEST with the right edge/corner results, and cursor points over
#      the edges route to it (so edge-drag and Snap work),
#   3. real scripted drags on edge bands engage the OS modal sizing loop and
#      the window follows the cursor until release (end-to-end edge resize),
#   4. minimize/restore round-trips,
#   5. maximize lands on the monitor work area (the taskbar stays visible),
#   6. after an external snap-like resize the webview and the mpv surface
#      follow the new client area (responsive layout at any size).
#
# Attach to a running instance:
#     powershell -ExecutionPolicy Bypass -File scripts/window-probe.ps1
# Window geometry is restored afterwards; the app is left running.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WProbe
{
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    public struct POINT { public int X; public int Y; }
    public struct MONITORINFO { public uint cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowLongW(IntPtr h, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string cls, string name);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfoW(IntPtr mon, ref MONITORINFO info);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);

    public const int GWL_STYLE = -16;
    public const uint WM_NCHITTEST = 0x0084;

    public static string HitName(IntPtr r)
    {
        switch ((uint)r)
        {
            case 1: return "HTCLIENT";
            case 2: return "HTCAPTION";
            case 10: return "HTLEFT";
            case 11: return "HTRIGHT";
            case 12: return "HTTOP";
            case 13: return "HTTOPLEFT";
            case 14: return "HTTOPRIGHT";
            case 15: return "HTBOTTOM";
            case 16: return "HTBOTTOMLEFT";
            case 17: return "HTBOTTOMRIGHT";
            default: return ((uint)r).ToString();
        }
    }

    public static string HitNameAtPoint(IntPtr target, POINT p)
    {
        int packed = (p.Y << 16) | (p.X & 0xFFFF);
        return HitName(SendMessage(target, WM_NCHITTEST, IntPtr.Zero,
            (IntPtr)packed));
    }

    public static string ClassOf(IntPtr h)
    {
        var sb = new StringBuilder(64);
        GetClassName(h, sb, 64);
        return sb.ToString();
    }

    public static RECT WindowRect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
    public static RECT ClientRect(IntPtr h) { RECT r; GetClientRect(h, out r); return r; }

    /// FindWindowExW by class with a real NULL name - PowerShell marshals
    /// $null as "", which would match only titleless windows instead.
    public static IntPtr FindChildByClass(IntPtr parent, string cls)
    {
        return FindWindowExW(parent, IntPtr.Zero, cls, null);
    }

    /// Largest child window that is not of `excludeClass` - the WebView2 host.
    public static IntPtr FindLargestChild(IntPtr parent, string excludeClass)
    {
        IntPtr best = IntPtr.Zero; long bestArea = 0;
        EnumChildWindows(parent, (h, l) =>
        {
            if (ClassOf(h) != excludeClass)
            {
                RECT w; GetWindowRect(h, out w);
                long area = (long)(w.Right - w.Left) * (w.Bottom - w.Top);
                if (area > bestArea) { bestArea = area; best = h; }
            }
            return true;
        }, IntPtr.Zero);
        return best;
    }

    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumChildProc proc, IntPtr lp);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lp);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadCursorW(IntPtr h, IntPtr id);

    // ---- real-input helpers: scripted mouse drags must reach the ring ----
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
    [DllImport("user32.dll")] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
    public const uint MOUSEEVENTF_MOVE = 1;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    public const uint MOUSEEVENTF_LEFTDOWN = 2;
    public const uint MOUSEEVENTF_LEFTUP = 4;

    /// Move/inject-click at an absolute screen point. Coordinates are given in
    /// the physical pixel space the (process-DPI-aware) helper sees, which is
    /// what SendInput's 0..65535 absolute range spans for the primary monitor.
    public static void MouseAbs(int x, int y, uint extraFlags)
    {
        var inputs = new INPUT[1];
        inputs[0].type = 0;
        inputs[0].mi.dx = (int)((x * 65536L) / GetSystemMetrics(0)); // SM_CXSCREEN
        inputs[0].mi.dy = (int)((y * 65536L) / GetSystemMetrics(1)); // SM_CYSCREEN
        inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | extraFlags;
        uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1) throw new Exception("SendInput was blocked (sent=" + sent + ")");
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO
    {
        public uint cbSize; public uint flags;
        public IntPtr hwndActive; public IntPtr hwndFocus; public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner; public IntPtr hwndMoveSize; public IntPtr hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO info);

    /// True while the OS modal sizing/moving loop for `hwnd` is running
    /// (entered from a real border click on the resize ring).
    public static bool InSizingLoop(IntPtr hwnd)
    {
        uint pid; uint tid = GetWindowThreadProcessId(hwnd, out pid);
        var g = new GUITHREADINFO();
        g.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
        if (!GetGUIThreadInfo(tid, ref g)) return false;
        return g.hwndMoveSize == hwnd || g.hwndCapture == hwnd;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CURSORINFO { public uint cbSize; public uint flags; public IntPtr hCursor; public POINT pt; }
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO info);

    /// The shared system cursor over the current mouse point is the horizontal
    /// size cursor (IDC_SIZEWE) - the OS visibly confirmed an edge hit-test.
    public static bool CursorIsSizeWe()
    {
        var ci = new CURSORINFO();
        ci.cbSize = (uint)Marshal.SizeOf(typeof(CURSORINFO));
        if (!GetCursorInfo(ref ci)) return false;
        IntPtr sizeWe = LoadCursorW(IntPtr.Zero, (IntPtr)32644); // IDC_SIZEWE
        return ci.hCursor == sizeWe;
    }

    /// The top-level window of `pid` that owns our mpv surface child - not
    /// transitively through WebView2's own hidden windows.
    public static IntPtr FindMainWindow(uint pid, string surfaceClass)
    {
        IntPtr main = IntPtr.Zero;
        EnumWindows((h, l) =>
        {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h) &&
                FindWindowExW(h, IntPtr.Zero, surfaceClass, null) != IntPtr.Zero)
            {
                main = h; return false;
            }
            return true;
        }, IntPtr.Zero);
        return main;
    }

    /// Diagnostics: first-level child classes of one window.
    public static string LogChildClasses(IntPtr parent)
    {
        var kids = new StringBuilder();
        EnumChildWindows(parent, (c, l2) => { kids.Append(ClassOf(c)).Append(' '); return true; }, IntPtr.Zero);
        return kids.ToString();
    }

    /// Diagnostics: every top-level window of `pid` with class, rect and
    /// first-level child classes.
    public static string LogAllWindows(uint pid)
    {
        var lines = new System.Collections.Generic.List<string>();
        EnumWindows((h, l) =>
        {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid) return true;
            RECT w; GetWindowRect(h, out w);
            var kids = new StringBuilder();
            EnumChildWindows(h, (c, l2) => { kids.Append(ClassOf(c)).Append(' '); return true; }, IntPtr.Zero);
            lines.Add(string.Format("top {0} visible={1} rect=({2},{3})-({4},{5}) children: {6}",
                ClassOf(h), IsWindowVisible(h), w.Left, w.Top, w.Right, w.Bottom, kids));
            return true;
        }, IntPtr.Zero);
        return string.Join(Environment.NewLine, lines);
    }
}
"@

$failures = New-Object System.Collections.Generic.List[string]
function Assert-That {
  param([string] $Name, [bool] $Condition, [string] $Details)
  if ($Condition) {
    Write-Output ("PASS  {0}" -f $Name)
  } else {
    Write-Output ("FAIL  {0}: {1}" -f $Name, $Details)
    $failures.Add($Name)
  }
}

[void][WProbe]::SetProcessDPIAware()

$logDir = Join-Path ([IO.Path]::GetTempPath()) "vlctest\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$report = New-Object System.Collections.Generic.List[string]
function Log { param([string] $Line) $report.Add($Line) }

$proc = Get-Process -Name batplayer -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { throw "no running batplayer with a window was found" }
# MainWindowHandle can resolve to one of WebView2's own windows; the real
# Tauri top-level is the process window that owns our mpv surface child.
$hwnd = [IntPtr][WProbe]::FindMainWindow($proc.Id, "BatPlayerVideoSurface")
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Output "surface-owner window not found; all top-level windows of pid $($proc.Id):"
    [WProbe]::LogAllWindows($proc.Id) | ForEach-Object { Write-Output $_ }
    throw "tao main window (owner of the mpv surface) not found for pid $($proc.Id)"
}
Log ("main window class={0}" -f [WProbe]::ClassOf($hwnd))
Log ("children: {0}" -f ([WProbe]::LogChildClasses($hwnd)))

# ---------------------------------------------------------------------------
# Phase A: styles + child inventory in a normalized restored state.
# The app restores its own boot size (1280x720 logical centered); normalize
# to a modest size so the band points sit clear of the taskbar, then read.
# ---------------------------------------------------------------------------
[void][WProbe]::SetWindowPos($hwnd, [IntPtr]::Zero, 200, 150, 1000, 600, 0x0004)
Start-Sleep -Milliseconds 700

$before = [WProbe]::WindowRect($hwnd)
Log ("rect=({0},{1})-({2},{3})" -f $before.Left, $before.Top, $before.Right, $before.Bottom)
Log ("dpi={0}" -f [WProbe]::GetDpiForWindow($hwnd))
$style = [WProbe]::GetWindowLongW($hwnd, [WProbe]::GWL_STYLE)
Log ("styles=0x{0:X}" -f $style)
$WS_CAPTION = 0x00C00000; $WS_SIZEBOX = 0x00040000; $WS_MAXIMIZEBOX = 0x00010000; $WS_MINIMIZEBOX = 0x00020000

Assert-That "style keeps WS_SIZEBOX (resizable)"        (($style -band $WS_SIZEBOX) -ne 0)      ("styles=0x{0:X}" -f $style)
Assert-That "style keeps WS_MAXIMIZEBOX (snap/maximize)" (($style -band $WS_MAXIMIZEBOX) -ne 0) ("styles=0x{0:X}" -f $style)
Assert-That "style keeps WS_MINIMIZEBOX (minimize)"      (($style -band $WS_MINIMIZEBOX) -ne 0) ("styles=0x{0:X}" -f $style)

$ring = [WProbe]::FindChildByClass($hwnd, "TAURI_DRAG_RESIZE_BORDERS")
Assert-That "Tauri drag/resizing ring child exists" ($ring -ne [IntPtr]::Zero) "ring not found under the main window"
$surface = [WProbe]::FindChildByClass($hwnd, "BatPlayerVideoSurface")
Assert-That "mpv surface child exists" ($surface -ne [IntPtr]::Zero) "video surface not found"

# ---------------------------------------------------------------------------
# Phase B: hit-testing, direct (SendMessage to the ring), routed
# (WindowFromPoint decides which window the OS hands the cursor to) and real
# scripted drags. Routing checks require OUR window to be the top-level owner
# of the screen point: any overlapping window of the probe host itself would
# otherwise shadow the ring, so the window is brought to the top first.
# ---------------------------------------------------------------------------
$WS_MINIMIZE = 6; $WS_RESTORE = 9; $WS_MAXIMIZE = 3

$HWND_TOPMOST = [IntPtr](-1)
$HWND_NOTOPMOST = [IntPtr](-2)
function Bring-MainToFront {
  # Focus is not needed for pointer routing; what matters is z-order. The
  # topmost-then-untopmost trick raises the window above every normal
  # (non-topmost) window of the probe host without fighting focus policy.
  $swp = 0x0002 -bor 0x0001 -bor 0x0010   # NOMOVE | NOSIZE | NOACTIVATE
  [void][WProbe]::SetWindowPos($hwnd, $HWND_TOPMOST, 0, 0, 0, 0, $swp)
  Start-Sleep -Milliseconds 150
  [void][WProbe]::SetWindowPos($hwnd, $HWND_NOTOPMOST, 0, 0, 0, 0, $swp)
  [void][WProbe]::SetForegroundWindow($hwnd)  # best-effort, for click activation
  Start-Sleep -Milliseconds 250
}
Bring-MainToFront

# Band points must be INSIDE the client area (the ring covers the client
# rectangle's outermost border_x/border_y pixels only; the ~7px invisible
# frame outside belongs to tao's own nonclient handling).
$clientL = $before.Left + 9    # client left edge + band pixels
$clientR = $before.Right - 10  # client right edge band
$clientT = $before.Top + 4     # client top edge band
$clientB = $before.Bottom - 10 # client bottom edge band

$cases = @(
  @{ name = "left edge";           x = $clientL; y = [int](($before.Top + $before.Bottom) / 2); want = "HTLEFT" },
  @{ name = "right edge";          x = $clientR; y = [int](($before.Top + $before.Bottom) / 2); want = "HTRIGHT" },
  @{ name = "top edge";            x = [int](($before.Left + $before.Right) / 2); y = $clientT; want = "HTTOP" },
  @{ name = "bottom edge";         x = [int](($before.Left + $before.Right) / 2); y = $clientB; want = "HTBOTTOM" },
  @{ name = "bottom-right corner"; x = $clientR; y = $clientB; want = "HTBOTTOMRIGHT" }
)

foreach ($case in $cases) {
  $pt = New-Object WProbe+POINT
  $pt.X = $case.x; $pt.Y = $case.y
  $direct = [WProbe]::HitNameAtPoint($ring, $pt)
  Assert-That "$($case.name) answers $($case.want)" ($direct -eq $case.want) "ring says $direct"

  $routed = [WProbe]::WindowFromPoint($pt)
  $routedClass = [WProbe]::ClassOf($routed)
  Assert-That "$($case.name) routes to the resize ring" ($routedClass -eq "TAURI_DRAG_RESIZE_BORDERS") "point hit class $routedClass"
}

# ---------------------------------------------------------------------------
# Phase B2: real scripted drags. The ring must convert a real mouse click on
# an edge band into the OS modal sizing loop, and the window must follow the
# cursor until release. This is the end-to-end proof for edge-drag resizing.
# ---------------------------------------------------------------------------

function Test-EdgeDrag {
  param([string] $Name, [string] $HT, [long] $CursorId, [int] $StartX, [int] $StartY, [int] $MoveX, [int] $MoveY, [int] $ExpectDx, [int] $ExpectDy)
  Bring-MainToFront
  $rect0 = [WProbe]::WindowRect($hwnd)

  # cursor settles on the band; the OS must already show the size cursor
  # matching the hit-test result the ring answers
  [void][WProbe]::MouseAbs($StartX, $StartY, 0)
  Start-Sleep -Milliseconds 300
  $weCursor = [WProbe]::LoadCursorW([IntPtr]::Zero, [IntPtr]$CursorId)
  $ci = New-Object WProbe+CURSORINFO
  $ci.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf([type][WProbe+CURSORINFO])
  $cursorOk = $false
  for ($try = 0; $try -lt 3; $try++) {
    [void][WProbe]::GetCursorInfo([ref]$ci)
    $cursorOk = ($ci.hCursor -eq $weCursor)
    if ($cursorOk) { break }
    Start-Sleep -Milliseconds 250
  }
  Assert-That "${Name}: cursor over the band is the $HT size cursor" $cursorOk ("OS cursor handle 0x{0:X} at screen ({1},{2}), wanted 0x{3:X}" -f $ci.hCursor.ToInt64(), $ci.pt.X, $ci.pt.Y, $weCursor.ToInt64())

  # press: the ring forwards NCLBUTTONDOWN to the parent, the OS starts the
  # modal sizing loop for the window
  [void][WProbe]::MouseAbs($StartX, $StartY, [WProbe]::MOUSEEVENTF_LEFTDOWN)
  Start-Sleep -Milliseconds 120
  Assert-That "${Name}: click engages the OS sizing loop" ([WProbe]::InSizingLoop($hwnd)) "GetGUIThreadInfo shows no move/size loop for the window"

  # drag and check the geometry live
  [void][WProbe]::MouseAbs(($StartX + $MoveX), ($StartY + $MoveY), 0)
  Start-Sleep -Milliseconds 150
  $rectMid = [WProbe]::WindowRect($hwnd)
  [void][WProbe]::MouseAbs(($StartX + $MoveX), ($StartY + $MoveY), [WProbe]::MOUSEEVENTF_LEFTUP)
  Start-Sleep -Milliseconds 400
  Assert-That "${Name}: sizing loop ended on release" (-not [WProbe]::InSizingLoop($hwnd)) "loop still engaged after LEFTUP"

  $rect1 = [WProbe]::WindowRect($hwnd)
  $dW = ($rect1.Right - $rect1.Left) - ($rect0.Right - $rect0.Left)
  $dH = ($rect1.Bottom - $rect1.Top) - ($rect0.Bottom - $rect0.Top)
  Log ("{0}: rect0=({1},{2})-({3},{4}) mid=({5},{6})-({7},{8}) rect1=({9},{10})-({11},{12}) loop-mid={13}" -f `
    $Name, $rect0.Left, $rect0.Top, $rect0.Right, $rect0.Bottom, `
    $rectMid.Left, $rectMid.Top, $rectMid.Right, $rectMid.Bottom, `
    $rect1.Left, $rect1.Top, $rect1.Right, $rect1.Bottom, [WProbe]::InSizingLoop($hwnd))
  Assert-That "${Name}: window follows the cursor" `
    ([Math]::Abs($dW - $ExpectDx) -le 6 -and [Math]::Abs($dH - $ExpectDy) -le 6) `
    ("window moved W{0:+#;-#;0} H{1:+#;-#;0}, expected ({2:+#;-#;0},{3:+#;-#;0}); mid-drag w={4}" -f $dW, $dH, $ExpectDx, $ExpectDy, ($rectMid.Right - $rectMid.Left))

  # restore so later phases start from the known geometry
  [void][WProbe]::SetWindowPos($hwnd, [IntPtr]::Zero, $before.Left, $before.Top, `
    ($before.Right - $before.Left), ($before.Bottom - $before.Top), 0x0004)
  Start-Sleep -Milliseconds 400
}

# Left edge: dragging right moves the left edge inward, so the width shrinks
# by the cursor delta. Bottom edge: dragging down grows the height 1:1.
Test-EdgeDrag -Name "real left-edge drag" -HT HTLEFT -CursorId 32644 `
  -StartX $clientL -StartY ([int](($before.Top + $before.Bottom) / 2)) `
  -MoveX 60 -MoveY 0 -ExpectDx (-60) -ExpectDy 0
Test-EdgeDrag -Name "real bottom-edge drag" -HT HTBOTTOM -CursorId 32645 `
  -StartX ([int](($before.Left + $before.Right) / 2)) -StartY $clientB `
  -MoveX 0 -MoveY 60 -ExpectDx 0 -ExpectDy 60

# ---------------------------------------------------------------------------
# Phase C: minimize / restore round trip
# ---------------------------------------------------------------------------
[void][WProbe]::ShowWindow($hwnd, 6)
Start-Sleep -Milliseconds 900
Assert-That "minimize lands the window iconic" ([WProbe]::IsIconic($hwnd)) "IsIconic=false after SW_MINIMIZE"
[void][WProbe]::ShowWindow($hwnd, 9)
Start-Sleep -Milliseconds 900
$afterMin = [WProbe]::WindowRect($hwnd)
Assert-That "restore returns the pre-minimize geometry" `
  ([Math]::Abs($afterMin.Left - $before.Left) -le 2 -and [Math]::Abs($afterMin.Top - $before.Top) -le 2 -and
   [Math]::Abs($afterMin.Right - $before.Right) -le 2 -and [Math]::Abs($afterMin.Bottom - $before.Bottom) -le 2) `
  ("before ({0},{1})-({2},{3}) after ({4},{5})-({6},{7})" -f `
    $before.Left, $before.Top, $before.Right, $before.Bottom, `
    $afterMin.Left, $afterMin.Top, $afterMin.Right, $afterMin.Bottom)

# ---------------------------------------------------------------------------
# Phase D: maximize -> monitor work area (taskbar visible), restore
# ---------------------------------------------------------------------------
[void][WProbe]::ShowWindow($hwnd, 3)
Start-Sleep -Milliseconds 1100
$max = [WProbe]::WindowRect($hwnd)
$mon = [IntPtr][WProbe]::MonitorFromWindow($hwnd, 2)  # MONITOR_DEFAULTTONEAREST
$mi = New-Object WProbe+MONITORINFO
$mi.cbSize = 40
[void][WProbe]::GetMonitorInfoW($mon, [ref]$mi)
Log ("maximized rect=({0},{1})-({2},{3})  work=({4},{5})-({6},{7})  monitor=({8},{9})-({10},{11})" -f `
  $max.Left, $max.Top, $max.Right, $max.Bottom, `
  $mi.rcWork.Left, $mi.rcWork.Top, $mi.rcWork.Right, $mi.rcWork.Bottom, `
  $mi.rcMonitor.Left, $mi.rcMonitor.Top, $mi.rcMonitor.Right, $mi.rcMonitor.Bottom)
Assert-That "maximize is zoomed" ([WProbe]::IsZoomed($hwnd)) "IsZoomed=false"
# The outer rect grows past the work area by the invisible resize frame; what
# matters for the taskbar is the client area.
$mc = [WProbe]::ClientRect($hwnd)
Assert-That "maximize respects the taskbar (client == work area)" `
  ($mc.Left -ge 0 -and $mc.Top -ge 0 -and
   $mc.Right -le $mi.rcWork.Right + 2 -and $mc.Bottom -le $mi.rcWork.Bottom + 2 -and
   $mc.Bottom -lt $mi.rcMonitor.Bottom - 2) `
  ("client ({0},{1})-({2},{3}) work=({4},{5})-({6},{7}) monitor=({8},{9})-({10},{11})" -f `
    $mc.Left, $mc.Top, $mc.Right, $mc.Bottom, `
    $mi.rcWork.Left, $mi.rcWork.Top, $mi.rcWork.Right, $mi.rcWork.Bottom, `
    $mi.rcMonitor.Left, $mi.rcMonitor.Top, $mi.rcMonitor.Right, $mi.rcMonitor.Bottom)
[void][WProbe]::ShowWindow($hwnd, 9)
Start-Sleep -Milliseconds 900
$back = [WProbe]::WindowRect($hwnd)
Assert-That "unmaximize returns the original geometry" `
  ([Math]::Abs($back.Left - $before.Left) -le 2 -and [Math]::Abs($back.Top - $before.Top) -le 2 -and
   [Math]::Abs($back.Right - $before.Right) -le 2 -and [Math]::Abs($back.Bottom - $before.Bottom) -le 2) `
  ("after maximize+restore ({0},{1})-({2},{3})" -f $back.Left, $back.Top, $back.Right, $back.Bottom)

# ---------------------------------------------------------------------------
# Phase E: external snap-like resize (the Win+arrow path is a SetWindowPos)
# and a small-window shrink: the webview host and mpv surface must follow.
# ---------------------------------------------------------------------------
function Test-SnapResize {
  param([string] $Name, [int] $X, [int] $Y, [int] $Cx, [int] $Cy, [string] $SaveShot)
  [void][WProbe]::SetWindowPos($hwnd, [IntPtr]::Zero, $X, $Y, $Cx, $Cy, 0x0004)
  Start-Sleep -Milliseconds 1000
  $r = [WProbe]::WindowRect($hwnd)
  Assert-That "$Name sets the window size" `
    ([Math]::Abs(($r.Right - $r.Left) - $Cx) -le 2 -and [Math]::Abs(($r.Bottom - $r.Top) - $Cy) -le 2) `
    "want ${Cx}x${Cy} got $(($r.Right - $r.Left))x$(($r.Bottom - $r.Top))"

  # The wry webview host child must equal the client after the resize.
  $host_ = [WProbe]::FindChildByClass($hwnd, "WRY_WEBVIEW")
  if ($host_ -ne [IntPtr]::Zero) {
    $wv = [WProbe]::WindowRect($host_)
    $wvW = $wv.Right - $wv.Left; $wvH = $wv.Bottom - $wv.Top
    $cl = [WProbe]::ClientRect($hwnd)
    $clW = $cl.Right - $cl.Left; $clH = $cl.Bottom - $cl.Top
    Assert-That "${Name}: webview host follows the client area" `
      ([Math]::Abs($wvW - $clW) -le 2 -and [Math]::Abs($wvH - $clH) -le 2) `
      "webview ${wvW}x${wvH} vs client ${clW}x${clH}"
  } else {
    Assert-That "${Name}: webview host follows the client area" $false "WRY_WEBVIEW child not found"
  }

  $sf = [WProbe]::WindowRect($surface)
  $cl2 = [WProbe]::ClientRect($hwnd)
  Assert-That "${Name}: mpv surface follows the client area" `
    ([Math]::Abs(($sf.Right - $sf.Left) - ($cl2.Right - $cl2.Left)) -le 2 -and
     [Math]::Abs(($sf.Bottom - $sf.Top) - ($cl2.Bottom - $cl2.Top)) -le 2) `
    "surface $(($sf.Right - $sf.Left))x$(($sf.Bottom - $sf.Top)) vs client $(($cl2.Right - $cl2.Left))x$(($cl2.Bottom - $cl2.Top))"

  if ($SaveShot) {
    $bmp = $null; $gfx = $null
    try {
      $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
      $gfx = [System.Drawing.Graphics]::FromImage($bmp)
      $hdc = $gfx.GetHdc()
      [void][WProbe]::PrintWindow($hwnd, $hdc, 2)
      $gfx.ReleaseHdc($hdc)
      $bmp.Save($SaveShot, [System.Drawing.Imaging.ImageFormat]::Png)
      $bright = 0
      $w = $r.Right - $r.Left
      for ($x = $w - 150; $x -lt $w - 10; $x += 2) {
        for ($y = 6; $y -lt 34; $y += 2) {
          $p = $bmp.GetPixel($x, $y)
          if ([Math]::Max($p.R, [Math]::Max($p.G, $p.B)) -gt 130) { $bright++ }
        }
      }
      Assert-That "${Name}: chrome spans the full width (close button visible)" ($bright -ge 4) "bright pixels in the top-right corner: $bright"
    } finally {
      if ($gfx) { $gfx.Dispose() }
      if ($bmp) { $bmp.Dispose() }
    }
  }
}

Test-SnapResize -Name "snap-left resize" -X $mi.rcWork.Left -Y $mi.rcWork.Top `
  -Cx ([int](($mi.rcWork.Right - $mi.rcWork.Left) / 2)) -Cy ($mi.rcWork.Bottom - $mi.rcWork.Top) `
  -SaveShot (Join-Path $logDir "probe-snap-left.png")
Test-SnapResize -Name "minimum-size shrink" -X 200 -Y 120 -Cx 800 -Cy 520 `
  -SaveShot (Join-Path $logDir "probe-shrink.png")

# leave the app as it was
[void][WProbe]::SetWindowPos($hwnd, [IntPtr]::Zero, $before.Left, $before.Top, `
  ($before.Right - $before.Left), ($before.Bottom - $before.Top), 0x0004)

$reportPath = Join-Path $logDir "window-probe-report.txt"
$report | Out-File -Encoding utf8 $reportPath
Write-Output ("report saved: {0}" -f $reportPath)

if ($failures.Count -gt 0) {
  Write-Output ("{0} probe check(s) failed" -f $failures.Count)
  exit 1
}
Write-Output "PROBE ALL PASS"
