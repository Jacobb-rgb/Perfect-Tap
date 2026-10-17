# Visual upgrade plan (owner request, 2026-10-16)

The owner sent a second concept image, **docs/art/lobby_concept_v2.webp**, plus seven Kenney kits (all CC0) and asked:
- Make the **SHOP, the wheel of fortune (SPIN & WIN), CAPSULES and the other buildings** look like concept v2:
  sci-fi/neon modules with thick metal frames, glowing blue neon outlines and big neon signs (SHOP with a cart icon,
  CAPSULES, SPIN & WIN with a crown), glass display cases, a huge glowing capsule, a giant mechanical wheel ring with
  stairs, the Great Forge with a dark slate roof, red banners with hammer icons and a big glowing crossed-hammers
  emblem, a plaza of dark polished tiles with blue and orange neon rings, walkways with orange neon edge strips and
  chevrons, dark lantern pillars with glowing slots, an airship in the sky.
- **Train Kit**: use the train model that fits a mining game best (our future per-player ore train).
- **Space Station Kit + City Kit (commercial)**: use their blocks to build the buildings.
- **Graveyard Kit**: only the small **brick walls** – they become the border of every plot.
- **Factory Kit**: the style of all tech machines, e.g. **water flowing out of pipes into a machine**.
- **Planets**: put **2–3 big planets** in the sky.
- **Blaster Kit**: give our blasters a better shape (keep our ore colors).
- **Ore podium (stand)**: it is too basic; build it from kit pieces.
"I need the game to be the best."

## Ground rules
- Kits live outside the repo in `/Users/kuban/Desktop/Terra Forge Roblox game KIT/kity/` (`kenney_train-kit`,
  `kenney_space-station-kit`, `kenney_graveyard-kit`, `kenney_city-kit-commercial`, `kenney_factory-kit_3.0`,
  `kenney_planets`, `kenney_blaster-kit`), each with `Models/GLB format`, `Previews/*.png`.
  Reference sheets rendered from the GLB files: **docs/art/kenney_refs/*.jpg** (more with
  `KENNEY_KIT="<kit>/Models/GLB format" node tools/preview/kenney_sheet/sheet.mjs out.jpg name1,name2`).
- **Rebuild the shapes from Roblox parts** (blocks, wedges, corner wedges, cylinders, balls) like before: Roblox cannot
  load mesh files from code (they need uploading under the owner's account), parts work at once and stay light on
  phones. Match the kit models' proportions, bevels, bands and details closely; use our palette (Style.C, ore colors).
- Keep every gameplay hook, tag, attachment, name, footprint and test; stay inside part/light budgets (mobile).
- Every package renders its work next to the reference (concept v2 and/or the Kenney sheet), looks, fixes, repeats.

## Packages (each owns its files; nobody else edits them)
| Package | Owns | What |
|---|---|---|
| **Stalls** | src/server/World/Lobby/Districts/** , tests/LobbyDistricts.spec.luau | SHOP, Tobin's Sell stall, UPGRADES (Tech shop), SPIN & WIN, CAPSULES, ENCHANT, HALL OF FAME, ROCK SCANNER, FOSSIL DIG and the guild board in the concept v2 style (Space Station walls/banners/door frames/display walls/table-displays/structures + City Kit awnings/overhangs) |
| **Plaza** | src/server/World/Lobby/Plaza/** , tests/LobbyPlaza.spec.luau | dark polished plaza tiles with blue + orange neon rings, the fire crystal's mechanical ring, neon walkway edges and chevrons, dark lantern pillars with glowing slots, the Great Forge restyle (slate roof, red banners, glowing crossed-hammers emblem, wide stairs) |
| **Sky** | src/server/World/Lobby/Sky/** , tests/LobbySky.spec.luau | 2–3 big planets (Kenney Planets sprites as color/pattern refs: banded/blotched spheres from stacked balls/discs, one with a ring), an airship like concept v2, keep the balloon/islands |
| **Base** | src/server/World/PlotBuilder.luau , tests/PlotService.spec.luau | brick-wall plot borders (Graveyard brick-wall, brick-wall-end pillars, brick-wall-curve corners) around every plot pad and yard (gaps at the road entrance and the yard gate), a showpiece ore podium (Space Station table-display-planet base + Factory/Space Station trims + neon rim; keep Podium1..4/Top/OrePoint/Prompt/Lock/PricePlate), nicer pen fence and train stop |
| **Machines** | src/shared/Builders/MachineBuilder.luau , src/client/Controllers/MachineFxController.luau , tests/Machines.spec.luau | every machine in the Factory Kit style (docs/KENNEY_FACTORY_KIT.md mapping), water that flows out of pipes into the Cleaning Station and the Auto Cleaner (client-side animated water: falling stream + splash + puddle shimmer), conveyors with rollers and hazard stripes |
| **Blaster** | src/shared/Builders/BlasterBuilder.luau , tests/Config.spec.luau (blaster part) | blaster shapes after the Blaster Kit (blaster-a…r: chunky bodies, carry handle on top, magazine/grip, barrel shrouds, scopes at higher levels), ore colors kept, <= 25 parts, Muzzle + grip contract kept |
| **Train** | src/shared/Builders/TrainBuilder.luau (new), tests/Train.spec.luau (new) | steam locomotive after Train Kit `train-locomotive-a/b/c` + ore wagon after `train-carriage-dirt` (load in ore colors) + track piece after `track-detailed`, colors from a plot banner color; locomotive <= 60 parts, wagon <= 20; for the step 2 train system |
Preview scenes: each package adds its own `tools/lune/lib/<package>_gallery.luau` + one `elseif` line in
tools/lune/export_scene.luau and its own `tools/preview/<package>_shots.json` (no shared preview files).

## Review loop
After the packages merge: a panel of critics compares the renders with concept v2 (lobby), concept v1 (overall
lobby), and the Kenney reference sheets (machines, blasters, train, fences), lists concrete differences, a fixer per
package fixes them, and the loop repeats until no major difference is left (at most 3 rounds). Then QA (budgets,
mobile performance, hooks), rebake, commit, push, pictures for the owner.

## Package notes: Sky (deviations awaiting the lead's sign-off)
- **Streaming Persistent instead of Lod** for the planets (114 parts), the airship (69) and the cloud banks (336):
  519 always-replicated parts. With `LevelOfDetail = StreamingMesh` anything past the 384-stud
  StreamingTargetRadius only ever shows its imposter mesh (no Neon glow, no translucent rim, smeared camouflage),
  and the airship (~400 studs) would pop in and out at the radius. Caps kept: <= 40 parts per planet (120 for the
  three), CloudBanks <= 350, airship <= 70; the cloud count did not grow.
- **Planets at 700-800 studs instead of 1500-3000.** The Atmosphere haze grows with the square of the distance: at
  1500 studs only ~40% of a Neon color survives (the round-2 planets came out salmon, periwinkle and flat lavender).
  At 700-800 studs ~75% survives, and the planets still hang 2x beyond the massif and the floating islands.
- **The small teal world shows only from the plaza (lobby_spawn), not in lobby_hero.** The hero frame's sky ends
  below the massif's top; every spot there is behind the mountain from the spawn. The hero frames the mountain with
  the ember world (top left) and the ringed gas giant (bleeding off the right edge).
- **Request to the Lighting owner:** `LightingConfig.Presets.Surface.Atmosphere` Density 0.26 -> ~0.19 and Haze
  0.9 -> ~0.5 (and the same in the `Lighting.Atmosphere` of default.project.json). The planet palette is solved for
  the current haze and holds up under the thinner one (docs/screenshots/sky_lighting_whatif.jpg).
