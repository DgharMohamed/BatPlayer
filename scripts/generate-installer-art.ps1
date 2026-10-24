# Generates the themed NSIS installer bitmaps from the logo source:
#
#   icons/installer-header.bmp   150x57  - band shown on most installer pages
#   icons/installer-sidebar.bmp  164x314 - Welcome/Finish page side panel
#
# Tokens mirror src/styles/variables.css (dark theme) so the installer reads as
# the same product the user sees after setup. Run after changing the logo or
# theme:  powershell -File scripts\generate-installer-art.ps1
# Bitmaps are 24bpp RGB, the format NSIS MUI2 requires for these defines.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root  = Split-Path $PSScriptRoot -Parent
$icons = Join-Path $root "src-tauri\icons"

# --- Theme tokens (variables.css) -------------------------------------------
$bg       = [System.Drawing.Color]::FromArgb(255, 0x0a, 0x0a, 0x0c)
$elevated = [System.Drawing.Color]::FromArgb(255, 0x13, 0x13, 0x18)
# The MUI header band paints 0D1018 (MUI_BGCOLOR in installer.nsi); the header
# bitmap must melt into it exactly or a faint tonal seam shows at its edges.
$bandBg   = [System.Drawing.Color]::FromArgb(255, 0x0d, 0x10, 0x18)
$text     = [System.Drawing.Color]::FromArgb(255, 0xe9, 0xe9, 0xec)
$dim      = [System.Drawing.Color]::FromArgb(255, 0xd6, 0xd6, 0xdc)
$faint    = [System.Drawing.Color]::FromArgb(255, 0x5c, 0x5c, 0x66)
$goldTop  = [System.Drawing.Color]::FromArgb(255, 0xff, 0xd4, 0x00)  # --accent
$goldBot  = [System.Drawing.Color]::FromArgb(255, 0xf5, 0xa6, 0x23)  # logo gradient tail

# --- Logo: crop the bat glyph out of the branded tile -----------------------
$src = [System.Drawing.Bitmap]::new((Join-Path $icons "batplayer-logo-source.png"))
$minX = $src.Width; $minY = $src.Height; $maxX = 0; $maxY = 0
for ($y = 0; $y -lt $src.Height; $y += 3) {
    for ($x = 0; $x -lt $src.Width; $x += 3) {
        $p = $src.GetPixel($x, $y)
        if ($p.A -gt 40 -and ($p.R -gt 26 -or $p.G -gt 26 -or $p.B -gt 26)) {
            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$pad = 6
$rect = [System.Drawing.Rectangle]::new(
    [Math]::Max(0, $minX - $pad), [Math]::Max(0, $minY - $pad),
    [Math]::Min($src.Width, $maxX + $pad) - [Math]::Max(0, $minX - $pad),
    [Math]::Min($src.Height, $maxY + $pad) - [Math]::Max(0, $minY - $pad))
# Clone must preserve the source alpha: converting to 24bpp flattens
# transparency onto black, which paints a dark rectangle behind the glyph.
$glyph = $src.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

# The asset also carries an opaque black "card" behind the glyph inside its
# bounding box (the transparent margin is A=0, the card is A=255, both with
# RGB 0). Key every near-black pixel to fully transparent so the mark can
# float on any installer background.
$crect = [System.Drawing.Rectangle]::new(0, 0, $glyph.Width, $glyph.Height)
$cbits = $glyph.LockBits($crect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$buf = [byte[]]::new($cbits.Stride * $glyph.Height)
[System.Runtime.InteropServices.Marshal]::Copy($cbits.Scan0, $buf, 0, $buf.Length)
for ($i = 0; $i -lt $buf.Length; $i += 4) {
    if ($buf[$i] -lt 14 -and $buf[$i + 1] -lt 14 -and $buf[$i + 2] -lt 14) { $buf[$i + 3] = 0 }
}
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $cbits.Scan0, $buf.Length)
$glyph.UnlockBits($cbits)
"logo glyph: $($glyph.Width)x$($glyph.Height)"

function New-ArtGraphics([System.Drawing.Bitmap]$bmp) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint  = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return $g
}

function Draw-GoldBar($g, [System.Drawing.Rectangle]$rect, [float]$angle) {
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $goldTop, $goldBot, $angle)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()
}

# Draws `text` with per-character letter spacing justified to exactly
# `targetW` px. Measuring via GenericTypographic is required: plain
# MeasureString pads every single character by ~1/3 em, which compounds
# across a string and pushes spaced text off the small bitmaps.
function Draw-SpacedText($g, [string]$text, [System.Drawing.Font]$font,
                         [System.Drawing.Brush]$brush, [float]$x, [float]$targetW, [float]$y) {
    $tight = [System.Drawing.StringFormat]::GenericTypographic
    $advances = @()
    $natural = 0.0
    foreach ($ch in $text.ToCharArray()) {
        $a = $g.MeasureString("$ch", $font, [int]::MaxValue, $tight).Width
        $advances += ,@($ch, $a)
        $natural += $a
    }
    $gap = 0.0
    $n = $advances.Count
    if ($n -gt 1) { $gap = ($targetW - $natural) / ($n - 1) }
    if ($gap -lt 0) { $gap = 0 }
    $cx = $x
    foreach ($pair in $advances) {
        $g.DrawString($pair[0], $font, $brush, $cx, $y)
        $cx += $pair[1] + $gap
    }
    return $x + $targetW
}

function Draw-Glyph($g, [System.Drawing.Image]$img, [float]$x, [float]$y, [float]$height, [float]$alpha = 1.0) {
    $w = [Math]::Round($img.Width * $height / $img.Height)
    $dest = [System.Drawing.Rectangle]::new([int]$x, [int]$y, [int]$w, [int]$height)
    if ($alpha -ge 1.0) {
        $g.DrawImage($img, $dest, 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel)
    } else {
        $cm = [System.Drawing.Imaging.ColorMatrix]::new()
        $cm.Matrix33 = $alpha
        $ia = [System.Drawing.Imaging.ImageAttributes]::new()
        $ia.SetColorMatrix($cm)
        $g.DrawImage($img, $dest, 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $ia.Dispose()
    }
    return $w
}

# Fixed-pixel canvases get pixel-unit fonts: point sizes would scale with the
# display DPI (GDI+ multiplies by Graphics.DpiY) and blow past these tiny
# images on high-DPI machines.
$fontTitle    = [System.Drawing.Font]::new("Segoe UI Semibold", 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontTagline  = [System.Drawing.Font]::new("Segoe UI", 6, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fontHeading  = [System.Drawing.Font]::new("Segoe UI Semibold", 20, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontSideTag  = [System.Drawing.Font]::new("Segoe UI", 7, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontFeature  = [System.Drawing.Font]::new("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fontFooter   = [System.Drawing.Font]::new("Segoe UI", 6.5, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$centerFormat = [System.Drawing.StringFormat]::new()
$centerFormat.Alignment = [System.Drawing.StringAlignment]::Center
$centerFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

try {
    # --- Header: 150x57 ------------------------------------------------------
    $bmp = [System.Drawing.Bitmap]::new(150, 57, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-ArtGraphics $bmp
    $g.Clear($bandBg)

    # Gold spine on the left edge, mirroring the app's accent.
    $spine = [System.Drawing.Rectangle]::new(0, 0, 4, 57)
    $bar = [System.Drawing.Rectangle]::new(4, 0, 1, 57)
    Draw-GoldBar $g $spine 90
    $g.FillRectangle([System.Drawing.SolidBrush]::new($goldBot), $bar)

    # Bat glyph on the left, wordmark + tagline to the right.
    $glyphH = 34
    $gy = [Math]::Ceiling((57 - $glyphH) / 2)
    $gw = Draw-Glyph $g $glyph 12 $gy $glyphH
    $tx = 12 + $gw + 12
    $gold = [System.Drawing.SolidBrush]::new($goldTop)
    $white = [System.Drawing.SolidBrush]::new($text)
    $g.DrawString("BatPlayer", $fontTitle, $white, $tx, 15)
    [void](Draw-SpacedText $g "MEDIA PLAYER" $fontTagline $gold ($tx + 2) (150 - $tx - 8) 36)

    $g.Dispose()
    $bmp.Save((Join-Path $icons "installer-header.bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()

    # --- Sidebar: 164x314 ----------------------------------------------------
    $bmp = [System.Drawing.Bitmap]::new(164, 314, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-ArtGraphics $bmp
    $g.Clear($bg)

    # Oversized ghost bat: depth without stealing contrast from the content.
    $bgGlyphH = 200
    [void](Draw-Glyph $g $glyph 40 (314 - $bgGlyphH - 24) $bgGlyphH 0.05)

    # Gold top strip + right border bracket the panel.
    Draw-GoldBar $g ([System.Drawing.Rectangle]::new(0, 0, 164, 3)) 0
    Draw-GoldBar $g ([System.Drawing.Rectangle]::new(161, 3, 3, 311)) 90

    # Logo glyph, centered (width follows from the crop's aspect ratio).
    $glyphH = 96
    $gw = $glyph.Width * $glyphH / $glyph.Height
    [void](Draw-Glyph $g $glyph ([Math]::Floor((164 - $gw) / 2)) 26 $glyphH)

    $center = 164 / 2
    $gold = [System.Drawing.SolidBrush]::new($goldTop)
    $white = [System.Drawing.SolidBrush]::new($text)
    $soft  = [System.Drawing.SolidBrush]::new($dim)
    $ghost = [System.Drawing.SolidBrush]::new($faint)

    # Wordmark + tagline, centered by the layout engine itself (no manual
    # measuring: DrawString centers each string inside the panel width).
    $g.DrawString("BatPlayer", $fontHeading, $white,
        ([System.Drawing.RectangleF]::new(-8, 132, 180, 26)), $centerFormat)
    [void](Draw-SpacedText $g "YOUR MEDIA. YOUR PACE." $fontSideTag $gold ($center - 58) 116 166)

    # Feature list with accent bullets.
    $features = @("Smooth playback controls", "Simple playlists", "Audio & subtitles built in")
    $fy = 196
    foreach ($feature in $features) {
        $g.FillEllipse($gold, 26, $fy + 3.0, 3.6, 3.6)
        $g.DrawString($feature, $fontFeature, $soft, 34, $fy - 1)
        $fy += 23
    }

    $footer = "FREE & OPEN SOURCE   |   MIT LICENSE"
    $g.DrawString($footer, $fontFooter, $ghost,
        ([System.Drawing.RectangleF]::new(-8, 290, 180, 14)), $centerFormat)

    $g.Dispose()
    $bmp.Save((Join-Path $icons "installer-sidebar.bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()

    # --- Welcome mark: 470x244, bat centered on the installer's MUI_BGCOLOR --
    # The nsDialogs welcome page stretches this bitmap into a control whose
    # aspect matches (150u x 60u dialog units). 0D1018 must equal MUI_BGCOLOR
    # in src-tauri/nsis/installer.nsi so the bitmap melts into the page.
    $bmp = [System.Drawing.Bitmap]::new(470, 244, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-ArtGraphics $bmp
    $welcomeBg = [System.Drawing.Color]::FromArgb(255, 0x0d, 0x10, 0x18)
    $g.Clear($welcomeBg)
    $batH = 224
    $batW = [Math]::Round($batH * $glyph.Width / $glyph.Height)
    Draw-Glyph $g $glyph ([Math]::Floor((470 - $batW) / 2)) ((244 - $batH) / 2 + 4) $batH

    $g.Dispose()
    $bmp.Save((Join-Path $icons "installer-welcome.bmp"), [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()
} finally {
    $glyph.Dispose()
    $src.Dispose()
    foreach ($f in $fontTitle, $fontTagline, $fontHeading, $fontSideTag, $fontFeature, $fontFooter) { $f.Dispose() }
}

"installer art written: " + (Join-Path $icons "installer-header.bmp")
"                       " + (Join-Path $icons "installer-sidebar.bmp")
"                       " + (Join-Path $icons "installer-welcome.bmp")
