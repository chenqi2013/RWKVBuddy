# TECNO Buddy desktop icon

Blue rounded tile with a white conversation bubble and a blue **T**. The mark
connects the TECNO Buddy name to its conversational assistant role. Large shapes
remain legible at desktop sizes; transparent margins suit macOS and Windows.

- Editable source: `tecno-buddy-icon.svg`.
- Master PNG: `tecno-buddy-icon-1024.png` (1024 × 1024, RGBA).
- Windows: `tecno-buddy.ico` (16, 24, 32, 48, 64, 128, 256 px).
- macOS: `tecno-buddy.icns`, plus the AppIcon asset catalog in `macos/Runner/`.
- Size and light/dark background preview: `desktop-icon-preview.png`.

Created directly as vector artwork; no image generation API is required.
Regenerate using Python with Pillow and ImageMagick installed:

```sh
python3 scripts/generate-desktop-icons.py
```

On macOS, `iconutil` also exports the standalone ICNS file. Platform resource
files are updated by the script. Only Windows and macOS icons are included.
