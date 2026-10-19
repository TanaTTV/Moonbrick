"""Compose the v1 banner (1280x640, also the GitHub social preview) from the Blender hero render.
Run: blender -b -P .github/assets/blender/hero.py -- <render.png> banner 64
     python -I .github/assets/compose_banner.py <render.png>      (needs Pillow + numpy)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_brand import S, font, pill  # noqa: E402  (same fonts and chips as the original brand)

HERE = os.path.dirname(os.path.abspath(__file__))


def grade(render):
    """Darken the sky toward the top and the right, add a violet glow behind the hero and a vignette."""
    W, H = render.size
    img = np.asarray(render.convert("RGB")).astype(float)
    y, x = np.mgrid[0:H, 0:W].astype(float)
    u, v = x / W, y / H
    shade = 0.55 + 0.45 * v  # darker sky at the top
    shade *= 1 - 0.35 * np.clip((u - 0.55) / 0.45, 0, 1)  # quieter right side for the title
    vignette = 1 - 0.45 * np.clip(np.hypot(u - 0.42, (v - 0.5) * 0.8) - 0.35, 0, 1)
    img *= (shade * vignette)[..., None]
    glow = np.exp(-((u - 0.3) ** 2 / 0.05 + (v - 0.45) ** 2 / 0.08))
    img += np.array([90, 50, 170]) * (glow * 0.35)[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def banner(render_path):
    W, H = 1280 * S, 640 * S
    img = grade(Image.open(render_path).resize((W, H), Image.LANCZOS))
    title = font(["seguibl.ttf", "Arial Black.ttf", "arialbd.ttf"], 104)
    tag = font(["segoeuisl.ttf", "segoeui.ttf", "Arial.ttf"], 31)
    small = font(["seguisb.ttf", "segoeui.ttf", "Arial.ttf"], 20)
    tx, ty = 640 * S, 176 * S
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((tx, ty), "Moonbrick", font=title, fill=(170, 140, 255, 170))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18 * S)))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((tx, ty), "Moonbrick", font=title, fill=255)
    yy = np.linspace(0, 1, H)[:, None]
    grad = np.zeros((H, W, 4), np.uint8)
    grad[..., 0], grad[..., 1], grad[..., 2] = 255, (255 - 54 * yy).clip(0, 255), (255 - 150 * yy).clip(0, 255)
    grad[..., 3] = 255
    img.paste(Image.fromarray(grad, "RGBA"), (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.text((tx + 6 * S, ty + 140 * S), "Build Roblox games at the speed of thought.", font=tag, fill=(214, 206, 248, 255))
    x = tx + 6 * S
    for label in ("Claude Code plugin", "Rojo + Luau", "v1.0"):
        x = pill(img, x, ty + 212 * S, label, small) + 12 * S
    return img.resize((1280, 640), Image.LANCZOS)


if __name__ == "__main__":
    out = banner(sys.argv[1])
    out.convert("RGB").save(os.path.join(HERE, "banner.png"), optimize=True)
    print("wrote banner.png")
