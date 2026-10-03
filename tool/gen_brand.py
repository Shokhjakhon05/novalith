#!/usr/bin/env python3
"""Draws every Novalith brand image from code: launcher icons, adaptive icon layers, splash mark,
in-app logo and the Play Store graphics. Run: python3 tool/gen_brand.py (needs Pillow only)."""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
S = 1024  # master size


def ramp(stops):
    """Builds three 256-entry lookup tables from [(pos 0..1, (r, g, b))] colour stops."""
    luts = [[], [], []]
    for i in range(256):
        t = i / 255
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                k = 0 if p1 == p0 else (t - p0) / (p1 - p0)
                for ch in range(3):
                    luts[ch].append(int(round(c0[ch] + (c1[ch] - c0[ch]) * k)))
                break
        else:
            for ch in range(3):
                luts[ch].append(stops[-1][1][ch])
    return luts


def radial(size, stops):
    g = Image.radial_gradient('L').resize((size, size), Image.LANCZOS)
    luts = ramp(stops)
    return Image.merge('RGB', [g.point(luts[ch]) for ch in range(3)])


def glow(canvas, cx, cy, r, color, alpha, blur):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (alpha,))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def background(size, seed=7):
    img = Image.new('RGBA', (size, size))
    top, bottom = (9, 12, 36), (24, 10, 48)
    px = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        px.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    k = size / S
    glow(img, int(230 * k), int(250 * k), int(300 * k), (150, 60, 255), 70, 150 * k)
    glow(img, int(820 * k), int(800 * k), int(320 * k), (30, 190, 255), 55, 160 * k)
    rnd = random.Random(seed)
    stars = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(stars)
    for _ in range(int(90 * k * k) + 40):
        x, y = rnd.uniform(0, size), rnd.uniform(0, size)
        r = rnd.choice([1, 1, 1.5, 2, 3]) * k
        a = rnd.randint(70, 230)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, a))
    img.alpha_composite(stars.filter(ImageFilter.GaussianBlur(0.6 * k)))
    return img


def ring_layers(size, cx, cy, rx, ry, width, angle):
    """Returns (back, front) RGBA layers of a tilted ring; back goes behind the orb."""
    # A clean annulus: outer ellipse minus inner ellipse, tinted with a horizontal gradient.
    ring = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(ring)
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    w2 = width * 0.55
    d.ellipse((cx - rx + width, cy - ry + w2, cx + rx - width, cy + ry - w2), fill=0)
    tint = Image.new('RGB', (size, size))
    td = ImageDraw.Draw(tint)
    for x in range(size):
        t = min(1.0, max(0.0, (x - (cx - rx)) / (2 * rx)))
        t = t * t * (3 - 2 * t)
        td.line([(x, 0), (x, size)], fill=(int(70 + 185 * t), int(205 + 50 * t), 255))
    layer = tint.convert('RGBA')
    layer.putalpha(ring)
    half = Image.new('L', (size, size), 0)
    ImageDraw.Draw(half).rectangle((0, 0, size, cy), fill=255)
    back = layer.copy()
    back.putalpha(ImageChops.multiply(layer.getchannel('A'), half))
    front = layer.copy()
    front.putalpha(ImageChops.multiply(layer.getchannel('A'), ImageChops.invert(half)))
    return (back.rotate(angle, resample=Image.BICUBIC, center=(cx, cy)),
            front.rotate(angle, resample=Image.BICUBIC, center=(cx, cy)))


def mark(size, scale=1.0):
    """The Novalith mark on a transparent square: a nova sphere, its ring and a small moon."""
    ss = 2  # supersample
    n = size * ss
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    k = n / S * scale
    cx = cy = n // 2
    r = int(250 * k)

    glow(img, cx, cy, int(330 * k), (255, 120, 80), 120, 70 * k)
    glow(img, cx, cy, int(290 * k), (255, 190, 110), 90, 30 * k)

    back, front = ring_layers(n, cx, cy, int(415 * k), int(118 * k), max(2, int(30 * k)), 24)
    img.alpha_composite(back.filter(ImageFilter.GaussianBlur(10 * k)))
    img.alpha_composite(back)

    grad = radial(4 * r, [(0.0, (255, 250, 220)), (0.10, (255, 226, 150)), (0.24, (255, 160, 80)),
                           (0.36, (255, 86, 120)), (0.47, (150, 50, 240)), (0.5, (70, 24, 150)), (1.0, (70, 24, 150))])
    # Light comes from the upper left: shift the gradient centre.
    ox, oy = int(-0.34 * r), int(-0.36 * r)
    sphere = grad.crop((r - ox, r - oy, 3 * r - ox, 3 * r - oy)).convert('RGBA')
    mask = Image.new('L', (2 * r, 2 * r), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 2 * r - 1, 2 * r - 1), fill=255)
    sphere.putalpha(mask)
    img.alpha_composite(sphere, (cx - r, cy - r))

    # Rim light on the dark side.
    rim = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(rim).arc((cx - r, cy - r, cx + r, cy + r), 10, 100, fill=(190, 150, 255, 200), width=max(2, int(9 * k)))
    img.alpha_composite(rim.filter(ImageFilter.GaussianBlur(5 * k)))

    img.alpha_composite(front.filter(ImageFilter.GaussianBlur(9 * k)))
    img.alpha_composite(front)

    # The moon riding the front of the ring.
    ang = math.radians(-24)
    px, py = 300 * k, 82 * k
    mx = cx + px * math.cos(ang) - py * math.sin(ang)
    my = cy + px * math.sin(ang) + py * math.cos(ang)
    mr = int(54 * k)
    glow(img, int(mx), int(my), int(mr * 1.7), (120, 230, 255), 150, 22 * k)
    mg = radial(4 * mr, [(0.0, (255, 255, 255)), (0.2, (200, 245, 255)), (0.5, (60, 170, 250)), (1.0, (60, 170, 250))])
    moon = mg.crop((mr + int(0.3 * mr), mr + int(0.3 * mr), 3 * mr + int(0.3 * mr), 3 * mr + int(0.3 * mr))).convert('RGBA')
    mm = Image.new('L', (2 * mr, 2 * mr), 0)
    ImageDraw.Draw(mm).ellipse((0, 0, 2 * mr - 1, 2 * mr - 1), fill=255)
    moon.putalpha(mm)
    img.alpha_composite(moon, (int(mx) - mr, int(my) - mr))
    return img.resize((size, size), Image.LANCZOS)


def save(img, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print('wrote', os.path.relpath(path, ROOT))


def main():
    full = background(S)
    full.alpha_composite(mark(S, 0.86))
    save(full.convert('RGB'), ROOT, 'assets', 'brand', 'icon_1024.png')
    save(full.convert('RGB').resize((512, 512), Image.LANCZOS), ROOT, 'docs', 'store', 'play_icon_512.png')
    save(mark(512, 1.0), ROOT, 'assets', 'brand', 'logo.png')

    # Legacy launcher icons (rounded square) for Android < 8.
    for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        big = full.resize((px * 4, px * 4), Image.LANCZOS)
        mask = Image.new('L', big.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, big.size[0] - 1, big.size[1] - 1), radius=int(px * 4 * 0.22), fill=255)
        big.putalpha(mask)
        save(big.resize((px, px), Image.LANCZOS), RES, f'mipmap-{name}', 'ic_launcher.png')

    # Adaptive icon: 108dp layers; the mark stays inside the 66dp safe zone.
    for name, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
        save(mark(px, 0.60), RES, f'mipmap-{name}', 'ic_launcher_foreground.png')
        save(background(px).convert('RGB'), RES, f'mipmap-{name}', 'ic_launcher_background.png')

    # Splash mark (shown by the native launch theme before Flutter draws).
    for name, px in {'mdpi': 192, 'hdpi': 288, 'xhdpi': 384, 'xxhdpi': 576, 'xxxhdpi': 768}.items():
        save(mark(px, 0.62), RES, f'drawable-{name}', 'splash_mark.png')

    # Play Store feature graphic 1024x500.
    wide = background(1024).crop((0, 262, 1024, 762))
    wide.alpha_composite(mark(400, 0.9), (40, 50))
    font_path = os.path.join(ROOT, 'assets', 'fonts', 'Exo2.ttf')
    title = ImageFont.truetype(font_path, 118)
    title.set_variation_by_name('Bold')
    sub = ImageFont.truetype(font_path, 40)
    sub.set_variation_by_name('Medium')
    d = ImageDraw.Draw(wide)
    d.text((440, 150), 'NOVALITH', font=title, fill=(255, 255, 255, 255))
    d.text((446, 292), 'C O S M I C   M E R G E', font=sub, fill=(130, 225, 255, 255))
    save(wide.convert('RGB'), ROOT, 'docs', 'store', 'feature_graphic_1024x500.png')

if __name__ == '__main__':
    main()
