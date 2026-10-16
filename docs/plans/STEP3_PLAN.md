# Step 3 plan (design v2): machines + automation + the Foundry

Part of docs/plans/V2_PLAN.md. Owner's words (DESIGN_V2_NOTES): with money you buy machines (furnaces, conveyors,
smelters, crushers, cleaners) in the **Tech shop**; you clean by hand only **until you buy the automatic cleaner**,
whose upgrades make it clean **better** (grade cap up to Flawless) and **faster**; every machine has upgrades; from the
cleaner the ore drops into an **Iron Box** where you see what it is and choose what to **keep** (pen → podium) and
what to **send on**; in the pen you take out what you don't want and press **Send**: items slowly move onto the
**conveyors** and ride to the cleaner / further machines, the route depends on how you build; smelted ore → **ingots**
→ the **Foundry** makes **blasters** (10 levels, look follows the ore); with a high enough **pen upgrade** the train
dumps raw ore straight into the cleaning line; a **sorting billboard** (pen upgrade) marks ore types to keep.

## The factory at a glance
```
 train ──(Direct Unload upgrade)──► TRAIN CHUTE cell ─belts─► CLEANING PLANT ─► IRON BOX ─keep─► Ore Pen ─► podiums
 Ore Pen ──"Send"──► PEN CHUTE cell ─belts─► CRUSHER / FURNACE ─► ingots ─belts─► FOUNDRY CHUTE cell ─► FOUNDRY
                                                                  IRON BOX ─send on─► belts ─► …
```
The three chute cells sit on the back row of the 12×12 grid (next to the yard). They are fixtures: only conveyors may
be placed on them (Placement refuses other machines there, the grid shows them with a colored plate and an icon).

## P0 contracts (integrator, before the packages)
| File | What |
|---|---|
| src/shared/Config/BaseLayout.luau | `Chutes = { Pen = {gx, gz, dir}, Foundry = {…}, Train = {…} }` on the back grid row + their world points |
| src/shared/Config/MachineData.luau | `IronBox` (2×2, Processing, accepts Clean/Crushed/Ingot/Raw, takes belts on all sides but the front), upgrade tables per machine: `Upgrades = { Speed = { prices… }, Quality = { prices… }? }`; Auto Cleaner renamed in UI "Cleaning Plant" with `QualityLevels` grade odds (L0 60/40 Rough/Clean … L5 0/20/50/30 Clean/Pristine/Flawless) |
| src/shared/Machines/Placement.luau | chute cells: conveyors only |
| src/server/Data/DataTemplate.luau | `MachineUpgrades = { [machineId] = { Speed = 0, Quality = 0 } }`, `KeepList = {}` (ore ids the Iron Box/pen keep), `Foundry = { Stock = {} }` (ingot descs), `Upgrades.PenAutomation = 0` (1 = sorting billboard, 2 = train Direct Unload) |
| src/shared/Net.luau | `PenAction "Send" {Key?, Count, Filter?}`, `IronBoxAction`, `FoundryAction ("Forge" {Ore}, "Strike"…)`, `ShopBuy {Shop, Item, Count?}`, server→client `FoundryBegin/FoundryResult` |
| src/shared/Config/EconomyConfig.luau | Tech shop catalog (machines + prices), machine upgrade price curves, PenAutomation prices |
| tests | contracts tested (Config, Placement chutes, Migration of the new fields) |

## Packages
### WP-Belts: conveyors and the pen "Send"
Owns: src/server/Services/ConveyorService.luau (new), PenService (Send queue), PenView (Send buttons), tests.
ConveyorService as in docs/plans/STEP_D_PLAN.md "WP-Conveyor" (belt velocity, walk-through collision group, open rail
sides, jam nudges, cheap on mobile). Pen "Send": queue per player, one item every 0.5 s spawns on the PEN CHUTE cell
and rides the belts (stays in the pen when the player leaves or the chute is blocked); "Send all dirty", "Send this".

### WP-CleanerBox: Cleaning Plant upgrades + Iron Box + sorting billboard
Owns: ProcessingService (quality odds by upgrade level, speed by upgrade), MachineBuilder (Iron Box model in the
Factory Kit style of the restyled machines), IronBoxService (new), IronBoxView (keep-list: discovered ores as
toggles, defaults Rare+), the pen sorting billboard (PenAutomation 1), tests.
Iron Box: reveals (items are clean already), items on the keep list go to the pen (bounce out the front when full),
the rest leave the front onto belts; a small screen shows the last item and a counter.

### WP-Foundry: ingots → blasters
Owns: FoundryService (new), FoundryController + FoundryView (new), PlotBuilder Foundry building (replace the
placeholder: Factory Kit furnace with crucible, molten channel, anvil and a blaster rack), tests.
FOUNDRY CHUTE cell absorbs ingots into `Foundry.Stock`; ingots can also be thrown into its hopper. UI shows the stock and
the next level's recipe (BlasterData.Levels[n].Recipe: N ingots of MinRarity+, coins); "Forge" picks the skin ore (the
best ore among the used ingots by default) and starts the hammer moment (every tap counts; PERFECT/GOOD only changes
the effect; server checks the strike timing like the old anvil plan); success: ingots + coins taken, BlasterLevel + 1,
BlasterOre = skin, Stats.BlastersForged, a big reveal of the new blaster; level 11 shows "Coming soon".

### WP-TechShop: buying machines and upgrades
Owns: ShopService (new, ShopBuy), TechShopController + TechShopView (new), the UpgradeCounter prompt, tests.
Catalog: Conveyor, Crusher, Clay/Blast Furnace, Cleaning Plant, Iron Box (+ counts), per-machine Speed/Quality upgrades,
Bellows, slot upgrades, PenAutomation; prices from EconomyConfig (exponential), EconomyService.spend, MachineInventory.

### Also in this step
- Direct Unload (PenAutomation 2): TrainService delivers raw cargo onto the TRAIN CHUTE cell instead of the pen (needs
  step 2's TrainService).
- Gear items and the Anvil stay retired; GAME_DESIGN.md gets the v2 machine table.

## Done when
A player can: buy belts + a Cleaning Plant + Iron Box + furnace in the Tech shop, place them, Send dirty ore from the pen,
watch it ride through cleaner → box (keep list) → furnace → Foundry chute, forge a level-2 blaster in the Foundry with
the hammer moment, and upgrade the cleaner to get better grades. QA: no item dup across pen/belts/box/foundry, no lost
items on leave, belts cheap on phones, all inputs. Pictures: a full factory line on a plot, the Foundry forging.
