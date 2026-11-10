"""The left menu's whole tiles in one image for the owner to upload (owner 2026-11-07).

tools/preview/tile_art/tile_<name>.png are the finished tiles and potions, 256 px with a margin, cut
from his pictures; this lays them out in IconAssets.TileArt's order, cells of 256 px.

  python3 tools/preview/make_tile_sheet.py
Output: ../NAHRAJ_DO_ROBLOXU/ikony_ui/hud_dlazdice.png and hud_dlazdice_2.png (a changed file needs a new upload and a new id).
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 256
FOLDER = os.path.abspath(os.path.join(HERE, "../../../NAHRAJ_DO_ROBLOXU/ikony_ui"))
SHEETS = {
    "hud_dlazdice.png": (4, 3, ["shop", "build", "golems", "hoverboard", "index", "daily", "inventory", "rebirth", "more", "spin", "elevator"]),
    "hud_dlazdice_2.png": (3, 3, ["boosts", "settings", "trade", "lucky", "coins", "mining", "speed", "strength", "mythic"]),
}

for file, (columns, rows, order) in SHEETS.items():
    sheet = Image.new("RGBA", (columns * CELL, rows * CELL), (0, 0, 0, 0))
    for i, name in enumerate(order):
        tile = Image.open(os.path.join(HERE, "tile_art", f"tile_{name}.png")).convert("RGBA")
        sheet.alpha_composite(tile, ((i % columns) * CELL, (i // columns) * CELL))
    sheet.save(os.path.join(FOLDER, file))
