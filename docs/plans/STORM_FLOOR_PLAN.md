# Stormglass Rift: the gate-8 mine floor (option 4, owner's yes 2026-10-20)

The balance study (docs/BALANCE_SIM.md, "Options for the flat 3h–5h stretch") showed that income stays flat from about
3h to 5h because blaster 8 opens no floor. The owner chose both options 3 and 4; option 4 is this floor.

- New floor **Stormglass Rift** (Id `StormglassRift`): gate blaster 8, elevator only, between the Sunken Palace and the
  Heartstone Core. It becomes **index 5**; the Heartstone Core moves to **index 6** (gate 9) and "Coming soon" to
  **index 7** (blaster 11). Floor logic that keyed on indices moves to Ids.
- Placement: about world (0, -310, -800), between the palace (y -220) and the core (y -400 .. -477); the area keeps to
  local y -25 .. +60.
- Look: dark indigo stone, electric yellow-white storm crystals, silver storm-catcher machinery with copper coils, a
  "Storm Crown" of thunderclouds with frozen lightning over the Giant Crystal plaza, crystal pylons with arcs.
- Budgets: ≤ 2,500 parts (MineKit.PartBudget), ≤ 24 lights; nothing Persistent.

## Ore tables (variant A2 from the sim owner "Návrhy strojů", balance_sim reads MineFloors directly since 4c96f1f)
Floor averages incl. 10 % crystal rocks: 4 → 62 → 958 → 12.8K → 77K → 395K (×3.9, ×3.9, ×3.7, ×6.0, ×5.1 per blaster
level); crystal tables 2.7–3.8× the floor average (the core 1.6×). 5–8 home ores per floor; OreData.Tier = the home
floor's gate.

| Floor (gate) | Ores | CrystalOres |
|---|---|---|
| 1 Greystone Quarry (1) | Coal 26, Copper 21, Tin 16, Iron 12, Quartz 9, Oakwood 7, Honeycomb 5, LeafOre 4 | Quartz 15, Oakwood 20, Honeycomb 25, LeafOre 25, Frostbite 10, Emberite 5 |
| 2 Ember Caves (3) | Frostbite 28, Emberite 22, Cobalt 17, Bogwood 13, Amber 9, Bronze 7, Silver 4 | Amber 20, Bronze 30, Silver 30, Gold 15, Jade 5 |
| 3 Deep Hollow (5) | Gold 22, Jade 20, Sapphire 18, DragonEgg 16, Diamond 13, Amethyst 11 | Diamond 20, Amethyst 30, Obsidian 30, CrystalRose 20 |
| 4 Sunken Palace (7, elevator) | Obsidian 12, CrystalRose 18, StormPearl 22, GalaxyStone 24, RoyalAurum 24 | RoyalAurum 30, Sunstone 35, Moonstone 35 |
| 5 Stormglass Rift (8, elevator) | Sunstone 16, Moonstone 22, StormGem 26, LeafGem 22, VolcanicCore 14 | VolcanicCore 30, Aetherium 40, PhoenixFeather 30 |
| 6 Heartstone Core (9, elevator) | Aetherium 30, PhoenixFeather 25, DragonScale 20, CelestialCore 15, Heartstone 10 | DragonScale 30, CelestialCore 35, Heartstone 35 |

After landing: the sim owner re-calibrates the Foundry curve on the real tables (send the tip); the integrator lands it.

## Phases
A. Art + pictures (Floor5Storm.luau, storm rock look keyed by Id, previews) — owner sees the pictures.
B. Into the game: MineFloors (insert index 5, renumber, A2 tables, OreData.Tier), placement + zone + lighting preset,
   TrainConfig lift, RockBuilder/ElevatorView/ElevatorRideView/MineAmbience by Id, the elevator list with 7 cards,
   tests, world pictures, check.sh, ping the integrator.
