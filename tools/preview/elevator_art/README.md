# Elevator window floor pictures

The pictures on the ELEVATOR window's floor cards (owner 2026-11-15: his reference with a bright
picture of every floor filling its card, and a wide dark COMING SOON banner under them).

| File | What |
|---|---|
| `NAHRAJ_DO_ROBLOXU/ikony_vytah/vytah_patra.png` (KIT folder) | the upload: 1024 x 1024 RGB PNG, no alpha |
| `build/preview/icons/elevator_<FloorId>.png` | each floor alone, 512 x 288 (the preview renders) |
| `build/preview/icons/elevator_ComingSoon.png` | the banner alone, 1024 x 160 |

Sheet cells (px, top-left origin; `IconAssets.ElevatorArt.Cells`): Quarry (0,0), EmberCaves (512,0),
DeepHollow (0,288), SunkenPalace (512,288), StormglassRift (0,576), HeartstoneCore (512,576), each
512 x 288; ComingSoon (0,864), 1024 x 160. Each cell is made on its own and pasted, so nothing
crosses a cell edge; each cell's outer 3 px are a little darker, so GPU filtering at an
ImageRect edge only ever blends dark into dark. The single files are the sheet's cells pixel for pixel.

## Which look

The floors as they will be in the game: the owner's Meshy dioramas on **art/meshy-models at
48ca9cab** (not landed when these were made). That branch's `src/shared/Assets/MeshAssets.rbxm`
already holds every catalog model, the sharp HD floor tiles `Floor_<Id>HD_NN` included (his upload
of 2026-11-14, commit 16add215), so no `MESHY` env was needed: the scene exports list the HD tiles,
and `tools/preview/render.mjs` draws every uploaded MeshPart from its processed .glb in the KIT
folder (`NAHRAJ_DO_ROBLOXU/3D_modely_2026-11-14_ostre_patra` for the floors, `3D_modely_2026-11-13`
for the rocks and props).

## How they were made

1. A throwaway detached worktree of that commit (nothing committed), node_modules borrowed:

   ```bash
   git worktree add --detach .claude/worktrees/elevator-art art/meshy-models      # 48ca9cab
   ln -s "$PWD/tools/preview/node_modules" .claude/worktrees/elevator-art/tools/preview/node_modules
   cd .claude/worktrees/elevator-art
   ```

2. Scenes, the game's own builders (`tools/lune/export_scene.luau`):

   ```bash
   for n in 1 3 4 5; do lune run tools/lune/export_scene.luau mine_floor $n; done   # build/preview/mine_floor_<n>.json
   lune run tools/lune/export_scene.luau world_cards                              # build/preview/world_cards.json (the whole map)
   ```

   `mine_floor N`: one floor alone at the origin, the preview cutaway (no ceiling, no front wall),
   rocks on its RockSpawns, the Giant Crystal on its GiantSpawn, a stand-in player at the entrance
   (every camera here leaves it behind). `world_cards`: the whole map, each floor at
   `MineFloors.Placement` with its real ceiling, the Ember Caves' veiled way in and the Heartstone
   Core's void enclosure. Floors 2 and 6 are shot in the world (the closed cave under its ceiling,
   the Core in its violet void); floors 1, 3, 4, 5 in their cutaways (in the world the lobby's DEPTHS
   portal with its text stands over the quarry's back; 3-5 look the same in both, the cutaway renders
   in seconds instead of minutes).

3. Renders: the shots below saved as one JSON file, then

   ```bash
   SHOTS_EXTRA=elevator_shots.json node tools/preview/render.mjs x elev_1 elev_2 elev_3 elev_4 elev_5 elev_6 elev_soon
   ```

   -> `build/preview/shots/elev_*.jpg` (render.mjs JPEG q88; the cards 2048 x 1152, the banner
   2048 x 320; the first argument is only the default scene, every shot names its own).

4. Post-processing, `elevator_art.py` next to this file (Python 3, Pillow, numpy):

   ```bash
   python3 elevator_art.py build/preview/shots "<KIT>/NAHRAJ_DO_ROBLOXU/ikony_vytah/vytah_patra.png" <icons dir> [contact.jpg]
   ```

## Cameras

Floor-local (x right, y up from the floor's ground, +z toward the entrance); fov is vertical degrees.

| Card | Scene | Camera | Looks at | fov | Preset | exposure |
|---|---|---|---|---|---|---|
| 1 Quarry | mine_floor_1 | (-18, 30, 46) | (16, 2, -20) | 58 | Quarry, sunDir (-0.5, 0.72, 0.48) | 1 |
| 2 EmberCaves | world_cards | (8, 18, 22) | (-14, 6, -36) | 50 | EmberCaves | 1.7 |
| 3 DeepHollow | mine_floor_3 | (-32, 21, 30) | (12, 4, -6) | 58 | Lagoon | 1.2 |
| 4 SunkenPalace | mine_floor_4 | (10, 30, 40) | (-10, 6, -30) | 56 | Palace | 1.25 |
| 5 StormglassRift | mine_floor_5 | (-18, 22, 28) | (14, 4, -16) | 58 | Storm | 1.25 |
| 6 HeartstoneCore | world_cards | (-24, 30, 34) | (-6, 15, -44) | 56 | Core | 2.2 |
| ComingSoon | mine_floor_1 | (-2, 11, 44) | (-30, 10, -48) | 14 | Core (cave light, no sun) | 1 |

The same shots in scene coordinates (the world ones plus `MineFloors.Placement`: floor 2 at
(0, -12, -300), floor 6 at (0, -400, -800)), exactly as rendered:

```json
{
 "elev_1": {"scene": "mine_floor_1", "position": [-18, 30, 46], "target": [16, 2, -20], "fov": 58, "preset": "Quarry", "shadowExtent": 160, "maxLights": 40, "sunDir": [-0.5, 0.72, 0.48], "width": 2048, "height": 1152},
 "elev_2": {"scene": "world_cards", "position": [8, 6, -278], "target": [-14, -6, -336], "fov": 50, "preset": "EmberCaves", "shadowExtent": 160, "maxLights": 40, "exposure": 1.7, "width": 2048, "height": 1152},
 "elev_3": {"scene": "mine_floor_3", "position": [-32, 21, 30], "target": [12, 4, -6], "fov": 58, "preset": "Lagoon", "shadowExtent": 160, "maxLights": 40, "exposure": 1.2, "width": 2048, "height": 1152},
 "elev_4": {"scene": "mine_floor_4", "position": [10, 30, 40], "target": [-10, 6, -30], "fov": 56, "preset": "Palace", "shadowExtent": 160, "maxLights": 40, "exposure": 1.25, "width": 2048, "height": 1152},
 "elev_5": {"scene": "mine_floor_5", "position": [-18, 22, 28], "target": [14, 4, -16], "fov": 58, "preset": "Storm", "shadowExtent": 160, "maxLights": 40, "exposure": 1.25, "width": 2048, "height": 1152},
 "elev_6": {"scene": "world_cards", "position": [-24, -370, -766], "target": [-6, -385, -844], "fov": 56, "preset": "Core", "shadowExtent": 160, "maxLights": 40, "exposure": 2.2, "width": 2048, "height": 1152},
 "elev_soon": {"scene": "mine_floor_1", "position": [-2, 11, 44], "target": [-30, 10, -48], "fov": 14, "preset": "Core", "shadowExtent": 160, "maxLights": 24, "sunDir": [-0.5, 0.72, 0.48], "width": 2048, "height": 320}
}
```

What each shows: 1 the quarry pit from above the entrance: the wooden mine door with lanterns, the
giant purple crystal, the cyan crystal fan, grassy terraces and trees, rocks, rails; 2 the lava
rivers round a stone causeway, the two big red crystals (one ringed) and glowing lava pillars;
3 the cyan lagoon with its bridge, waterfall doorways and the giant blue crystal; 4 the
checkered throne hall: columns, red carpet, the golden king on his throne, the big orange crystal;
5 the Rift's gate passage with Tesla coils, the ice golem statue and the giant golden crystal with
lightning; 6 the giant magenta heart crystal on its island over the violet void, glowing bridges,
floating rocks. The banner: floor 1's mine door and crystals, re-graded to a dark night cave.

## Post-processing (elevator_art.py)

Per card: Lanczos down-scale of the whole 16:9 render to 512 x 288 (4x); exposure in linear light
to a mean-luma target per floor (bisection within +-1 EV, +1.5 for the Core; the big brightness
changes are the renders' own `exposure`), a soft filmic shoulder instead of clipping, saturation
x1.12 (x1.2 quarry, x1.16 palace), a gentle S-curve, a little extra bloom (highlights blurred and
screened back), a soft vignette, the top band and the top-left corner a little darker (the card's
number, name and chips go there), a 3 px darker rim, a 1 px unsharp mask. The banner (2x
down-scale) maps its luma through a dark indigo -> violet -> lavender ramp (the brightest
saturated bits keep 28 % of their own colour: the crystal glints and the lit doorway) and darkens a
soft band round 45 % of its width where the window writes COMING SOON. All numbers are at the top of
the script (BASE, LOOK, SOON).
