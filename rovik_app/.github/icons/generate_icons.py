#!/usr/bin/env python3
"""Generate all RovikVpn icon PNGs from the base64 master logo.

Why this exists: the GitHub push API used for this repo accepts text files
only, so the binary icon PNGs cannot be pushed directly. Instead the repo
stores the master logo as base64 text (rovikvpn_icon.b64) and this script
regenerates every derived icon at build time, before `flutter build apk`.

Run from the rovik_app directory (CI does this right after checkout):
    python3 .github/icons/generate_icons.py

Outputs (LANCZOS resampling):
    assets/rovikvpn_icon.png                          (splash + in-app)
    android/.../res/mipmap-{mdpi:48, hdpi:72, xhdpi:96, xxhdpi:144, xxxhdpi:192}/ic_launcher.png
    android/.../res/drawable-nodpi/rovik_splash_logo.png (480x480)
    android/.../res/drawable-{mdpi:24, hdpi:36, xhdpi:48, xxhdpi:72, xxxhdpi:96}/ic_tile.png
      (from rovikvpn_tile.b64 — a white R glyph on transparency, because
      Quick Settings tiles must be a monochrome glyph, not the full logo)
"""

import base64
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # rovik_app/
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

MIPMAP_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
TILE_SIZES = {
    "mdpi": 24,
    "hdpi": 36,
    "xhdpi": 48,
    "xxhdpi": 72,
    "xxxhdpi": 96,
}
SPLASH_SIZE = 480


def main() -> int:
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required: pip install pillow", file=sys.stderr)
        return 1

    b64_path = os.path.join(HERE, "rovikvpn_icon.b64")
    with open(b64_path, "r", encoding="ascii") as f:
        raw = base64.b64decode("".join(f.read().split()))

    master_path = os.path.join(ROOT, "assets", "rovikvpn_icon.png")
    os.makedirs(os.path.dirname(master_path), exist_ok=True)
    with open(master_path, "wb") as f:
        f.write(raw)

    img = Image.open(master_path).convert("RGBA")
    if img.size[0] != img.size[1]:
        print(f"master logo is not square: {img.size}", file=sys.stderr)
        return 1

    def save(size: int, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img.resize((size, size), Image.LANCZOS).save(path, "PNG")
        print(f"wrote {size}x{size} -> {os.path.relpath(path, ROOT)}")

    for density, size in MIPMAP_SIZES.items():
        save(size, os.path.join(RES, f"mipmap-{density}", "ic_launcher.png"))
    save(
        SPLASH_SIZE,
        os.path.join(RES, "drawable-nodpi", "rovik_splash_logo.png"),
    )

    # Tile glyph: white R on transparency (decoded from its own base64
    # master at 96x96, then downscaled per density).
    tile_b64_path = os.path.join(HERE, "rovikvpn_tile.b64")
    with open(tile_b64_path, "r", encoding="ascii") as f:
        tile_raw = base64.b64decode("".join(f.read().split()))
    tile_path = os.path.join(RES, "drawable-xxxhdpi", "ic_tile.png")
    os.makedirs(os.path.dirname(tile_path), exist_ok=True)
    with open(tile_path, "wb") as f:
        f.write(tile_raw)
    tile = Image.open(tile_path).convert("RGBA")
    for density, size in TILE_SIZES.items():
        p = os.path.join(RES, f"drawable-{density}", "ic_tile.png")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tile.resize((size, size), Image.LANCZOS).save(p, "PNG")
        print(f"wrote {size}x{size} -> {os.path.relpath(p, ROOT)}")
    print("icons generated OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
