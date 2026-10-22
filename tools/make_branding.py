#!/usr/bin/env python3
"""Makes the game's icons, splash, title logo and README banner from the logo art (D198).

The source is the art on a solid black background: the background is keyed out from the
borders, so dark parts inside the art (text, a gauge face) stay. Needs Pillow (the system
python3 has it; the project's .venv does not).

    python3 tools/make_branding.py "<...>/noss2_short_black.png"
    python3 tools/make_branding.py ART --cutout OUT.png   # also the full-size cut-out

Writes content/branding/ (icon.png, icon.ico, icon.icns, splash.png, logo.png) and
docs/images/banner.png.
"""

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "content" / "branding"
BANNER = ROOT / "docs" / "images" / "banner.png"
FONTS = ROOT / "content" / "fonts" / "atkinson_hyperlegible"

# Background: anything this dark joined to the border. Edge pixels ramp from clear at FLOOR
# to solid at SOLID (their brightness over black is their coverage).
DARK = 24
FLOOR = 4
SOLID = 64
EDGE = 2  # px either side of the outline that get the ramp
# Enclosed dark patches that are mostly background black (0-3) and at least HOLE px are
# background seen through a gap (behind the gauge); smaller ones (a pipe's bore) stay.
HOLE = 1000

# The title screen's colours (game/ui/title/title_screen.tscn).
BACKGROUND = (18, 18, 23)
TITLE_TEXT = (245, 245, 245)
TAGLINE_TEXT = (179, 179, 191)
TAGLINE = "Bring your own car."

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def flood(fillable: bytearray, w: int, h: int) -> bytearray:
    """The fillable pixels joined to the image's border (scanline fill)."""
    out = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        row = y * w
        if not fillable[row + x] or out[row + x]:
            continue
        left = x
        while left > 0 and fillable[row + left - 1] and not out[row + left - 1]:
            left -= 1
        right = x
        while right < w - 1 and fillable[row + right + 1] and not out[row + right + 1]:
            right += 1
        out[row + left:row + right + 1] = b"\x01" * (right - left + 1)
        for ny in (y - 1, y + 1):
            if ny < 0 or ny >= h:
                continue
            nrow = ny * w
            nx = left
            while nx <= right:
                if fillable[nrow + nx] and not out[nrow + nx]:
                    stack.append((nx, ny))
                    while nx <= right and fillable[nrow + nx] and not out[nrow + nx]:
                        nx += 1
                nx += 1
    return out


def see_through(dark: bytearray, bg: bytearray, bright: bytes, w: int) -> bytearray:
    """The enclosed dark patches that are background seen through a gap."""
    out = bytearray(len(dark))
    seen = bytearray(len(dark))
    for i in [i for i, d in enumerate(dark) if d and not bg[i]]:
        if seen[i]:
            continue
        seen[i] = 1
        stack = [i]
        patch = []
        while stack:  # enclosed, so never on the image's edge: no bounds to check
            j = stack.pop()
            patch.append(j)
            for k in (j - 1, j + 1, j - w, j + w):
                if dark[k] and not bg[k] and not seen[k]:
                    seen[k] = 1
                    stack.append(k)
        if len(patch) >= HOLE and sum(1 for j in patch if bright[j] <= 3) * 2 >= len(patch):
            for j in patch:
                out[j] = 1
    return out


def cut_out(art: Image.Image) -> Image.Image:
    """The art with its black background made transparent."""
    rgb = art.convert("RGB")
    w, h = rgb.size
    r, g, b = rgb.split()
    bright = ImageChops.lighter(ImageChops.lighter(r, g), b)
    levels = bright.tobytes()
    dark = bytearray(1 if v <= DARK else 0 for v in levels)
    bg = flood(dark, w, h)
    for i, hole in enumerate(see_through(dark, bg, levels, w)):
        if hole:
            bg[i] = 1
    bg = Image.frombytes("L", (w, h), bytes(bg)).point(lambda v: 255 if v else 0)
    subject = ImageChops.invert(bg)
    grow = ImageFilter.MaxFilter(2 * EDGE + 1)
    band = ImageChops.multiply(subject.filter(grow), bg.filter(grow))
    alpha = subject.copy()
    out = rgb.convert("RGBA")
    px = out.load()
    band_px = band.load()
    bright_px = bright.load()
    alpha_px = alpha.load()
    for y in range(h):
        for x in range(w):
            if not band_px[x, y]:
                continue
            a = max(0, min(255, (bright_px[x, y] - FLOOR) * 255 // (SOLID - FLOOR)))
            alpha_px[x, y] = a
            if a:  # over black the pixel is colour x coverage: divide it back out
                c = px[x, y]
                px[x, y] = (min(255, c[0] * 255 // a), min(255, c[1] * 255 // a), min(255, c[2] * 255 // a), 255)
    out.putalpha(alpha)
    return out


def subject_box(cut: Image.Image) -> tuple:
    return cut.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()


def square(cut: Image.Image, box: tuple, height_share: float) -> Image.Image:
    """A transparent square around the subject, which fills `height_share` of its height."""
    side = round((box[3] - box[1]) / height_share)
    cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cut, (side // 2 - cx, side // 2 - cy))
    return canvas


def tall(cut: Image.Image, box: tuple, margin: float, height: int) -> Image.Image:
    """The subject with `margin` (a share of its height) all round, `height` px tall."""
    pad = round((box[3] - box[1]) * margin)
    crop = cut.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))
    return crop.resize((round(crop.width * height / crop.height), height), Image.Resampling.LANCZOS)


def banner(cut: Image.Image, box: tuple) -> Image.Image:
    """1280 x 640 (GitHub's social preview size): the logo left, the name and tagline right."""
    w, h = 1280, 640
    out = Image.new("RGB", (w, h), BACKGROUND)
    logo = tall(cut, box, 0.0, round(h * 0.8))
    out.paste(logo, (380 - logo.width // 2, (h - logo.height) // 2), logo)
    draw = ImageDraw.Draw(out)
    name_font = ImageFont.truetype(str(FONTS / "AtkinsonHyperlegible-Bold.ttf"), 190)
    tag_font = ImageFont.truetype(str(FONTS / "AtkinsonHyperlegible-Regular.ttf"), 52)
    name_box = draw.textbbox((0, 0), "nOSS", font=name_font)
    tag_box = draw.textbbox((0, 0), TAGLINE, font=tag_font)
    gap = 28
    block = (name_box[3] - name_box[1]) + gap + (tag_box[3] - tag_box[1])
    left = 560
    top = (h - block) // 2
    draw.text((left - name_box[0], top - name_box[1]), "nOSS", font=name_font, fill=TITLE_TEXT)
    top += name_box[3] - name_box[1] + gap
    draw.text((left - tag_box[0], top - tag_box[1]), TAGLINE, font=tag_font, fill=TAGLINE_TEXT)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("art", type=Path, help="the logo art on a solid black background")
    parser.add_argument("--cutout", type=Path, help="also write the full-size cut-out here")
    args = parser.parse_args()

    cut = cut_out(Image.open(args.art))
    box = subject_box(cut)
    if args.cutout:
        cut.save(args.cutout, optimize=True)
        print(f"{args.cutout} {cut.width}x{cut.height}")

    BRANDING.mkdir(parents=True, exist_ok=True)
    BANNER.parent.mkdir(parents=True, exist_ok=True)
    icon = square(cut, box, 0.94).resize((1024, 1024), Image.Resampling.LANCZOS)
    outputs = {
        BRANDING / "icon.png": icon.resize((256, 256), Image.Resampling.LANCZOS),
        BRANDING / "splash.png": square(cut, box, 0.6).resize((1080, 1080), Image.Resampling.LANCZOS),
        BRANDING / "logo.png": tall(cut, box, 0.02, 1024),
        BANNER: banner(cut, box),
    }
    for path, im in outputs.items():
        im.save(path, optimize=True)
    icon.save(BRANDING / "icon.ico", sizes=[(s, s) for s in ICO_SIZES])  # PNG entries (Vista and up)
    icon.save(BRANDING / "icon.icns")
    for path in [*outputs, BRANDING / "icon.ico", BRANDING / "icon.icns"]:
        print(f"{path.relative_to(ROOT)} {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
