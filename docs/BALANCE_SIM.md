# Balance simulation (2026-10-18)

A model of a typical player from the first minute to 10 hours, after the 36-ore roster from the owner's picture.
Script: `tools/lune/balance_sim.luau` (`lune run tools/lune/balance_sim.luau` for today's prices,
`... calibrate` for the price proposal); chart: `node tools/balance/chart.mjs` → `docs/screenshots/balance_chart.png`.
Raw output: `build/balance/sim.json`, `build/balance/proposal.json`. Nothing in the game config was changed.

![Money and income over 10 hours](screenshots/balance_chart.png)

## What the model does
- Reads the real config: OreData (36 ores, Income, Value = Income × 30), ItemData (grades, Raw 0.4 / Crushed 0.75 /
  Ingot 1.25), BlasterData (damage, Foundry recipes, Vault = 4 × coins), MachineData (prices, times, power),
  ToolData (carry), TrainConfig (capacity, trip seconds).
- Mine floors as built on `art/mine-floors` (MineFloors.luau): blaster gates 1 / 3 / 5 / 7 / 9, floors 4–5 only with
  the $500K elevator, rocks that the floor's weakest allowed blaster breaks in ~4.5 s, 3.3 ores per rock. Ore tables
  follow the mine chat's plan for the new roster: floor N = the Nth rarity; 10 % crystal rocks roll from the floor's
  best 3 ores (70 %) or the next rarity's cheapest 3 (30 %). Weights inside a table fall with value (1 / rank^0.8).
- Player loop per 5 s step: mine → carry to the floor's train (12 s walk per load) → train to the pen → clean by
  hand (18 s per ore + the trip back) until the first Auto Cleaner (8 s per ore, Quality 0 odds) → best 2 cleaned ores
  on the 2 free podiums → the rest sold, through the Crusher (×2) and furnaces (ingots ×1.25) when owned.
- Buying (greedy): the next blaster as soon as ingots + coins are there (Foundry) or the Vault is affordable; the
  elevator once floor 4 is in reach; hoverboards ($5K / $80K / $1.5M, walking × 0.8 / 0.65 / 0.5) when they cost at
  most a quarter of the coins; otherwise the machine / upgrade with the best payback under 20 min (carry levels, train
  capacity and speed, up to 4 Auto Cleaners, Crusher, Brick → Blast → Plasma furnace with the cheapest power).
- Player types: efficiency = how well the player's own actions go (mining, walking, hand cleaning); machines run full.
  Typical 50 %, Skilled 80 %, Casual 30 %. 120 players each (seeded ore draws), medians.
- Not modelled: golems, boosts, enchants, rebirths, capsules, artifacts (steps 6–7 are not on main yet), machine Speed
  / Quality upgrades, podiums 3–4 (Robux), offline earnings, the Grotto, Golden / Geode rocks and the Giant Crystal.

## Today's prices
| Milestone | Typical (50 %) | Skilled (80 %) | Casual (30 %) |
|---|---|---|---|
| Floor 1 | 0m 05s | 0m 05s | 0m 05s |
| First podium filled | 1m 05s | 0m 40s | 1m 50s |
| Blaster 2 | 3m 05s | 1m 55s | 4m 45s |
| First machine bought | 4m 30s | 3m 00s | 6m 30s |
| Floor 2 | 7m 35s | 4m 45s | 11m 05s |
| Blaster 3 | 7m 35s | 4m 45s | 11m 05s |
| Blaster 4 | 8m 50s | 6m 15s | 13m 00s |
| Hoverboard 1 ($5000) | 9m 30s | 6m 50s | 13m 35s |
| Floor 3 | 11m 55s | 8m 45s | 16m 50s |
| Blaster 5 | 11m 55s | 8m 45s | 16m 50s |
| Hoverboard 2 ($80000) | 12m 55s | 9m 40s | 18m 10s |
| Blaster 6 | 14m 00s | 10m 35s | 19m 35s |
| Blaster 7 | 21m 10s | 17m 15s | 29m 30s |
| Elevator bought | 21m 50s | 17m 50s | 30m 15s |
| Floor 4 | 21m 50s | 17m 50s | 30m 15s |
| Hoverboard 3 ($1500000) | 22m 55s | 18m 40s | 31m 55s |
| Blaster 8 | 26m 35s | 21m 45s | 37m 35s |
| Blaster 9 | 47m 35s | 41m 05s | 1h 05m |
| Floor 5 | 47m 35s | 41m 05s | 1h 05m |
| Blaster 10 | 1h 03m | 52m 30s | 1h 25m |

## Proposal: Foundry coin prices calibrated to a ~8 h journey
Targets for the Typical player: blaster 2 at 3 min, 3 at 12 min, 4 at 25 min, 5 at 45 min, 6 at 1h20, 7 at 2h,
8 at 3h15, 9 at 5h, 10 at 8h. Ingot recipes, Vault multiplier (4 ×) and everything else unchanged.

| Level | Today | Proposal | × today |
|---|---|---|---|
| 2 | 250 | 180 | 0.7 |
| 3 | 2,000 | 15,000 | 7.5 |
| 4 | 15,000 | 400,000 | 27 |
| 5 | 100,000 | 1,300,000 | 13 |
| 6 | 700,000 | 20,000,000 | 29 |
| 7 | 5,000,000 | 37,000,000 | 7.4 |
| 8 | 35,000,000 | 800,000,000 | 23 |
| 9 | 250,000,000 | 1,400,000,000 | 5.6 |
| 10 | 1,500,000,000 | 21,000,000,000 | 14 |

| Milestone | Typical (50 %) | Skilled (80 %) | Casual (30 %) |
|---|---|---|---|
| Floor 1 | 0m 05s | 0m 05s | 0m 05s |
| First podium filled | 1m 05s | 0m 40s | 1m 50s |
| Blaster 2 | 2m 50s | 1m 55s | 4m 10s |
| First machine bought | 4m 30s | 3m 00s | 6m 30s |
| Floor 2 | 12m 30s | 9m 40s | 16m 50s |
| Blaster 3 | 12m 30s | 9m 40s | 16m 50s |
| Hoverboard 1 ($5000) | 14m 25s | 11m 15s | 18m 50s |
| Hoverboard 2 ($80000) | 22m 35s | 18m 55s | 28m 45s |
| Blaster 4 | 26m 05s | 22m 10s | 32m 50s |
| Floor 3 | 47m 40s | 43m 05s | 56m 55s |
| Blaster 5 | 47m 40s | 43m 05s | 56m 55s |
| Hoverboard 3 ($1500000) | 58m 35s | 53m 50s | 1h 11m |
| Blaster 6 | 1h 19m | 1h 13m | 1h 36m |
| Blaster 7 | 1h 59m | 1h 53m | 2h 24m |
| Elevator bought | 1h 59m | 1h 54m | 2h 24m |
| Floor 4 | 1h 59m | 1h 54m | 2h 24m |
| Blaster 8 | 3h 15m | 2h 58m | 4h 01m |
| Blaster 9 | 5h 01m | 4h 36m | 6h 17m |
| Floor 5 | 5h 01m | 4h 36m | 6h 17m |
| Blaster 10 | 8h 00m | 6h 54m | 9h 53m (43 % reach it) |

The saw-tooth (cheap 5 / 7 / 9, expensive 6 / 8 / 10) comes from the floor gates: the odd levels open a floor whose ores
are worth about 10 × the floor before, so the level after it has to cost a lot more to keep the pace.

## Spots that look too fast or too slow
1. **Far too fast overall (today).** A typical player has blaster 10 and all 5 floors after about **1 hour** (casual
   1h25). After that nothing is left to buy: income stays flat for 9 hours (the orange line). Main causes: each floor's
   ores earn about 10 × the floor before while a blaster level costs about 7 × the one before; Auto Cleaners make the
   income independent of the player's time; Crusher + furnace turn every ore into 2.5 × its value.
2. **The cleaning minigame (the signature) is automated after ~3–6 minutes**: the first $5,000 Auto Cleaner pays back
   so fast that hand cleaning stops being worth it. A higher price (e.g. $25K–$50K) or the cleaner in a later step
   would keep the minigame alive for the first half hour.
3. **The elevator is trivial**: $500K arrives when blaster 7 costs $5M (today) or $37M (proposal). Proposal: about
   **$25M** (about 2/3 of blaster 7), so it is a real goal before floor 4.
4. **Hoverboards** ($5K / $80K / $1.5M) land at 14 / 23 / 59 min with the proposal (10 / 13 / 23 min today). The third
   one could cost more (e.g. $5M) to stay a goal past the first hour.
5. **Dead zones even with the proposal**: 3h15 → 5h (income flat at ~200K/s, nothing new to buy after the blaster 8
   machines) and 5h → 8h (saving for blaster 10). Steps 6–7 (golems, boosts, enchants, capsules, artifacts) and
   machine Speed / Quality upgrades should land as goals in these windows.
6. **Early game is fine**: first podium in about a minute, first machine at 3–6 min, blaster 2 at 2–5 min.
7. **Skill matters little later on**: Skilled and Casual players end only ~1 h apart from Typical, because machines
   do most of the work after the first hour. Player-driven bonuses (hand-cleaning quality, mining combos, Giant
   Crystal) would give active players more edge.

## Who decides
Blaster / step 6 prices and balance: "TERRA FORGE Roblox hra vývoj" (integrator). Floors, elevator and hoverboard
prices: the mine-floors chat. This file only proposes; nothing here changes the game.
