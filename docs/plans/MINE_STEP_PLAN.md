# Mine floors in the game (owner, 2026-10-17: "continue with the next step")

Design: docs/DESIGN_V2_NOTES.md "Mine floors", docs/plans/MINE_FLOORS_PLAN.md. Branch `art/mine-floors`.
The approved floor areas (src/server/World/Mine/Floor1Quarry … Floor5Core) become the real mine, the approved rocks
(RockBuilder) grow on their spawns, players blast them with the new HP/ore rules, see name + HP labels, watch them
crack and shatter, and ride the elevator (bought once) to floors 4–5.

## World placement (contract, MineFloors.Placement)
Every floor area is built with `Floor.build(parent, MineFloors.Placement[n], { Cutaway = false })`; +Z of the
placement (front, entrance) faces the previous floor / the town.

| Floor | Origin (ground center) | World box (x, z) | Replaces | Connections |
|---|---|---|---|---|
| 1 Greystone Quarry | (0, -12, -180) | -70..70, -240..-120 | Land's quarry pit | front: the town ramp x -8..8 from (0,0,-112) to (0,-12,-140); back: opening x -9..9, 16 high at z -240 straight into floor 2; east wall: the VIP Grotto door at z -188..-176 |
| 2 Ember Caves | (0, -12, -300) | -68..68, -240..-360 | Land's Ember Caves room + tunnel | front opening x -9..9 at z -240; back: the ramp down to floor 3 starts at (0,-12,-354), opening x -11..11 in the back wall |
| 3 Deep Hollow | (0, -40, -444) | -68..68, -386..-502 | Land's Deep Hollow room | front: the ramp from floor 2 ends at (0,-40,-394), opening x -11..11 at z -386 |
| 4 Sunken Palace | (0, -220, -800) | -66..66, -744..-856 | new | elevator only (far north and deep: never streams in near the town) |
| 5 Heartstone Core | (0, -400, -800) | -80..80, -730..-870 | new | elevator only; a dark void enclosure and a void catcher under the islands (above FallenPartsDestroyHeight -700, default.project.json) |

Land builds the town ramp, the tunnel/ramp between floors 2 and 3 (z -360..-386) and the grotto tunnel; the floors
leave the openings. The train session's pieces stay exactly where they are (Railway, TrainConfig): the Mine Station
(platform x 12..40, z -150..-144), the quarry line z = -156 (x -72..72) with portals at the quarry walls, the Mine
Lifts EmberCaves (22, -12, -258) and DeepHollow (16, -40, -402); floors 1–3 keep those boxes clear (WorldLayout.KeepOut)
and do not build their own ore lift in the game. Floors 4–5 get Mine Lifts in TrainConfig.Lifts at their designed
lift spots (Railway builds them). WorldLayout.Zones / WorldLayout.Caves follow the new boxes (lighting presets:
Quarry, EmberCaves, Lagoon, Palace, Core).

## Work packages (each owns its files)
| WP | Owner | Files | What |
|---|---|---|---|
| World | lead | MineFloors (Placement), WorldLayout, Land, WorldBuilder, TrainConfig (lifts 4–5), World/Railway tests | place the 5 areas, zones, keep-outs, spawn markers from the floors' RockSpawns/GiantSpawn (attributes Zone, Floor, Deep, Kind), bump WorldBuilder.Version, rebake |
| Floors | floor agents | src/server/World/Mine/Floor<N>*.luau | in-game mode: the openings and clear boxes above, no own ore lift in the game (MineKit.oreLift only when Cutaway), floor 5 void enclosure + "VoidCatcher" part |
| Mining | lead | MiningService, tests/Mining.spec | floor rocks: kind roll (MineFloors.SpawnChance, Deep spawns favor crystals), ores from Ores/CrystalOres, HP MineFloors.rockHealth, gate MinBlaster, one ore per stage (N ores → stages at k/N HP, the last at the shatter), RockBuilder visuals + applyStage, Giant Crystal event (every Interval, shared HP, reward for ≥ MinDamageShare), attributes Floor/Kind for the labels |
| Client | client agent | MiningController, FxController, Vfx (+ RockLabel) | RockLabel over the ~12 nearest rocks (name, HP, "Lv N" when locked) replacing the old aimed-rock info sign; breaking animation: stage pop (pieces fling, glow cracks), shatter burst (debris chunks + crystal shards in the rock's colors, dust, flash, sound), works on phone (pooled, capped) |
| Elevator | elevator agent | ElevatorService (server), ElevatorController + ElevatorView (client), Net, DataTemplate, init ORDER lists, tests | prompt at every MineElevator stop: "Buy Elevator $X" (once, EconomyService.spend, saved) / "Use Elevator"; floor picker (floors 1–5 + "Coming soon" 6, locked if blaster < MinBlaster); teleport to the target stop; VoidCatcher → back to the floor's Entrance; mouse, touch, gamepad |

Every WP: strict Luau, `lune run tools/lune/test.luau` 0 failed, previews where visual; the lead integrates, runs
`bash tools/check.sh`, rebakes, renders the town + every floor in the real map, commits and pushes.

## Parts and streaming (integrator's model, 2026-10-18)
Budgets: `LobbyLayout.Budget.MapParts` = 32,000 counts the floors; every floor ≤ `MineKit.PartBudget` 2,500 and
floors 1–3 (they stream near the town) ≤ `MineKit.NearPartBudget` 1,250 (tests/MineFloorAreas.spec.luau). The floors
use the default per-part streaming (nothing Persistent, so tests/PhoneBudget.spec.luau doesn't count them).

| Floor (game build) | Before trim | After trim |
|---|---|---|
| 1 Greystone Quarry | 1,462 | 1,125 |
| 2 Ember Caves | 1,776 | 1,187 |
| 3 Deep Hollow | 1,688 | 1,144 |
| 4 Sunken Palace | 2,720 | 2,350 |
| 5 Heartstone Core | 2,824 | 2,353 |

Measured with every BasePart of the built map within StreamingTargetRadius 384 (3D) of an eye at y 4 (map v27,
28,201 parts in all; the persistent Horizon adds its parts outside that radius):

| Spot | Parts within 384 | of which mine floors |
|---|---|---|
| worst lobby spot: the quarry ramp top (10, 4, −122) | 20,458 (21,928 before the trim) | 3,363 |
| inside floor 1 (0, −8, −180) | 20,592 | 3,364 |
| inside floor 2 (0, −8, −300) | 15,532 | 3,364 |
| inside floor 3 (0, −36, −444) | 9,935 | 4,019 |
| floor 4 (0, −216, −800) / floor 5 (0, −396, −800) | 5,396 / 4,799 | 5,167 / 4,651 |

Without the floors the quarry ramp top is ~17.1k. Agreed with the integrator: keep StreamingTargetRadius 384 and
revisit a smaller radius only if a Studio phone test (device emulator, low memory) shows trouble at the quarry rim.
