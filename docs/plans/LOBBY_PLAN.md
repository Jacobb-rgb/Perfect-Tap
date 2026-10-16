# Lobby plan: Emberfall to match the concept

Goal: the town lobby must read like the owner's concept image
[`docs/art/lobby_concept.webp`](../art/lobby_concept.webp) when seen from the hero camera,
and feel like it from the ground. Style rules: [`docs/ART_DIRECTION.md`](../ART_DIRECTION.md).
Layout data: [`src/shared/Config/LobbyLayout.luau`](../../src/shared/Config/LobbyLayout.luau)
(the single source of truth for every set piece below; only the art director edits it).

The build is split into **exactly five packages** (Sky, Backdrop, Plaza, Districts, Flora)
that work in parallel without touching the same files (section 6).

> **Design v2 (2026-10-16) changes – read section 0 first.** They override the rows below where they differ.

## 0. Design v2 changes (docs/DESIGN_V2_NOTES.md, docs/plans/V2_PLAN.md)
- **SHOP** (`Shop`) is the **Gear shop** (boots, helmet with a head lamp, backpack, gloves, magnet): hook
  `ShopCounter` only. Pell is gone.
- **`ShopFront` is Tobin's Sell stall** next to the SHOP: an ore cart with a counter and a brass scale (hook
  `SellCounter` moves here), the `SellBin` (+ child part `Intake`), the NPC **Tobin the Miner**
  (`Props.npc`-style, named "Tobin"), a `SELL` sign (Wood or Glow, readable from the plaza). Height budget 10.
- **UPGRADES** (`Upgrades`) is the **Tech shop** (automation machines and machine upgrades); the sign keeps saying
  UPGRADES like the concept. `UpgradesFront` shows a glowing **laser blaster** on the pedestal (no pickaxe).
- **SPIN & WIN** is the free daily wheel of fortune (`EmberChest` hook unchanged).
- **ROCK SCANNER** = Ore Codex of the 30 ores; **FOSSIL DIG** = artifacts and the Kingdom of Kaldrum story corner.
- New Districts pieces (LobbyLayout.Pieces): **`CapsuleStall`** (-40, 0, 36), left of the spawn next to the wheel:
  a round stall with a big glass capsule machine (gumball-machine shape, capsules in many colors), little golem
  figures on shelves (Kenney Mini Characters proportions, ore/metal colors, original), a `CAPSULES` Glow sign and an
  odds board; tag **`CapsuleStall`** on the Model (PrimaryPart). **`EnchantShop`** (50, 0, -84), behind UPGRADES past
  the pink trees: a small mystic workshop, purple rune table with a glowing top (BasePart tagged
  **`EnchantCounter`**), floating crystals, `ENCHANT` sign. **`HallOfFame`** (30, 0, 36), right of the spawn: four
  leaderboard boards in a gentle arc facing the spawn, BaseParts named `Board1`..`Board4` tagged **`Leaderboard`**
  with attribute `Board` = 1..4 (a SurfaceGui is added at runtime later), a `HALL OF FAME` header and lanterns.
- `RedTree` moved to (38, 0, 47).
- Player bases grew a **yard** on their sea side (plot-local z 25..66, see src/shared/Config/BaseLayout.luau):
  `LobbyLayout.isFree` keeps scatter off plots *and* yards; never build there.
- Districts budget is now 1400 parts / 11 lights.
- The legacy `tradingPost` in TownLegacy.luau is being renamed to Tobin by another package right now; Districts
  replaces it anyway. Do not edit TownLegacy.luau, Land.luau, PlotBuilder.luau or WorldBuilder.luau.

## 0.1 Polish pass (2026-10-16, art director) - closer to the concept
- **Hero camera** moved closer and lower (table in section 3): the town fills the middle, the massif the upper
  middle, sky only in the top corners; MINE, signpost, ponds/bridge, FOSSIL DIG, ROCK SCANNER and SPIN & WIN are
  all in frame. The plots stay at the image sides, foreshortened.
- **Colors and atmosphere** (LightingConfig = default.project.json): light haze (Density 0.26, Haze 0.9), warm
  peach toward the sun, lavender-blue `Decay` away from it, cool purple-blue ambient shadows, more contrast and
  saturation, a neutral tint. Style stone is now blue-grey (`Stone`, `StoneDark`, `StoneDeep`, `StoneLight`), the
  sky deeper purple-blue at the zenith. The preview (tools/preview/viewer.js) fades far things toward Atmosphere
  `Color` toward the sun and `Decay` away from it (like Roblox), mirrors the sky in reflective parts (water, sea)
  and lights shaded faces with EnvironmentDiffuseScale too.
- **Plot pads** (PlotBuilder visuals only): mown lawn with subtle stripes per cell row, a paving band inside
  blue-grey stone curbs, lamp caps on the corner posts. Names, attachments, tags, the grid, the yard and the gate
  are unchanged; everything over the grid stays flat (tops <= 0.048).
- **Massif**: lighter blue-grey blocks, mossy grass drips over every grassy ledge, 16 trees in five colors, 12 big
  crystal clusters (size 12-18), three miners' huts with lit windows, 20 lit tunnel windows, a gold cart on the
  cart ledge. ForgeMountain per-piece budget 700 -> **1000** (outside the lobby area, StreamingMesh LOD).
- **Waterfalls** (`Style.waterfall`): light sky-blue sheet with a paler middle band, cyan glints, white foam slab
  and cubes at the foot; the massif cascades are 7.5-10 wide, the quarry falls 7.4-9.4.
- **Signs**: THE FORGE 30 x 8.5 (+ 8.5 icon board), DEPTHS 26 x 7.4 with brighter arch rings; THE GREAT FORGE board
  moved onto the nave gable (y 22) with the hammer roundel at the apex and two lit windows over the door, and the
  fire crystal's base lowered by 0.8 so the board reads above the crystal from the spawn; a second FOSSIL DIG
  board faces south over the dig's south fence; a second MINE board stands on the mine hill facing the south
  road; bigger signpost boards; a bigger glowing ROCK SCANNER ring.
- **Sky**: puffy voxel cloud banks (a dome of puffs, warm lower halves, purple tops, glowing pink/orange
  under-rims, golden front rims toward the sun).

---

## 1. How to look at it

```bash
export PATH=<tools>/bin:$PATH
lune run tools/lune/export_scene.luau world            # the real world
lune run tools/lune/export_scene.luau lobby_blockout   # world + a box per set piece
lune run tools/lune/export_scene.luau style            # the Style kit gallery
SHOTS_EXTRA=$PWD/tools/preview/lobby_shots.json node tools/preview/render.mjs world lobby_hero lobby_spawn
#   -> build/preview/shots/<shot>.jpg ; open with an image viewer (or the Read tool)
lune run tools/lune/lobby_stats.luau                   # parts and lights per package vs budget
bash tools/check.sh                                    # types + tests + place build
```

Current state renders (legacy town, before the packages): `lobby_hero`, `lobby_spawn`,
`lobby_west`, `lobby_east`, `lobby_south`, `lobby_backdrop`; the blockout shows every set
piece as a translucent colored box (`blockout_hero`, `blockout_top`). A copy of the hero
blockout is in [`docs/art/lobby_blockout_hero.jpg`](../art/lobby_blockout_hero.jpg): put it
next to the concept to see where each concept element lands.

## 2. World frame and fixed things

- Studs; ground level Y = 0; sea surface Y = -21 (sea parts -23..-21). North = -Z.
- Plaza center (0, 0, 0), radius 36. Spawn `TownSpawn` at (0, 0, 26) (Town.luau builds it).
- Great Forge landmark at (0, 0, -52), facing south (+Z) toward the plaza.
- Plots (can't move): 8 pads 56x56 centered at x = +-104, z = 84, 28, -28, -84.
- Roads (can't move): south road x=0 z 36..140; spurs z=0 x +-36..70; plot roads x = +-70
  z -112..116; forge paths x = +-26 z -28..-112; quarry rim road z=-112 x -70..70.
- Quarry pit x -72..72, z -236..-122, floor Y -12, ramp at x=0 from z -112 to -140.
- Ember Caves entrance (0, -12, -240) (18 wide x 16 tall), caves behind it under a roof
  slab at Y 22..26 (x -74..74, z -362..-234). Deep Hollow further north, Glimmer Grotto
  (VIP) east of the quarry (door at x=80, z=-182).
- Ore outcrop spots: (+-56, 46), (+-50, 58), (+-60, -40), (+-52, -52), (+-82, 118).
- Island walk bounds: x -172..172, z ..152 (invisible walls). Sea beyond.
- Lobby budget area: x -170..170, z -122..150 (any height).
- Sun: low in the WSW over the sea, `LobbyLayout.SunDirection = (-0.965, 0.225, 0.136)`.

The concept has no plots; ours sit left and right of the lobby corridor (x -65..65). The
hero camera frames the corridor and lets the plots fall to the image edges, where Flora
lines the plot roads with trees.

## 3. Hero cameras (`tools/preview/lobby_shots.json`)

| Shot | Camera -> target (fov) | Purpose |
|---|---|---|
| `lobby_hero` | (6, 62, 168) -> (0, 12, -46) (48) | **The concept angle** (polish pass). From the south over the bridge and ponds, MINE bottom left, ROCK SCANNER bottom right, the plaza with the fire crystal, SHOP / SPIN & WIN left, UPGRADES / FOSSIL DIG right, THE GREAT FORGE in the middle, the massif with DEPTHS, THE FORGE, waterfalls and crystals filling the upper middle, sky, islands and balloon in the top corners. Compare it side by side with the concept (docs/screenshots/lobby_compare.jpg). |
| `lobby_spawn` | (0, 9, 46) -> (0, 12, -40) (70) | What a new player sees: fire crystal, Great Forge, SHOP left, UPGRADES right, mountain and portal above the roof. |
| `lobby_west` | (18, 18, 26) -> (-70, 6, -14) (65) | Toward the sunset: SHOP, SPIN & WIN, NW cliff and waterfall, sea, ships, pier, sun glitter. |
| `lobby_east` | (-14, 16, 36) -> (64, 6, -6) (65) | UPGRADES, FOSSIL DIG, ROCK SCANNER, pink grove, NEXT AREA in the distance. |
| `lobby_south` | (6, 34, -28) -> (-4, 0, 78) (65) | From the forge porch over the plaza to the bridge, ponds, signpost, mine and the autumn corner. |
| `lobby_backdrop` | (26, 24, -96) -> (4, 16, -240) (62) | From the quarry rim: DEPTHS portal, ForgeWorks, waterfalls, crane, the massif. |

All shots use `sunDir` = SunDirection. Packages render the shots listed in their section
after every visible change and look at them before committing.

## 4. Concept element -> world map

Every row is a `LobbyLayout.Pieces` entry (Id) unless marked "rule". Center = bottom center
(ground point), Size = width x height budget x depth in the piece's frame, Facing = the
piece's front (LookVector). Build inside your footprint and height budget.

### Sky and sea (package Sky)
| Concept element | Id | Center | Size | Facing | Notes |
|---|---|---|---|---|---|
| sunset sky, sun low over the sea | rule | - | - | - | Lighting, Atmosphere, Sky, Clouds (ART_DIRECTION 7) |
| purple/orange clouds | CloudBanks | (-300, 160, -500) | 1400 x 160 x 1400 | N | voxel cloud clusters W/NW/N, 450-900 studs out, kept out of the lobby box |
| sun path on the water | SunGlitter | (-520, -21.8, 73) | 36 x 0.2 x 660 | toward the sun | broken neon strips, wider far out |
| sailing ships | ShipA | (-240, -22, -90) | 14 x 26 x 34 | S | 2 masts, lit stern |
| | ShipB | (-330, -22, 10) | 10 x 20 x 24 | NNE | 1 mast |
| castle on a far islet | CastleIsland | (-430, -22, -380) | 110 x 80 x 70 | ENE | low-detail silhouette, lighthouse |
| floating island (left) | FloatingIslandWest | (-150, 95, -250) | 40 x 50 x 34 | SSE | cottage, tree, small waterfall |
| floating islands (right) | FloatingIslandEast | (150, 92, -185) | 44 x 50 x 36 | SSW | trees, long waterfall, watchtower |
| island past NEXT AREA | NextIsland | (255, 40, -112) | 46 x 46 x 40 | W | tower house, bridge stub |
| hot air balloon | Balloon | (-72, 74, -84) | 16 x 26 x 16 | SSE | red/yellow, small airship gondola, slow bob |
| pier with boats (left) | WestPier | (-196, -22, -36) | 10 x 26 x 44 | W | stairs down the cliff, dock, boats |

### Backdrop: mountain, DEPTHS, mine (package Backdrop)
| Concept element | Id | Center | Size | Facing | Notes |
|---|---|---|---|---|---|
| dark voxel mountain with ledges, trees, crystals | ForgeMountain | (40, 22, -290) | 240 x 100 x 100 | S | 3 stepped tiers on the cave roof, peak ~y 112 |
| DEPTHS tunnel with glowing arches | DepthsPortal | (0, -12, -236) | 44 x 40 x 8 | S | frames the real Ember Caves entrance |
| rails out of the tunnel | DepthsRails | (0, -12, -218) | 8 x 3 x 34 | S | ore cart, buffer stop |
| THE FORGE sign + works building (PWR) | ForgeWorks | (34, 26, -250) | 34 x 34 x 18 | S | right of the portal = right of the forge in the hero shot |
| waterfalls down the mountain | QuarryFallsWest / East | (-44 / 44, -12, -232) | 12 x 46 x 6 | S | from tier-1 lips into pools at the quarry wall |
| scaffold / derrick towers (left) | ScaffoldWest, ScaffoldWest2 | (-96, 0, -170), (-124, 0, -206) | 10 x 60 x 10 | S | stand on the west mountains |
| crane | Crane | (104, 64, -268) | 40 x 40 x 12 | SW | jib over the quarry, hanging crate |
| tower on the peak | Beacon | (60, 104, -300) | 10 x 30 x 10 | S | red beacon |
| waterfall left of the forge | NWCliff + NWPool | (-48, 0, -98) / (-48, 0, -88) | 32 x 22 x 10 / 18 x 2 x 8 | S | cliff, falls, purple crystals |
| MINE entrance | MineEntrance | (-46, 0, 88) | 26 x 20 x 20 | E | rock hill, timber portal, MINE sign |
| rails with gold carts | MineYard | (-20, 0, 88) | 12 x 4 x 30 | E | 2 gold carts, buffer stop |
| cliff edges, sea color, ground color | rule (Land.luau) | - | - | - | dark voxel rim cliffs, Style colors |

### Plaza and Great Forge (package Plaza)
| Concept element | Id | Center | Size | Facing | Notes |
|---|---|---|---|---|---|
| round flagstone plaza | Plaza | (0, 0, 0) | r 36 | - | rings, seams, curb with road gaps |
| giant fire crystal in a stone ring | FireCrystal | (0, 0, 0) | r 11, h 24 | - | glowing ring insets, tag Spin |
| spawn | SpawnPad | (0, 0, 26) | r 9 | N | flat inlay only; TownSpawn stays clear |
| THE GREAT FORGE | GreatForge | (0, 0, -58) | 42 x 44 x 40 | S | stone, red roofs, crossed hammers, glowing interior; ridge <= 32 |
| roads, paths, lanterns | rule | - | - | - | all WorldLayout.Roads + LobbyLayout.Paths, lantern rhythm |

### Districts (package Districts)
| Concept element | Id | Center | Size | Facing | Notes |
|---|---|---|---|---|---|
| SHOP stall (pink/white awning, blue sign) | Shop | (-46, 0, -22) | 20 x 20 x 14 | (0.9, 0, 0.43) to plaza | Pell's Trading Post: ShopCounter + SellCounter |
| sell bin in front of SHOP | ShopFront | (-35.6, 0, -17) | 14 x 7 x 8 | same | SellBin + Intake |
| UPGRADES stall (purple/white, blue sign) | Upgrades | (46, 0, -22) | 20 x 20 x 14 | (-0.9, 0, 0.43) | UpgradeCounter, blue neon trims |
| display in front of UPGRADES | UpgradesFront | (35.6, 0, -17) | 14 x 7 x 8 | same | glowing pickaxe pedestal |
| SPIN & WIN wheel | SpinWheel | (-48, 0, 18) | 18 x 26 x 10 | (0.85, 0, 0.53) | wheel spins (Spin), EmberChest on its platform |
| guild notice board | GuildBoard | (-15, 0, -30) | 9 x 10 x 3 | S | tag GuildBoard |
| FOSSIL DIG with dinosaur skeleton | FossilDig | (50, 0, 24) | 18 x 8 x 24 | W | tag FossilDig |
| ROCK SCANNER terminal | RockScanner | (56, 0, 80) | 12 x 10 x 10 | (-0.71, 0, 0.71) | tag OreCodex on the terminal |

### Water, trees, wayfinding (package Flora)
| Concept element | Id | Center | Size | Facing | Notes |
|---|---|---|---|---|---|
| pond with lily pads (left) | LilyPond | (-26, 0, 62) | 24 x 2 x 14 | S | crystals on the bank |
| koi pond (center front) | KoiPond | (26, 0, 62) | 24 x 2 x 14 | S | koi, stepping stones |
| creek under the bridge | Creek | (0, 0, 62) | 28 x 1 x 6 | S | joins the ponds |
| arched wooden bridge | CreekBridge | (0, 0, 62) | 12 x 5 x 16 | S | carries the south road |
| MINE / UPGRADE / EXPLORE / BUILD signpost | Signpost | (-14, 0, 46) | 7 x 10 x 3 | (0.52, 0, 0.86) | double-sided, icons |
| NEXT AREA sign | NextArea | (150, 0, -120) | 14 x 12 x 4 | S | arrow east, closed gate |
| boardwalk to the next area | NextAreaBoardwalk | (205, 0, -112) | 8 x 3 x 70 | E | out over the sea to NextIsland |
| pink cherry trees (right of forge) | PinkGrove | (41, 0, -66) | r 9, h 22 | - | two hero trees |
| big red tree (foreground right) | RedTree | (28, 0, 40) | r 6, h 18 | - | hero tree |
| yellow/orange trees (foreground left) | AutumnCorner | (-50, 0, 118) | r 12, h 18 | - | cluster |
| colorful voxel trees, flowers, fences, lanterns | rule | - | - | - | scatter with `LobbyLayout.isFree` |

### Paths (`LobbyLayout.Paths`, rendered by Plaza)
| Id | From -> To | Width | Kind |
|---|---|---|---|
| ToShop | (-28, -13) -> (-40, -19) | 12 | Cobble |
| ToUpgrades | (28, -13) -> (40, -19) | 12 | Cobble |
| ToWheel | (-31, 17) -> (-41, 22) | 7 | Cobble |
| ToFossil | (33, 14) -> (40, 20) | 7 | Cobble |
| ToScanner | (5, 80) -> (49, 80) | 6 | Cobble |
| ToMine | (-5, 88) -> (-34, 88) | 10 | Dirt |
| ToNextArea | (75, -115) -> (160, -115) | 6 | Cobble |

## 5. Gameplay hooks (other services depend on these)

| Hook | What | Where | Package |
|---|---|---|---|
| `SellCounter` (tag) | BasePart: Tobin's counter top (v2: at ShopFront) | ShopFront | Districts |
| `SellBin` (tag) | Model with a child BasePart named `Intake` (non-collide, ~8x5x6) | ShopFront | Districts |
| `CapsuleStall` (tag, v2) | Model with PrimaryPart | CapsuleStall | Districts |
| `EnchantCounter` (tag, v2) | BasePart: the rune table top | EnchantShop | Districts |
| `Leaderboard` (tag, v2) | BaseParts `Board1`..`Board4`, attribute `Board` | HallOfFame | Districts |
| `ShopCounter` (tag) | BasePart: the tool shop counter | SHOP | Districts |
| `UpgradeCounter` (tag, new) | BasePart: the upgrades counter | UPGRADES | Districts |
| `EmberChest` (tag) | Model with PrimaryPart, inside the `SpinWheel` model (free daily reward) | SPIN & WIN | Districts |
| `GuildBoard` (tag) | Model with PrimaryPart | GuildBoard | Districts |
| `OreCodex` (tag, new) | Model (terminal) with PrimaryPart | ROCK SCANNER | Districts |
| `FossilDig` (tag, new) | Model (dig site) with PrimaryPart | FOSSIL DIG | Districts |
| `Spin` (tag) | Model with PrimaryPart and Atomic streaming; attributes SpinSpeed, BobHeight, BobSpeed | fire crystal (Plaza), wheel disc (Districts), balloon (Sky), ships bob (Sky) | several |
| `TownSpawn` (name) | SpawnLocation at (0, 0.25, 26) | built by Town.luau | none (keep clear) |

Until a package lands, `TownLegacy.luau` keeps building the old piece that provides the
hook (see 7.2), so every hook exists at every commit.

## 6. The five packages

Common rules for all packages:
- You own the files listed for you and nothing else. Never edit `LobbyLayout.luau`,
  `Lobby/Style.luau`, `Town.luau`, `TownLegacy.luau`, `tests/Lobby.spec.luau`,
  `tests/Style.spec.luau`, `tools/preview/lobby_shots.json`, `WorldBuilder.luau`,
  `PlotBuilder.luau`, `Palette.luau`, `Props.luau`, `Geo.luau`. Need a change there? Ask the
  art director; meanwhile write a local helper in your own module.
- Module contract (Town.luau): `src/server/World/Lobby/<Package>.luau` (or
  `Lobby/<Package>/init.luau` with sibling submodules) returns
  `{ Replaces = { ... }, build = function(parent: Model, rng: Rng.Rng) }`. Town builds it into
  `Map.Emberfall.Lobby.<Package>` with its own random stream. Pure builder: Instance
  creation only, deterministic from `rng`.
- Read positions from `LobbyLayout.get(id)` and `LobbyLayout.frame(piece)`; do not
  hard-code piece centers. Stay inside your pieces' footprints and height budgets.
- Use `Style.C` colors and Style helpers (ART_DIRECTION.md). Small details `Style.tiny()`.
- Budgets (`LobbyLayout.Budget.Packages`, enforced by tests/Lobby.spec.luau):

  | Package | Parts | Parts in lobby area | Lights | Lights in lobby area |
  |---|---|---|---|---|
  | Sky | 1400 | 150 | 6 | 2 |
  | Backdrop | 1800 (+300 in Land.luau) | 500 | 10 | 3 |
  | Plaza | 1100 | 1100 | 10 | 10 |
  | Districts | 1000 | 1000 | 8 | 8 |
  | Flora | 1500 | 1300 | 8 | 8 |
- Add your own spec `tests/Lobby<Package>.spec.luau` (hooks, footprints, walkability of
  your walkable pieces). `tools/check.sh` must pass. Render your shots and look at them.
- Commit without `build/TerraForge.rbxl` (`git checkout -- build/TerraForge.rbxl`).

### 6.1 Package Sky

**Owns:** `src/server/World/Lobby/Sky.luau` (+ `Lobby/Sky/*`),
`src/shared/Config/LightingConfig.luau`, the `Lighting` section of `default.project.json`,
`src/client/Controllers/LightingController.luau`, `tools/preview/viewer.js` (sky dome, sun
glow and clouds only), `tests/LobbySky.spec.luau`.
**Replaces:** nothing. **Hooks:** Spin on the Balloon (and ships, bob only).

Build:
1. **Sunset lighting.** Apply ART_DIRECTION section 7 to `LightingConfig.Presets.Surface`
   and to `default.project.json` (they must stay identical). Quarry preset = the same
   sunset, a bit dustier. Add a `Sky` (default skybox, SunAngularSize ~16, StarCount 0) and
   create `Clouds` under `Workspace.Terrain` at runtime in LightingController if missing
   (Cover ~0.5, Density ~0.6, Color 255,196,176). Tune ClockTime (~17.6) and
   GeographicLatitude in Studio until `Lighting:GetSunDirection()` ~= SunDirection.
2. **Preview sky.** In viewer.js replace the blue dome for surface presets with a gradient
   SkyHorizon (255,162,86) -> SkyPurple (150,98,168) at ~25 degrees -> SkyTop (64,72,150) at
   the zenith, plus an additive sun glow (Sun 255,222,150; ~10 degree halo, 2 degree disc)
   around `shot.sunDir`. Optionally read the colors from a new `Sky` group in the preset.
3. **CloudBanks** (<= 350 parts): 14-20 clusters at 450-900 studs from the plaza, y 120-240,
   from W through NW to N and a few NE; each 3-7 flat blocks (12-60 wide, 6-18 tall): tops
   CloudPurple/SkyPurple, west faces and undersides CloudOrange/CloudPink/CloudLight.
   CanCollide/CanQuery/CastShadow false, Persistent streaming. Keep every cloud part out of
   the lobby area box (x -170..170, z -122..150).
4. **SunGlitter** (<= 120): neon strips (Sun, CloudOrange; Transparency 0.25-0.5; 0.2 thick,
   1-3 wide, 4-24 long across the path) along the piece's axis from x=-185 to -850, spread
   +-6 near to +-18 far, denser toward the horizon, top at y -20.85. Persistent.
5. **ShipA / ShipB** (<= 90 / 60): stepped hulls (WoodDark keel, Wood sides, Plank deck,
   RoofTrim stripe), stern castle with Lamp windows, masts 0.8 thick, square sails in
   AwningWhite/FlagLight (2-3 blocks each, slightly bowed), AwningRed pennants, a stern
   lantern (neon). Tag Spin with SpinSpeed 0, BobHeight 0.5, BobSpeed 0.8; Atomic.
6. **CastleIsland** (<= 90): rock islet of StoneDeep blocks rising ~20 above the sea, three
   crenellated towers and walls, a lighthouse with a Lamp neon top; muted colors
   (StoneDeep/SkyPurple). `Style.streaming(m, "Lod")`.
7. **FloatingIslandWest / East** (<= 170 / 200): grass top slab (Grass + GrassLight cap),
   DirtDark band, 4-5 inverted stone tiers (StoneDark -> StoneDeep) narrowing to a point
   30-40 below, hanging chunks; West: a small cottage (Stone walls, Wood gable roof via
   `Style.gableRoof{Color = Wood}`, Lamp windows), a Green and a Pink tree, a 30-stud
   waterfall off the south edge ending in mist; East: Green + Orange trees, a watchtower
   with a lit window, a 45-stud waterfall, a blue crystal cluster. Lod streaming.
8. **NextIsland** (<= 170, 1 light): floating island with a tall tower house (stone base,
   two timber floors, Lamp windows, steep roof), a plank bridge stub reaching west to x~240
   (meets Flora's boardwalk). Lod streaming.
9. **Balloon** (<= 80, 1 light in the lobby): envelope ~14 across, 6 stacked layers
   (widths 8,12,14,14,12,8) each made of two blocks turned 45 degrees to each other, one
   AwningRed and one LeafYellow, which gives vertical stripes; skirt, 4 ropes, Wood basket,
   a neon Fire burner with one PointLight (range 14); a small airship hull with a
   propeller under it. Tag Spin (SpinSpeed 0.05, BobHeight 2, BobSpeed 0.5), Atomic,
   PrimaryPart = basket.
10. **WestPier** (<= 90, 1 light outside the lobby): timber stairs down the cliff face from
    (-178, 0, -32) to a plank dock 8 wide at y -19.5 running west to x~-222, posts into
    the water every 5 studs, 4 lantern posts (glow), a rowboat and a small sailboat.

Shots: `lobby_hero`, `lobby_west`, `lobby_spawn`, `lobby_backdrop` (+ a private wide sky
shot). Done when the hero shot has an orange-to-purple sky, pink/purple clouds, glitter on
the sea, ships, three islands and the balloon in the places the concept has them.

### 6.2 Package Backdrop

**Owns:** `src/server/World/Lobby/Backdrop.luau` (+ `Lobby/Backdrop/*`),
`src/server/World/Land.luau` (restyle only), `tests/LobbyBackdrop.spec.luau`.
**Replaces:** nothing in TownLegacy (it removes Land's own "EMBER CAVES" sign).

Land.luau restyle rules: keep every protected space, the quarry pit/ramp/walls footprint,
tunnels, cave rooms and roofs, entrances, VipDoor + sign, Bounds, ground extents and sea
strips exactly where they are; tests/World.spec.luau (cave intrusion) must pass; at most
+300 parts; no new lights. Use `Style.C` (require `script.Parent.Lobby.Style`), not
Palette, for new colors.

Build:
1. **Land restyle**: ground Grass, patches GrassLight/GrassDark; sea Sea with Reflectance
   0.2; island rim cliffs axis-aligned dark voxel stone (StoneDark/Stone/StoneDeep) with
   DirtDark bands and Grass caps; mountain columns axis-aligned (no yaw jitter, no tilted
   caps), Stone at the bottom to StoneDark/StoneDeep up high, grass slabs on columns under
   40 high, StoneLight caps above, Style.tree (Green, sparse) instead of pines; skip the
   columns inside the ForgeMountain box (x -80..160, z -340..-240) and let the massif
   replace them; quarry walls recolored to Stone/StoneDark; delete the EMBER CAVES sign.
2. **ForgeMountain** (<= 700, raised to 1000 by the polish pass, section 0.1): three stepped tiers of dark voxel columns (8-12 wide):
   tier 1 y 22-52 over the full width, front face at z ~ -242 right above the quarry's
   north wall; tier 2 y 52-82, x -50..140, set back to z ~ -258; tier 3 y 82-112,
   x 20..100, z ~ -275 (peak). Tier 1 leaves a ledge at y 26 for ForgeWorks (x 17..51,
   z -259..-241) and stays below y 28 right above the portal (x -22..22). Grass ledges with trees and timber railings, 6-8 crystal
   clusters (4 CrystalPurple, 3 CrystalBlue, 1 CrystalPink, size 6-12, two with lights),
   a zig-zag timber walkway with ladders on tier 1, a cart track with one cart on a ledge.
   Never below y 22 above the caves (x -74..74); outside that x range columns may reach
   the ground. Lod streaming.
3. **DepthsPortal** (<= 90, 1 light): two `Style.pillar` columns (width 4, height 22) at
   x = +-14, a stone lintel arch y 6-12 with a keystone, `DEPTHS` sign (Stone kind, 14 x 4)
   above it with an ArrowDown icon board, 3 receding U-shaped iron arch frames inside the
   tunnel (z -238, -241, -244) with Ember neon inner edges, Pillar lanterns either side,
   one PointLight (Fire, range 22). Keep x -9..9, y -12..4 open and walkable.
4. **ForgeWorks** (<= 160, 1 light): a stone-and-iron block house (14 x 10 x 10, Iron roof,
   3 `Style.window`s) on the cave roof, `THE FORGE` sign (Wood, 20 x 5) with a
   CrossedHammers icon board on a timber frame at y ~38 facing south, a PWR board (Glow
   sign "PWR" 4 x 2 + a vertical neon gauge bar), a chute + conveyor (Hazard trims) down
   to the quarry floor near x 30, a 20-stud iron lattice derrick with a red neon beacon,
   flanged pipes (ART_DIRECTION 9 kit look).
5. **DepthsRails** (<= 60): `Style.rails` z -238 -> -202, an ore cart (Load "Ore") at
   z ~ -212, a buffer stop.
6. **QuarryFallsWest / East** (<= 40 each): `Style.waterfall` from a tier-1 lip at y ~44 to
   the quarry floor (width 6), pool hugging the north wall (z -234..-228), clear of the
   quarry's node spawns (`WorldBuilder.generateNodeSpawns()`).
7. **ScaffoldWest / ScaffoldWest2** (<= 50 each): timber derricks (WoodDark posts 0.8,
   X-braces every 8 studs, two platforms, a ladder, a pulley wheel, a lantern on top),
   standing on the west mountain columns (plinth down to the column top).
8. **Crane** (<= 60): iron + Hazard lattice tower, counter-jib with a weight, a 30-stud jib
   toward the Facing, trolley, cable and a hanging WoodLight crate over the quarry.
9. **Beacon** (<= 30, 1 light): lattice tower on the peak with a red neon light.
10. **NWCliff + NWPool** (<= 90 + 40, 1 light): `Style.voxelCliff` 32 x 22 x 10, two trees on
    top, ivy cubes, a waterfall (height 18, width 5) at x ~ -48 into the pool (stone rim,
    foam, mist), two purple crystal clusters on the ledges (one PointLight).
11. **MineEntrance** (<= 140, 1 light): voxel rock hill (dark stone, grass top, a Yellow
    tree), timber portal on its east face (posts 1.4 thick x 10, lintel 12, braces),
    `MINE` sign (Wood, 10 x 3.5) with CrossedPickaxes, an 8 x 8 StoneDeep mouth 4 deep with
    a dim Ember strip inside (name the recess part `MineMouth`, future teleport), 2 hanging
    lanterns (one light), tools and crates.
12. **MineYard** (<= 90): rails from the mouth (x ~ -34) east to x ~ -8, buffer stop, two
    `Style.mineCart{Load = "Gold"}`, a gold nugget pile, a wheelbarrow, a lantern post.

Shots: `lobby_hero`, `lobby_backdrop`, `lobby_west`, `lobby_south`. Done when the hero
shot shows a dark stepped massif towering behind the forge with DEPTHS peeking above the
forge roof, THE FORGE to its right, waterfalls, crystals, crane and scaffolds.

### 6.3 Package Plaza

**Owns:** `src/server/World/Lobby/Plaza.luau` (+ `Lobby/Plaza/*`), `tests/LobbyPlaza.spec.luau`.
**Replaces:** `roads`, `plaza`, `greatForge`. **Hooks:** `Spin` on the fire crystal
(the legacy Heartstone shard provides it until then). TownSpawn stays in Town.luau.

Build:
1. **Plaza paving** (<= 170): base disc r 36 (Flag, top at y 0.4, collides), FlagDark
   bands at r 30-31.2 and 18-19, FlagLight disc r 14, 16 radial FlagDark seams (0.5 wide)
   from r 14 to 30, ~40 worn tiles, a StoneDark curb (1 tall) at r ~35.6 with gaps for the
   south road, both spurs, the forge approach (x -10..10) and the four district paths.
2. **FireCrystal** (<= 70, 1 light): outer `Style.stoneRing` r 11 (Height 1.6, Width 2.4,
   Glow = Fire) with gaps at S and N for steps, inner ring r 7.5 (2.8 tall, StoneDark
   cap), an octagonal pedestal (two 7 x 2.2 x 7 blocks turned 45 degrees) with an Ember
   seam, the crystal model `FireCrystal`: main crystal 3.6 wide x 13 tall (Fire body,
   FireCore tip) + 4 leaning side crystals (5-8 tall, Ember/Fire); tag Spin (SpinSpeed
   0.25, BobHeight 0.5), Atomic, PrimaryPart = main body. PointLight Fire range 40,
   brightness 2.2. Emitters: Fire at the pedestal, Embers, Sparkle. Two gold carts
   (`Style.mineCart`) and a few crates/barrels at the plaza edge (concept).
3. **SpawnPad** (<= 30): a flush compass-rose inlay (thin FlagLight/Brass strips, 0.05
   proud) around (0, 0, 26), r 8. Nothing that collides above y 0.6 within r 9.
4. **GreatForge** (<= 320, 2 lights): footprint x -21..21, z -78..-38, front z = -38.
   StoneDark plinth with 3 front steps; ground floor `Style.stoneWall` 12 tall with
   `Style.pillar` corners and entrance pillars; entrance 14 wide x 10 tall under a WoodDark
   lintel with braces, interior visible: back-wall Molten neon named `ForgeGlow`, two
   furnaces with Ember mouths, anvils (Metal), chains, embers, PointLight #1 (Fire, range
   36). Timber upper floor (6 tall, WoodDark beams, Wood infill, 4 Lamp windows front, 2
   per side). Main `Style.gableRoof` (ridge along X) width 44, depth 34, height 10, eave
   y 18 (ridge ~28); front cross gable (ridge along Z) width 18, depth 14, height 7 over
   the entrance with a StoneLight roundel and the CrossedHammers icon (Gold, size 5) at
   y ~22. `THE GREAT FORGE` sign (Wood, 24 x 4.6) at y ~14.5 over the entrance, hanging
   lanterns at its ends. Two chimneys at (x +-17, z -72), 6 x 6, top y 40-44, Ember neon tops,
   Smoke + Embers (at x +-17 they stay clear of the DEPTHS sign in the hero shot). Optional `MoltenChannel` to a basin in front (PointLight #2) or a porch
   lantern. Ridge <= 32 so DEPTHS shows above it from the hero camera.
5. **Roads and paths** (<= 320): every WorldLayout.Roads and LobbyLayout.Paths strip:
   south road, spurs, forge paths and the district paths as Cobble (`Style.path`,
   TileEvery ~4.5, CurbEvery 4 within 20 studs of the plaza); plot roads, rim road, ToMine
   and ToNextArea as Dirt (TileEvery ~6). Flat and non-collide (the ground is solid).
6. **Lanterns** (<= 220, <= 7 lights): Post lanterns every 18-20 studs alternating sides on
   the south road, spurs, forge paths and rim road; Pillar lanterns at the four plaza
   entrances (lights on four of them); Ground lights along the forge steps.

Shots: `lobby_spawn` (the money shot), `lobby_hero`, `lobby_south`, `lobby_east`.
Done when the spawn view matches the concept's center: the flagstone plaza, the turning
fire crystal in its glowing ring, the Great Forge with red roofs and crossed hammers.

### 6.4 Package Districts

**Owns:** `src/server/World/Lobby/Districts.luau` (+ `Lobby/Districts/*`),
`tests/LobbyDistricts.spec.luau`.
**Replaces:** `tradingPost`, `toolSmithy`, `emberChest`, `guildBoard`.
**Hooks (all moved here):** SellCounter, SellBin (+ Intake), ShopCounter, UpgradeCounter,
EmberChest (inside SpinWheel), GuildBoard, OreCodex, FossilDig, Spin (wheel disc). The
legacy builders keep providing SellBin/SellCounter/ShopCounter/EmberChest/GuildBoard until
this package lands; tests/Lobby.spec.luau then requires all of them under `Lobby.Districts`.

Build:
1. **Shop: Pell's Trading Post** (<= 200, 2 lights): StoneDark plinth, plank walls with
   WoodDark posts (10 tall), `Style.awning` AwningPink/AwningWhite (7 stripes, depth 6, drop
   2.5) over the counter at y 9, a small Wood gable roof (not red) behind it, `SHOP` sign
   (Glow, 10 x 3.4) on the roof front at y ~13 plus a Coin icon board,
   `PELL'S TRADING POST` (Wood, 12 x 2) under the awning edge. Counter 3.5 tall, 16 wide:
   left half = `ShopCounter` part (pickaxe rack, gem samples), right half = `SellCounter`
   part (brass scale, coin stacks). Props.npc "Pell the Trader" behind the SellCounter,
   ore shelves, hanging lanterns (1 light), crates and barrels.
2. **ShopFront** (<= 60): the `SellBin` model (tag) at the piece center: bin 9 x 4 x 7
   (Wood, Gold Metal bands), `Intake` part (Transparency 1, CanCollide/CanTouch/CanQuery
   false, ~8 x 5 x 6), `SELL` sign (Wood 5 x 1.8), Gold neon coins inside (Transparency
   0.2). Open toward the plaza.
3. **Upgrades** (<= 200, 2 lights): the mirror of the SHOP with AwningPurple/AwningWhite,
   `UPGRADES` sign (Glow, 12 x 3.4) + Gear icon, GlowEdge neon trims along the counter top,
   posts and roof edge, `UpgradeCounter` part, Props.npc "Forgemaster Ulda", a rack of
   tiered pickaxes, a bench with a CrystalBlue screen.
4. **UpgradesFront** (<= 50): a glowing pickaxe (WoodDark handle, CrystalBlue neon head)
   floating over a `Style.pillar` (height 3, Glow GlowEdge), two gear crates.
5. **SpinWheel** (<= 150, 1 light): stone platform 18 x 1 x 10, timber A-frame (WoodDark
   legs 1.2 thick) with the axle at y 12; wheel diameter 16: 8 colored segments
   (AwningRed, LeafOrange, LeafYellow, LeafGreen, CrystalCyan, CrystalBlue, CrystalPurple,
   AwningPink) with WoodDark dividers, a Gold rim with 16 Lamp neon bulbs, a Gold star hub,
   Coin icons on a few segments; a Gold pointer on the frame at the top (not spinning).
   The disc is a sub-model `Wheel` tagged Spin (SpinSpeed 0.6, BobHeight 0), Atomic, whose
   PrimaryPart (hub) has its Y axis along the axle (hub CFrame = frame *
   CFrame.Angles(math.pi / 2, 0, 0) at the axle). `SPIN & WIN` sign (Wood, 12 x 3) under the
   wheel facing the plaza. `EmberChest` model (tag, PrimaryPart "Chest") on the platform in
   front of the wheel: chest 4.6 x 2.6 x 3, Gold bands, Ember neon lock, 1 PointLight.
   Hierarchy: `SpinWheel { frame parts, Wheel, EmberChest, sign }`.
6. **GuildBoard** (<= 30): two posts, a WoodLight board 7.2 x 3.6 named `Board` with a
   `FORGEKEEPERS' GUILD` header, 4-6 pinned notes, a small Roof-red cap. Tag on the model,
   PrimaryPart = Board.
7. **FossilDig** (<= 170, 1 light): a capped `Style.fence` around the site with an
   entrance gap facing the plaza (west), corner lantern posts; a DirtDark bed 14 x 18
   flush with the ground with stepped Dirt/DirtLight terraces at the edges (pit look, no
   hole); a half-buried dinosaur skeleton in FlowerWhite/Sand (skull + jaw, 10 vertebra
   cubes in a curve, 6 rib arches, 4 leg bones, tapering tail); shovel, pick, brush, a
   sieve frame, a wheelbarrow, a small canvas tent (AwningWhite); `FOSSIL DIG` sign (Wood,
   10 x 2.6) with a Bone icon at the entrance. Tag FossilDig on the model, PrimaryPart =
   the bed.
8. **RockScanner** (<= 90, 1 light): stone platform 12 x 1 x 10; terminal model (tag
   OreCodex, PrimaryPart = cabinet): Iron cabinet 4 x 6 x 2.5 with a slanted desk and a
   CrystalBlue neon screen, a CrystalCyan neon scanner ring (octagon of 8 blocks, 6 across)
   over a sample pedestal, three sample rocks; `ROCK SCANNER` sign (Stone, 10 x 2.6) with a
   Target icon; one PointLight (CrystalBlue, range 14).

Shots: `lobby_hero`, `lobby_spawn`, `lobby_west`, `lobby_east`. Done when SHOP and UPGRADES
read like the concept's stalls (stripes + glowing blue signs), the wheel is the colorful
landmark on the left, and the dig and scanner read at a glance.

### 6.5 Package Flora

**Owns:** `src/server/World/Lobby/Flora.luau` (+ `Lobby/Flora/*`), `tests/LobbyFlora.spec.luau`.
**Replaces:** `scatter`.

Build:
1. **LilyPond** (<= 60): `Style.pond` 24 x 14, LilyPads 5, pink flowers, cattails
   (LeafGreenDark sticks), two small purple crystal clusters on the west bank (no light),
   a Ground lantern.
2. **KoiPond** (<= 70, 1 light): `Style.pond` 24 x 14, LilyPads 4, Koi 6, StoneLight
   stepping stones, two Ground lanterns and one Post lantern with a light.
3. **Creek** (<= 30): water strip from x -14 to 14 at z 59..65 (non-collide over ground,
   like the ponds), bank stones; joins both ponds under the bridge.
4. **CreekBridge** (<= 45, 1 light): `Style.archBridge` from (0, 0, 54) to (0, 0, 70),
   width 10, rise 2.4, two Post lanterns at the south end (one light).
5. **Signpost** (<= 60): WoodDark post 1.2 x 10 with a cap and a lantern (glow); four
   double-sided Wood boards 6.5 x 1.6 at y 8.2 / 6.4 / 4.6 / 2.8, each with a 1.6 icon board
   at its left end: MINE (Pickaxe, turned toward the mine, SW), UPGRADE (Gear, NE),
   EXPLORE (Compass, N), BUILD (House, E). Eighth turns at most.
6. **NextArea** (<= 60): `NEXT AREA` sign (Wood 11 x 3) with an Arrow icon (points east) on
   two posts, two lantern posts, a closed rope gate (AwningRed rope) at x ~168 with a
   small "SOON" plank.
7. **NextAreaBoardwalk** (<= 110): `Style.planks` deck 6 wide from x 166 to 240, stepping
   down over the cliff edge onto posts above the sea, rails, lantern posts every 15 (glow),
   ending at the NextIsland bridge stub.
8. **PinkGrove** (<= 45): Pink trees scale 1.5 and 1.3 at about (37, 0, -68) and
   (46, 0, -62), pink bushes, a pink Sparkle emitter (rate 2) for falling petals.
9. **RedTree** (<= 30): one Red tree scale 1.5, red/orange bushes, a flower ring.
10. **AutumnCorner** (<= 80): 3 Yellow + 2 Orange trees (scale 1.0-1.3), bushes, orange
    pumpkin cubes, flowers.
11. **Scatter** (<= 750): <= 45 trees (45% Green, 15% Pink, 12% Red, 14% Yellow, 14%
    Orange; scale 0.8-1.2), denser along the plot roads (x +-56..64), behind the forge
    (z -80..-110) and in the south foreground (z 95..140); <= 35 bushes; <= 50 flower
    patches (FlowerYellow/White/Purple/Pink/Red/Blue); <= 15 `Style.boulder`s. Place with
    `LobbyLayout.isFree(p, radius)`. Keep sight lines: no tree within 6 studs of the south
    road between z 36 and 100, nothing taller than 12 within 10 studs of the plaza curb.
12. **Fences** (<= 100): capped `Style.fence` along the creek banks (gaps at the bridge),
    the ponds' outer sides, one side of ToScanner and ToMine.
13. **Garden lanterns** (<= 60): Post lanterns at path junctions, Ground lanterns on the
    pond banks (lights counted in the 8).

Shots: `lobby_hero`, `lobby_south`, `lobby_spawn`, `lobby_east`. Done when the hero
shot's foreground matches the concept: bridge over the creek between two ponds, the
signpost, the red tree, the autumn corner, pink trees behind UPGRADES, and no bare lawn.

## 7. Integration

### 7.1 Town.luau loader
`Town.build` builds the legacy pieces nobody replaces yet, then every lobby module that
exists (`LobbyLayout.Packages` order) into `Emberfall.Lobby.<Package>` with
`Rng.new("Lobby/<Package>/<Seed>")`, then the TownSpawn. Modules never need to edit Town.

### 7.2 Legacy fallback (TownLegacy.luau)
| Legacy piece | Provides | Replaced by |
|---|---|---|
| roads | dirt roads + 13 road lights | Plaza |
| plaza | paving, Heartstone shard (`Spin`) | Plaza |
| greatForge | old forge | Plaza |
| tradingPost | `SellCounter`, `SellBin` | Districts |
| toolSmithy | `ShopCounter` | Districts |
| emberChest | `EmberChest` | Districts |
| guildBoard | `GuildBoard` | Districts |
| scatter | old trees, rocks, flowers | Flora |

When all five packages have landed, the art director deletes TownLegacy.luau.

### 7.3 Merge order
Any order works (no shared files). Suggested: Backdrop and Sky first (they change the
whole mood), then Plaza, Districts, Flora. After each merge: `tools/check.sh`,
`lune run tools/lune/lobby_stats.luau`, render `lobby_hero` and compare with the concept.
