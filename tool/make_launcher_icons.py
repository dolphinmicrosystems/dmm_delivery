"""Draws the app icon: the truck the driver sees on the navigation map.

Same picture as the marker in lib/driver/driving/driving_screen.dart -
Material's `local_shipping_rounded` glyph, white, on AppColors.brand - so the
home screen, the Play listing and the map all show one truck.

Writes:
  android/app/src/main/res/mipmap-*/ic_launcher.png           old launchers (round)
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png Android 8+ adaptive icon
  docs/store/play-icon-512.png                                Play Console app icon

Run from the repo root:  python3 tool/make_launcher_icons.py   (needs Pillow)
"""

import pathlib
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
BRAND = (0x1A, 0x56, 0xDB, 255)  # AppColors.brand
WHITE = (255, 255, 255, 255)
TRUCK = chr(0xF87F)  # Icons.local_shipping_rounded
SS = 4  # draw big, shrink: smooth edges

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def font_path() -> str:
    flutter = pathlib.Path(subprocess.check_output(["which", "flutter"], text=True).strip()).resolve()
    return str(flutter.parent / "cache/artifacts/material_fonts/MaterialIcons-Regular.otf")


FONT = font_path()


def truck(canvas: Image.Image, box: float) -> None:
    """The truck glyph, white, centred, its 24-unit em square [box] px wide."""
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT, round(box))
    w, h = canvas.size
    draw.text((w / 2, h / 2), TRUCK, font=font, fill=WHITE, anchor="mm")


def legacy(px: int) -> Image.Image:
    """Pre-Android-8 launcher: the map marker itself - blue disc, white ring."""
    s = px * SS
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pad = s * 0.04
    d.ellipse([pad, pad, s - pad, s - pad], fill=WHITE)
    ring = s * 0.075
    d.ellipse([ring, ring, s - ring, s - ring], fill=BRAND)
    truck(im, s * 0.58)
    return im.resize((px, px), Image.LANCZOS)


def foreground(px: int) -> Image.Image:
    """Adaptive foreground (108dp). Launchers crop to the middle 72dp and
    keep 66dp safe, so the truck stays well inside that."""
    s = px * SS
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    truck(im, s * 0.56)
    return im.resize((px, px), Image.LANCZOS)


def play_icon() -> Image.Image:
    """512x512, full square: Play rounds the corners itself."""
    s = 512 * SS
    im = Image.new("RGBA", (s, s), BRAND)
    truck(im, s * 0.66)
    return im.resize((512, 512), Image.LANCZOS)


def main() -> None:
    for name, scale in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(exist_ok=True)
        legacy(round(48 * scale)).save(folder / "ic_launcher.png")
        foreground(round(108 * scale)).save(folder / "ic_launcher_foreground.png")
    store = ROOT / "docs/store"
    store.mkdir(parents=True, exist_ok=True)
    play_icon().save(store / "play-icon-512.png")
    print("icons written")


if __name__ == "__main__":
    main()
