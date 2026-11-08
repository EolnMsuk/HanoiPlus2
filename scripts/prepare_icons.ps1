$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$iconDirectory = Join-Path $projectRoot 'ios/HanoiPlus/Assets.xcassets/AppIcon.appiconset'
[void][System.IO.Directory]::CreateDirectory($iconDirectory)
$artwork = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'iTunesArtwork'))
try {
    if ($artwork.Width -ne 512 -or $artwork.Height -ne 512) { throw 'Unexpected reference artwork size' }
    foreach ($size in @(40, 58, 60, 80, 87, 120, 180, 1024)) {
        $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
        try {
            $graphics.Clear([System.Drawing.Color]::White)
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $rectangle = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
            $graphics.DrawImage($artwork, $rectangle, 0, 0, 512, 512, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
            $bitmap.Save((Join-Path $iconDirectory "Icon-$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $attributes.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
} finally { $artwork.Dispose() }
