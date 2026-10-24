# Stud style: classic Roblox studs on the whole map

Owner request 2026-10-24: every ground, road, floor, wall, fence board and post, building, stall and machine
gets the classic Roblox studded look, colours unchanged, no part per stud, safe to switch off.
Owner picked **proposal A, Classic**, for the game (2026-10-24): `StudStyleConfig.Enabled = true`,
`Look = "Classic"`. Proposal B stays available (`Look = "Custom"` + the 3 uploads).

## The two looks (`StudStyleConfig.Look`)

| | Classic | Custom |
|---|---|---|
| Studs | Roblox's own square studs (`SurfaceType.Studs`, `Inlet` underneath) | our studs, the same shape (`docs/art/studs/*.png`) |
| How | every face's surface set; parts of every stud material (SmoothPlastic, slate, wood, marble, fabric …) turn **Plastic** because Roblox only draws surfaces on Plastic; each gets its own material's `PhysicalProperties` so it slides and weighs the same | `BasePart.MaterialVariant = "TFStuds"`: one `MaterialVariant` per base material in `MaterialService.TFStudStyle` (colour map tinted by the part's colour + normal map + roughness map) |
| Material | → Plastic (the look only; `Classic.Convert` = every stud material) | unchanged |
| Uploads | none | the 3 pictures |
| Lighting | studs are baked shading | studs catch the sun (normal map) |

Both: 1 stud per stud everywhere (`StudsPerTile = 2`, the pictures hold 2 x 2 studs), counted from each face's
corner like Roblox bricks.

## What gets studs (`StudStyle.skipReason`)

Suitable: `Part`, `WedgePart`, `CornerWedgePart`, block / wedge / cylinder shape, a stud material
(`StudStyleConfig.Materials`), opaque (`Transparency <= 0.02`), not a mirror (`Reflectance <= 0.1`), middle size
`>= 0.35` and longest `>= 1` stud (fence boards 0.35 x 0.45 qualify, pebbles and trim do not).

Never: Neon, Glass, ForceField, Foil, Water, Air (Metal off by default), balls, MeshParts, unions, trusses, parts
with a mesh (SpecialMesh / BlockMesh: Roblox draws no surfaces on them), parts with a sign (a SurfaceGui with
words or pictures, or an empty one that a script fills later like the SKY EGG odds board; plain-frame GUIs like the
plot plates' tile seams are fine), a Decal / Texture / SurfaceAppearance, a custom MaterialVariant of their own,
anything on a character (Humanoid), in an Accessory or Tool, under the Camera, in `Workspace.Nodes / Items /
Debris` (ore rocks, carried ore), or tagged / attributed `NoStuds`.

Names (`StudStyleConfig.SkipNames`, Lua patterns on the part and everything above it): clouds, water, the sea, the
island's boundary walls, ghosts / previews, golem followers, hoverboards, WorldMotion effects, the golem
`OpenPop`; the crystals (`^Crystals?%d*$`, `^CrystalCluster`, `^CrystalGroup`, `^CrystalFacet`, `EggCrystal`,
`IconCrystal`; the plaza's FireCrystalRing, its CrystalFloor and the CrystalIsle's ground keep their studs); ores
and relics on show (`^Display`, `^Artifact$`); the client's trains, the cleaning minigame and the crate opening.
Only the map (ground, roads, floors, walls, fences, buildings, stalls, machines) gets studs, not what lies or
moves on it (review 2026-10-24; crystals and trains can be switched back on by taking their patterns out).

Parts another script changes later (`StudStyleConfig.SkipParts`, own name + model name): the podium rims
(`Rim` in `Podium<slot>`, PodiumService flips them Neon) and the belts' side rails (`RailL` / `RailR`,
ConveyorService opens them: Transparency 1), so every client sees the same mix.

On today's map (v52, 33,178 parts): 20,543 parts get studs (Classic needs no upload).

## Code

| File | Role |
|---|---|
| `src/shared/Config/StudStyleConfig.luau` | switch, look, asset ids, materials, size limits, skip lists, batch size |
| `src/shared/StudStyle.luau` | `skipReason`, `applyPart / restorePart`, `applyTree / restoreTree`, `watch`, `ensureVariants / removeVariants`, `look` |
| `src/server/Services/StudStyleService.luau` | Workspace attributes `StudStyle` + `StudStyleLook` from the config; makes / removes the stud MaterialVariants |
| `src/client/Controllers/StudStyleController.luau` | every client restyles what streams to it (`StudStyle.watch(Workspace)`), follows the attributes |
| `tests/StudStyle.spec.luau` | rules, look-only changes, no duplicates, exact restore, whole map |
| `tools/studs/make_stud_textures.mjs` | draws the 3 stud pictures |

The server's map is never changed: each client restyles its own copy (no network cost, no server time). Every
restyled part carries the attribute `StudStyle` with what it was (`C;<Material>;<6 surfaces>;<physics set>` or
`V;<old MaterialVariant>`): a part with it is never restyled twice, and `restorePart` puts back exactly that.
Nothing new is created except the MaterialVariants (Custom), all in `MaterialService.TFStudStyle`.

## Switching

- Config: `StudStyleConfig.Enabled = true`, `StudStyleConfig.Look = "Classic"` or `"Custom"`.
- Live, from the server (Studio command bar while playing, server side):
  `workspace:SetAttribute("StudStyle", false)` puts the map back on every client;
  `workspace:SetAttribute("StudStyleLook", "Custom")` switches the look.
- Edit mode look (do **not** save the place like this):
  ```lua
  local S = require(game.ReplicatedStorage.Shared.StudStyle)
  S.ensureVariants(game.MaterialService) print(S.applyTree(workspace, "Classic"))
  -- back:
  print(S.restoreTree(workspace)) S.removeVariants(game.MaterialService)
  ```
- Test places: `lune run tools/lune/make_stud_test_place.luau build/TerraForge.rbxl <out.rbxl> Classic|Custom`
  switches the Workspace attributes on and adds the Studio-only script `TEST_Vystupky`
  (`tools/studs/TEST_Vystupky.luau`): paste the uploaded picture ids into its attributes `ColorMap`, `NormalMap`,
  `RoughnessMap` and the server makes the stud materials; clients take them from `MaterialService.TFStudStyle`
  (`StudStyle.customReady`), so the ids are needed on the server only.
  2026-10-24: `HRA_K_TESTOVANI/TerraForge_VYSTUPKY_A_klasicke_2026-10-24.rbxl` and `..._B_vlastni_...rbxl`,
  owner steps in `NAHRAJ_DO_ROBLOXU/vystupky/NAVOD.md`.

## Custom look: uploading the pictures

1. `node tools/studs/make_stud_textures.mjs` (already in `docs/art/studs`).
2. Studio → Asset Manager → Bulk Import `studs_color.png`, `studs_normal.png`, `studs_roughness.png`
   (or Creator Hub → Decals/Images).
3. Copy each image's id into `StudStyleConfig.Assets` (`ColorMap`, `NormalMap`, `RoughnessMap`).
   Without `NormalMap` the Custom studs stay off (`StudStyleConfig.customReady`).

## Using it in another place

Copy `ReplicatedStorage.Shared.StudStyle` and `ReplicatedStorage.Shared.Config.StudStyleConfig` (same paths), then
a LocalScript in StarterPlayerScripts: `require(game.ReplicatedStorage.Shared.StudStyle).watch(workspace, "Classic")`,
and for the Custom look a Script in ServerScriptService:
`require(game.ReplicatedStorage.Shared.StudStyle).ensureVariants(game.MaterialService)`.

## Performance

- 0 new parts, 0 Textures / Decals; Custom adds ~26 MaterialVariants sharing 3 pictures (512 px).
- A client restyles new parts for about `BudgetMs` (2 ms) of each frame, checking the clock every
  `MinPerFrame` (50) parts, so a full stream-in is spread over as many frames as it needs and always goes on.
  Check it in Studio's MicroProfiler on a phone profile.
- Classic sets 7 properties per part and one attribute (on the client only, never replicated).

## Limits / to check in Studio

- Previews are three.js approximations (`STUD_STYLE=Classic|Custom lune run tools/lune/export_scene.luau
  world_studs_classic`, shots in `tools/preview/stud_shots.json`). The Classic previews use Roblox's own stud
  tile from the local Studio install (never committed).
- Material textures on parts: Roblox chooses where a part's tiling starts; studs on neighbouring parts line up
  when their edges sit on whole studs.
- Cylinders: Classic studs only on the flat ends (Roblox draws surfaces there); Custom wraps round them.
- A script that later sets a styled part's Material (a glow flash) wins: that part loses its Classic studs until
  it streams in again. Custom studs survive it. The parts the game itself flips (podium rims, belt rails) are
  in `SkipParts`.
