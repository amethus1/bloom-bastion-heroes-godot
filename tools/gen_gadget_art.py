#!/usr/bin/env python3
"""Build the four owner-color variants from each painted slot-zero tower."""
import json
from pathlib import Path

from PIL import Image, ImageColor


ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art"


def main():
    atlas = json.loads((ART / "atlas.json").read_text())
    players = json.loads((ROOT / "data/meta.json").read_text())["playerColors"]
    colors = [ImageColor.getrgb(player["hex"]) for player in players]
    for gadget in atlas["gadgets"].values():
        for look, file in gadget["looks"].items():
            rank, slot = look.split("_s")
            if slot == "0":
                continue
            master = ART / gadget["looks"][rank + "_s0"]
            with Image.open(master) as original:
                image = original.convert("RGBA")
            # The enamel owner jewel sits beside the rank leaves below the roots.
            for y in range(195, 213):
                for x in range(84, 122):
                    pixel = image.getpixel((x, y))
                    if pixel[:3] == colors[0]:
                        image.putpixel((x, y), (*colors[int(slot)], pixel[3]))
            image.save(ART / file)


if __name__ == "__main__":
    main()
