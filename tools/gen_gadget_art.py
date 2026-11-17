#!/usr/bin/env python3
"""Draws the art for the towers added in the Godot version (Bloom Pot, Sap
Pitcher, Gust Blossom) in the same flat style as the original tower art, and
adds them (and the Thornback Toad's tinted picture) to art/atlas.json.

    python3 tools/gen_gadget_art.py

Each tower gets 4 looks (level 1, 2, 3 path A, 3 path B) x 4 player colors,
225x240 pixels (the 150x160 cell at 1.5x), feet at (112.5, 177).
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "art", "gadgets")
S = 4  # draw 4x bigger, then shrink: smooth edges
W, H = 225, 240
INK = (40, 30, 22, 255)
SLOTS = ["#FF5A5F", "#38BDF8", "#FBBF24", "#C084FC"]


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def P(x, y):
    return (x * S, y * S)


class Pen:
    def __init__(self):
        self.im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def ellipse(self, cx, cy, rx, ry, fill=None, outline=None, width=2.0):
        self.d.ellipse([P(cx - rx, cy - ry), P(cx + rx, cy + ry)], fill=fill, outline=outline, width=int(width * S) if outline else 0)

    def poly(self, pts, fill=None, outline=INK, width=2.0):
        q = [P(x, y) for x, y in pts]
        self.d.polygon(q, fill=fill)
        if outline:
            self.d.line(q + [q[0]], fill=outline, width=int(width * S), joint="curve")

    def line(self, pts, col, width=2.0):
        self.d.line([P(x, y) for x, y in pts], fill=col, width=int(width * S), joint="curve")

    def arc(self, cx, cy, r, a0, a1, col, width=2.0):
        self.d.arc([P(cx - r, cy - r), P(cx + r, cy + r)], a0, a1, fill=col, width=int(width * S))

    def done(self):
        return self.im.resize((W, H), Image.LANCZOS)


def star(pen, cx, cy, r, fill=(250, 204, 21, 255)):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    pen.poly(pts, fill=fill, outline=INK, width=1.2)


def base(pen, level, tower=True):
    # soft shadow, then the stone (level 2) or golden (level 3) disc
    pen.ellipse(112, 193, 44, 12, fill=(0, 0, 0, 55))
    if level >= 3:
        for k in range(6, 0, -1):
            pen.ellipse(112, 190, 44 + k * 7, 16 + k * 5, fill=(253, 224, 71, 10))
        pen.ellipse(112, 194, 42, 12, fill=hexc("#ca8a04"), outline=INK, width=1.6)
        pen.ellipse(112, 191, 40, 10, fill=hexc("#facc15"))
    elif level == 2 and tower:
        pen.ellipse(112, 194, 42, 12, fill=hexc("#6b7280"), outline=INK, width=1.6)
        pen.ellipse(112, 191, 40, 10, fill=hexc("#9ca3af"))


def badge(pen, slot, level, icon_fn=None):
    # owner colour dot + one star per level (+ the branch icon at level 3)
    n = min(level, 3)
    total = 16 + n * 15 + (18 if icon_fn else 0)
    x = 112 - total / 2 + 7
    pen.ellipse(x, 221, 7, 7, fill=hexc(SLOTS[slot]), outline=(255, 255, 255, 255), width=1.6)
    x += 16
    for i in range(n):
        star(pen, x, 221, 7)
        x += 15
    if icon_fn:
        icon_fn(pen, x + 4, 221)


# ---------------------------------------------------------------------------
def petals(pen, cx, cy, r, n, col, center, outline=INK):
    for i in range(n):
        a = i * 2 * math.pi / n
        pen.ellipse(cx + math.cos(a) * r * 0.75, cy + math.sin(a) * r * 0.75, r * 0.55, r * 0.55, fill=col, outline=outline, width=1.4)
    pen.ellipse(cx, cy, r * 0.5, r * 0.5, fill=center, outline=outline, width=1.4)


def acorn(pen, cx, cy, k=1.0):
    pen.ellipse(cx, cy + 3 * k, 6 * k, 7 * k, fill=hexc("#b45309"), outline=INK, width=1.2)
    pen.poly([(cx - 7 * k, cy), (cx + 7 * k, cy), (cx + 6 * k, cy - 4 * k), (cx - 6 * k, cy - 4 * k)], fill=hexc("#78350f"), width=1.2)
    pen.line([(cx, cy - 4 * k), (cx + 2 * k, cy - 8 * k)], INK, 1.4)


def draw_pot(level, branch, slot):
    pen = Pen()
    base(pen, level)
    golden = branch == "a"
    sunny = branch == "b"
    # terracotta pot
    pot = hexc("#c2410c")
    pen.poly([(80, 150), (144, 150), (136, 192), (88, 192)], fill=pot, width=2.2)
    pen.poly([(76, 142), (148, 142), (148, 154), (76, 154)], fill=hexc("#ea580c"), width=2.2)
    pen.ellipse(112, 172, 9, 9, fill=hexc(SLOTS[slot]), outline=INK, width=1.4)  # a little owner-colour heart spot
    if golden:
        for i, ax in enumerate([94, 108, 122, 132]):
            acorn(pen, ax, 138 - (i % 2) * 3, 0.9)
    # stems + blooms
    heads = [(112, 92, 22)] if level == 1 else [(104, 88, 22), (128, 106, 15)]
    if level >= 3:
        heads = [(110, 80, 25), (134, 104, 16), (88, 108, 13)]
    for hx, hy, r in heads:
        pen.line([(112, 145), (hx, hy + r * 0.4)], hexc("#15803d"), 4.0)
        pen.ellipse((112 + hx) / 2 + 8, (145 + hy) / 2, 8, 4, fill=hexc("#22c55e"), outline=INK, width=1.2)
    for hx, hy, r in heads:
        if sunny:
            for i in range(12):
                a = i * math.pi / 6
                pen.line([(hx + math.cos(a) * r * 1.0, hy + math.sin(a) * r * 1.0), (hx + math.cos(a) * r * 1.45, hy + math.sin(a) * r * 1.45)], hexc("#fbbf24"), 3.0)
            petals(pen, hx, hy, r, 8, hexc("#fde047"), hexc("#f97316"))
        elif golden:
            petals(pen, hx, hy, r, 6, hexc("#facc15"), hexc("#a16207"))
        else:
            petals(pen, hx, hy, r, 6, hexc("#f472b6"), hexc("#fde047"))
    icon = None
    if level >= 3:
        icon = (lambda p, x, y: acorn(p, x, y - 2, 0.9)) if golden else (lambda p, x, y: petals(p, x, y, 7, 8, hexc("#fde047"), hexc("#f97316")))
    badge(pen, slot, level, icon)
    return pen.done()


def draw_sap(level, branch, slot):
    pen = Pen()
    fuel = branch == "b"
    sticky = branch == "a"
    r = 72 * 1.5 if not fuel else 90 * 1.5
    # dashed range ring on the ground (like the Thorn Patch)
    for i in range(28):
        a0 = i * 360 / 28
        pen.d.arc([P(112 - r * 0.98, 186 - r * 0.33), P(112 + r * 0.98, 186 + r * 0.33)], a0, a0 + 7, fill=(255, 251, 235, 150), width=int(1.6 * S))
    # puddle of sap
    sap = hexc("#f97316" if fuel else "#f59e0b", 230)
    pen.ellipse(112, 188, 58 + level * 6, 18 + level * 2, fill=sap, outline=INK, width=1.6)
    pen.ellipse(100, 184, 22, 6, fill=(255, 255, 255, 90))
    if sticky:
        for bx, by in [(70, 190), (152, 192), (128, 198)]:
            pen.ellipse(bx, by, 7, 4, fill=hexc("#fbbf24"), outline=INK, width=1.0)
    # the pitcher plant
    green = hexc("#65a30d")
    top = 118 - level * 6
    pen.poly([(98, 188), (126, 188), (132, top + 22), (120, top), (102, top), (92, top + 22)], fill=green, width=2.2)
    pen.ellipse(111, top, 13, 6, fill=hexc("#7f1d1d"), outline=INK, width=1.8)
    pen.poly([(100, top - 2), (124, top - 2), (118, top - 22), (106, top - 22)], fill=hexc("#84cc16"), width=1.8)  # the lid
    pen.line([(104, top + 30), (104, 180)], hexc("#a3e635"), 2.0)
    # drips of sap
    for dx, dy in [(132, top + 26), (95, top + 40)]:
        pen.poly([(dx, dy), (dx + 4, dy + 8), (dx, dy + 12), (dx - 4, dy + 8)], fill=sap, width=1.0)
    if fuel:
        pen.poly([(112, top - 56), (121, top - 38), (117, top - 27), (107, top - 27), (103, top - 38)], fill=hexc("#ef4444"), width=1.2)
        pen.poly([(112, top - 44), (116, top - 34), (112, top - 29), (108, top - 34)], fill=hexc("#fde047"), outline=None)
    icon = None
    if level >= 3:
        icon = (lambda p, x, y: p.ellipse(x, y, 6, 6, fill=hexc("#fbbf24"), outline=INK, width=1.2)) if sticky else \
            (lambda p, x, y: p.poly([(x, y - 8), (x + 6, y + 5), (x - 6, y + 5)], fill=hexc("#ef4444"), width=1.2))
    badge(pen, slot, level, icon)
    return pen.done()


def swirl(pen, cx, cy, r, col, width=3.0, turns=1.3):
    pts = []
    n = 40
    for i in range(n):
        t = i / (n - 1)
        a = t * turns * 2 * math.pi
        rr = r * (0.25 + 0.75 * t)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.8))
    pen.line(pts, col, width)


def draw_gust(level, branch, slot):
    pen = Pen()
    base(pen, level)
    whirl = branch == "a"
    dizzy = branch == "b"
    # pale blue pot
    pen.poly([(86, 156), (138, 156), (132, 192), (92, 192)], fill=hexc("#38bdf8"), width=2.2)
    pen.poly([(82, 148), (142, 148), (142, 159), (82, 159)], fill=hexc("#7dd3fc"), width=2.2)
    pen.ellipse(112, 175, 8, 8, fill=hexc(SLOTS[slot]), outline=INK, width=1.4)
    # tall stem + puffball (a dandelion clock)
    top = 82 - level * 6
    pen.line([(112, 150), (112, top + 20)], hexc("#15803d"), 4.0)
    pen.ellipse(124, 128, 10, 4, fill=hexc("#22c55e"), outline=INK, width=1.2)
    pr = 24 + level * 3
    for i in range(18):
        a = i * 2 * math.pi / 18
        pen.line([(112, top), (112 + math.cos(a) * pr, top + math.sin(a) * pr)], (226, 232, 240, 255), 1.6)
        pen.ellipse(112 + math.cos(a) * pr, top + math.sin(a) * pr, 3.2, 3.2, fill=(255, 255, 255, 255))
    pen.ellipse(112, top, 7, 7, fill=hexc("#a3a3a3"), outline=INK, width=1.2)
    # wind
    col = hexc("#c084fc") if dizzy else hexc("#e0f2fe")
    if whirl:
        pen.poly([(150, 100), (184, 100), (174, 120), (166, 140), (160, 152), (156, 140), (152, 120)], fill=(224, 242, 254, 200), outline=INK, width=1.4)
        for yy, ww in [(108, 15), (122, 10), (136, 6)]:
            pen.line([(167 - ww, yy), (167 + ww, yy)], hexc("#7dd3fc"), 2.0)
    swirl(pen, 162, top + 34, 18, col, 3.0)
    swirl(pen, 62, top + 50, 14, col, 3.0)
    if level >= 2:
        pen.line([(40, top + 18), (70, top + 14), (82, top + 22)], col, 3.0)
    if dizzy:
        for k in range(3):
            star(pen, 112 + math.cos(k * 2.1) * (pr + 12), top - 8 + math.sin(k * 2.1) * 10, 5, hexc("#fde047"))
    icon = None
    if level >= 3:
        icon = (lambda p, x, y: swirl(p, x, y, 7, hexc("#38bdf8"), 2.2)) if whirl else (lambda p, x, y: star(p, x, y, 7, hexc("#c084fc")))
    badge(pen, slot, level, icon)
    return pen.done()


def main():
    atlas_path = os.path.join(ROOT, "art", "atlas.json")
    atlas = json.load(open(atlas_path))
    for kind, fn in [("pot", draw_pot), ("sap", draw_sap), ("gust", draw_gust)]:
        looks = {}
        for look, level, branch in [("1", 1, ""), ("2", 2, ""), ("3a", 3, "a"), ("3b", 3, "b")]:
            for slot in range(4):
                name = "%s_%s_s%d" % (kind, look, slot)
                fn(level, branch, slot).save(os.path.join(OUT, name + ".png"))
                looks["%s_s%d" % (look, slot)] = "gadgets/%s.png" % name
        atlas["gadgets"][kind] = {"cell": [150, 160], "origin": [75, 118], "looks": looks}
    # the Thornback Toad mini-boss wears the Rumble Toad's picture, darker
    if "rumbletoad" in atlas.get("pests", {}):
        atlas["pests"]["thorntoad"] = dict(atlas["pests"]["rumbletoad"], tint=[0.82, 0.72, 0.56])
    with open(atlas_path, "w") as f:
        json.dump(atlas, f, indent=1)
    print("wrote pot, sap and gust art")


if __name__ == "__main__":
    main()
