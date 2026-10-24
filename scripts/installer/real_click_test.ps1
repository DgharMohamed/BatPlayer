# Drives the installer with REAL mouse input only (SetCursorPos + mouse_event),
# verifying each step by observing process/window state. No PostMessage anywhere.
# Phase "install": welcome -> click Install Now -> expect progress page -> wait finish -> click Finish -> expect exit.
# Phase "reinstallX": (2nd run, registry present) -> wait reinstall page -> click X -> expect exit.
param(
    [ValidateSet('install','reinstallX','reinstallFull','welcomeX','finishX','probes')]
    [string]$Phase = 'install',
    [string]$ProcName = "BatPlayer_Setup",
    [string]$ExePath = "",
    [string]$ShotDir = ""
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class RC {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint rel);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hpos, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct WINDOWPLACEMENT { public int length; public int flags; public int showCmd; public PT ptMin; public PT ptMax; public RECT rcNormal; }
    [StructLayout(LayoutKind.Sequential)] public struct PT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
'@
[RC]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Drawing

$XCtlText = [string][char]0x2715   # the UTF-8 close glyph used by the template

# Default installer exe: the newest NSIS bundle produced by `npm run tauri build`
# (version-agnostic). Default shots dir: outside the repo, keeping artifacts out of git.
if ($ExePath -eq "") {
    $bundleDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src-tauri\target\release\bundle\nsis'
    $latest = Get-ChildItem $bundleDir -Filter '*-setup.exe' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "no installer bundle in $bundleDir - run 'npm run tauri build' first (or pass -ExePath)" }
    $ExePath = $latest.FullName
}
if ($ShotDir -eq "") {
    $ShotDir = Join-Path ([System.IO.Path]::GetTempPath()) 'batplayer-installer-shots'
}

function Log($msg) { Write-Output ("[{0:HH:mm:ss.fff}] {1}" -f (Get-Date), $msg) }

function Get-Proc([string]$name) {
    return Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-Controls([string]$procName) {
    # returns list of @{h, cls, txt, vis, L,T,R,B}
    $p = Get-Proc $procName
    if (-not $p) { return $null }
    $outer = $p.MainWindowHandle
    if ($outer -eq [IntPtr]::Zero) { return $null }
    $result = @()
    $stack = @([PSCustomObject]@{ h = $outer; depth = 0 })
    while ($stack.Count -gt 0) {
        $cur = $stack[0]; $stack = $stack[1..($stack.Count)]
        $h = $cur.h
        while ($h -ne [IntPtr]::Zero) {
            $cls = New-Object System.Text.StringBuilder 64
            [void][RC]::GetClassName($h, $cls, 64)
            $txt = New-Object System.Text.StringBuilder 256
            [void][RC]::GetWindowText($h, $txt, 256)
            $r = New-Object RC+RECT
            [void][RC]::GetWindowRect($h, [ref]$r)
            $result += [PSCustomObject]@{ h = $h; cls = $cls.ToString(); txt = $txt.ToString(); vis = [RC]::IsWindowVisible($h); L = $r.L; T = $r.T; R = $r.R; B = $r.B; depth = $cur.depth }
            $child = [RC]::GetWindow($h, 5)
            if ($child -ne [IntPtr]::Zero) { $stack += [PSCustomObject]@{ h = $child; depth = $cur.depth + 1 } }
            $h = [RC]::GetWindow($h, 2) 
        }
    }
    return $result
}

function Find-Ctl([string]$procName, [string]$text, [string[]]$cls = @('Static','Button')) {
    $list = Get-Controls $procName
    if (-not $list) { return $null }
    foreach ($c in $list) { if ($c.vis -and ($cls -contains $c.cls) -and $c.txt.Trim() -eq $text) { return $c } }
    return $null
}

function Wait-Disappear([string]$procName, $ctl, [int]$ms) {
    $deadline = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $deadline) {
        $c = Find-Ctl $procName $ctl.txt
        if (-not $c -or -not $c.vis) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Bring-To-Top($outer) {
    # Restore first if the window got minimized (parked at -32000,-32000).
    $wp = New-Object RC+WINDOWPLACEMENT
    $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf($wp)
    if ([RC]::GetWindowPlacement($outer, [ref]$wp) -and $wp.showCmd -eq 2) {
        Show-Window $outer 9   # SW_RESTORE
        Start-Sleep -Milliseconds 300
    }
    # HWND_TOPMOST: a background process may not enter the foreground band with
    # HWND_TOP, so force topmost (allowed without activation) so real clicks land.
    $null = [RC]::SetWindowPos($outer, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010)
}

function Real-Click($ctl) {
    $x = [int](($ctl.L + $ctl.R) / 2); $y = [int](($ctl.T + $ctl.B) / 2)
    $outer = (Get-Proc $ProcName).MainWindowHandle
    Bring-To-Top $outer
    [void][RC]::SetForegroundWindow($outer)
    Start-Sleep -Milliseconds 250
    # re-resolve the rect AFTER reordering the window (it may have moved)
    $list = Get-Controls $ProcName
    $fresh = $list | Where-Object { $_.h -eq $ctl.h }
    if ($fresh) { $ctl = $fresh; $x = [int](($ctl.L + $ctl.R) / 2); $y = [int](($ctl.T + $ctl.B) / 2) }
    [void][RC]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 200
    # verify the click will land on the installer
    $pt = New-Object RC+POINT; $pt.X = $x; $pt.Y = $y
    $wfp = [RC]::WindowFromPoint($pt)
    Log ("REALCLICK '{0}' at {1},{2} (FromPoint={3})" -f $ctl.txt, $x, $y, $wfp)
    [RC]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)   # down
    Start-Sleep -Milliseconds 90
    [RC]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)   # up
    Start-Sleep -Milliseconds 200
}

function Set-Owning-Process($hwnd, [string]$tag) {
    $procIdOut = 0
    [void][RC]::GetWindowThreadProcessId($hwnd, [ref]$procIdOut)
    $proc = Get-Process -Id $procIdOut -ErrorAction SilentlyContinue
    Log ("owner of {0} (h={1}): pid={2} name={3}" -f $tag, $hwnd, $procIdOut, $proc.ProcessName)
}

function Shot([string]$name) {
    $p = Get-Proc $ProcName
    if (-not $p -or $p.MainWindowHandle -eq [IntPtr]::Zero) { return }
    $r = New-Object RC+RECT
    [void][RC]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][RC]::PrintWindow($p.MainWindowHandle, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $ShotDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null

Log "PHASE=$Phase launching $ExePath"
Start-Process $ExePath
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    $p = Get-Proc $ProcName
    if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 300
}
$p = Get-Proc $ProcName
if (-not $p) { Log "FAIL: installer did not start"; exit 2 }
[void][RC]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 800

if ($Phase -eq 'install') {
    $btn = Find-Ctl $ProcName 'Install Now'
    if (-not $btn) { Log "FAIL: Install Now pill not found"; Shot 'fA_nopill.png'; exit 3 }
    Real-Click $btn
    # UI thread may stall several seconds right after launch; poll patiently
    $advMs = -1; $t0 = Get-Date
    $advDeadline = $t0.AddSeconds(15)
    while ((Get-Date) -lt $advDeadline) {
        $list = Get-Controls $ProcName
        if (($list | Where-Object { $_.cls -eq 'msctls_progress32' -and $_.vis })) { $advMs = [int]((Get-Date) - $t0).TotalMilliseconds; break }
        Start-Sleep -Milliseconds 300
    }
    if ($advMs -ge 0) { Log "PASS: real click on Install Now advanced to progress page (${advMs} ms)" } else {
        Log "FAIL: still on welcome after real click"; Shot 'fA_stuck.png'; exit 4
    }
    # wait for finish page
    $finDeadline = (Get-Date).AddSeconds(120); $fin = $null
    while ((Get-Date) -lt $finDeadline) {
        $fin = Find-Ctl $ProcName 'Finish'
        if ($fin) { break }
        Start-Sleep -Milliseconds 400
    }
    if (-not $fin) { Log "FAIL: finish page never appeared"; exit 5 }
    Shot 'fA_finish.png'
    # exercise the dark toggle: click the label -> expect state var flips (unchecked)
    $lab = Find-Ctl $ProcName "Launch BatPlayer now"
    if (-not $lab) { Log "WARN: launch label not found (skipping toggle test)" } else {
        Real-Click $lab
        Start-Sleep -Milliseconds 600
        Shot 'fA_toggle_off.png'
        Log "toggled launch checkbox OFF via click"
    }
    Real-Click $fin
    # Poll liveness closely to measure exact exit latency (observe natural exit)
    $exitMs = -1; $t0 = Get-Date
    $deadlineX = $t0.AddSeconds(30)
    while ((Get-Date) -lt $deadlineX) {
        $cur = Get-Proc $ProcName
        if (-not $cur) { $exitMs = [int]((Get-Date) - $t0).TotalMilliseconds; break }
        Start-Sleep -Milliseconds 250
    }
    if ($exitMs -ge 0) { Log "PASS: real click on Finish closed the installer in ${exitMs} ms (natural exit)" } else {
        Log "FAIL: installer still open 30s after Finish click (natural exit not observed)"; Shot 'fA_stuck_finish2.png'
        Stop-Process -Id (Get-Proc $ProcName).Id -Force -ErrorAction SilentlyContinue
        exit 6
    }
    $app = Get-Proc 'batplayer' -ErrorAction SilentlyContinue
    if ($app) { Log "FAIL: batplayer launched although launch toggle was OFF"; Stop-Process -Name batplayer -Force -ErrorAction SilentlyContinue; exit 7 }
    else { Log "PASS: batplayer not launched (toggle was OFF)" }
    exit 0
}

if ($Phase -eq 'welcomeX') {
    $btn = Find-Ctl $ProcName 'Install Now'
    if (-not $btn) { Log "FAIL: welcome page not detected"; Shot 'fX_no_welcome.png'; exit 3 }
    Log "welcome page detected"
    $x = Find-Ctl $ProcName $XCtlText
    if (-not $x) { Log "FAIL: X not found"; exit 4 }
    Real-Click $x
    Start-Sleep -Seconds 3
    $p = Get-Proc $ProcName
    if (-not $p) { Log "PASS: real click on X closed installer on WELCOME page" } else {
        Log "FAIL: still open after X click (welcome)"; Shot 'fX_stuck_x.png'
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        exit 5
    }
    exit 0
}

if ($Phase -eq 'finishX') {
    $btn = Find-Ctl $ProcName 'Install Now'
    if (-not $btn) { Log "FAIL: Install Now not found"; exit 3 }
    Real-Click $btn
    Start-Sleep -Milliseconds 2500
    $finDeadline = (Get-Date).AddSeconds(120); $fin = $null
    while ((Get-Date) -lt $finDeadline) {
        $fin = Find-Ctl $ProcName 'Finish'
        if ($fin) { break }
        Start-Sleep -Milliseconds 400
    }
    if (-not $fin) { Log "FAIL: finish page never appeared"; exit 5 }
    Log "finish page detected"
    Shot 'fX_finish.png'
    $x = Find-Ctl $ProcName $XCtlText
    if (-not $x) { Log "FAIL: X not found on finish page"; exit 4 }
    Real-Click $x
    Start-Sleep -Seconds 3
    $p = Get-Proc $ProcName
    if (-not $p) { Log "PASS: real click on X closed installer on FINISH page" } else {
        Log "FAIL: still open after X click (finish)"; Shot 'fX_stuck_x.png'
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        exit 5
    }
    exit 0
}

if ($Phase -eq 'probes') {
    $btn = Find-Ctl $ProcName 'Install Now'
    if (-not $btn) { Log "FAIL: welcome not detected"; exit 3 }
    Log "== DUMP BEFORE X click =="
    $list = Get-Controls $ProcName
    foreach ($c in $list) { Log ("  h={0} cls={1} vis={2} rect={3},{4},{5},{6} txt=[{7}]" -f $c.h, $c.cls, $c.vis, $c.L, $c.T, $c.R, $c.B, $c.txt) }
    $x = Find-Ctl $ProcName $XCtlText
    if (-not $x) { Log "FAIL: X not found"; exit 4 }
    Log ("X control: h={0} rect={1},{2}..{3},{4}" -f $x.h, $x.L, $x.T, $x.R, $x.B)
    # what is at the click point (WindowFromPoint)?
    $ptX = [int](($x.L + $x.R) / 2); $ptY = [int](($x.T + $x.B) / 2)
    Log "click point: $ptX,$ptY"
    $pt = New-Object RC+POINT; $pt.X = $ptX; $pt.Y = $ptY
    $wfp = [RC]::WindowFromPoint($pt)
    Log ("WindowFromPoint(before) = {0} (X ctl = {1}), fg = {2}" -f $wfp, $x.h, [RC]::GetForegroundWindow())
    $outer = (Get-Proc $ProcName).MainWindowHandle
    Log ("our outer = {0}, page #32770 visible rect = see dump" -f $outer)
    $ok = [RC]::SetForegroundWindow($outer)
    Log ("SetForegroundWindow(outer) returned {0}; fg now {1}" -f $ok, [RC]::GetForegroundWindow())
    $wfp2 = [RC]::WindowFromPoint($pt)
    Log ("WindowFromPoint(after fg) = {0}" -f $wfp2)
    Set-Owning-Process $wfp "windowfrompoint"
    Set-Owning-Process $wfp2 "windowfrompoint_after_fg"
    Set-Owning-Process $outer "our_outer"
    Real-Click $x
    Start-Sleep -Seconds 2
    Log "== DUMP AFTER X click =="
    $list2 = Get-Controls $ProcName
    foreach ($c in $list2) { Log ("  h={0} cls={1} vis={2} rect={3},{4},{5},{6} txt=[{7}]" -f $c.h, $c.cls, $c.vis, $c.L, $c.T, $c.R, $c.B, $c.txt) }
    Shot 'probes_after.png'
    $p = Get-Proc $ProcName
    if ($p) { Log "still open - killing"; Stop-Process -Id $p.Id -Force } else { Log "process exited after X click" }
    exit 0
}

if ($Phase -eq 'reinstallFull') {
    # The reinstall page sits after the welcome page in NSIS page order, so if
    # the welcome page is up, click Install Now first.
    $deadlineW = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadlineW) {
        $wnow = Find-Ctl $ProcName 'Install Now'
        if ($wnow) { Real-Click $wnow; Start-Sleep -Milliseconds 1500; break }
        $cNow = Find-Ctl $ProcName 'Continue'
        if ($cNow) { break }
        Start-Sleep -Milliseconds 300
    }
    $cDeadline = (Get-Date).AddSeconds(40); $cont = $null
    while ((Get-Date) -lt $cDeadline) {
        $cont = Find-Ctl $ProcName 'Continue'
        if ($cont) { break }
        Start-Sleep -Milliseconds 300
    }
    if (-not $cont) { Log "FAIL: reinstall page not detected"; Shot 'fC_no_reinstall.png'; exit 3 }
    Log "reinstall page detected"
    Shot 'fC_reinstall.png'
    Real-Click $cont
    Start-Sleep -Milliseconds 2500
    $finDeadline = (Get-Date).AddSeconds(120); $fin = $null
    while ((Get-Date) -lt $finDeadline) {
        $fin = Find-Ctl $ProcName 'Finish'
        if ($fin) { break }
        Start-Sleep -Milliseconds 400
    }
    if (-not $fin) { Log "FAIL: finish never appeared after Continue"; exit 5 }
    Shot 'fC_finish.png'
    Real-Click $fin
    $exitMs = -1; $t0 = Get-Date
    $deadlineX = $t0.AddSeconds(20)
    while ((Get-Date) -lt $deadlineX) {
        if (-not (Get-Proc $ProcName)) { $exitMs = [int]((Get-Date) - $t0).TotalMilliseconds; break }
        Start-Sleep -Milliseconds 250
    }
    if ($exitMs -ge 0) { Log "PASS: real click on Finish closed the installer (reinstall flow, ${exitMs} ms)" } else {
        Log "FAIL: installer still open after Finish click (reinstall flow)"; Shot 'fC_stuck.png'
        Stop-Process -Id (Get-Proc $ProcName).Id -Force -ErrorAction SilentlyContinue
        exit 6
    }
    $app = Get-Proc 'batplayer' -ErrorAction SilentlyContinue
    if ($app) { Log "PASS: batplayer launched (default ON): PID $($app.Id)"; Start-Sleep -Seconds 8; $app = Get-Proc 'batplayer' -ErrorAction SilentlyContinue; if ($app) { Log "PASS: batplayer stable after 8s"; Stop-Process -Name batplayer -Force -ErrorAction SilentlyContinue } else { Log "CHECK: batplayer exited within 8s" } }
    else { Log "FAIL: batplayer did not launch (default ON)"; exit 7 }
    exit 0
}

if ($Phase -eq 'reinstallX') {
    # The reinstall page sits after the welcome page in NSIS page order, so if
    # the welcome page is up, click Install Now first.
    $deadlineW = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadlineW) {
        $wnow = Find-Ctl $ProcName 'Install Now'
        if ($wnow) { Real-Click $wnow; Start-Sleep -Milliseconds 1500; break }
        $cNow = Find-Ctl $ProcName 'Continue'
        if ($cNow) { break }
        Start-Sleep -Milliseconds 300
    }
    # wait for reinstall page (Continue pill)
    $cDeadline = (Get-Date).AddSeconds(40); $cont = $null
    while ((Get-Date) -lt $cDeadline) {
        $cont = Find-Ctl $ProcName 'Continue'
        if ($cont) { break }
        Start-Sleep -Milliseconds 300
    }
    if (-not $cont) { Log "FAIL: reinstall page not detected"; Shot 'fB_no_reinstall.png'; exit 3 }
    Log "reinstall page detected"
    Shot 'fB_reinstall.png'
    # click the X
    $x = Find-Ctl $ProcName $XCtlText
    if (-not $x) { Log "FAIL: X control not found"; exit 4 }
    Real-Click $x
    Start-Sleep -Seconds 3
    $p = Get-Proc $ProcName
    if (-not $p) { Log "PASS: real click on X closed the installer" } else {
        Log "FAIL: installer still open after X click"; Shot 'fB_stuck_x.png'
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        exit 5
    }
    exit 0
}
