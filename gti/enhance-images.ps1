param([switch]$NormalizeWhiteOnly)

Add-Type -AssemblyName System.Drawing

$source = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BannerEnhancer
{
    public static void Enhance(string inputPath, string outputPath, int scale, double strength)
    {
        using (var source = new Bitmap(inputPath))
        using (var resized = new Bitmap(source.Width * scale, source.Height * scale, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(resized))
            using (var attributes = new ImageAttributes())
            {
                graphics.CompositingMode = CompositingMode.SourceCopy;
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                attributes.SetWrapMode(WrapMode.TileFlipXY);
                graphics.DrawImage(
                    source,
                    new Rectangle(0, 0, resized.Width, resized.Height),
                    0,
                    0,
                    source.Width,
                    source.Height,
                    GraphicsUnit.Pixel,
                    attributes
                );
            }

            ApplySharpen(resized, strength);
            resized.Save(outputPath, ImageFormat.Png);
        }
    }

    private static void ApplySharpen(Bitmap image, double strength)
    {
        var bounds = new Rectangle(0, 0, image.Width, image.Height);
        var data = image.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);

        try
        {
            int stride = data.Stride;
            int byteCount = Math.Abs(stride) * image.Height;
            var original = new byte[byteCount];
            var sharpened = new byte[byteCount];
            Marshal.Copy(data.Scan0, original, 0, byteCount);
            Buffer.BlockCopy(original, 0, sharpened, 0, byteCount);

            double center = 1.0 + 4.0 * strength;
            for (int y = 1; y < image.Height - 1; y++)
            {
                int row = y * stride;
                for (int x = 1; x < image.Width - 1; x++)
                {
                    int pixel = row + x * 4;
                    for (int channel = 0; channel < 3; channel++)
                    {
                        double value = original[pixel + channel] * center
                            - original[pixel - 4 + channel] * strength
                            - original[pixel + 4 + channel] * strength
                            - original[pixel - stride + channel] * strength
                            - original[pixel + stride + channel] * strength;
                        sharpened[pixel + channel] = (byte)Math.Max(0, Math.Min(255, Math.Round(value)));
                    }
                }
            }

            Marshal.Copy(sharpened, 0, data.Scan0, byteCount);
        }
        finally
        {
            image.UnlockBits(data);
        }
    }

    public static void MakeBackgroundWhite(string inputPath, string outputPath)
    {
        using (var image = new Bitmap(inputPath))
        {
            var bounds = new Rectangle(0, 0, image.Width, image.Height);
            var data = image.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);

            try
            {
                int stride = data.Stride;
                int byteCount = Math.Abs(stride) * image.Height;
                var pixels = new byte[byteCount];
                var foreground = new bool[image.Width * image.Height];
                var distance = new short[image.Width * image.Height];
                var queue = new Queue<int>();
                Marshal.Copy(data.Scan0, pixels, 0, byteCount);
                for (int i = 0; i < distance.Length; i++) distance[i] = -1;

                for (int y = 3; y < image.Height - 3; y++)
                {
                    for (int x = 3; x < image.Width - 3; x++)
                    {
                        int index = y * image.Width + x;
                        if (!IsForegroundPixel(pixels, y * stride + x * 4)) continue;
                        foreground[index] = true;
                        distance[index] = 0;
                        queue.Enqueue(index);
                    }
                }

                while (queue.Count > 0)
                {
                    int index = queue.Dequeue();
                    int x = index % image.Width;
                    int y = index / image.Width;
                    if (distance[index] >= 14) continue;

                    int[] neighbors = {
                        x > 0 ? index - 1 : -1,
                        x + 1 < image.Width ? index + 1 : -1,
                        y > 0 ? index - image.Width : -1,
                        y + 1 < image.Height ? index + image.Width : -1
                    };

                    foreach (int neighbor in neighbors)
                    {
                        if (neighbor < 0 || distance[neighbor] >= 0) continue;
                        foreground[neighbor] = true;
                        distance[neighbor] = (short)(distance[index] + 1);
                        queue.Enqueue(neighbor);
                    }
                }

                for (int y = 0; y < image.Height; y++)
                {
                    for (int x = 0; x < image.Width; x++)
                    {
                        if (foreground[y * image.Width + x]) continue;
                        int pixel = y * stride + x * 4;
                        pixels[pixel] = 255;
                        pixels[pixel + 1] = 255;
                        pixels[pixel + 2] = 255;
                    }
                }

                Marshal.Copy(pixels, 0, data.Scan0, byteCount);
            }
            finally
            {
                image.UnlockBits(data);
            }

            image.Save(outputPath, ImageFormat.Png);
        }
    }

    private static bool IsForegroundPixel(byte[] pixels, int pixel)
    {
        int blue = pixels[pixel];
        int green = pixels[pixel + 1];
        int red = pixels[pixel + 2];
        int minimum = Math.Min(red, Math.Min(green, blue));
        int maximum = Math.Max(red, Math.Max(green, blue));
        double brightness = (red + green + blue) / 3.0;
        return brightness < 145 || maximum - minimum > 48;
    }

    public static void NormalizeNearWhite(string inputPath, string outputPath)
    {
        using (var image = new Bitmap(inputPath))
        {
            var bounds = new Rectangle(0, 0, image.Width, image.Height);
            var data = image.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int byteCount = Math.Abs(data.Stride) * image.Height;
                var pixels = new byte[byteCount];
                Marshal.Copy(data.Scan0, pixels, 0, byteCount);
                for (int y = 0; y < image.Height; y++)
                {
                    for (int x = 0; x < image.Width; x++)
                    {
                        int pixel = y * data.Stride + x * 4;
                        int minimum = Math.Min(pixels[pixel], Math.Min(pixels[pixel + 1], pixels[pixel + 2]));
                        int maximum = Math.Max(pixels[pixel], Math.Max(pixels[pixel + 1], pixels[pixel + 2]));
                        if (minimum < 245 || maximum - minimum > 10) continue;
                        pixels[pixel] = 255;
                        pixels[pixel + 1] = 255;
                        pixels[pixel + 2] = 255;
                    }
                }
                Marshal.Copy(pixels, 0, data.Scan0, byteCount);
            }
            finally
            {
                image.UnlockBits(data);
            }
            image.Save(outputPath, ImageFormat.Png);
        }
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

$images = @(
    'bee_doctor',
    'bit',
    'd_wolf',
    'lao_bei_zha',
    'no_name'
)

if ($NormalizeWhiteOnly) {
    foreach ($name in $images) {
        $inputPath = Join-Path $PSScriptRoot "$name-white.png"
        $tempPath = Join-Path $PSScriptRoot "$name-white.tmp.png"
        [BannerEnhancer]::NormalizeNearWhite($inputPath, $tempPath)
        Move-Item -LiteralPath $tempPath -Destination $inputPath -Force
        Write-Output "$name-white.png"
    }
    return
}

foreach ($name in $images) {
    $inputPath = Join-Path $PSScriptRoot "$name.png"
    $outputPath = Join-Path $PSScriptRoot "$name-hd.png"
    [BannerEnhancer]::Enhance($inputPath, $outputPath, 3, 0.10)
    Write-Output "$name-hd.png"
}
