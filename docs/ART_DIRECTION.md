# Terra Forge: Art Direction (style bible)

Target: the owner's concept image [`docs/art/lobby_concept.webp`](art/lobby_concept.webp)
("I want the lobby to look EXACTLY like this"). Machine reference: Kenney Factory Kit
renders in `docs/art/kenney_*.jpg` (CC0). Layout and work split: [`docs/plans/LOBBY_PLAN.md`](plans/LOBBY_PLAN.md).
Code: every lobby builder uses the shared kit `src/server/World/Lobby/Style.luau`
(palette `Style.C` + helpers). Gallery of every helper: scene `style`, shots `style_*`.

Everything is original. No logos, fonts-as-images, brand names or copied assets. Roblox
parts only: no meshes, decals, textures or uploads (built-in particle textures are fine).

---

## 1. What makes the concept read

Study the concept before building anything. It works because of seven things; every set
piece must contribute to them:

1. **Chunky voxel shapes.** Everything is built from big cubes and slabs on a coarse grid:
   cliffs are stacked stone blocks, trees are lumpy clusters of leaf cubes, roofs are thick
   tiles. Nothing is thin, round or smooth except crystals, water and wheels.
2. **Three shades per material.** Each surface uses a light, mid and dark shade of one hue
   (top faces and caps lighter, undersides and recesses darker). That is what gives the
   "painted voxel" depth, not lighting alone.
3. **Warm light against cool stone.** Dark blue-grey stone and deep shadows everywhere, with
   orange fire light (forge mouth, fire crystal, lanterns, molten carts) and cool purple/blue
   crystal glows punching through. The sunset adds orange rims and purple shadows.
4. **Saturated accents on a calm base.** The base is grass green, flagstone beige and stone
   grey. The accents are tiny but loud: pink/red/yellow/orange tree crowns, pink-white and
   purple-white awnings, gold, glowing blue signs, purple crystals.
5. **Big readable signs.** Every place has a name board with huge bold letters and a simple
   pictogram (crossed hammers, pickaxe, gear, compass, house, arrow, bone, target).
6. **Dense, layered composition.** Foreground (bridge, pond, signpost, trees), midground
   (plaza, stalls, wheel, dig site), background (forge, mountain, waterfalls, towers) and
   sky (islands, balloon, clouds) all overlap. There is no empty lawn: gaps get flowers,
   fences, lanterns, crates, rocks.
7. **Golden-hour sky.** Low sun over the sea on the left, orange horizon, pink and purple
   clouds, a sparkling sun path on the water.

## 2. Palette (exact RGB, `Style.C`)

Use these names in code (`Style.C.Grass`), never new ad-hoc colors. `Style.vary(color, rng)`
adds a small value/saturation jitter so repeated blocks do not look copy-pasted (default 5%).

### Ground and stone

| Name | RGB | Use |
|---|---|---|
| Grass | 104, 178, 62 | lawns, cliff caps |
| GrassLight | 142, 204, 78 | sunlit grass patches, top steps |
| GrassDark | 66, 138, 52 | shaded patches, grass under trees |
| Dirt | 138, 98, 62 | dig site, mine yard, dirt paths (dark) |
| DirtDark | 102, 72, 48 | dirt band under grass caps, pit floor |
| DirtLight | 176, 132, 86 | dirt paths |
| Sand | 222, 196, 146 | beach strips, pond shores |
| Stone | 124, 118, 122 | walls, rings, pillars (mid) |
| StoneDark | 86, 80, 88 | cliffs, curbs, plinths, caps |
| StoneDeep | 60, 56, 66 | mountain shadows, tunnel mouths, sign boards (stone) |
| StoneLight | 162, 156, 152 | accent bricks, lit edges, sign frames (stone) |
| Flag | 178, 152, 126 | plaza flagstones (mid) |
| FlagDark | 146, 122, 102 | plaza seams and ring bands |
| FlagLight | 204, 180, 146 | worn tiles, highlights |
| Cobble | 156, 142, 128 | cobble roads and paths |
| CobbleDark | 122, 110, 102 | cobble tiles, shade |

### Wood, roofs, metals

| Name | RGB | Use |
|---|---|---|
| WoodDark | 88, 56, 36 | posts, frames, fence posts, beams |
| Wood | 138, 90, 54 | walls, rails, barrels |
| WoodLight | 186, 130, 78 | planks, crates, highlights |
| Plank | 164, 110, 64 | decks, bridges |
| Roof | 198, 54, 42 | red roof tiles (mid) |
| RoofDark | 150, 38, 32 | tile rows, shaded slope |
| RoofTrim | 104, 30, 26 | eaves, gable boards, ridge |
| Iron | 64, 64, 72 | brackets, cart bodies, lantern caps |
| IronLight | 116, 118, 128 | rails, rims, lit iron |
| Copper | 198, 112, 62 | cart bands, pipes, machine accents |
| Brass | 214, 170, 76 | bolts, caps, trims, gauges |
| Gold | 255, 196, 64 | coins, loot, pointer, wheel rim |

### Glows (always `Enum.Material.Neon`)

| Name | RGB | Use |
|---|---|---|
| Fire | 255, 140, 32 | fire crystal, braziers, ring insets |
| FireCore | 255, 200, 96 | hottest centers (small) |
| Ember | 255, 92, 24 | chimney tops, deep fire, molten trim |
| Molten | 255, 112, 26 | molten metal, forge mouth |
| Lamp | 255, 200, 120 | lantern glass, windows |
| CrystalPurple | 180, 96, 255 | crystal clusters (main) |
| CrystalViolet | 124, 84, 255 | crystal clusters (deep) |
| CrystalBlue | 84, 168, 255 | crystal clusters, scanner screen |
| CrystalCyan | 96, 232, 255 | waterfall highlights, scanner ring |
| CrystalPink | 255, 110, 200 | rare crystal accents |

### Signs, cloth, water, foliage, sky, factory

| Name | RGB | Use |
|---|---|---|
| SignBoard | 70, 44, 30 | wooden sign boards |
| SignFrame | 158, 106, 60 | wooden sign frames |
| SignText | 255, 210, 96 | gold letters and icons |
| GlowBoard | 26, 50, 120 | glowing sign boards (SHOP, UPGRADES) |
| GlowEdge | 70, 176, 255 | glowing sign frames, blue neon trims |
| GlowText | 232, 246, 255 | glowing sign letters |
| TextShadow | 40, 22, 14 | letter outline |
| AwningPink | 236, 82, 150 | SHOP awning stripes |
| AwningPurple | 150, 82, 214 | UPGRADES awning stripes |
| AwningRed | 214, 56, 50 | other awnings, flags |
| AwningWhite | 250, 242, 236 | awning stripes |
| Water | 62, 152, 196 | ponds, creek, pools |
| WaterDeep | 34, 92, 140 | pond beds |
| Falls | 196, 232, 255 | waterfall sheets |
| Foam | 242, 250, 255 | foam, mist, falls highlights |
| Sea | 44, 112, 156 | the sea |
| LeafGreen / Light / Dark | 92, 176, 62 / 146, 206, 80 / 54, 130, 52 | green crowns |
| LeafPink / Light / Dark | 246, 142, 194 / 255, 188, 222 / 214, 100, 160 | cherry crowns |
| LeafRed / Light / Dark | 214, 52, 50 / 240, 98, 80 / 160, 32, 40 | red maple crowns |
| LeafYellow / Light | 248, 204, 62 / 255, 232, 122 | yellow crowns |
| LeafOrange / Dark | 242, 138, 40 / 204, 92, 30 | orange crowns |
| Trunk / TrunkDark | 110, 72, 44 / 80, 52, 34 | trunks, roots |
| FlowerYellow / White / Purple / Pink / Red / Blue | 255,222,80 / 250,250,244 / 182,112,255 / 255,124,176 / 240,70,60 / 100,160,255 | flower cubes |
| SkyTop | 64, 72, 150 | zenith (preview sky, cloud shadows) |
| SkyPurple | 150, 98, 168 | mid sky, cloud tops |
| SkyHorizon | 255, 162, 86 | horizon glow |
| Sun | 255, 222, 150 | sun disc, sun glitter |
| CloudPink / CloudPurple / CloudOrange / CloudLight | 240,150,168 / 148,108,176 / 255,176,112 / 255,216,200 | voxel clouds |
| Hazard | 255, 150, 36 | machine base trims, crane, warning bands |
| HazardDark | 40, 36, 40 | hazard chevrons |

Tree kinds (`Style.TreeKinds`, `{light, mid, dark}`): Green, Pink, Red, Yellow, Orange.
Mix for scattered trees: about 45% Green, 15% Pink, 12% Red, 14% Yellow, 14% Orange; hero
trees are Pink (behind UPGRADES), Red (foreground right) and Yellow/Orange (foreground left).

## 3. Materials

- **SmoothPlastic** for almost everything (flat painted look; the default of `Style.block`).
- **Neon** for every glow: fire, lamps, windows, crystals, signs' blue frames, molten metal,
  sun glitter. Neon parts never cast shadows (`Style.tiny()`). Keep neon colors saturated
  (the values above); never pure white, which blooms into a blob.
- **Metal** only for forge iron that should catch light: anvil faces, rails, rims. Never for
  large walls.
- **Glass** (Transparency 0.3-0.5) is allowed for a crystal shell over a neon core and for
  lantern panes, sparingly (transparency costs on mobile).
- Water: SmoothPlastic, Transparency 0.12-0.2, Reflectance 0.1-0.15 (`Style.water`).
- No textures, no decals, no Granite/Brick/WoodPlanks materials: the voxel look comes from
  geometry and shade, and material textures fight it.

## 4. Shape language (chunky voxel low-poly)

- **Grid.** Think in 1-stud voxels: sizes in whole or half studs (0.5 minimum for anything
  visible from the plaza; 0.3 only for trims and seams). Buildings and props are
  axis-aligned to their own frame and rotate in quarter turns. Only rocks, crystals, loot and
  icons tilt.
- **Chunky over detailed.** Prefer one big block with two contrasting caps over ten small
  blocks. Posts are at least 0.7 studs thick, beams 0.5, fence rails 0.35.
- **Stepped silhouettes.** Cliffs, roofs, canopies, pedestals and mountains step back in
  layers (each step ~10-25% smaller). Avoid perfectly flat walls taller than 6 studs:
  add a plinth, a course line, a cap and a few protruding bricks.
- **Caps and undersides.** Top faces get a lighter cap block (grass cap, stone cap, lighter
  leaf cube); undersides and recesses get a darker block. This is the concept's main trick.
- **Scale.** A player is 5 studs tall. Doors 5-7 tall, counters 3.5, lantern posts 7, sign
  letters at least 1.5 studs tall for plaza signs (3+ for landmark signs), trees 11-18 tall,
  hero trees up to 22.
- **Collision.** Only what players walk on or bump into collides (`Style.solid()` /
  `Style.decor()`): floors, walls, counters, trunks, big rocks, fences. Canopies, awnings,
  roof overhangs above head height use `Style.ghost()`. Small details use `Style.tiny()`
  (no collision, no query, no shadow).

## 5. Recipes

Each recipe names the Style helper that implements it. Extend locally in your package when
you need a variant; propose additions to `Style.luau` to the art director.

### Stone and brick walls (`Style.stoneWall`, `Style.pillar`)
1. A plinth 0.8-1.2 tall in StoneDark, 0.6 wider than the wall.
2. The wall slab in Stone (Flag for warm town walls), `Style.vary` 3%.
3. Mortar course lines every 2 studs (thin darker strips, built in).
4. 4-8 protruding bricks per 10x6 face in StoneLight and StoneDark (0.3 proud), more near
   corners and the base.
5. A cap row in StoneDark, 0.4 wider than the wall.
6. Corners get `Style.pillar` columns (stacked blocks with alternating 0.12 offsets).
7. Openings: frame with 0.8-thick blocks (lintel 1.2 tall) in StoneLight or WoodDark; the
   recess behind in StoneDeep or a Neon glow.

### Roofs (`Style.gableRoof`)
- Red tiles: Roof slopes, RoofDark tile rows (2-3 per slope), RoofTrim eaves, gable boards
  and ridge. Pitch about 35-45 degrees (height = 0.6-0.8 x half depth). Overhang 1 stud.
- Stepped or crossed roofs for important buildings: a main gable plus a smaller front gable
  over the entrance, or two gables of different heights.
- Stalls use striped awnings (`Style.awning`), never tiled roofs.
- Mountain and works buildings use dark iron or plank roofs (Iron/WoodDark) so the red of
  the Great Forge stays unique.

### Voxel trees, bushes, flowers (`Style.tree`, `Style.canopy`, `Style.bush`, `Style.flowers`)
- Trunk 1.7 x 6-7.5 studs (x scale), a root stub and a side branch stub.
- Crown: one core cube (light/mid/dark shades from `Style.TreeKinds`), a lighter top cap,
  4-6 side lumps, 2 top shoulders, a darker underside slab. The crown is wider than tall
  (about 1.3:1) and sits 60-70% up the tree. Big trees (scale >= 1.15) get a second crown.
- Quarter-turn yaw only, so trees share the voxel grid with buildings.
- Bushes: 2-3 cubes, walk-through. Flowers: patches of 4-6 tiny cubes plus a leaf cube.
- Plant in clusters of 2-4 with bushes and flowers at their feet; leave sight lines to
  signs and doors open.

### Cliffs and mountains (`Style.voxelCliff`)
- Columns of dark stone (StoneDark, StoneDeep for shaded or distant parts) 5-8 studs wide,
  heights varying 60-100% of the cliff; each column has a DirtDark band and a Grass cap
  (overhanging 0.3) when it is lower than ~40 studs, bare StoneDark/StoneLight caps above.
- Accent stones: 2 per column face in Stone/StoneDeep, protruding 0.6.
- Big massifs: stack tiers (each tier 15-30 studs tall, set back 6-15 studs), put grass
  ledges, trees, crystal clusters and timber walkways on the steps, and let waterfalls
  pour from the ledges. The silhouette must step, never slope smoothly.
- Far mountains (beyond ~300 studs) use fewer, bigger blocks and the StreamingMesh LOD
  (`Style.streaming(model, "Lod")`).

### Waterfalls and water (`Style.waterfall`, `Style.pond`, `Style.water`)
- A Falls sheet (0.6 thick, Transparency 0.12), a Water lip at the top, 3 neon Foam streaks
  (Transparency 0.35), foam cubes and mist particles at the bottom, a pool below.
- Every waterfall ends in a pool or a pond; every pond gets a stone-cube rim, lily pads
  (LeafGreen discs with pink flower cubes) and, in town, koi (orange, white, red).
- Water surfaces never replace ground: they are non-collide over solid ground ("wading"),
  so the walkability tests keep passing.

### Crystals (`Style.crystal`, `Style.crystalCluster`)
- Diamond-section prisms with a two-tone ridge tip, one tall crystal plus 3-5 smaller ones
  leaning outward, on a dark rock base. Purple and blue on the mountain, the fire crystal
  orange in the plaza.
- Only one cluster in four gets a PointLight (range 12-26); the rest glow by Neon alone.
- The plaza's fire crystal is special: Neon Ember core, Fire facets, a lighter FireCore
  tip, about 14 studs tall over a stepped stone pedestal, slowly turning (tag Spin).

### Lanterns and fire (`Style.lantern`, `Props.brazier`)
- Kinds: Post (wooden post + arm + hanging lamp), Pillar (stone column + lamp box), Hanging
  (under eaves and arches), Ground (path lights).
- Every lantern glows (Neon Lamp); only every 3rd-4th lantern near a gathering spot gets a
  PointLight (`opts.Light = true`, range 14-18, brightness 1.2-1.5, shadows off).
- Lantern rhythm: every 14-20 studs along roads and fences, always in pairs at doors,
  bridges and sign posts.

### Signs with big readable letters (`Style.sign`, `Style.icon`)
- Kinds: **Wood** (SignBoard + SignFrame + SignText gold letters, the default), **Glow**
  (GlowBoard + neon GlowEdge frame + GlowText white letters, LightInfluence 0, for SHOP and
  UPGRADES), **Stone** (StoneDeep board, StoneLight frame, gold letters: DEPTHS, MINE).
- Font: LuckiestGuy for names (`Style.SignFont`), FredokaOne for small labels.
- Size: text fills ~75% of the board; board height >= 3 studs for landmark signs readable
  from the spawn, >= 1.8 for plaza signs, >= 6 for THE FORGE / THE GREAT FORGE.
- Pictograms are part-built (`Style.icon`): CrossedHammers (forge), CrossedPickaxes /
  Pickaxe (mine), Gear (upgrade), Compass (explore), House (build), Arrow / ArrowLeft /
  ArrowDown, Coin (shop), Bone (fossils), Target (scanner). Place them on a square board
  left of the text, or alone on a gable roundel.
- Signs face where players come from. Double-sided when seen from both sides (signpost).
- Seen from the front, a frame's local +X is on the viewer's left: build asymmetric icons
  with that in mind ("Arrow" already points to the viewer's right).

### Plaza paving and paths (`Style.path`, `Style.planks`)
- Plaza: concentric flagstone rings (Flag / FlagDark / FlagLight), 12-16 radial seams, a
  low StoneDark curb with gaps where roads enter.
- Main roads: Cobble with CobbleDark/FlagLight tiles and curb stones near the plaza. Side
  paths: Dirt (DirtLight + Dirt tiles). Docks and bridges: Plank.
- Paths are flat (0.3 high, non-collide over solid ground) so they never create steps.

### Small props
`Style.crate`, `Style.barrel`, `Style.boulder`, `Style.mineCart` (Load Gold has two neon
nuggets), `Style.fence`, `Style.rails`, `Style.archBridge`, `Style.window`. Props.npc for
shopkeepers. Group props in threes (crate + barrel + sack) at doors and stalls.

## 6. Light, glow and atmosphere

- **Light budget**: at most 45 PointLights/SpotLights inside the lobby area (budget per
  package in `LobbyLayout.Budget`). Everything else glows with Neon. Shadows on lights:
  never (`Style.light` turns them off).
- **Where the real lights go**: the fire crystal (big, warm), the Great Forge mouth, the
  SHOP and UPGRADES counters, the SPIN & WIN wheel, a few lanterns at the plaza edge and on
  the bridge, one purple crystal near the NW waterfall, the DEPTHS portal, the mine mouth.
- **Particles** (built-in textures via `Style.emitter`): Embers at forge, crystal and
  chimneys; Smoke at chimneys (rate <= 4); Mist at waterfall feet; Sparkle on crystals and
  gold. At most ~25 emitters in the lobby, rates as low as reads well.
- Glowing parts named `ForgeGlow`, `Lava` or `MoltenChannel` pulse on the client
  (DecorController). Use those names for forge mouths and molten channels only.

## 7. Sunset sky and lighting

The lobby is always at golden hour, sun low over the west sea.

- **Sun**: azimuth ~262 degrees (just south of west), ~13 degrees high:
  `LobbyLayout.SunDirection = (-0.965, 0.225, 0.136)`. Preview shots pass it as `sunDir`.
  In Studio tune `Lighting.ClockTime` (start at 17.6) and `GeographicLatitude` until
  `Lighting:GetSunDirection()` matches it (X negative, Y about 0.2).
- **Lighting (Surface preset)**: Brightness ~2.3; Ambient (0.30, 0.22, 0.26); OutdoorAmbient
  (0.58, 0.44, 0.48) (warm with a purple lift in the shadows); ExposureCompensation ~0.1;
  EnvironmentDiffuseScale 0.5; EnvironmentSpecularScale 0.6.
- **Atmosphere**: Density ~0.34, Offset ~0.25, Color (0.98, 0.64, 0.46) (orange haze),
  Decay (0.50, 0.32, 0.56) (purple distance), Glare ~0.6, Haze ~1.8.
- **Color**: ColorCorrection Saturation +0.25, Contrast +0.14, Tint (1, 0.95, 0.9); Bloom
  Intensity ~0.9, Size ~32, Threshold ~0.92; SunRays Intensity ~0.12, Spread ~0.7.
- **Sky**: a `Sky` object with the default skybox, SunAngularSize ~16 (big sun),
  CelestialBodiesShown true, StarCount 0. Roblox `Clouds` (under Workspace.Terrain, created at
  runtime by the client or in the place file): Cover ~0.5, Density ~0.6, Color
  (255, 196, 176).
- **Voxel clouds**: flat clusters of 3-7 big blocks (12-60 studs) at 120-240 high, mostly
  W/NW/N (where the camera looks), tops CloudPurple/SkyPurple, sun-facing sides and
  undersides CloudOrange/CloudPink/CloudLight. No collision, no shadow, Persistent streaming.
- **Sea**: Sea color, Reflectance ~0.2; a broken path of neon sun glitter strips (Sun and
  CloudOrange) from the west shore toward the sun, wider and denser near the horizon.
- **Preview**: the renderer's sky dome should match: zenith SkyTop, mid SkyPurple,
  horizon SkyHorizon, plus a soft sun glow around `sunDir`.

## 8. Budgets and performance (mobile first)

| Budget | Limit | Checked by |
|---|---|---|
| Whole map parts | 11,000 | tests/World.spec.luau, tests/Lobby.spec.luau |
| Lobby area parts (x -170..170, z -122..150) | 5,000 | tests/Lobby.spec.luau |
| Lobby PointLights + SpotLights | 45 | tests/Lobby.spec.luau |
| Per package parts / lobby parts / lights / lobby lights | `LobbyLayout.Budget.Packages` | tests/Lobby.spec.luau |
| Land.luau growth (Backdrop restyle) | +300 parts | tests/Lobby.spec.luau |

`lune run tools/lune/lobby_stats.luau` prints where the parts and lights go.

Rules:
- Everything Anchored. CastShadow off on small props (`Style.tiny`), on neon and on water.
- StreamingEnabled is on (target radius 384): far backdrop models (beyond ~350 studs from
  the plaza) use `Style.streaming(model, "Lod")`; sky props that must always show (clouds,
  sun glitter, balloon) use "Persistent" and stay cheap; anything tagged `Spin` is a Model
  with "Atomic" streaming and a PrimaryPart.
- No scripts in the world, no per-frame server work. Motion is client-side only
  (DecorController: tag `Spin` with attributes SpinSpeed, BobHeight, BobSpeed).
- Builders stay pure (Instance creation only), deterministic from their `rng`.

## 9. Machines (later restyle, Kenney Factory Kit style)

Machines (`src/shared/Builders/MachineBuilder.luau`) will be rebuilt to read like the Kenney
Factory Kit (`docs/art/kenney_machines.jpg`, `kenney_pipes_conveyors.jpg`,
`kenney_structures_props.jpg`): chunky bevelled housings, thick frames around openings,
octagonal pipe flanges, hoppers, rollers and orange hazard trims, but in Terra Forge's
forge palette instead of Kenney's slate blue. The MachineBuilder contract stays: origin at
the footprint center, front = -Z, PrimaryPart "Base", the Attachments (Intake, Output,
Prompt, Status, OrePoint, CamPoint, AnvilPoint, IngotSlot1..4), named moving parts
(Roller, Drum, Glow), conveyors exactly 6 parts.

### Machine palette (to add to MachineBuilder's color table)

| Name | RGB | Use |
|---|---|---|
| Housing | 92, 96, 112 | main bodies (forged iron, slightly blue) |
| HousingLight | 138, 142, 160 | frames, bevels, bands, rails |
| HousingDark | 58, 60, 72 | recesses, throats, undersides |
| Copper | 198, 112, 62 | pipes, tanks, flanges |
| Brass | 214, 170, 76 | bolts, caps, gauges, handles |
| Hazard | 255, 150, 36 | base trims, rims of moving parts |
| HazardDark | 40, 36, 40 | chevrons on hazard trims |
| Molten (Neon) | 255, 112, 26 | furnace windows, taps, glowing seams |
| ClayBrick | 196, 112, 70 / 150, 80, 50 | Clay Furnace body / courses |
| Belt | 46, 42, 44 | conveyor belts |

### Kit parts (build once in a MachineKit module, reuse everywhere)
- **Bevelled housing**: body block + a slightly smaller top slab + wedge bevels on the top
  edges (2-4 wedges); a 0.3-0.5 thick HousingLight band framing the front opening (U
  shape, 3 blocks); a dark recess inside; a Hazard base strip 0.4 tall along the front.
- **Octagonal pipe**: two square prisms rotated 45 degrees about the pipe axis (reads as an
  octagon), Copper or Housing. **Flange**: same trick, 1.4x the pipe width, 0.4 thick,
  HousingLight, with 2-4 brass bolt cubes. Bends = two straight pieces meeting at a flange.
  Glass pipe: Glass shell with a Molten neon core.
- **Hopper**: four wedges forming an upside-down frustum (the existing `funnel`) plus a
  thick rim (4 blocks) and a throat block; square for most machines, a taller one for the
  Blast Furnace. The Intake attachment sits in the hopper.
- **Rollers**: Roblox Cylinders in HousingLight with Brass end caps, named Roller.
- **Tanks**: upright octagonal prisms (2 parts) in Copper with Brass bands and a stepped top
  (two smaller octagon slabs), a gauge (Brass disc + dark needle) and a valve wheel.
- **Feet and frames**: chunky HousingDark feet with Hazard pads (like `scanner-high`).

### Per machine
- **Cleaning Station** (3x2 cells): a heavy workbench like Kenney `machine-bed`: plank top
  (WoodLight, thick bevel) on a Housing frame with Hazard feet, an iron vise with a brass
  screw handle at OrePoint, a tool rack (chisel, scraper, brush) at the back, a brass lamp
  arm with a Lamp neon bulb, the output tray on the right (Output). Keep the close-up camera
  clear (CamPoint).
- **Clay Furnace** (2x2): a squat kiln of ClayBrick with mortar courses, a Housing collar
  band with bolts, an arched mouth with a Molten glow named ForgeGlow, a short octagonal
  chimney with a Copper flange and smoke, a small square hopper on top (Intake), a chute lip
  at Output.
- **Blast Furnace** (3x3): Kenney `machine-fortified` on a stone plinth: tall bevelled
  Housing body, a high square hopper (Intake), a Molten window (ForgeGlow) behind a thick
  frame, two Copper fuel tanks at the back corners piped into the body through flanged
  octagonal pipes, a tap spout with a molten trickle at Output, a pressure gauge, a Hazard
  base trim with chevrons.
- **Crusher** (2x2): Kenney `machine-connection-hole`: bevelled housing, a wide square
  hopper with Hazard rim and chevrons (Intake), two heavy Rollers visible in the throat, a
  short exhaust pipe with a flange, a front chute at Output.
- **Auto Cleaner** (2x2): a `scanner-high` style arch over a short conveyor bed: Housing
  arch with Hazard feet, a brush Drum (Brass core, Cloth bristle blocks), a status light
  post (stacked red/amber/green neon, like `warning-traffic`), a hopper at the back.
- **Anvil** (2x2): a big classic anvil (Metal face in HousingLight, horn wedge, waist) on a
  wooden stump with iron bands, a quench barrel with water, a hammer rack, a Brass plate.
  AnvilPoint and IngotSlot1..4 unchanged.
- **Storage Crate** (2x2): Kenney `box-large`: WoodLight crate with a thick WoodDark band,
  Housing corner brackets, a lid with a Brass latch and a slot in the lid (Intake).
- **Sell Chute** (1x1): a round-ish hopper (`hopper-high-round`) on an iron post, Brass rim,
  a Gold neon coin lamp and a small coin sign; the pipe below disappears into the plot with a
  flange on the ground.
- **Conveyor** (1x1, exactly 6 parts): Base (Housing frame), Belt (Belt color, tag
  ConveyorBelt), RailL/RailR (HousingLight with a Hazard top stripe color), 2 Arrow (Brass).
- **Fuel tanks, pipes, hoppers** (decor around machines and in the ForgeWorks backdrop):
  as in the kit above. Pipes always end in a flange; tanks always stand on feet.

Machine budgets: <= 40 parts per machine (Blast Furnace <= 60), only Base and main
bodies collide, everything under 1 stud is `tiny` (no collision, no shadow), at most one
PointLight per machine (furnaces only).

## 10. Review checklist

- [ ] Matches its LOBBY_PLAN.md entry: position, footprint, facing, height budget.
- [ ] Uses `Style.C` colors, three shades per material, caps light / undersides dark.
- [ ] Chunky: nothing thinner than 0.3, quarter turns for built things.
- [ ] Signs readable from the hero and spawn shots; pictogram + text.
- [ ] Within the package's part and light budgets (`lobby_stats.luau`), small parts `tiny`.
- [ ] Hooks tagged exactly as specified; spawn and plaza walkable; tests green.
- [ ] Rendered from the hero shots and looked at.
