#!/usr/bin/env python3
"""Makes the app icon (art/icon.png, 512x512) from the game's own art:
the Bloom Tree with a Pea Blaster and a Frost Lotus in front of it.

    python3 tools/gen_icon.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ART = os.path.join(ROOT, "art")
N = 512


def frame(path, frames, i=0):
    im = Image.open(os.path.join(ART, path)).convert("RGBA")
    w = im.width // frames
    return im.crop((w * i, 0, w * (i + 1), im.height))


def fit(im, h):
    box = im.getbbox()
    im = im.crop(box)
    return im.resize((int(im.width * h / im.height), h), Image.LANCZOS)


def main():
    S = 2  # draw big, shrink at the end
    W = N * S
    icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    # rounded green tile with a soft light in the middle
    bg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    d.rounded_rectangle([0, 0, W - 1, W - 1], radius=W // 5, fill=(22, 101, 52, 255))
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W * 0.12, W * 0.08, W * 0.88, W * 0.84], fill=(134, 239, 172, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(W // 12))
    mask = bg.split()[3]
    bg.paste(Image.alpha_composite(bg, glow), (0, 0), mask)
    icon = Image.alpha_composite(icon, bg)
    # grass hill
    hill = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(hill).ellipse([-W * 0.2, W * 0.70, W * 1.2, W * 1.4], fill=(74, 222, 128, 255))
    hill.putalpha(Image.composite(hill.split()[3], Image.new("L", (W, W), 0), mask))
    icon = Image.alpha_composite(icon, hill)
    tree = fit(frame("misc/tree.png", 4, 0), int(W * 0.62))
    icon.alpha_composite(tree, ((W - tree.width) // 2, int(W * 0.10)))
    lotus = fit(Image.open(os.path.join(ART, "heroes", "frostlotus_00.png")).convert("RGBA").crop((0, 0, 180, 180)), int(W * 0.36))
    pea = fit(Image.open(os.path.join(ART, "heroes", "peashooter_00.png")).convert("RGBA").crop((0, 0, 180, 180)), int(W * 0.40))
    icon.alpha_composite(lotus, (int(W * 0.60), int(W * 0.56)))
    icon.alpha_composite(pea, (int(W * 0.10), int(W * 0.52)))
    icon.resize((N, N), Image.LANCZOS).save(os.path.join(ART, "icon.png"))
    print("wrote art/icon.png")


if __name__ == "__main__":
    main()
