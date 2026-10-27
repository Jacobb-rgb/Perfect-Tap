# Terra Forge – Game Design

> The numbers below are a readable summary. The source of truth is the config
> modules in `src/shared/Config/`. Change balance there, not here.

## Lore (original)
Terra was once whole: a world forged around the **Heartstone**, a living ember
at its core. When the Heartstone cracked, its shards sank into the rock as
glowing ores, and the land cooled and fell asleep.

The **Forgekeepers' Guild** rekindled the **Great Forge** in **Emberfall**, the
last town on the rim of the Ember Caldera. You arrive as an apprentice
Forgekeeper. Dig through the crust, free the glowing cores, clean them by hand,
smelt them into ingots and forge gear. Every Heartstone shard you bring back
gets the Guild closer to reforging the heart of Terra.

Places:
- **Emberfall** – the hub: Great Forge, Pell's Trading Post (sell), Forgemaster Ulda's Tool Smithy (shop), daily Ember Chest.
- **Forge Plots** – 8 workshop plots around town; each player gets one.
- **Starter Outcrops** – small copper/iron rocks right next to the plots (tutorial).
- **Greystone Quarry** – open pit north of town (Copper, Iron, Silver, rare Gold).
- **Ember Caves** – dark, lava-lit caves (Emberite, Gold, Azurium).
- **Deep Hollow** – the deepest cavern (Verdantine, Stormcore, Solarite, Heartstone).
- **Glimmer Grotto** – VIP cave with dense Silver/Gold/Emberite nodes.

## Core loop
1. Mine a node with your pickaxe. It cracks in 3 visible stages and spits out
   **physical raw ore chunks**.
2. Pick chunks up, carry them (stacked in your arms) or throw them.
3. Put a raw chunk on your **Cleaning Station** → close-up minigame:
   **spray-wash** the dirt off (owner's pick, 2026-10-20: like his pressure-washer video) →
   "% CLEAN" fills → the ore rises and spins → grade (speed, aim, cracked crystals).
4. Optional **Crusher** (1 clean ore → 2 crushed piles = more ingots).
5. **Furnace** smelts clean or crushed ore into an **ingot**.
6. **Anvil** forges ingots into **gear** (worth the most).
7. Sell at Pell's Trading Post (or a Sell Chute on your plot). Money buys
   better pickaxes, carry upgrades, machines and speed upgrades.

## Rarities
| Rarity | Color | Dirt thickness | Crystals | A good clean |
|---|---|---|---|---|
| Common | light grey | 1.0 | 0 | ~5 s |
| Uncommon | green | 1.12 | 0 | ~5 s |
| Rare | blue | 1.25 | 2 | ~5 s |
| Epic | purple | 1.4 | 3 | ~5 s |
| Legendary | gold | 1.55 | 4 | ~5 s |
| Mythic | pink-red | 1.7 | 5 | ~5 s |

The dirt is a 14×14 grid of cells over the clump (CleaningPatterns); the spray washes every cell within its reach
(SprayScoring). The jet is wide and strong (owner 2026-10-25: "clean in 5-7 s"): a steady sweep washes even thick
Mythic dirt in one pass, so a good clean takes about 5 s on every rarity (a slow careful one ~7 s, scribbling ~8-10 s).
Spraying a glowing crystal point-blank for a third of a second cracks it; a moving pass never stays that long, so the
crystals only cost a player who parks the jet on them (rarer clumps no longer take longer: thicker dirt or touchier
crystals would bring that back if the owner wants it). A steady sweep at par pace is Flawless, a slow careful one
Pristine, scribbling with the spray always on mostly Clean (anything from Rough to a lucky Flawless)
(tools/lune/spray_calibrate.luau).

## Ores
| Ore | Rarity | Pickaxe tier | Base value | Node HP | Where |
|---|---|---|---|---|---|
| Copper | Common | 1 | 6 | 6 | Outcrops, Quarry |
| Iron | Common | 1 | 9 | 8 | Outcrops, Quarry |
| Silver | Uncommon | 2 | 20 | 14 | Quarry, Grotto |
| Emberite | Uncommon | 3 | 34 | 20 | Ember Caves, Grotto |
| Gold | Rare | 3 | 60 | 26 | Quarry (rare), Ember Caves, Grotto |
| Azurium | Rare | 4 | 100 | 36 | Ember Caves |
| Verdantine | Epic | 5 | 180 | 50 | Deep Hollow |
| Stormcore | Epic | 5 | 300 | 64 | Deep Hollow |
| Solarite | Legendary | 6 | 600 | 90 | Deep Hollow |
| Heartstone | Mythic | 7 | 1500 | 130 | Deep Hollow (very rare) |

## Item values
`value = ore base value × stage multiplier × grade multiplier`

| Stage | Multiplier | Notes |
|---|---|---|
| Raw chunk | 0.4 | can be sold, but cleaning is always better |
| Clean ore | 1.0 | |
| Crushed pile | 0.75 each | Crusher makes 2 → 1.5 total |
| Ingot | 1.25 | 1 clean ore or 1 crushed pile → 1 ingot |
| Gear | ingots × 1.25 × recipe bonus | Dagger 1 ingot ×1.5, Tool Head 2 ×1.6, Helm 3 ×1.7, Greatsword 4 ×1.9 |

Grades: **Rough ×1.0, Clean ×1.3, Pristine ×1.7, Flawless ×2.4**.
The Auto Cleaner only produces Rough or Clean, so hand-cleaning rare ore stays worth it.

## Pickaxes (Tool Smithy)
| Pickaxe | Tier | Damage | Swing cooldown | Price |
|---|---|---|---|---|
| Stone | 1 | 2 | 0.60 s | free |
| Copper | 2 | 3 | 0.55 s | 200 |
| Iron | 3 | 5 | 0.50 s | 900 |
| Emberite | 4 | 8 | 0.45 s | 3,500 |
| Azurium | 5 | 12 | 0.42 s | 12,000 |
| Stormcore | 6 | 18 | 0.38 s | 40,000 |
| Solarite | 7 | 28 | 0.34 s | 125,000 |

## Carry upgrades
Hands (1) → Ore Sling (2, 300) → Miner's Harness (3, 1,500) → Ore Frame (5, 6,000) → Titan Frame (8, 25,000).
The *Strong Back* pass doubles it.

## Machines (placed on your 12×12 plot grid, 4 studs per cell)
| Machine | Size | Price | What it does |
|---|---|---|---|
| Storage Crate | 2×2 | 150 | crates share one store: 60 per crate, 300 max; take items out again |
| Cleaning Station | 3×2 | 250 | the hand-cleaning minigame |
| Furnace | 2×2 | 500 | crushed ore → ingot, 6 s. Queue: 4 items. The one furnace (owner 2026-10-24): the Tech shop's Furnace Upgrade turns every furnace into Brick (4 s, no power), Blast (2.5 s, 20 power) and Plasma (2.5 s, 2 at once, 60 power) |
| Crusher | 2×2 | 450 | clean ore → 2 crushed piles, 3 s. Queue: 4 items |
| Anvil | 2×2 | 600 | holds 4 ingots of one ore; 3/4/5/6 hammer taps make a Dagger / Tool Head / Helm / Greatsword |
| Auto Cleaner | 2×2 | 2,500 | raw → clean, 8 s: 60% Rough / 40% Clean. Queue: 4 items |
| Sell Chute | 1×1 | 1,200 | sells anything dropped in; pays the item's owner |
| Conveyor | 1×1 | 25 | moves items 7 studs/s, 4 rotations; players walk through |

New players start with a Cleaning Station, a Furnace and a Crusher behind it (the Furnace takes crushed ore only).
Drop or throw items into the hopper on top, or run a belt into any side
except the output front (crates and Sell Chutes take all sides). Results go
out of the front cell (the right front cell on 2-wide machines), straight
into a machine standing there if it takes them. A machine holds up to 4
finished items while its front is blocked. Wrong items bounce back out with
a hint; items owned by someone else only go into Sell Chutes.

### Build controls
| Action | PC | Touch | Gamepad |
|---|---|---|---|
| Open / close build mode | B or the BUILD button | BUILD button / Done | D-pad Up / B |
| Pick a machine | click a card in the tray | tap a card | LB / RB |
| Move the cursor | mouse | tap a cell | left stick |
| Rotate | R | Rotate button | X |
| Place | left click (drag to paint belts) | Place button | A |
| Select a placed machine | click it | tap it | cursor on it |
| Move / pack up the selection | M / X or Delete | Move / Pack Up buttons | Y |
| Cancel | right click or C | Cancel button | B |
| Pan the camera | WASD or right-drag | one-finger drag | right stick |
| Zoom | mouse wheel | pinch | LT / RT |

Belts auto-advance one cell after placing, so you can lay a line by placing
again. The ghost turns red with the reason when a spot doesn't work.

Speed upgrade *Bellows* (5 levels, −10% machine time each): 500 / 1,500 / 4,000 / 10,000 / 25,000.
Machine slots: 10 (+3 for 1,000, +3 for 5,000, +6 with *Workshop Expansion*). Conveyor slots: 40 (+20 with the pass).

## Retention
- **Daily Ember Chest**: 7-day streak (100 → 2,000 coins, scaled by pickaxe tier; day 7 also gives a raw Gold chunk).
- **Tutorial**: mine → pick up → clean → smelt → sell, about 2–3 minutes, rewards 250 coins.
- **Badges**: Welcome, First Ore, First Clean, First Flawless, First Legendary, First Mythic, First Gear, Tutorial Done, Tycoon (100k earned).
- **Ore Codex**: tracks discovered ores (saved).
- **Group reward**: 500 coins once for joining the group.

## Monetization (fair, not pay-to-win)
- Game passes: *Strong Back* (2× carry), *Forge VIP* (Glimmer Grotto + VIP tag), *Workshop Expansion* (+6 machine, +20 conveyor slots).
- Developer products: coin pouches (small/medium/large/huge).
- Nothing sold is exclusive power: every ore can be mined by every player.
