#!/usr/bin/env python3
"""One-off generator for the "training" flavor's launcher icon.

Reads the existing production icon assets under
android/app/src/main/res/mipmap-*/ and writes orange-badged counterparts to
android/app/src/training/res/mipmap-*/ — Android's flavor-specific resource
source set, which the "training" product flavor (android/app/build.gradle.kts)
picks up automatically over src/main/res/.

Two different treatments, chosen for reliability across OEM launchers:
  - ic_launcher.png (legacy, flattened, never mask-clipped): a diagonal
    orange ribbon with "TRAIN" text across the top-right corner.
  - ic_launcher_foreground.png (adaptive-icon foreground layer, shown through
    an OEM-specific circle/squircle/rounded-square mask whose exact shape we
    can't predict): a whole-image orange tint instead of a corner ribbon, so
    it reads as orange regardless of what the mask crops away.

Run this once (or re-run only if the base production icon ever changes) —
there is no icon-generation pipeline in this repo, and the output is meant to
be committed as static assets, not regenerated on every build.

Usage:
    python3 scripts/generate_training_icon.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC_RES = ROOT / "android/app/src/main/res"
DST_RES = ROOT / "android/app/src/training/res"

DENSITIES = ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]
RIBBON_COLOR = (234, 88, 12, 255)  # AppColors.trainingOrange, #EA580C
RIBBON_TEXT_COLOR = (255, 255, 255, 255)


def _font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        if Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                continue
    return ImageFont.load_default()


def badge_with_ribbon(src: Image.Image) -> Image.Image:
    """Diagonal orange ribbon + 'TRAIN' text across the top-right corner."""
    w, h = src.size
    out = src.convert("RGBA")

    # Ribbon drawn on an oversized transparent layer, rotated 45°, then
    # cropped back to the icon's own size — simpler than computing a rotated
    # parallelogram's corners by hand.
    diag = int(math.hypot(w, h))
    band_h = max(1, round(h * 0.26))
    layer = Image.new("RGBA", (diag, diag), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    band_y0 = diag // 2 - band_h // 2
    draw.rectangle([0, band_y0, diag, band_y0 + band_h], fill=RIBBON_COLOR)

    font = _font(max(8, round(band_h * 0.6)))
    text = "TRAIN"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w, text_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(
        (diag / 2 - text_w / 2 - bbox[0], band_y0 + band_h / 2 - text_h / 2 - bbox[1]),
        text,
        font=font,
        fill=RIBBON_TEXT_COLOR,
    )

    layer = layer.rotate(-45, resample=Image.BICUBIC, expand=False)
    offset = ((diag - w) // 2, (diag - h) // 2)
    crop = layer.crop((offset[0], offset[1], offset[0] + w, offset[1] + h))

    out.alpha_composite(crop)
    return out


def tint_foreground(src: Image.Image) -> Image.Image:
    """Recolor to solid orange, preserving the original alpha/shape.

    A partial blend still reads as the original brand pink/magenta at a
    glance — a full recolor (keeping only the source alpha channel as a
    silhouette mask) is unambiguous as "orange" regardless of launcher mask.
    """
    src = src.convert("RGBA")
    _, _, _, orig_a = src.split()
    orange_layer = Image.new("RGBA", src.size, RIBBON_COLOR)
    r, g, b, _ = orange_layer.split()
    return Image.merge("RGBA", (r, g, b, orig_a))


def main() -> None:
    for density in DENSITIES:
        src_dir = SRC_RES / f"mipmap-{density}"
        dst_dir = DST_RES / f"mipmap-{density}"
        dst_dir.mkdir(parents=True, exist_ok=True)

        legacy = src_dir / "ic_launcher.png"
        if legacy.exists():
            badge_with_ribbon(Image.open(legacy)).save(dst_dir / "ic_launcher.png")
            print(f"✓ {dst_dir / 'ic_launcher.png'}")

        foreground = src_dir / "ic_launcher_foreground.png"
        if foreground.exists():
            tint_foreground(Image.open(foreground)).save(dst_dir / "ic_launcher_foreground.png")
            print(f"✓ {dst_dir / 'ic_launcher_foreground.png'}")


if __name__ == "__main__":
    main()
