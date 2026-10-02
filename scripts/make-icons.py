#!/usr/bin/env python3
"""Generate the Kocharian AI icon set (PWA + iOS) from code — no external assets.

Usage: python3 scripts/make-icons.py
Writes:  public/icons/*.png, public/icons/icon.svg,
         ios/KocharianAI/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "public", "icons")
IOS = os.path.join(ROOT, "ios", "KocharianAI", "Assets.xcassets", "AppIcon.appiconset")

S = 2048                      # master render size (downsampled later)
TEAL_DARK = (6, 60, 54)
TEAL = (16, 163, 127)
MINT = (74, 222, 164)
ACCENT = (125, 249, 199)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(size: int) -> Image.Image:
    """Diagonal 3-stop gradient."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.45) + (y / size * 0.55)
            if t < 0.5:
                px[x, y] = lerp(TEAL_DARK, TEAL, t / 0.5)
            else:
                px[x, y] = lerp(TEAL, MINT, (t - 0.5) / 0.5)
    return img


def squircle_mask(size: int, radius_ratio: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    return mask


def poly(d: ImageDraw.ImageDraw, pts, fill):
    d.polygon(pts, fill=fill)


def draw_mark(img: Image.Image, cx: float, cy: float, scale: float) -> None:
    """A geometric 'K' built from a stem + two chevron arms, with a spark node."""
    d = ImageDraw.Draw(img, "RGBA")
    u = scale                              # 1 unit
    white = (255, 255, 255, 255)
    soft = (236, 255, 248, 255)

    stem_w = 0.26 * u
    top = cy - 1.05 * u
    bot = cy + 1.05 * u
    sx = cx - 0.72 * u
    d.rounded_rectangle([sx - stem_w / 2, top, sx + stem_w / 2, bot],
                        radius=stem_w / 2, fill=white)

    arm_w = 0.26 * u
    joint = (sx + 0.06 * u, cy + 0.02 * u)
    up_end = (cx + 0.86 * u, top + 0.08 * u)
    dn_end = (cx + 0.88 * u, bot - 0.06 * u)

    def thick_line(p0, p1, w):
        d.line([p0, p1], fill=white, width=int(w), joint="curve")
        r = w / 2
        for p in (p0, p1):
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=white)

    thick_line(joint, up_end, arm_w)
    thick_line(joint, dn_end, arm_w)

    # spark / "AI" node at the top of the rising arm
    r = 0.30 * u
    hx, hy = up_end[0] + 0.02 * u, up_end[1] - 0.02 * u
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=soft)
    inner = 0.145 * u
    d.ellipse([hx - inner, hy - inner, hx + inner, hy + inner], fill=(10, 94, 76, 255))

    # four-point sparkle above the node
    sxp, syp = cx - 0.14 * u, top - 0.34 * u
    a, b = 0.26 * u, 0.075 * u
    poly(d, [(sxp, syp - a), (sxp + b, syp), (sxp, syp + a), (sxp - b, syp)], soft)
    poly(d, [(sxp - a, syp), (sxp, syp - b), (sxp + a, syp), (sxp, syp + b)], soft)


def build_master(size: int = S, pad: float = 0.0, radius: float = 0.225) -> Image.Image:
    """Full icon. `pad` = fraction of the canvas kept empty around the tile."""
    inner = int(size * (1 - pad * 2))
    base = gradient(inner).convert("RGBA")

    # highlight sweep
    hl = Image.new("L", (inner, inner), 0)
    hd = ImageDraw.Draw(hl)
    hd.ellipse([-inner * 0.35, -inner * 0.75, inner * 0.95, inner * 0.45], fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(inner * 0.08))
    base = Image.alpha_composite(
        base, Image.merge("RGBA", (*Image.new("RGB", (inner, inner), (225, 255, 243)).split(), hl))
    )

    # subtle grid of dots (neural texture)
    tex = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    td = ImageDraw.Draw(tex)
    step = inner // 14
    rr = max(1, inner // 420)
    for gy in range(step // 2, inner, step):
        for gx in range(step // 2, inner, step):
            t = 1 - (gx + gy) / (2 * inner)
            td.ellipse([gx - rr, gy - rr, gx + rr, gy + rr], fill=(255, 255, 255, int(46 * t)))
    base = Image.alpha_composite(base, tex)

    # soft shadow under the mark
    sh = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    draw_mark(sh, inner * 0.5, inner * 0.54, inner * 0.265)
    sh = sh.filter(ImageFilter.GaussianBlur(inner * 0.035))
    sh = Image.merge("RGBA", (*Image.new("RGB", (inner, inner), (2, 38, 32)).split(),
                              sh.split()[3].point(lambda v: int(v * 0.55))))
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -inner * 0.012))
    base = Image.alpha_composite(base, sh)

    draw_mark(base, inner * 0.5, inner * 0.54, inner * 0.265)

    if radius > 0:
        base.putalpha(squircle_mask(inner, radius))

    if pad <= 0:
        return base
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(base, (int(size * pad), int(size * pad)), base)
    return canvas


def save(img: Image.Image, path: str, size: int, bg=None) -> None:
    out = img.resize((size, size), Image.LANCZOS)
    if bg is not None:
        flat = Image.new("RGBA", (size, size), bg)
        out = Image.alpha_composite(flat, out)
        out = out.convert("RGB")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, optimize=True)
    print(f"  {os.path.relpath(path, ROOT)}  {size}x{size}")


SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="Kocharian AI">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#063c36"/>
      <stop offset="0.5" stop-color="#10a37f"/>
      <stop offset="1" stop-color="#4adea4"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="115" fill="url(#g)"/>
  <g fill="none" stroke="#fff" stroke-width="40" stroke-linecap="round" stroke-linejoin="round">
    <path d="M182 148 V364"/>
    <path d="M190 258 L329 151"/>
    <path d="M190 258 L332 363"/>
  </g>
  <circle cx="335" cy="148" r="46" fill="#ecfff8"/>
  <circle cx="335" cy="148" r="22" fill="#0a5e4c"/>
  <path d="M249 106 l13 29 29 13 -29 13 -13 29 -13 -29 -29 -13 29 -13z" fill="#ecfff8"/>
</svg>
"""


def main() -> None:
    print("rendering master…")
    master = build_master()                      # rounded tile, transparent corners
    full = build_master(radius=0.0)              # full-bleed square (iOS / maskable base)
    maskable = build_master(pad=0.105, radius=0.0)
    maskable_flat = Image.alpha_composite(
        Image.new("RGBA", maskable.size, (8, 70, 60, 255)), maskable)

    os.makedirs(OUT, exist_ok=True)
    save(master, os.path.join(OUT, "icon-1024.png"), 1024)
    save(master, os.path.join(OUT, "icon-512.png"), 512)
    save(master, os.path.join(OUT, "icon-192.png"), 192)
    save(maskable_flat, os.path.join(OUT, "maskable-512.png"), 512)
    save(maskable_flat, os.path.join(OUT, "maskable-192.png"), 192)
    save(full, os.path.join(OUT, "apple-touch-icon.png"), 180, bg=(16, 163, 127, 255))
    save(master, os.path.join(OUT, "favicon-32.png"), 32)
    save(master, os.path.join(ROOT, "docs", "icon-master.png"), 512)
    with open(os.path.join(OUT, "icon.svg"), "w", encoding="utf-8") as fh:
        fh.write(SVG)
    print("  public/icons/icon.svg")

    # iOS app icon must be opaque, square, no alpha
    save(full, os.path.join(IOS, "icon-1024.png"), 1024, bg=(16, 163, 127, 255))
    print("done.")


if __name__ == "__main__":
    main()
