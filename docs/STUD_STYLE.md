# Stud style: classic Roblox studs on the whole map

Owner request 2026-10-24: every ground, road, floor, wall, fence board and post, building, stall and machine
gets the classic Roblox studded look, colours unchanged, no part per stud, safe to switch off.
Branch `art/stud-style`, pictures first: **off on main** (`StudStyleConfig.Enabled = false`) until the owner
picks a look.

## The two looks (`StudStyleConfig.Look`)

| | Classic | Custom |
|---|---|---|
| Studs | Roblox's own square studs (`SurfaceType.Studs`, `Inlet` underneath) | our studs, the same shape (`docs/art/studs/*.png`) |
| How | every face's surface set; SmoothPlastic parts turn **Plastic** because Roblox only draws surfaces on Plastic; they get SmoothPlastic's `PhysicalProperties` so they slide and weigh the same | `BasePart.MaterialVariant = "TFStuds"`: one `MaterialVariant` per base material in `MaterialService.TFStudStyle` (colour map tinted by the part's colour + normal map + roughness map) |
| Material | SmoothPlastic → Plastic (the look only) | unchanged |
| Uploads | none for plastic parts; slate, wood, marble, fabric … use the Custom studs once uploaded | the 3 pictures |
| Lighting | studs are baked shading | studs catch the sun (normal map) |

Both: 1 stud per stud everywhere (`StudsPerTile = 2`, the pictures hold 2 x 2 studs), counted from each face's
corner like Roblox bricks.

## What gets studs (`StudStyle.skipReason`)

Suitable: `Part`, `WedgePart`, `CornerWedgePart`, block / wedge / cylinder shape, a stud material
(`StudStyleConfig.Materials`), opaque (`Transparency <= 0.02`), not a mirror (`Reflectance <= 0.1`), middle size
`>= 0.35` and longest `>= 1` stud (fence boards 0.35 x 0.45 qualify, pebbles and trim do not).

Never: Neon, Glass, ForceField, Foil, Water, Air (Metal off by default), balls, MeshParts, unions, trusses, parts
with a sign (SurfaceGui with words or pictures; plain-frame GUIs like the plot plates' tile seams are fine), a
Decal / Texture / SurfaceAppearance, a custom MaterialVariant of their own, anything on a character (Humanoid),
in an Accessory or Tool, under the Camera, in `Workspace.Nodes / Items / Debris` (ore rocks, carried ore), under
a name matching Cloud / Water / Sea$ / Boundary / Ghost / Preview / GolemFollowers / Hoverboards / WorldMotion
(golem pets, riders' boards, effects), or tagged / attributed `NoStuds`.

On today's map (v52, 33,178 parts): 20,792 parts get studs, 19,163 of them plastic (Classic needs no upload).

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
- A client restyles `BatchSize` (1,500) parts per frame: a full stream-in of ~21,000 parts is spread over ~14
  frames. The number is a first guess: check it in Studio's MicroProfiler on a phone profile.
- Classic sets 7 properties per part and one attribute (on the client only, never replicated).

## Limits / to check in Studio

- Previews are three.js approximations (`STUD_STYLE=Classic|Custom lune run tools/lune/export_scene.luau
  world_studs_classic`, shots in `tools/preview/stud_shots.json`). The Classic previews use Roblox's own stud
  tile from the local Studio install (never committed).
- Material textures on parts: Roblox chooses where a part's tiling starts; studs on neighbouring parts line up
  when their edges sit on whole studs.
- Cylinders: Classic studs only on the flat ends (Roblox draws surfaces there); Custom wraps round them.
- A script that later sets a styled part's Material (a glow flash) wins: that part loses its Classic studs until
  it streams in again. Custom studs survive it.
