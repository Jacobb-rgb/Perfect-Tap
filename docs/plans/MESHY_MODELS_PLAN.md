# The owner's Meshy 3D models in the game (2026-11-13)

The owner made 87 models with Meshy AI (Downloads/Meshy_AI_*.glb) and asked: replace the game's own
part-built looks with them — ores, rocks ("kameny"), the plot, the cleaning station, trees, "everything" —
and turn his 6 floor dioramas into the 6 mine floors ("just scale them up"). The meteor model is the look
of the meteor event (feat/meteor, not on main).

Branch `art/meshy-models` (worktree `.claude/worktrees/meshy-models`). Lands only on the owner's yes,
through the integrator.

## Pipeline (done)

- `tools/meshy/process_glb.py` (Blender 5.2, `/Applications/Blender.app`): every source -> a Roblox-ready
  .glb in `NAHRAJ_DO_ROBLOXU/3D_modely_2026-11-13/` (outside the repo, ~430 MB):
  - ores: geometry kept (~5k tris, faces doubled back-to-back because some Meshy ores had flipped faces),
    PBR textures 1024; plus `_Low` (700 tris, color 256, re-baked) for crowds;
  - rocks: 0.3-2.7M tris -> 3.5-9k tris, color + normal 1024 re-baked from the high-poly;
  - props: kept (<=15k tris), trees re-baked to 3k tris;
  - floors: 1.2-2.4M tris -> 160k tris in 16-20 tiles (<= 19k tris each), one 1024 color texture per tile.
- `tools/meshy/manifest_2026-11-13.json` -> `tools/meshy/make_catalog.py` -> `src/shared/Config/MeshCatalog.luau`
  (Box = size at import in studs, Center = centre, Tris; Ores/Rocks/Props/Floors lists).
- The owner imports the whole folder once with Studio's 3D Importer (uploads under his account) and saves
  `hotovo.rbxl` there; `lune run tools/lune/import_meshes.luau <hotovo.rbxl> 3D_modely_2026-11-13` writes
  `src/shared/Assets/MeshAssets.rbxm` (templates) + `Config/MeshUpload.luau` (Uploaded = true).
  A place a current Studio saved (zstd chunks, Content properties) is rewritten first by
  `tools/meshy/unpack_place.mjs` (Node 22+; the import tool calls it when Lune 0.8.9 can't read the file).
  An asset imported twice takes the later copy (a fixed file imported next to the old one).
- Done 2026-11-13: his `Documents/d.rbxl` gave 212 templates (everything but the 6 files of the three
  epic ores; his own imports of their raw Meshy files are ignored). Still to import, all in
  `NAHRAJ_DO_ROBLOXU/3D_doplnit_7_souboru_2026-11-13` (8 files): the 3 epic ores x2, the fixed
  `Prop_PlotBase` (no hidden layers) and `Prop_MuseumOpen`. tests/MeshAssets.spec.luau checks the
  real templates (the test runner sets them aside: the other specs build the parts looks or mount
  stand-ins).

## Names (MeshCatalog)

| Template | What |
|---|---|
| `Ore_<OreId>`, `Ore_<OreId>_Low` | 31 ores: Coal Copper Tin Iron Quartz Oakwood Honeycomb LeafOre Frostbite Emberite Cobalt Bronze Silver Gold Jade Sapphire DragonEgg Amethyst RoyalAurum Sunstone Moonstone StormGem VolcanicCore Aetherium PhoenixFeather DragonScale CelestialCore Heartstone CrystalRose StormPearl GalaxyStone. No model (keep the part look): Diamond LeafGem + the 6 secret ores (Bogwood Amber Obsidian left the game) |
| `Rock_<FloorId>_<Kind>` | FloorId = MineFloors Id (Quarry EmberCaves DeepHollow SunkenPalace StormglassRift HeartstoneCore), Kind = Small Big Crystal Golden Geode Artifact Giant |
| `Prop_PlotBase` | the plot's floor (square base with a raised frame and corner posts) |
| `Prop_CleaningStation` | the cleaning station (long sci-fi bench, ore trays) |
| `Prop_DisplayPedestal` | the yard podiums |
| `Prop_Museum` | the base museum (sci-fi booth with 3 glass cases): uploaded, not used (its glass is painted on) |
| `Prop_MuseumOpen` | the same booth with its 3 glass boxes cut away (jobs "cut"): MuseumBuilder puts real glass, a lid, a light and the relics of one collection on each of his pedestals (3 collections since 2026-11-13) |
| `Prop_TreeGreen`, `Prop_TreeOrange`, `Prop_TreeYellow` | trees |
| `Prop_GardenPond` | lily pond with stones and flowers |
| `Prop_MossyCliff` | grey-purple cliff with moss and vines |
| `Prop_MineElevator` | the mine elevator stop (tall wooden shaft, blue crystals) |
| `Prop_Meteor` | the meteor stone (feat/meteor) |
| `Floor_<FloorId>_<NN>` | diorama tiles; Center = where the tile sits in its diorama (8 studs wide at import) |

## Rules for every builder

1. **Clone, never set.** `MeshKit.part/fit/scaled` clone a template (MeshId and SurfaceAppearance maps are not
   writable at runtime). Every clone keeps the attribute `Asset` (the previews draw that .glb).
2. **Fallback is the old look, unchanged.** `MeshKit.*` returns nil while there is no upload (or no model for
   that id): the builder then runs its existing code exactly as before, so today's tests stay green
   without edits and the live game never shows an empty part.
3. **Meshes are looks; physics stays on primitive parts.** A MeshPart is CanCollide/CanQuery/CanTouch false
   unless a contract needs it (a rock's `Rock1` is CanQuery for the blaster ray). Keep invisible primitive
   colliders/bodies where gameplay needs them (item Body must stay a primitive Part: ItemService.transplant).
4. **Keep contracts.** Same model names, PrimaryPart names, attributes, tags, attachments as today (see the
   map in this file's history / the contract notes in each builder). Keep the old footprint (box) unless the
   owner asked otherwise.
5. **Specs for the mesh path.** In a spec: `require("../tools/lune/lib/mesh_fakes")(Loader, true)` mounts
   stand-in templates (MeshParts sized to Box with Asset + Placeholder attributes); call
   `require("../tools/lune/lib/mesh_fakes").unmount(Loader)` at the end. Assert the contracts and budgets
   with meshes on; the fallback is covered by the existing specs.
6. **Pictures.** `MESHY=1 lune run tools/lune/export_scene.luau <scene>` mounts the stand-ins; `node
   tools/preview/render.mjs <scene> <shots>` draws the processed .glb files. Owner pictures go to
   `obrazky/<topic>_2026-11-13/` in the main checkout with Czech file names (before/after pairs).
7. Strict Luau, never start a line with `(`, stylua only on the files you touched, full `bash tools/check.sh`
   output saved to a log and gated on its exit code. Do not bump `WorldBuilder.Version` on sub-branches
   (the integration bumps it once).

## Work packages

| Package | Branch | Owns |
|---|---|---|
| A ores | art/meshy-ores | ItemBuilder (clean/light/display looks), OreShellBuilder treasure, ore specs |
| B lobby | art/meshy-lobby | trees (Style.tree, Flora Kit trees, Meadow, Props.tree, Vault jungle trees if fitting), ponds, mossy cliffs, lobby budget specs |
| C plot | art/meshy-plot | PlotBuilder pad/podiums, MuseumBuilder, KitMachines.cleaningStation, their specs |
| D mine | art/meshy-models | RockBuilder + MiningService stages, MineKit.elevator, the 6 floors from the dioramas, meteor hand-off |

## Mine floors from the dioramas (done on art/meshy-models)

`src/server/World/Mine/Diorama.luau` builds a floor from its tiles when `MineFloors.usesDiorama(index)`
(layout in `MineFloors.Dioramas`, every tile uploaded); otherwise the Floor<N> modules build their part
floors as before.

- `tools/meshy/floor_heights.py` (Blender): per cell the lowest ground with headroom (paths under arches
  count, lava under a bridge deck does not), its colour; `tools/meshy/floor_layout.py`: the diorama scaled
  evenly into Floor.Size (depth fits), usual ground at y 0; collision boxes (greedy, walls in 4-stud steps),
  spawns on flat open ground (keep circles, zones), anchors on flat squares, lights;
  `tools/meshy/make_diorama_data.py` -> `src/server/World/Mine/DioramaData.luau`. Config:
  `tools/meshy/floors/config.json`.
- Tiles are looks only; players walk on invisible `Ground` boxes; RockSpawns/GiantSpawn/Entrance/elevator
  tower/blaster gate/ore lift (steel deck where the lift's spot stands above the ground) on flat ground;
  near-white lights; ambience on the boxes; a dark ceiling over the caves; floor 6 keeps its void
  enclosure + VoidCatcher.
- Lifts move with the dioramas: `MineFloors.liftSpot` / `liftPosition` (TrainConfig) follow
  `MineFloors.Dioramas[i].Lift`.
- Floor 2's back opening is the diorama's own; Land's ramp to floor 3 starts at floor 2's back edge when
  floor 2 is a diorama. Floor 3's front is open for the ramp.
- Floor 1 (the quarry in the town): the diorama is re-cut (`Floor_QuarryB`, `process_glb.py` cut boxes:
  DEPTHS portal, train band both sides, grotto door); its painted rails lie on the real track (z +24). The
  part-built pit stays only outside the diorama (Floor1Quarry.DioramaKeep: terraces up to the town, band
  walls, grotto lintel, back wall under the massif); dirt fills the openings.
- Specs: tests/DioramaFloors.spec.luau (contract with stand-ins), tests/RockMeshes.spec.luau,
  tests/MineMeshes.spec.luau.

## Owner's overnight list (2026-11-14, test mode: branch only, never landed without his yes)

- Melted walls ("like warm marzipan"): the floor tiles and the elevator tower carry
  `RenderFidelity = Precise` (import_meshes `fidelity`: Automatic swapped in coarse versions with
  distance); the six dioramas re-processed sharper as `Floor_<Id>HD_<NN>` (jobs_2026-11-14.json:
  240k triangles in 16 balanced tiles of 15k, `split: "kd"`; colour + normal map 1024 per tile, the
  normal bake now through the source's own BSDF so its normal map comes along, `bsdf_surface`).
  `MeshCatalog.FloorsHD`; `MineFloors.floorTiles` takes them once every HD tile is uploaded
  (folder `NAHRAJ_DO_ROBLOXU/3D_modely_2026-11-14_ostre_patra`), else the first set.
- Things in the way on floor 1: no BlasterGate where every blaster may go (MinBlaster 1); the quarry's
  blue sign gate is squashed flat in the HD tiles (`flatten` boxes: a patch of its own texture, no hole).
- Void behind the walls / one ceiling height: floors 2-5 (`MineFloors.CeilingFloors`) get a closed
  room (Diorama `room`): jagged rock walls tight round the diorama on the sides `Diorama.Floors[id].Walls`
  lists, a dark slab right behind them (hides Land's mountains between the caves), Land's passages kept
  open (`Openings`: Ember north tunnel, Hollow south tunnel end), Ember's south side a thin wall right at
  the diorama's edge in front of the DEPTHS portal's back (`Thin`); one ceiling at
  `MineFloors.CeilingHeight` = 33.5 (the ForgeMountain massif rests on Ember's roof at local 34; the Rift
  diorama reaches 32.7). Floor 6 keeps its void (its heartstone crystal reaches local 41).
- Elevator: the tower from its plate up to the ceiling (quarry: its cliffs' top 27.6), 12 studs wide
  (8 in the quarry), three warm lamp bars up its front, glowing edge strips, the call panel on the
  plate beside it; riders arrive in front of it (stop attribute `ArrivalZ`, ElevatorService); the Mine
  Lift's cable reaches the room's ceiling (`MineFloors.ceilingY`, Railway).
- Ore lift beside the elevator: layout anchors `"beside": "elevator"` (floor_layout.py) on 16-stud
  elevator squares, never in the door's sector (`door_angle` 55; the Core's island has no room: 0);
  `MineFloors.Dioramas[i].Lift` = the layout's Lift anchor (spec checks it).
- Room details from the review: no solid facets (MineKit.wall `Facets = false`), shards 2.5 off
  openings, openings 0.3 wider than Land's tunnel (no shared faces), the ceiling 0.5 thick (top at the
  massif's foot), Cutaway = no ceiling and no front wall; the sharper quarry's squashed gate lowers
  its walk boxes (`Diorama.Floors.Quarry.Flatten` = the job's box).
- Yard cleaning station: 1.6x, in the back-right corner, a stud clear of the fence's corner wall
  (BaseLayout.CleaningStation).

## Owner's morning list (2026-11-14 09:00, after testing the overnight test place)

- "Take the ore lift out of every location, it really bothers me": the Mine Lifts are gone
  (`TrainConfig.Lifts = {}`; Railway.buildLift, MineKit.oreLift, the diorama/part floors' calls, the
  client's lift prompt, `MineFloors.liftSpot/liftPosition/ceilingY`, the diorama lift keep-outs).
  Ore from floors 2-6 goes up in the backpack (elevator, BASE + the pen's Put In) to the Mine Station.
  Nothing saved was per lift (`data.Train.Cargo` is one list); TrainService still takes any tagged
  hook (its specs keep fixture lifts). The floor layouts still keep the old lift square clear, so
  the rock spawns did not move; the part-built floors keep their lift beams as decoration.
- "At the very side of floor 1 you still see into the void, and on the other side": the pit's band
  floor between the diorama's walls and the train portals went with the parts under DioramaKeep;
  `Floor1Quarry.DioramaFills` now reach the quarry's edge (x +-72.5) plus one sand underlay just
  under the diorama's lowest ground, in the diorama's painted sand colour.
- "The walls still look melted": the raw Meshy source renders just as soft (its shapes are soft), so
  processing alone cannot make them hard; what made them look like melted chocolate in Studio is a
  waxy sheen: the tiles came in as Plastic with only a TextureID. The sharper set is re-made matte:
  every tile material gets a shared 8x8 metal/roughness map (G = 1, B = 0; `matte`), so the importer
  gives each a SurfaceAppearance with Color + Normal + Roughness + Metalness maps, and the colour maps
  get an unsharp mask (`sharpen` 0.7). Tried and dropped: flat facets (`facet`, dissolve_limited)
  showed triangle seams on flat faces; a posterized palette (`poster`) turned the lava blotchy.

## Open

- The owner's Studio import -> `import_meshes.luau` -> real templates; then the test place and Studio
  checks (walking the floors, the train through the quarry, the ramp 2 -> 3, phones' frame rate with
  160k-triangle floors 1-3 near the town).
- The meteor (feat/meteor, Návrhy strojů chat): use `MeshKit.fit("Prop_Meteor", ...)` for the stone once
  both are on main.
- Ores without a model keep their part look (Diamond, Leaf Gem + the 6 secret ores); the owner may make
  more. (Bogwood, Amber and Obsidian left the game 2026-11-13; the Royal Railway collection too: three
  collections for the museum's three cases, its artifacts paid out as coins once, Migrations.)
- The plot frame question (owner: "jak to myslíš stojí na něm"): a picture went to him
  (obrazky/pozemek_okraj_2026-11-13); his answer decides whether the frame stays.

## Owner's noon list (2026-11-14, after the morning test place)

- "Extend the walls and add them on top so it lines up: you must not see behind them": the open
  quarry gets the rooms' rock walls too (Diorama.Floors.Quarry Walls E/W/S, `WallTops` E/W 28,
  S 14 so the town still looks in, the diorama's lavender stone `WallColors`, a grass `WallCap`, no
  ceiling), with openings for the ramp, the train band (a lintel at 12 over the trains' clearance)
  and the grotto door; Land's voxel cliff on the town side is built and dropped when the quarry is
  its diorama (the town's random draws stay the same).
- "The bridges and things in the passages: to the sides, or remove them": a workflow walked every
  floor's routes (entrances, elevator, tunnels, doors) on the walk boxes and rendered the HD tiles;
  a second agent checked each box. Moving baked mesh parts is not possible, so they are squashed:
  `Diorama.Floors[id].Flatten` lists [x0, y0, z0, x1, y1, z1] boxes (= the HD jobs' "flatten"; spec
  keeps them equal), `Diorama.flattenBoxes` cuts the walk boxes to each box's floor and splits them
  round it, ramps whose centre lies inside are skipped. Quarry: the blue sign gate (+ its two ramps),
  the rock sheet in the VIP door, the rail spur in the DEPTHS tunnel, the railing + lamp across the
  elevator's way; Ember: the central lava bridge (a flat path stays), the beam gate and the sign gate
  on the main path; Hollow: the stone sign gate over the path from the tunnel (two ground heights),
  lantern walk boxes; Palace: the velvet rope in the doorway; Rift: walk-only lanes through the two
  coil gates (the gates stay); Core: the south bridge's gate beam and the pink rails across the glass
  bridges' ends. Only with the sharper set uploaded (the first tiles still show them).
