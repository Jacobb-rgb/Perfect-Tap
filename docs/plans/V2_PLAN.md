# Terra Forge v2 – build plan (2026-10-16)

Source: the owner's design in docs/DESIGN_V2_NOTES.md (overrides GAME_DESIGN.md where they conflict) and the old
"Next steps" in docs/HANDOFF.md. This file says what stays, what changes, what is new, and the order of work.
Every step ends with: `bash tools/check.sh` (ALL CHECKS PASSED), QA review, docs/QA_REPORTS.md "test in Studio" list,
commit, push, preview pictures for the owner (Czech caption).

## 1. The v2 loop in one line
Blast rocks with a laser blaster → dirty ore chunks drop → throw them into your cart at the mine station → your own
train brings them to your base → ore pen → clean them (by hand, later the Cleaning Plant) → best ores on podiums earn
money per second (also offline) → buy machines, gear and upgrades → smelt ingots → the Foundry forges stronger
blasters → deeper zones, rarer ores, artifacts and the story of Kaldrum.

## 2. What stays, what changes, what is new

### Stays (works as it is)
| Part | Notes |
|---|---|
| Tooling, Rojo, tests, preview renderer, Net/Guard, DataService/ProfileStore | unchanged; save Version goes 2 → 3 |
| World: island, Emberfall, 8 plots, quarry, Ember Caves, Deep Hollow, Glimmer Grotto (VIP) | zones keep; ore tables grow |
| Physical chunks, pick up / carry / throw (PC, touch, gamepad) | raw chunks become "dirty ore" |
| Cleaning Station minigame | now the reveal + value booster; manual only until the Cleaning Plant is bought |
| Machines core, IntakeService, ProcessingService, build mode, grid, conveyor logic | the processing chain into the Foundry |
| Clay / Blast Furnace (ore → ingot), Crusher (1 → 2) | unchanged rules |
| Lobby art direction + plan (docs/plans/LOBBY_PLAN.md, Style kit) | districts get the v2 stalls (section 5) |
| Store page, compliance guide | updated for capsules, boosts, trading |

### Changes
| Old | New |
|---|---|
| Pickaxes (7, Tool Smithy) | **Blasters**: hold to fire a laser, rock cracks gradually; 10 levels + an 11th "Coming soon"; forged in the Foundry; look follows the ore |
| 10 ores, ore nodes with one ore | **30 ores** (rarity, spawn weight, value per second, own look); **rocks** with 1–3 ores, rarer deeper, small artifact chance |
| Raw ore shows its name | **Dirty ore** hides its identity ("Dirty Ore ???", tiny colored glint) until cleaned |
| Storage Crate (shared pool) | **Ore Pen** built into every base (the same pool code, from the StorageSell WIP); capacity upgrades; pen UI |
| Selling at Pell's / Sell Chute | money comes from **podiums**; unwanted ore is sold at the **Sell stall** (miner NPC) in town; Sell Chute removed |
| Anvil + gear items | **Foundry** (fixed on every base): ingots in → next blaster level out; the anvil "tap to hammer" moment moves here |
| Auto Cleaner (60 % Rough / 40 % Clean) | **Cleaning Plant** with upgrades (speed, grade cap up to Flawless); bought in the Tech shop |
| Tool Smithy / UPGRADES | **Gear shop** (boots, helmet lamp, backpack, gloves, magnet) + **Tech shop** (automation machines) + **Enchant shop** (blaster perks) |
| Coins as plain numbers | big numbers K, M, B, T, Qa, Qi, Sx…; exponential price curves |
| Daily Ember Chest (7-day streak) | **Wheel of fortune**: 1 free spin per day (timer runs while offline), odds on the wheel |
| Tutorial mine → clean → smelt → sell | mine → cart → train → pen → clean → podium (< 3 min) |
| Game passes Strong Back / Forge VIP / Workshop | **Big pass (~560 R$)**: podiums 3–4, offline 12 h, more perks; podiums 3–4 alone 100 R$; offline extension 99 R$; train upgrade 150–200 R$; luck boosts; capsules; 2 rarest enchants 20 R$ |

### New systems
Per-player **trains** (mine station cart → coastal railway → base station → pen) · **podiums** (2 free + 2 locked,
income/s, "Remove" on hover/select) · **offline earnings** (50 % for 5 h, 12 h with the extension, "While you were
away" popup) · **automation** (pen "Send" onto conveyors, train → Cleaning Plant with a pen upgrade, **Iron Box**
after the cleaner to keep or send on, pen sorting billboard) · **golem pets** from **capsules** (coins and Robux,
open x1/x3/x10, Triple Lucky, Common→Mythic, 3 equipped, each gives a bonus) · **artifacts + story** (Kingdom of
Kaldrum, collections unlock chapters, collection book + museum on the base) · **4 leaderboards** (Money/s, Total
earned, Artifacts, Hours played) · **trading** (golems and ores only, two-step confirm) · **calm music** per area
· **rebirth** (later update, +25 % money each).

## 3. The base (plot) in v2
The 12×12 machine grid stays where it is. Each plot gets a **yard** on its sea side (outside the grid, toward x = ±160):
the **Ore Pen** (fenced, items you throw in are stored), **4 podiums** in a row (2 free, 2 locked with a Robux sign),
the **Foundry**, and the **train station** on a **coastal railway** that runs behind all plots from the mine.
New players get the Cleaning Station and a Clay Furnace on the grid (Storage Crate gone).

## 4. Order of work
| Step | Content | Old "Next steps" item it covers |
|---|---|---|
| **1. Core v2 loop** | 30 ores + rocks + dirty ore; blasters (levels 1–10 data, hold-to-fire, laser VFX, all inputs); Ore Pen; podiums + money/s + offline earnings + big numbers HUD; Sell stall (miner NPC); save Version 3 migration | 1. Storage + selling |
| **2. Trains** | mine station carts, per-player train on the coastal railway, base station → pen, train upgrades (capacity, speed) | new |
| **3. Machines + automation** | ConveyorService; pen "Send"; Cleaning Plant with upgrades + Iron Box; Foundry (replaces the Anvil) → blasters; pen sorting billboard; machine upgrades | 1. Conveyors + Anvil |
| **4. Lobby like the concept** | the 5 packages of LOBBY_PLAN (Sky, Backdrop, Plaza, Districts, Flora) with v2 stalls (section 5) | 2. Lobby |
| **5. Kenney look** | machines (Factory Kit), train (Train Kit), blasters (Blaster Kit), pen/podiums/foundry, golems (Mini Characters) | 3. Kenney restyle |
| **6. Economy + shops** | Gear shop, Tech shop, Enchant shop, side menu, price curves, balance simulation | 4. Step e |
| **7. Pets, wheel, artifacts, boards** | capsules + golems, daily wheel, artifacts + story + museum, 4 leaderboards | new |
| **8. Launch features** | tutorial, game passes + dev products (placeholders), badges, analytics, music + settings, trading, compliance update, PUBLISHING.md, Studio checklist | 5. Step f |
| **9. Owner test in Studio → publish** | the owner plays every QA list, then publishes; later updates: rebirth, new regions + story chapters | 6. |

The lobby (step 4) only touches src/server/World/Lobby/* and can run in parallel with steps 1–3.

## 5. Lobby stalls in v2 (concept element → use)
| Concept | v2 use | Hook |
|---|---|---|
| SHOP (pink awning) | **Gear shop** (boots, helmet lamp, backpack, gloves, magnet) | ShopCounter |
| sell bin + counter in front of SHOP | **Sell stall**, Tobin the miner NPC | SellCounter, SellBin(+Intake) |
| UPGRADES (purple awning) | **Tech shop** (automation machines, machine upgrades) | UpgradeCounter |
| SPIN & WIN | **daily wheel of fortune** | EmberChest → Wheel |
| ROCK SCANNER | **Ore Codex** (all 30 ores, found/not found) | OreCodex |
| FOSSIL DIG | **Artifacts + story** (collection book, chapters) | FossilDig |
| GuildBoard | story journal pages | GuildBoard |
| new small stalls on the plaza ring | **Capsule stall** (golems), **Enchant shop**, **4 leaderboards** | CapsuleStall, EnchantCounter, Leaderboard1..4 |
| THE GREAT FORGE | landmark (blaster gallery: levels 1–10 + "Coming soon") | – |

## 6. Decisions Claude made (the owner can change them)
1. Storage Crate, Sell Chute, Anvil and gear items are removed; their code is reused (pool → pen, selling → Sell
   stall, anvil tapping → Foundry).
2. Podiums take **cleaned** ore only (dirty ore has no known value). Income/s = ore value/s × grade
   (Rough 1, Clean 1.3, Pristine 1.7, Flawless 2.4) × bonuses (golems, passes, rebirth).
3. Selling at the stall pays about 30 seconds of that ore's podium income (dirty ore 40 % of that).
4. Blaster level N needs ingots (a minimum ore rarity per level) + coins; the blaster looks like the best ore used and
   gets a small bonus from its rarity. Power (damage per second) comes from the level.
5. One mine station at the quarry rim plus loading carts in Ember Caves and Deep Hollow; all of them fill the same
   personal train.
6. The miner NPC is called **Tobin**.
