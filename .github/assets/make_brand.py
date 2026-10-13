"""Render Moonbrick's banner (1280x640, also the GitHub social preview) and logo (512x512).
Run: python -I .github/assets/make_brand.py   (needs Pillow + numpy; fonts from C:/Windows/Fonts or ./fonts)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
S = 2  # supersampling
FONT_DIRS = [os.path.join(HERE, "fonts"), "C:/Windows/Fonts", "/Library/Fonts", "/System/Library/Fonts/Supplemental"]

MOON = (255, 243, 214)
BRICK_TOP, BRICK_LEFT, BRICK_RIGHT = (255, 112, 112), (232, 62, 82), (168, 36, 62)
STUD_TOP, STUD_SIDE = (255, 140, 138), (214, 56, 76)


def font(names, size):
    for d in FONT_DIRS:
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return ImageFont.truetype(p, size * S)
    return ImageFont.load_default()


def background(w, h, seed=3):
    y, x = np.mgrid[0:h, 0:w].astype(float)
    top, bottom = np.array([9, 7, 26]), np.array([30, 16, 66])
    t = (y / h)[..., None]
    img = top * (1 - t) + bottom * t
    # violet nebula glow behind the moon
    for cx, cy, r, col, k in ((0.26, 0.42, 0.42, (120, 70, 255), 0.55), (0.8, 0.9, 0.5, (255, 60, 110), 0.18)):
        d = np.hypot((x / w - cx) * (w / h), y / h - cy) / r
        img += np.array(col) * (np.exp(-d * d * 2.2) * k)[..., None]
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    rng = np.random.default_rng(seed)
    stars = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(stars)
    for _ in range(int(w * h / 9000)):
        sx, sy = rng.uniform(0, w), rng.uniform(0, h * 0.85)
        r = rng.choice([0.6, 0.9, 1.3, 2.0], p=[0.5, 0.3, 0.15, 0.05]) * S
        a = int(rng.uniform(70, 230))
        d.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(255, 255, 255, a))
    glow = stars.filter(ImageFilter.GaussianBlur(2.5 * S))
    out.alpha_composite(glow)
    out.alpha_composite(stars)
    return out


def moon(canvas, cx, cy, r):
    w, h = canvas.size
    halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for i, a in ((2.1, 26), (1.6, 40), (1.25, 60)):
        hd.ellipse([cx - r * i, cy - r * i, cx + r * i, cy + r * i], fill=(200, 170, 255, a))
    canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(r * 0.35)))
    # crescent = disc minus offset disc, with a soft terminator
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    cut = Image.new("L", (w, h), 0)
    ImageDraw.Draw(cut).ellipse([cx - r * 0.55, cy - r * 1.12, cx + r * 1.45, cy + r * 0.88], fill=255)
    cut = cut.filter(ImageFilter.GaussianBlur(r * 0.012))
    crescent = Image.fromarray(np.clip(np.array(mask, float) - np.array(cut, float), 0, 255).astype(np.uint8))
    body = Image.new("RGBA", (w, h), MOON + (255,))
    # subtle craters / shading
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for ox, oy, rr in ((-0.55, 0.25, 0.16), (-0.35, -0.45, 0.1), (-0.7, -0.1, 0.07), (-0.2, 0.62, 0.08)):
        sd.ellipse([cx + ox * r - rr * r, cy + oy * r - rr * r, cx + ox * r + rr * r, cy + oy * r + rr * r], fill=(214, 190, 160, 120))
    body.alpha_composite(shade.filter(ImageFilter.GaussianBlur(r * 0.02)))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer.paste(body, (0, 0), crescent)
    rim = crescent.filter(ImageFilter.GaussianBlur(r * 0.08))
    glow = Image.new("RGBA", (w, h), (255, 236, 200, 0))
    glow.putalpha(rim.point(lambda v: int(v * 0.7)))
    canvas.alpha_composite(glow)
    canvas.alpha_composite(layer)


def brick(canvas, cx, cy, u, studs=(4, 2), height=1.15):
    w, h = canvas.size
    nx, nz = studs
    c30, s30 = math.cos(math.radians(30)), 0.5

    def P(x, z, y):
        return (cx + (x - z) * c30 * u, cy + (x + z) * s30 * u - y * u)

    # moonlit glow pooled under the brick
    pool = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bx, by = P(nx / 2, nz / 2, 0)
    ImageDraw.Draw(pool).ellipse([bx - u * 3.6, by - u * 0.6, bx + u * 3.6, by + u * 1.4], fill=(255, 90, 120, 90))
    canvas.alpha_composite(pool.filter(ImageFilter.GaussianBlur(u * 0.7)))

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    hgt = height
    d.polygon([P(0, nz, 0), P(nx, nz, 0), P(nx, nz, hgt), P(0, nz, hgt)], fill=BRICK_LEFT)  # front-left face
    d.polygon([P(nx, 0, 0), P(nx, nz, 0), P(nx, nz, hgt), P(nx, 0, hgt)], fill=BRICK_RIGHT)  # front-right face
    d.polygon([P(0, 0, hgt), P(nx, 0, hgt), P(nx, nz, hgt), P(0, nz, hgt)], fill=BRICK_TOP)
    # classic Roblox studs: flat printed circles (inset ring + highlight), not raised cylinders
    sr = 0.3
    for i, j in ((i, j) for i in range(nx) for j in range(nz)):
        sx, sy = P(i + 0.5, j + 0.5, hgt)
        rx, ry = sr * u * 1.22, sr * u * 0.7
        d.ellipse([sx - rx, sy - ry, sx + rx, sy + ry], fill=STUD_SIDE)
        d.ellipse([sx - rx * 0.78, sy - ry * 0.78 - u * 0.03, sx + rx * 0.78, sy + ry * 0.78 - u * 0.03], fill=STUD_TOP)
        d.arc([sx - rx, sy - ry, sx + rx, sy + ry], 200, 340, fill=(255, 205, 200), width=max(1, int(u * 0.04)))
    # rim light on the top edges (moon side)
    lw = max(2, int(u * 0.06))
    d.line([P(0, nz, hgt), P(0, 0, hgt), P(nx, 0, hgt)], fill=(255, 215, 205), width=lw)
    d.line([P(0, nz, hgt), P(nx, nz, hgt), P(nx, 0, hgt)], fill=(255, 160, 160), width=lw)
    d.line([P(nx, nz, 0), P(nx, nz, hgt)], fill=(255, 150, 150), width=lw)
    canvas.alpha_composite(layer)


def pill(canvas, x, y, text, f, pad=16):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    l, t, r, b = draw.textbbox((0, 0), text, font=f)
    wpx, hpx = r - l + pad * 2 * S, b - t + pad * 1.1 * S
    draw.rounded_rectangle([x, y, x + wpx, y + hpx], radius=hpx / 2, fill=(255, 255, 255, 20), outline=(190, 170, 255, 110), width=S * 2)
    draw.text((x + pad * S - l, y + (hpx - (b - t)) / 2 - t), text, font=f, fill=(226, 220, 255, 255))
    canvas.alpha_composite(layer)
    return x + wpx


def banner():
    W, H = 1280 * S, 640 * S
    img = background(W, H)
    moon(img, 300 * S, 250 * S, 150 * S)
    brick(img, 300 * S, 395 * S, 50 * S)
    d = ImageDraw.Draw(img)
    title = font(["seguibl.ttf", "Arial Black.ttf", "arialbd.ttf"], 112)
    tag = font(["segoeuisl.ttf", "segoeui.ttf", "Arial.ttf"], 33)
    small = font(["seguisb.ttf", "segoeui.ttf", "Arial.ttf"], 21)
    tx, ty = 590 * S, 178 * S
    # title with a soft moonlight glow and a cream-to-white gradient
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((tx, ty), "Moonbrick", font=title, fill=(170, 140, 255, 160))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18 * S)))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((tx, ty), "Moonbrick", font=title, fill=255)
    grad = np.zeros((H, W, 4), np.uint8)
    yy = np.linspace(0, 1, H)[:, None]
    grad[..., 0], grad[..., 1], grad[..., 2] = 255, (255 - 18 * yy * 3).clip(0, 255), (255 - 50 * yy * 3).clip(0, 255)
    grad[..., 3] = 255
    gimg = Image.fromarray(grad, "RGBA")
    img.paste(gimg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.text((tx + 6 * S, ty + 150 * S), "Build Roblox games at the speed of thought.", font=tag, fill=(206, 198, 245, 255))
    x = tx + 6 * S
    for label in ("Claude Code plugin", "Rojo + Luau", "Open source"):
        x = pill(img, x, ty + 225 * S, label, small) + 12 * S
    return img.resize((1280, 640), Image.LANCZOS)


def logo():
    N = 512 * S
    img = background(N, N, seed=9)
    moon(img, 230 * S, 205 * S, 135 * S)
    brick(img, 256 * S, 330 * S, 44 * S)
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, N - 1, N - 1], radius=110 * S, fill=255)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out.resize((512, 512), Image.LANCZOS)


if __name__ == "__main__":
    banner().convert("RGB").save(os.path.join(HERE, "banner.png"), optimize=True)
    logo().save(os.path.join(HERE, "logo.png"), optimize=True)
    print("wrote banner.png, logo.png")
