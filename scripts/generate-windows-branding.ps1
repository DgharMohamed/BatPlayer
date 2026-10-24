$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$brandingGenerator = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class BatPlayerWindowsBranding
{
    private static Color C(int r, int g, int b) { return Color.FromArgb(r, g, b); }

    private static GraphicsPath RoundedRect(Rectangle rect, int radius)
    {
        int d = radius * 2;
        GraphicsPath path = new GraphicsPath();
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static Bitmap Resize(Bitmap source, int size)
    {
        Bitmap result = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(result))
        {
            g.Clear(Color.Transparent);
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.DrawImage(source, new Rectangle(0, 0, size, size));
        }
        return result;
    }

    private static byte[] PngBytes(Bitmap bitmap)
    {
        using (MemoryStream stream = new MemoryStream())
        {
            bitmap.Save(stream, ImageFormat.Png);
            return stream.ToArray();
        }
    }

    private static Bitmap CreateAppIcon(Bitmap logo)
    {
        Bitmap icon = new Bitmap(1024, 1024, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(icon))
        using (GraphicsPath shape = RoundedRect(new Rectangle(20, 20, 984, 984), 214))
        using (LinearGradientBrush background = new LinearGradientBrush(
            new Point(80, 40), new Point(940, 990), C(28, 31, 43), C(7, 8, 12)))
        {
            g.Clear(Color.Transparent);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.FillPath(background, shape);
            using (Pen outline = new Pen(Color.FromArgb(95, 255, 212, 0), 3))
                g.DrawPath(outline, shape);
            g.DrawImage(logo, new Rectangle(66, 238, 892, 548));
        }
        return icon;
    }

    private static void SaveIconFile(Bitmap master, string path)
    {
        int[] sizes = new int[] { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
        byte[][] images = new byte[sizes.Length][];
        for (int i = 0; i < sizes.Length; i++)
        {
            using (Bitmap frame = Resize(master, sizes[i])) images[i] = PngBytes(frame);
        }

        using (BinaryWriter writer = new BinaryWriter(File.Create(path)))
        {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)sizes.Length);
            int offset = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++)
            {
                writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                writer.Write((byte)0);
                writer.Write((byte)0);
                writer.Write((ushort)1);
                writer.Write((ushort)32);
                writer.Write(images[i].Length);
                writer.Write(offset);
                offset += images[i].Length;
            }
            foreach (byte[] image in images) writer.Write(image);
        }
    }

    private static void CreateHeader(string path, Bitmap logo)
    {
        using (Bitmap bitmap = new Bitmap(150, 57, PixelFormat.Format24bppRgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (LinearGradientBrush background = new LinearGradientBrush(
            new Rectangle(0, 0, 150, 57), C(25, 27, 36), C(12, 13, 18), 0f))
        using (Font title = new Font("Segoe UI", 12f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (Font subtitle = new Font("Segoe UI", 6f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (SolidBrush white = new SolidBrush(C(244, 244, 248)))
        using (SolidBrush gold = new SolidBrush(C(255, 212, 0)))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.FillRectangle(background, 0, 0, 150, 57);
            g.FillRectangle(gold, 0, 0, 3, 57);
            g.DrawImage(logo, new Rectangle(9, 13, 51, 31));
            g.DrawString("BatPlayer", title, white, 63f, 15f);
            g.DrawString("MEDIA PLAYER", subtitle, gold, 64f, 33f);
            bitmap.Save(path, ImageFormat.Bmp);
        }
    }

    private static void CreateSidebar(string path, Bitmap logo)
    {
        using (Bitmap bitmap = new Bitmap(164, 314, PixelFormat.Format24bppRgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (LinearGradientBrush background = new LinearGradientBrush(
            new Rectangle(0, 0, 164, 314), C(22, 25, 35), C(7, 8, 12), 35f))
        using (Font title = new Font("Segoe UI", 17f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (Font subtitle = new Font("Segoe UI", 8.2f, FontStyle.Regular, GraphicsUnit.Pixel))
        using (Font feature = new Font("Segoe UI", 7.4f, FontStyle.Regular, GraphicsUnit.Pixel))
        using (Font footer = new Font("Segoe UI", 6.4f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (SolidBrush white = new SolidBrush(C(239, 240, 245)))
        using (SolidBrush dim = new SolidBrush(C(160, 164, 177)))
        using (SolidBrush gold = new SolidBrush(C(255, 212, 0)))
        using (Pen line = new Pen(Color.FromArgb(150, 255, 212, 0), 1f))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.FillRectangle(background, 0, 0, 164, 314);
            g.FillRectangle(gold, 161, 0, 3, 314);
            g.DrawImage(logo, new Rectangle(12, 31, 140, 86));
            g.DrawString("BatPlayer", title, white, 14f, 133f);
            g.DrawString("YOUR MEDIA. YOUR PACE.", subtitle, gold, 15f, 160f);
            g.DrawLine(line, 15, 188, 146, 188);

            string[] items = new string[] {
                "Smooth playback controls",
                "Playlists made simple",
                "Audio and subtitles your way"
            };
            for (int i = 0; i < items.Length; i++)
            {
                int y = 207 + i * 25;
                g.FillEllipse(gold, 16, y + 3, 5, 5);
                g.DrawString(items[i], feature, dim, 27f, y);
            }

            g.DrawLine(line, 15, 286, 146, 286);
            g.DrawString("A BATPLAYER EXPERIENCE", footer, dim, 15f, 296f);
            bitmap.Save(path, ImageFormat.Bmp);
        }
    }

    public static void Generate(string root)
    {
        string iconDir = Path.Combine(root, "src-tauri", "icons");
        string sourcePath = Path.Combine(iconDir, "batplayer-logo-source.png");
        using (Bitmap source = new Bitmap(sourcePath))
        {
            int left = source.Width, top = source.Height, right = 0, bottom = 0;
            for (int y = 0; y < source.Height; y++)
                for (int x = 0; x < source.Width; x++)
                {
                    Color color = source.GetPixel(x, y);
                    if (Math.Max(color.R, Math.Max(color.G, color.B)) > 20)
                    {
                        if (x < left) left = x;
                        if (y < top) top = y;
                        if (x > right) right = x;
                        if (y > bottom) bottom = y;
                    }
                }

            int margin = 24;
            left = Math.Max(0, left - margin);
            top = Math.Max(0, top - margin);
            right = Math.Min(source.Width - 1, right + margin);
            bottom = Math.Min(source.Height - 1, bottom + margin);
            Bitmap cutout = new Bitmap(right - left + 1, bottom - top + 1, PixelFormat.Format32bppArgb);
            for (int y = top; y <= bottom; y++)
                for (int x = left; x <= right; x++)
                {
                    Color color = source.GetPixel(x, y);
                    int max = Math.Max(color.R, Math.Max(color.G, color.B));
                    int alpha = Math.Max(0, Math.Min(255, (max - 5) * 255 / 38));
                    cutout.SetPixel(x - left, y - top, Color.FromArgb(alpha, color.R, color.G, color.B));
                }

            using (Bitmap master = CreateAppIcon(cutout))
            {
                master.Save(Path.Combine(iconDir, "icon.png"), ImageFormat.Png);
                using (Bitmap small = Resize(master, 32)) small.Save(Path.Combine(iconDir, "32x32.png"), ImageFormat.Png);
                using (Bitmap medium = Resize(master, 128)) medium.Save(Path.Combine(iconDir, "128x128.png"), ImageFormat.Png);
                using (Bitmap large = Resize(master, 256)) large.Save(Path.Combine(iconDir, "128x128@2x.png"), ImageFormat.Png);
                SaveIconFile(master, Path.Combine(iconDir, "icon.ico"));
                CreateHeader(Path.Combine(iconDir, "installer-header.bmp"), cutout);
                CreateSidebar(Path.Combine(iconDir, "installer-sidebar.bmp"), cutout);
            }
            cutout.Dispose();
        }
    }
}
'@

Add-Type -TypeDefinition $brandingGenerator -ReferencedAssemblies System.Drawing
[BatPlayerWindowsBranding]::Generate((Resolve-Path (Join-Path $PSScriptRoot "..")))
Write-Output "Generated BatPlayer Windows application and installer branding assets."
