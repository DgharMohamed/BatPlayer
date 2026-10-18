# End-to-end check for BatPlayer (Windows, debug build).
#
# 1. makes sure the vendored libmpv files exist,
# 2. writes a raw Y4M test clip (no ffmpeg needed),
# 3. builds the frontend and runs the app with the autotest env vars,
# 4. waits for the mpv screenshot of the decoded frame and studies it,
# 5. captures the app window and pixel-checks bars, logo and video area.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts/autotest.ps1
#        (Windows PowerShell 5.1 or PowerShell 7)
# Pass -GenerateOnly to just (re)write the sample clip into %TEMP%.

param([switch] $GenerateOnly)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$mpvDir = Join-Path $root "src-tauri\mpv"
foreach ($name in "libmpv-2.dll", "mpv.lib") {
  if (-not (Test-Path (Join-Path $mpvDir $name))) {
    throw "missing src-tauri\mpv\$name - run scripts/fetch-mpv.ps1 first"
  }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "batplayer-e2e"
New-Item -ItemType Directory -Force -Path $work | Out-Null

$clip = Join-Path $work "sample.y4m"
$frameShot = Join-Path $work "decoded-frame.png"
$windowShot = Join-Path $work "app-window.png"
$mpvLog = Join-Path $work "mpv.log"
Remove-Item $frameShot, $windowShot, $mpvLog, $clip -ErrorAction SilentlyContinue

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

# ---------------------------------------------------------------------------
# Raw Y4M test clip: 320x240, 10 fps, 25 frames. A luminance ramp rolls
# across every frame and a colored block cycles red/green/blue/gray, so a
# decent decode is easy to tell from garbage.
# ---------------------------------------------------------------------------
function New-SampleClip {
  param([string] $Path, [int] $Width = 320, [int] $Height = 240, [int] $Frames = 25)

  $ySize = $Width * $Height
  $uvSize = ($Width / 2) * ($Height / 2)

  # per-column luminance ramp values
  $ramp = New-Object byte[] $Width
  for ($col = 0; $col -lt $Width; $col++) {
    $ramp[$col] = [byte][Math]::Min(255, 24 + $col * 255 / ($Width - 1))
  }

  # cycles of Y/U/V values for the chroma block
  $blocks = @(
    @([byte]76, [byte]84, [byte]255)    # red
    @([byte]149, [byte]43, [byte]21)    # green
    @([byte]29, [byte]240, [byte]255)   # blue
    @([byte]255, [byte]128, [byte]128)  # gray
  )

  $stream = [IO.File]::Create($Path)
  try {
    $header = [Text.Encoding]::ASCII.GetBytes("YUV4MPEG2 W$Width H$Height F10:1 Ip A1:1 C420jpeg`n")
    $stream.Write($header, 0, $header.Length)

    $y = New-Object byte[] $ySize
    $u = New-Object byte[] $uvSize
    $v = New-Object byte[] $uvSize
    for ($i = 0; $i -lt $uvSize; $i++) {
      $u[$i] = [byte]128
      $v[$i] = [byte]128
    }

    for ($f = 0; $f -lt $Frames; $f++) {
      $tag = [Text.Encoding]::ASCII.GetBytes("FRAME`n")
      $stream.Write($tag, 0, $tag.Length)

      # rolling ramp: every row shifts the ramp left by frame steps
      $shift = ($f * ($Width / 8)) % $Width
      for ($row = 0; $row -lt $Height; $row++) {
        $head = $row * $Width
        [Array]::Copy($ramp, $shift, $y, $head, $Width - $shift)
        if ($shift -gt 0) {
          [Array]::Copy($ramp, 0, $y, $head + ($Width - $shift), $shift)
        }
      }

      # moving chroma block in the lower-left quadrant
      $pick = $blocks[$f % $blocks.Count]
      $x0 = 40 + 20 * ($f % 3)
      $y0 = $Height - 90
      for ($yy = 0; $yy -lt 60; $yy++) {
        for ($xx = 0; $xx -lt 80; $xx++) {
          $y[($y0 + $yy) * $Width + $x0 + $xx] = $pick[0]
        }
      }
      for ($yy = 0; $yy -lt 30; $yy++) {
        $line = ($y0 / 2 + $yy) * ($Width / 2) + $x0 / 2
        for ($xx = 0; $xx -lt 40; $xx++) {
          $u[$line + $xx] = $pick[1]
          $v[$line + $xx] = $pick[2]
        }
      }

      $stream.Write($y, 0, $y.Length)
      $stream.Write($u, 0, $u.Length)
      $stream.Write($v, 0, $v.Length)
    }
  } finally {
    $stream.Dispose()
  }
}

# ---------------------------------------------------------------------------
# Helpers: process/window plumbing
# ---------------------------------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32Window
{
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);
}
"@

function Wait-ForFile {
  param([string] $Path, [int] $Seconds, [string] $What)
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) { return }
    Start-Sleep -Milliseconds 400
  }
  if ((Test-Path $mpvLog)) {
    Write-Output ("last mpv log lines:`n" + (Get-Content $mpvLog -Tail 40) | Out-String)
  }
  throw "$What never appeared: $Path (waited $Seconds s)"
}

function Wait-ForProcessWindow {
  param([string] $Name, [int] $Seconds)
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($proc) { return $proc }
    Start-Sleep -Milliseconds 400
  }
  throw "no window for process '$Name' appeared in $Seconds s"
}

function Stop-Hard {
  param([Parameter(ValueFromPipeline = $true)] $Process)
  process {
    if ($Process -and -not $Process.HasExited) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

function Copy-AppWindow {
  param($Process, [string] $Dest)
  [void][Win32Window]::SetProcessDPIAware()
  $hwnd = $Process.MainWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) { throw "process has no main window" }

  # The app paints through a transparent window with DirectComposition planes
  # (WebView2 + the native video surface), so CopyFromScreen only sees the
  # desktop behind it. PrintWindow(PW_RENDERFULLCONTENT) asks DWM for the
  # window's own visuals and reliably includes the webview and the video.
  if ([Win32Window]::IsIconic($hwnd)) { [void][Win32Window]::ShowWindow($hwnd, 9) }  # SW_RESTORE
  # HWND_TOPMOST | SWP_NOMOVE|NOSIZE|NOACTIVATE|SHOWWINDOW, so a minimized or
  # occluded window is compositing and nothing steals focus from the user.
  [void][Win32Window]::SetWindowPos($hwnd, [IntPtr]::new(-1), 0, 0, 0, 0, 0x0053)
  Start-Sleep -Milliseconds 700

  $rect = New-Object Win32Window+RECT
  [void][Win32Window]::GetWindowRect($hwnd, [ref]$rect)
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -lt 100 -or $height -lt 100) { throw "window rect looks wrong: $width x $height" }

  $bmp = $null
  $probe = $null
  try {
    # render the window content; retry in case the frame is still compositing
    for ($attempt = 1; $attempt -le 4; $attempt++) {
      $bmp = New-Object System.Drawing.Bitmap $width, $height
      $gfx = [System.Drawing.Graphics]::FromImage($bmp)
      $hdc = $gfx.GetHdc()
      [void][Win32Window]::PrintWindow($hwnd, $hdc, 2)  # PW_RENDERFULLCONTENT
      $gfx.ReleaseHdc($hdc)
      $gfx.Dispose()
      # sanity: the top bar menus must be in the frame - a bogus capture
      # (desktop behind the window) has no bright text there.
      $probe = Get-RegionStats -Bitmap $bmp -X0 4 -Y0 ([int]($height * 0.02)) -X1 ([int]($width * 0.3)) -Y1 ([int]($height * 0.07)) -Step 3
      if ($probe.Bright -ge 5) { break }
      $bmp.Dispose()
      Start-Sleep -Milliseconds 600
    }
    if ($probe.Bright -lt 5) { throw "window rendered no UI content after 4 attempts - the capture is not the app" }
    $bmp.Save($Dest, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    if ($bmp) { $bmp.Dispose() }
    [void][Win32Window]::SetWindowPos($hwnd, [IntPtr]::new(-2), 0, 0, 0, 0, 0x0013)  # back from topmost
  }
  return $Dest
}

# ---------------------------------------------------------------------------
# Helpers: pixel analysis
# ---------------------------------------------------------------------------
function Get-RegionStats {
  param([System.Drawing.Bitmap] $Bitmap, [int] $X0, [int] $Y0, [int] $X1, [int] $Y1, [int] $Step = 3)
  $accent = 0    # yellow-ish #FFD400
  $bright = 0
  $redBlock = 0  # red-ish block from the test clip
  $distinct = New-Object 'System.Collections.Generic.HashSet[int]'
  for ($y = $Y0; $y -lt $Y1; $y += $Step) {
    for ($x = $X0; $x -lt $X1; $x += $Step) {
      $p = $Bitmap.GetPixel($x, $y)
      if ($p.R -gt 180 -and $p.G -gt 140 -and $p.B -lt 90) { $accent++ }
      if ($p.R -gt 140 -and $p.G -lt 120 -and $p.B -lt 120) { $redBlock++ }
      if ([Math]::Max($p.R, [Math]::Max($p.G, $p.B)) -gt 110) { $bright++ }
      [void]$distinct.Add([int](($p.R -shl 16) -bor ($p.G -shl 8) -bor $p.B))
    }
  }
  return [pscustomobject]@{ Accent = $accent; Bright = $bright; RedBlock = $redBlock; Distinct = $distinct.Count }
}

function Test-DecodedFrame {
  param([string] $Path)
  # mpv dumps exactly the decoded frame: full clip resolution at end-of-file.
  $bmp = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    Assert-That -Name "decoded frame is the test clip size" `
      -Condition ($bmp.Width -eq 320 -and $bmp.Height -eq 240) `
      -Details "got $($bmp.Width)x$($bmp.Height)"

    $stats = Get-RegionStats -Bitmap $bmp -X0 0 -Y0 0 -X1 320 -Y1 240 -Step 2
    Assert-That -Name "decoded frame is non-uniform (video kept decoding)" `
      -Condition ($stats.Distinct -ge 20) -Details "distinct colors: $($stats.Distinct)"

    # the chroma block moves with the frame index; its color cycles too, so
    # look for a saturated (non-gray) pixel inside the union of block spots:
    # x in [80..119] for every x0 in {40,60,80}, y in 150..209.
    $chroma = 0
    for ($x = 80; $x -le 118; $x += 2) {
      for ($y = 152; $y -le 208; $y += 2) {
        $p = $bmp.GetPixel($x, $y)
        if (([Math]::Abs($p.R - $p.G) -gt 40) -or ([Math]::Abs($p.G - $p.B) -gt 40) -or ([Math]::Abs($p.R - $p.B) -gt 40)) {
          $chroma++
        }
      }
    }
    Assert-That -Name "decoded frame has chroma (block rendered)" `
      -Condition ($chroma -ge 10) `
      -Details "saturated pixels in block area: $chroma"
  } finally {
    $bmp.Dispose()
  }
}

function Test-AppWindow {
  param([string] $Path)
  $bmp = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    $w = $bmp.Width
    $h = $bmp.Height
    Assert-That -Name "app window captured at a sane size" `
      -Condition ($w -ge 1000 -and $h -ge 600) -Details "got ${w}x${h}"

    # everything below scans relative bands so the display scale (100/125%...)
    # and the invisible resize borders do not shift the crops off target.

    # bat mark in the top bar far left
    $logo = Get-RegionStats -Bitmap $bmp -X0 4 -Y0 ([int]($h * 0.015)) -X1 ([int]($w * 0.05)) -Y1 ([int]($h * 0.07)) -Step 1
    Assert-That -Name "top bar shows the bat logo (accent pixels)" `
      -Condition ($logo.Accent -ge 3) -Details "accent pixels: $($logo.Accent)"

    # menu labels across the left third of the top bar
    $menus = Get-RegionStats -Bitmap $bmp -X0 ([int]($w * 0.05)) -Y0 ([int]($h * 0.02)) -X1 ([int]($w * 0.3)) -Y1 ([int]($h * 0.07)) -Step 1
    Assert-That -Name "top bar shows the VLC-style menu bar" `
      -Condition ($menus.Bright -ge 30) -Details "bright text pixels: $($menus.Bright)"

    # play button in the bottom-left corner
    $play = Get-RegionStats -Bitmap $bmp -X0 ([int]($w * 0.01)) -Y0 ([int]($h * 0.88)) -X1 ([int]($w * 0.1)) -Y1 ([int]($h * 0.98)) -Step 1
    Assert-That -Name "control bar shows the play button (accent pixels)" `
      -Condition ($play.Accent -ge 3) -Details "accent pixels: $($play.Accent)"

    # video visibly rendered in the middle of the stage
    $video = Get-RegionStats -Bitmap $bmp -X0 ([int]($w / 2) - 120) -Y0 ([int]($h / 2) - 80) -X1 ([int]($w / 2) + 120) -Y1 ([int]($h / 2)) -Step 2
    Assert-That -Name "video output composited on the window (distinct colors)" `
      -Condition ($video.Distinct -ge 12) -Details "distinct colors: $($video.Distinct)"
  } finally {
    $bmp.Dispose()
  }
}

New-SampleClip $clip
Write-Output ("sample clip: {0} ({1:N1} MB)" -f $clip, ((Get-Item $clip).Length / 1mb))
if ($GenerateOnly) {
  exit 0
}

# ---------------------------------------------------------------------------
# Build the frontend, then run the app with the autotest hooks enabled.
# ---------------------------------------------------------------------------
Write-Output "building frontend..."
& npm run build | Out-Null
if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }

# A leftover instance from an earlier run or dev session would make the
# window lookup ambiguous, so always start from a clean slate.
Get-Process batplayer -ErrorAction SilentlyContinue | Stop-Hard

Write-Output "launching BatPlayer..."
$env:BATPLAYER_AUTOTEST_FILE = $clip
$env:BATPLAYER_AUTOTEST_SHOT = $frameShot
$env:BATPLAYER_MPV_LOG = $mpvLog

# Resolve cargo even when the script runs from a shell without rustup's PATH
# entry (e.g. a Git Bash session opened before Rust was installed).
$cargoExe = "cargo"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  $cargoExe = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
  if (-not (Test-Path $cargoExe)) { throw "cargo not found on PATH or in ~/.cargo/bin" }
}

# Plain debug builds serve tauri.conf.json's devUrl (localhost:1420), which
# needs a dev server that the autotest does not run. Enabling
# tauri/custom-protocol (what `tauri build --debug` does) serves the
# production `dist/` frontend built above instead.
$cargo = Start-Process -FilePath $cargoExe -ArgumentList "run", "--features", "tauri/custom-protocol" `
  -WorkingDirectory (Join-Path $root "src-tauri") `
  -PassThru -NoNewWindow
try {
  Wait-ForFile $frameShot 90 "mpv screenshot of the decoded frame"
  Assert-That -Name "mpv wrote the screenshot" -Condition (Test-Path $frameShot) -Details $frameShot

  $proc = Wait-ForProcessWindow "batplayer" 90
  Start-Sleep -Milliseconds 800
  $windowShotPath = Copy-AppWindow $proc $windowShot

  Test-DecodedFrame $frameShot
  Test-AppWindow $windowShotPath
} finally {
  Stop-Hard $cargo
  Get-Process batplayer -ErrorAction SilentlyContinue | Stop-Hard
}

if ($failures.Count -gt 0) {
  Write-Output ("{0} check(s) failed" -f $failures.Count)
  exit 1
}
Write-Output "ALL PASS"
