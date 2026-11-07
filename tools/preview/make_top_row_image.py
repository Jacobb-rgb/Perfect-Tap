"""The top row's one image (owner 2026-11-07): cart, lobby, base and vault in a row of 170 px cells,
cut from the icon sheets, so he uploads one file for the four buttons (IconAssets.TopRow).

  python3 tools/preview/make_top_row_image.py
Inputs and output: ../NAHRAJ_DO_ROBLOXU/ikony_ui (ikony_1_ui.png, ikony_4_menu.png -> horni_lista.png).
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FOLDER = os.path.abspath(os.path.join(HERE, "../../../NAHRAJ_DO_ROBLOXU/ikony_ui"))
CELL = 170


def cell(sheet, index):
    x, y = (index % 6) * CELL, (index // 6) * CELL
    return sheet.crop((x, y, x + CELL, y + CELL))


ui = Image.open(os.path.join(FOLDER, "ikony_1_ui.png")).convert("RGBA")
menus = Image.open(os.path.join(FOLDER, "ikony_4_menu.png")).convert("RGBA")
parts = [cell(menus, 24), cell(ui, 8), cell(ui, 7), cell(ui, 9)]  # cart, lobby, base, vault
out = Image.new("RGBA", (len(parts) * CELL, CELL), (0, 0, 0, 0))
for i, part in enumerate(parts):
    out.paste(part, (i * CELL, 0))
out.save(os.path.join(FOLDER, "horni_lista.png"))
