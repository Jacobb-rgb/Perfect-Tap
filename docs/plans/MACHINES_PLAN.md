# Machines plan (design v2): the full machine roster

Owner decisions from 2026-10-17 (chat, translated from Czech). This extends docs/plans/STEP3_PLAN.md (belts, Iron Box,
Cleaning Plant upgrades, Foundry, Tech shop) with the complete list of machines the game will have. Looks are designed
next (pictures first, owner approves), then built in the Kenney Factory Kit style from Roblox parts
(docs/KENNEY_FACTORY_KIT.md, .claude/skills/kenney-style-builder).

## Roster (24 placeable machines + 3 fixed base buildings)
Status: **have** = in MachineData.luau and working, **planned** = in STEP3_PLAN, **new** = added on 2026-10-17.

### Cleaning and sorting
| Machine | Status | What it does |
|---|---|---|
| Cleaning Station | have | hand cleaning minigame, Raw → Clean with a grade |
| Cleaning Plant (Auto Cleaner) | have | Raw → Clean on its own; Speed + Quality upgrades (STEP3_PLAN) |
| Iron Box | planned | reveals the ore; keep list → pen, the rest leaves on belts |
| Sorter | new | routes items by rarity: below a chosen rarity out one side, the rest out the other |
| Polisher | new | tries to raise a Clean item one grade (Clean → Pristine → Flawless); more podium income |

### Furnaces (a ladder from the start of the game to the end)
| Machine | Status | What it does |
|---|---|---|
| Clay Furnace | have | Clean/Crushed → Ingot, slow (6 s), starter kit |
| Brick Furnace | new | the owner's "normal furnace" for beginners and slightly advanced players, between Clay and Blast (~4 s) |
| Blast Furnace | have | fast (2.5 s), 3×3 |
| Plasma Furnace | new | end game, fastest, sci-fi neon look |
| Alloy Furnace | new | 2 different ingots → 1 alloy ingot for stronger blasters (new item kind; recipes to design, may come later) |

### Processing and special
| Machine | Status | What it does |
|---|---|---|
| Crusher | have | 1 Clean → 2 Crushed (twice the ingots) |
| Crystal Extractor | new | Crushed ore sometimes yields a shard (Enchant shop currency) |
| Restoration Table | new | cleans a found artifact so it can go to the base museum |
| Sell Box | new | items that ride into it are sold to Tobin automatically (30 s of podium income, like the stall); brings back the retired Sell Chute idea because the owner wants everything except mining automated |

### Transport
| Machine | Status | What it does |
|---|---|---|
| Conveyor | have | 7 studs/s (ConveyorService still missing, STEP3_PLAN WP-Belts) |
| Express Conveyor | new | 2× faster, pricier |
| Splitter | new | one belt in, alternates items between two outputs |
| Belt Lift | new | carries items up one floor (factories can grow upward) |
| Slide | new | items slide down one floor, cheap (the opposite of the lift) |
| Robot Arm | new | picks an item up and hands it to a belt or a machine; a showpiece when it moves |

### Power (new system)
| Machine | What it does |
|---|---|
| Solar Panel | weak, free power; for the start |
| Wind Turbine | medium; spins, looks good on the base |
| Fusion Reactor | strongest, end game, neon glow |
| Power Pole + cable | carries power from generators to machines |

Owner rules: **power goes through cables and poles** (owner chose this over base-wide power); **too little power slows
machines down** (they never stop, nothing is lost). Coal power was offered and not chosen.
Claude's proposal for the cables so they work well on phones and gamepads: poles link to each other automatically when
placed within range (a cable is drawn between them), and every machine inside a pole's range is powered; no manual cable
dragging. Machine speed = min(1, supply / demand) for the whole connected network.

### Fixed base buildings (not sold in the Tech shop)
Foundry (ingots → blasters), Ore Pen, Podiums.

## Looks
Owner (2026-10-17): build the machines **from the Kenney Factory Kit** (the pipes with water into the cleaner too:
"everything in the kit looks great"), **iron first**, and upgrades grow crystals: small shards first, after 3-4 upgrades
the whole machine is crystal.
- Concept: src/shared/Builders/KitMachines.luau (part-built kit pieces: machine housings, pipe-large + bends + valves +
  glass pipes with water / molten metal, hoppers, piston tanks, cogs, stack lights, screen panels, robot arm, scanner
  arch), same contract as MachineBuilder so it can replace it. Cleaning Station, Clay Furnace, Crusher, Cleaning
  Plant (Auto Cleaner) and Blast Furnace are done; the conveyor still uses MachineBuilder.
- Upgrade looks (KitMachines.build(id, level, theme)): L0 iron · L1 two small crystal clusters · L2 four clusters, the
  orange trims turn crystal · L3 six bigger clusters, frames / flanges / pipes turn crystal, a soft light · L4 (max) the
  whole machine is crystal (see-through body, glowing inside), a hero crystal on top, sparkles. Crystal colour themes:
  Aqua, Amethyst, Rose (owner to pick).
- Preview: scene `kit_machines` (tools/lune/lib/kit_machines_gallery.luau, shots tools/preview/kit_machines_shots.json),
  pictures docs/screenshots/kit_*.jpg. Tests: tests/KitMachines.spec.luau (contract at every level, footprints, FX
  part names, part budgets: 140 at L0, 240 at max, 280 for 3x3).
- Not decided yet: how the look level maps to the planned upgrades (MachineUpgrades Speed/Quality), the crystal theme,
  whether the kit's blue-purple colour is wanted instead of iron.

## Open questions
- The owner also ticked "Something else" under special machines without saying what; ask.
- Footprints, power use, prices and upgrade curves (economy step; prices must be exponential, DESIGN_V2_NOTES round 3).
- Plot space: the grid is 12×12 cells with 10 machine slots (+3, +3, +6 pass). With 24 machine kinds, power poles and
  floors, the slots and/or the plot size need to grow; the Belt Lift and Slide imply a second floor.
- Alloy recipes and what alloys give the blaster.
