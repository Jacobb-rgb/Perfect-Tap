"""The left menu's whole tiles in one image for the owner to upload (owner 2026-11-07).

tools/preview/tile_art/tile_<name>.png are the 11 finished tiles, 256 px with a 2 px margin, cut
from his picture; this lays them out in IconAssets.TileArt's order, 4 x 3 cells of 256 px.

  python3 tools/preview/make_tile_sheet.py
Output: ../NAHRAJ_DO_ROBLOXU/ikony_ui/hud_dlazdice.png (a new file needs a new upload and a new id).
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["shop", "build", "golems", "hoverboard", "index", "daily", "inventory", "rebirth", "more", "spin", "elevator"]
CELL, COLUMNS, ROWS = 256, 4, 3

sheet = Image.new("RGBA", (COLUMNS * CELL, ROWS * CELL), (0, 0, 0, 0))
for i, name in enumerate(ORDER):
    tile = Image.open(os.path.join(HERE, "tile_art", f"tile_{name}.png")).convert("RGBA")
    sheet.alpha_composite(tile, ((i % COLUMNS) * CELL, (i // COLUMNS) * CELL))
sheet.save(os.path.abspath(os.path.join(HERE, "../../../NAHRAJ_DO_ROBLOXU/ikony_ui/hud_dlazdice.png")))
