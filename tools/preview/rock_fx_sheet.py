"""Composes the rock breaking storyboard frames into one picture sheet.

  python3 tools/preview/rock_fx_sheet.py
Needs the renders of tools/lune/export_rock_fx.luau (scene rock_shatter):
build/preview/shots/rock_shatter_<id>.jpg -> build/preview/shots/rock_shatter_sheet.jpg
Captions come from the frame list in tools/lune/lib/rock_fx_preview.luau (FRAMES).
"""

import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SHOTS = os.path.join(REPO, "build", "preview", "shots")
LIB = os.path.join(REPO, "tools", "lune", "lib", "rock_fx_preview.luau")
FONT = os.path.join(HERE, "node_modules", "@fontsource", "fredoka-one", "files", "fredoka-one-latin-400-normal.woff2")

COLS = 4
TILE_W, TILE_H = 800, 450
CAPTION = 46
TITLE = 70


def frames():
    text = open(LIB, encoding="utf-8").read()
    return re.findall(r'\{ Id = "(\w+)", Caption = "([^"]+)"', text)


def font(size):
    for path in (FONT, "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    items = frames()
    if not items:
        sys.exit("no frames found in " + LIB)
    rows = (len(items) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * TILE_W, TITLE + rows * (TILE_H + CAPTION)), (24, 18, 16))
    draw = ImageDraw.Draw(sheet)
    draw.text((24, 16), "Rock breaking animation (client RockFx): one Greystone Boulder, then a Giant Crystal", font=font(34), fill=(255, 240, 220))
    small = font(26)
    for i, (frame_id, caption) in enumerate(items):
        path = os.path.join(SHOTS, "rock_shatter_%s.jpg" % frame_id)
        x = (i % COLS) * TILE_W
        y = TITLE + (i // COLS) * (TILE_H + CAPTION)
        if os.path.exists(path):
            tile = Image.open(path).convert("RGB").resize((TILE_W, TILE_H), Image.LANCZOS)
            sheet.paste(tile, (x, y))
        else:
            draw.rectangle((x, y, x + TILE_W - 1, y + TILE_H - 1), outline=(120, 60, 60), width=3)
            draw.text((x + 20, y + 20), "missing " + os.path.basename(path), font=small, fill=(236, 84, 70))
        draw.text((x + 14, y + TILE_H + 8), caption, font=small, fill=(255, 226, 190))
    out = os.path.join(SHOTS, "rock_shatter_sheet.jpg")
    sheet.save(out, quality=90)
    print("sheet ->", os.path.relpath(out, REPO))


if __name__ == "__main__":
    main()
