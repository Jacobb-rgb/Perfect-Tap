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

## Names (MeshCatalog)

| Template | What |
|---|---|
| `Ore_<OreId>`, `Ore_<OreId>_Low` | 28 ores: Coal Copper Tin Iron Quartz Oakwood Honeycomb LeafOre Frostbite Emberite Cobalt Bronze Silver Gold Jade Sapphire DragonEgg Amethyst RoyalAurum Sunstone Moonstone StormGem VolcanicCore Aetherium PhoenixFeather DragonScale CelestialCore Heartstone. No model (keep the part look): Bogwood Amber Diamond Obsidian CrystalRose StormPearl GalaxyStone LeafGem + the 6 secret ores |
| `Rock_<FloorId>_<Kind>` | FloorId = MineFloors Id (Quarry EmberCaves DeepHollow SunkenPalace StormglassRift HeartstoneCore), Kind = Small Big Crystal Golden Geode Artifact Giant |
| `Prop_PlotBase` | the plot's floor (square base with a raised frame and corner posts) |
| `Prop_CleaningStation` | the cleaning station (long sci-fi bench, ore trays) |
| `Prop_DisplayPedestal` | the yard podiums |
| `Prop_Museum` | the base museum (sci-fi booth with 3 glass cases) |
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
