#!/usr/bin/env python3
"""Brand wordmark generator: replaces the lettering under The PLO Show emblem.

The original artwork (`assets/logo.png`, `web/logo.png`, `web/splash.mp4`) was
"THE PLO SHOW" emblem over a "HAND HISTORY" wordmark. This rebuilds the
wordmark in the same style — chrome-gold Montserrat Bold with a horizon
gradient sampled from the original, a dark smoky backdrop, gold sparks and a
flare line — for any text (the app is now "The PLO Show App" → "APP").

Font: Montserrat (SIL Open Font License), variable TTF from
https://github.com/google/fonts/raw/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf

--src must be the ORIGINAL "HAND HISTORY" artwork (the geometry below is
measured on it), recoverable from git, e.g.:
  git show fecd144:plo-app/assets/logo.png > /tmp/logo_orig.png
  git show fecd144:plo-app/web/splash.mp4  > /tmp/splash_orig.mp4
web/logo.png is the 1024px logo resized to 640×665 (LANCZOS).

Usage:
  wordmark.py logo  --font Montserrat.ttf --text APP --src assets/logo.png --out assets/logo.png
  wordmark.py video --font Montserrat.ttf --text APP --src web/splash.mp4 --out web/splash.mp4
"""
import argparse
import math
import random
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# Row profile of the original lettering, top → bottom (sampled from the
# "HAND HISTORY" glyphs): pale gold, a sharp horizon just past half height,
# deeper gold below with a slight lift at the foot.
GRADIENT = [
    (0.00, (226, 216, 155)),
    (0.07, (250, 244, 158)),
    (0.25, (250, 240, 148)),
    (0.45, (248, 228, 128)),
    (0.50, (249, 217, 104)),
    (0.53, (226, 180, 72)),
    (0.65, (204, 152, 52)),
    (0.85, (212, 160, 54)),
    (1.00, (216, 168, 64)),
]


def gradient_color(t):
    for (t0, c0), (t1, c1) in zip(GRADIENT, GRADIENT[1:]):
        if t <= t1:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return GRADIENT[-1][1]


def text_mask(text, font, tracking):
    """Glyph coverage mask for [text] with letter spacing; tight bbox."""
    widths = [font.getbbox(ch)[2] - font.getbbox(ch)[0] for ch in text]
    asc, desc = font.getmetrics()
    w = sum(widths) + tracking * (len(text) - 1) + 40
    mask = Image.new('L', (w, asc + desc + 40), 0)
    d = ImageDraw.Draw(mask)
    x = 20
    for ch, cw in zip(text, widths):
        d.text((x - font.getbbox(ch)[0], 20), ch, font=font, fill=255)
        x += cw + tracking
    return mask.crop(mask.getbbox())


def wordmark(text, cap_height, font_path, seed=7, decor=True):
    """RGBA wordmark block: backdrop + sparks + gold text + flare line
    ([decor] False → just the lettering with its rim and shadow).

    Returns (image, text_box) where text_box is the glyph bbox inside it.
    """
    rng = random.Random(seed)
    font = ImageFont.truetype(font_path, 400)
    font.set_variation_by_name('Bold')
    # Scale the font so capital height matches [cap_height].
    cap = font.getbbox('H')
    size = round(400 * cap_height / (cap[3] - cap[1]))
    font = ImageFont.truetype(font_path, size)
    font.set_variation_by_name('Bold')
    mask = text_mask(text, font, tracking=round(cap_height * 0.06))
    tw, th = mask.size

    pad_x, pad_top, pad_bot = round(th * 2.2), round(th * 0.9), round(th * 0.9)
    W, H = tw + 2 * pad_x, th + pad_top + pad_bot
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    tx, ty = pad_x, pad_top

    if decor:
        _decorate(out, rng, W, H, tw, th, pad_x, pad_top, pad_bot, ty,
                  cap_height)

    # Drop shadow, dark rim, then the gradient-filled glyphs.
    shadow = Image.new('L', (W, H), 0)
    shadow.paste(mask, (tx, ty + round(th * 0.05)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(th * 0.06))
    out.alpha_composite(Image.merge(
        'RGBA', [Image.new('L', (W, H), 0)] * 3 + [shadow.point(lambda v: v * 0.8)]))
    rim = Image.new('L', (W, H), 0)
    rim.paste(mask, (tx, ty))
    rim = rim.filter(ImageFilter.MaxFilter(3))
    out.alpha_composite(Image.merge(
        'RGBA', [Image.new('L', (W, H), c) for c in (92, 62, 18)] + [rim]))
    fill = Image.new('RGB', (tw, th))
    for y in range(th):
        c = gradient_color(y / max(1, th - 1))
        ImageDraw.Draw(fill).line((0, y, tw, y), fill=c)
    glyphs = fill.convert('RGBA')
    glyphs.putalpha(mask)
    out.alpha_composite(glyphs, (tx, ty))
    return out, (tx, ty, tx + tw, ty + th)


def _decorate(out, rng, W, H, tw, th, pad_x, pad_top, pad_bot, ty, cap_height):
    """Smoky backdrop, gold sparks and the lens-flare line (logo artwork)."""
    smoke_a = Image.new('L', (W, H), 0)
    ImageDraw.Draw(smoke_a).ellipse(
        (pad_x * 0.25, pad_top * 0.15, W - pad_x * 0.25, H - pad_bot * 0.25),
        fill=215)
    smoke_a = smoke_a.filter(ImageFilter.GaussianBlur(th * 0.45))
    grain = Image.effect_noise((W, H), 70).filter(ImageFilter.GaussianBlur(1.6))
    smoke_a = ImageChops.multiply(smoke_a, grain.point(lambda v: min(255, 60 + v)))
    out.alpha_composite(Image.merge(
        'RGBA', [Image.new('L', (W, H), c) for c in (22, 17, 10)] + [smoke_a]))

    # Gold sparks scattered around the lettering.
    sparks = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparks)
    for _ in range(round(W / 34)):
        x = rng.uniform(pad_x * 0.3, W - pad_x * 0.3)
        y = rng.uniform(pad_top * 0.2, H - pad_bot * 0.4)
        r = rng.choice([0.8, 1, 1, 1.3, 1.6, 2.2]) * cap_height / 85
        sd.ellipse((x - r, y - r, x + r, y + r),
                   fill=(255, 200 + rng.randint(0, 40), 90, rng.randint(150, 255)))
    glow = sparks.filter(ImageFilter.GaussianBlur(3 * cap_height / 85))
    out.alpha_composite(glow)
    out.alpha_composite(sparks)

    # Flare line under the text: a lens flare — white-hot core and an orange
    # glow, both tapering smoothly to fine points. Nearly as wide as a
    # full-length wordmark so short text still sits on a stage.
    fy = ty + th + round(th * 0.52)
    half = min(W / 2 - 4, max(tw * 0.8, cap_height * 3.6))
    cx = W / 2
    flare = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    fp = flare.load()
    reach = round(th * 0.45)
    core_c, glow_c = (255, 247, 220), (255, 168, 48)
    for x in range(max(0, round(cx - half)), min(W, round(cx + half) + 1)):
        i = max(0.0, 1 - abs(x - cx) / half) ** 1.35
        if i <= 0:
            continue
        sc = max(0.5, cap_height * 0.03 * (0.35 + 0.65 * i))
        sg = th * 0.13 * (0.3 + 0.7 * i)
        for dy in range(-reach, reach + 1):
            y = fy + dy
            if not 0 <= y < H:
                continue
            core = i * math.exp(-0.5 * (dy / sc) ** 2)
            glow = 0.6 * i * math.exp(-0.5 * (dy / sg) ** 2)
            a = min(1.0, core + glow)
            if a < 0.01:
                continue
            w = core / (core + glow)
            fp[x, y] = tuple(round(c1 * w + c2 * (1 - w))
                             for c1, c2 in zip(core_c, glow_c)) + (round(255 * a),)
    out.alpha_composite(flare)


def fade_rows(img, start, end):
    """Fade alpha from full at row [start] to zero at row [end] and below."""
    a = img.getchannel('A')
    W, H = img.size
    ramp = Image.new('L', (W, H), 255)
    d = ImageDraw.Draw(ramp)
    for y in range(start, H):
        v = 0 if y >= end else round(255 * (end - y) / (end - start))
        d.line((0, y, W, y), fill=v)
    img.putalpha(ImageChops.multiply(a, ramp))


def logo(args):
    """Emblem from the source logo + the new wordmark where the old one was.

    Geometry is relative to the 1024×1064 master: old lettering at rows
    902–984, backdrop starting ~847.
    """
    src = Image.open(args.src).convert('RGBA')
    W, H = src.size
    k = W / 1024
    base = src.copy()
    fade_rows(base, round(845 * k), round(892 * k))
    wm, (tx, ty, tx2, ty2) = wordmark(args.text, round(82 * k), args.font)
    cx = W // 2
    x = cx - (tx + tx2) // 2
    y = round(902 * k) - ty
    if x < 0 or y < 0:
        raise SystemExit('wordmark block exceeds the canvas')
    base.alpha_composite(wm, (x, y))
    base.save(args.out)


def video(args):
    """Swap the splash's wordmark, on the original's timing.

    Measured on the 720×1280 splash: the old lettering (x≈80–640, cap ≈48px)
    rises from y≈940 to rest centred at y≈882 between 3.2s and 3.6s, while
    the emblem is still forming — so it can't be trimmed out.
    1. Erase its whole path: a `delogo` + blur copy of the frame, blended in
       through a full-width band mask (feathered top/bottom) that fades up
       over 3.0–3.22s, just before the old lettering shows.
    2. A soft smoky backdrop over the erased area (same fade) — the logo
       artwork's own treatment behind the lettering.
    3. The new lettering fades in at the rest position over 3.3–3.9s.
    """
    tmp = Path(tempfile.mkdtemp())
    W, H = 720, 1280
    bx, by, bw, bh = 1, 822, W - 2, 160  # erase band: the lettering's path
    # Full-width band, feathered top and bottom only: the lettering's ends
    # reach x≈80/640, so any side feather would let them ghost through.
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).rectangle((-40, 842, W + 40, 966), fill=255)
    mask.filter(ImageFilter.GaussianBlur(12)).save(tmp / 'mask.png')

    panel = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    a = Image.new('L', (W, H), 0)
    ImageDraw.Draw(a).ellipse((-120, 838, W + 120, 970), fill=215)
    a = a.filter(ImageFilter.GaussianBlur(22))
    grain = Image.effect_noise((W, H), 50).filter(ImageFilter.GaussianBlur(1.4))
    a = ImageChops.multiply(a, grain.point(lambda v: min(255, 140 + v)))
    panel = Image.merge('RGBA', [Image.new('L', (W, H), c) for c in (20, 15, 9)] + [a])
    panel.save(tmp / 'panel.png')

    wm, (tx, ty, tx2, ty2) = wordmark(args.text, 48, args.font, decor=False)
    wm.save(tmp / 'wm.png')
    wx, wy = W // 2 - (tx + tx2) // 2, 858 - ty

    flt = (
        f"[0:v]split[base][src];"
        f"[src]delogo=x={bx}:y={by}:w={bw}:h={bh},gblur=sigma=16[er];"
        f"[3:v]format=gray,fade=t=in:st=3.0:d=0.22[m];"
        f"[er][m]alphamerge[erm];"
        # shortest=1: the looped stills would otherwise run forever.
        f"[base][erm]overlay=0:0:shortest=1[v0];"
        f"[1:v]format=rgba,fade=t=in:st=3.0:d=0.3:alpha=1[p];"
        f"[2:v]format=rgba,fade=t=in:st=3.3:d=0.6:alpha=1[w];"
        f"[v0][p]overlay=0:0:shortest=1[v1];"
        f"[v1][w]overlay={wx}:{wy}:shortest=1,format=yuv420p[v]")
    still = ['-loop', '1', '-framerate', '24', '-i']
    subprocess.run([
        'ffmpeg', '-v', 'error', '-y', '-i', args.src,
        *still, str(tmp / 'panel.png'),
        *still, str(tmp / 'wm.png'),
        *still, str(tmp / 'mask.png'),
        '-filter_complex', flt, '-map', '[v]',
        '-c:v', 'libx264', '-profile:v', 'high', '-crf', '22', '-preset', 'slow',
        '-r', '24', '-movflags', '+faststart', '-an', args.out], check=True)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['logo', 'video'])
    ap.add_argument('--font', required=True)
    ap.add_argument('--text', default='APP')
    ap.add_argument('--src', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    {'logo': logo, 'video': video}[a.mode](a)
