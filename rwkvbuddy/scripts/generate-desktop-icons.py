"""Regenerate desktop icons from the editable SVG (requires ImageMagick and Pillow)."""
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'assets' / 'brand'
SOURCE = BRAND / 'tecno-buddy-icon.svg'
MAC = ROOT / 'macos' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
WINDOWS = ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico'


def main():
    with tempfile.TemporaryDirectory(prefix='tecno-buddy-icons-') as directory:
        temporary = Path(directory)
        raster = temporary / 'master.png'
        foreground = temporary / 'foreground.svg'
        foreground.write_text(SOURCE.read_text().replace('<rect x="96" y="96" width="832" height="832" rx="184" fill="url(#tile)"/>', ''), encoding='utf-8')
        subprocess.run(['magick', '-background', 'none', '-density', '192', str(foreground), str(raster)], check=True)
        overlay = Image.open(raster).convert('RGBA')
        resolution = overlay.width
        scale = resolution / 1024
        gradient = Image.new('RGBA', (resolution, resolution))
        pixels = gradient.load()
        stops = [(0, (22, 134, 255)), (0.48, (8, 100, 247)), (1, (18, 70, 220))]
        for vertical in range(resolution):
            for horizontal in range(resolution):
                position = max(0, min(1, ((horizontal / scale - 140) * 730 + (vertical / scale - 96) * 844) / (730 ** 2 + 844 ** 2)))
                lower, upper = (stops[0], stops[1]) if position < 0.48 else (stops[1], stops[2])
                ratio = (position - lower[0]) / (upper[0] - lower[0])
                pixels[horizontal, vertical] = tuple(round(start + (end - start) * ratio) for start, end in zip(lower[1], upper[1])) + (255,)
        mask = Image.new('L', (resolution, resolution))
        ImageDraw.Draw(mask).rounded_rectangle(tuple(round(value * scale) for value in (96, 96, 928, 928)), radius=round(184 * scale), fill=255)
        gradient.putalpha(mask)
        gradient.alpha_composite(overlay)
        master = gradient.resize((1024, 1024), Image.Resampling.LANCZOS)
        master.save(BRAND / 'tecno-buddy-icon-1024.png')
        for size in (16, 32, 64, 128, 256, 512, 1024):
            master.resize((size, size), Image.Resampling.LANCZOS).save(MAC / f'app_icon_{size}.png')
        master.save(WINDOWS, format='ICO', sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
        shutil.copyfile(WINDOWS, BRAND / 'tecno-buddy.ico')
        if shutil.which('iconutil'):
            iconset = temporary / 'TECNO Buddy.iconset'
            iconset.mkdir()
            for size in (16, 32, 128, 256, 512):
                for scale in (1, 2):
                    pixels = size * scale
                    suffix = '@2x' if scale == 2 else ''
                    master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(iconset / f'icon_{size}x{size}{suffix}.png')
            subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(BRAND / 'tecno-buddy.icns')], check=True)
        preview = Image.new('RGB', (1100, 650), '#F2F4F8')
        preview.paste(master.resize((512, 512), Image.Resampling.LANCZOS), (25, 65), master.resize((512, 512), Image.Resampling.LANCZOS))
        draw = ImageDraw.Draw(preview)
        draw.rounded_rectangle((580, 40, 1060, 305), radius=24, fill='#FFFFFF')
        draw.rounded_rectangle((580, 345, 1060, 610), radius=24, fill='#151D2D')
        for top in (75, 380):
            for x, size in ((610, 128), (780, 64), (890, 32), (980, 16)):
                icon = master.resize((size, size), Image.Resampling.LANCZOS)
                preview.paste(icon, (x, top + (128 - size) // 2), icon)
                draw.text((x, top + 165), f'{size}px', fill='#8290A7')
        preview.save(BRAND / 'desktop-icon-preview.png')
    print('Updated macOS AppIcon and Windows ICO; exports saved to assets/brand/.')


if __name__ == '__main__':
    main()
