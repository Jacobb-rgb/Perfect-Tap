---
name: ore-design
description: Design or change Terra Forge ores (the ~30 ore types, their rocks, rarities, values, looks, particles) and the blaster look that follows each ore. Use whenever adding/editing OreData, ore visuals (ItemBuilder, OreNodeBuilder/rocks, OreShellBuilder) or anything that must make an ore look unique and beautiful.
---
# Ore design (Terra Forge)

Goal: every ore is **instantly recognisable and beautiful**, on a phone at arm's length and on a TV.
Read first: docs/DESIGN_V2_NOTES.md (30 ores, rocks with 1–3 ores, dirty ore hides rarity, podium income/s,
blasters follow the ore), docs/ART_DIRECTION.md (palette `Style.C`, glows, budgets), src/shared/Config/OreData.luau,
src/shared/Config/Rarity.luau.

## Every ore gets a full identity card (in OreData)
`Id, Name (original, English), Rarity, Tier/zone, SpawnWeight, ValuePerSecond, SellValue, Color, Glow, Crust,
Shape, Material, Particles, Sound pitch, Lore line, BlasterSkin`.
- **Names:** mix of real minerals (Coal, Copper, Tin, Iron, Silver, Gold, Quartz, Amethyst, Emerald, Ruby,
  Sapphire, Diamond, Obsidian...) and original fantasy ores tied to the Kaldrum story (Emberite, Azurium, Stormcore,
  Solarite, Heartstone...). Never names from other games.
- **Rarity ladder:** Common → Uncommon → Rare → Epic → Legendary → Mythic (+ Secret for event ores). Values and
  spawn weights grow/shrink exponentially (see game-ui skill for number formatting).
- **Distinct silhouette per ore family**, not just a recolor:
  - shape families: blocky nuggets, hexagonal crystal spikes, layered slabs, round geodes, shards, molten blobs,
    banded stones, star clusters;
  - surface: SmoothPlastic/Slate/Basalt/Glass/Foil/Neon accents (Neon only on veins/tips so bloom stays readable);
  - two-tone tips and veins (light + dark of the same hue) so it reads under bloom.
- **Rarity readability:** Common = no glow; Uncommon = faint veins; Rare = glowing veins; Epic = glow + slow sparkle
  particles; Legendary = strong glow, rays on reveal, PointLight; Mythic = animated pulse, orbiting motes, unique
  reveal sound. Keep hue families far apart (check two ores side by side in a preview render).
- **Dirty state:** raw ore is a dull rock with a hint (tiny colored glint) only; rarity is revealed by cleaning.
- **Blaster skin:** the blaster forged from an ore uses that ore's Color/Glow on its core, barrel rings and laser
  color; higher tiers add more parts (fins, coils, glowing crystal core).

## Budgets
Raw chunk ≤ 6 parts, clean ore ≤ 8, ingot ≤ 4, ore on a podium ≤ 14 + 1 light (Legendary+ only), rock with ores
≤ 20 parts. Particles pooled (src/client/Effects/Vfx.luau), no per-ore emitters left running off-screen.

## Always finish with pictures
Render all ores side by side (add a gallery scene/shot, see preview-pictures skill), look at the image, fix ores that
look alike or unreadable, then send the picture to the owner. Add a Lune test that every ore has all fields and that
no two ores share the same Color+Shape pair.
