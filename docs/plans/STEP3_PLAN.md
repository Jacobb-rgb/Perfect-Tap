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

### P0 contract details (fix rounds 1 and 2, after the adversarial reviews)
- **Chutes** carry `Label`, `Color`, `Hint` for drawing them. A Source only spawns onto a belt standing on its cell
  whose front is not `SinkRotation` (`BaseLayout.sourceFeeds`: a belt running off the grid edge would drop the item
  loose in the yard) while that belt has room; with no such belt (or a jammed one) the pen's send queue waits and
  Direct Unload cargo goes into the pen. A Source never drops anything loose (the TRAIN cell is in the yard gate's
  walkway). **Sinks take only the plot owner's items**; a foreign item is refused as at machines (`"Foreign"`: pushed
  off, back to its owner). The FOUNDRY sink takes items at the end of a belt on its cell facing `SinkRotation` and,
  with no belt on the cell, items lying or rolling onto it (a cheap cell scan each `IntakeTick`, e.g. a furnace output
  landing there); a belt facing elsewhere just carries items across.
- **Placement / saved layouts**: `Placement.sanitize` returns `(ids, reasons)`; a machine moved off a chute
  (`"Chute"`) gets its own toast in MachineService ("A chute now sits where your X stood…"). **WP-Belts' chute plates
  must ship in the same merge as P0**, so the refusal and the toast always point at something visible.
- **Machine inventory cap** (`MachineData.MaxInventory` = 999 of one type, `EconomyConfig.TechShop.MaxOwned`): the
  shop refuses a buy past it (`techPrice`/`techQuote` → `"MaxOwned"`), `Placement.addInventory` refunds a machine
  packed up or moved off past it at its Price (`commitPickup` returns the refund count, MachineService toasts it),
  Migrations caps a bigger saved count (never drops it) and refunds a position-less machine at the cap.
- **Foundry sink** (GameConfig, `MaxFoundryStock`): ingots the next blaster level can use (rarity >= its
  `Recipe.MinRarity`) go into `Foundry.Stock` while it has room; every other item, and usable ingots once the stock is
  full, go into the Ore Pen. Only when the pen is full too does the item wait on the belt, and the receiver shows
  "Ore Pen full", so a full stock never jams the line. **Forging** uses exactly `Recipe.Ingots` usable ingots: one of
  the skin ore (its lowest-value ingot) plus the lowest-value other usable ingots (`ItemData.value` ascending, ties in
  stock order), so the best ones stay; the default skin is the ore of the most valuable usable ingot. In the same step
  as a successful forge, stock ingots the new next level can't use move to the pen (as many as fit).
  `BaseLayout.FoundryIntake` (`Mouth`, `Zone`) is where FoundryService builds the visible receiver (a hood over the
  end of the belt, leaning on the back wall, a pipe into the ground) so ingots never just vanish at the wall.
- **Keeping** (`MachineData.Keep`, `keeps`, `keepsOre`): only **clean** ore is sorted (only clean ore goes on
  podiums). Dirty ore, crushed ore and ingots always pass on (on to the cleaner, a furnace, the Foundry); old Gear
  counts as kept. `data.KeepMode` = `"RarePlus"` (default: Rare and better) | `"List"` (`data.KeepList[oreId]` =
  `true` keep / `false` send on; an ore the player never set follows the Rare+ rule, so a first-ever Mythic is kept)
  | `"All"`.
- **Iron Box**: Time 4 s (every Speed level still counts with full Bellows; tested); it is a *sorter*:
  `MachineLogic.outputs` gives back a copy of the input, so a generic `complete()` passes the item out of the front;
  kept items are completed with `{}` and put into the pen in the same step (never both). Fuzz-tested for conservation.
  A sorter job counts toward nothing: ProcessingService runs `countIngots`, Discovery and `onProcessed` only for
  machines with an `Output` (tested).
- **Remotes** (Net.luau): PenAction `"Send"` (Count 1..MaxStoredItems; Filter `"Dirty"` | `"Unkept"` (needs
  PenAutomation >= 1) | `"All"`) and `"StopSend"`. **The send queue holds intents only** (Key/Count or Filter, how many
  are left): items stay in `data.Storage` until the step that spawns one, which finds it, removes it and spawns it with
  no yield; leaving or StopSend drops the intents, nothing to put back. IronBoxAction (Burst 12) `"SetMode"`,
  `"SetKeep"`, `"SetKeepMany"`, `"ClearList"` (client redraws from State); FoundryAction `"Take" {Key, Count}` (stock
  ingots back to the pen, refused during a session); nothing is taken when forging starts: the final Strike re-checks
  and takes ingots + coins in one step with no yield (FoundryResult `"NotEnough"` possible then; also `"Busy"`,
  `"TooFar"`, `"BadOre"`); ShopBuy `Level` = the level being bought, the server refuses any other (`"Stale"`,
  `EconomyConfig.techQuote`); the handler quotes, spends and writes in one step with no yield and answers every request
  with **ShopResult** `{ Item, Ok, Reason?, Level?, Count? }` (texts: `EconomyConfig.TechShop.Reasons`).
- **Save**: MachineUpgrades keeps whole levels 0..99 for every non-retired machine id and upgrade kind, also ones this
  server doesn't sell (a newer server may, as with MachineInventory); PenAutomation is kept 0..99 too. Readers clamp
  to what is sold (`EconomyConfig.upgradeLevel` / `techLevel`, `MachineData.speedMult` / `gradeOdds`). KeepMode
  sanitized; KeepList keeps known ore ids mapped to booleans.
- **State** snapshot (StateService): `MachineUpgrades`, `KeepMode`, `KeepList`, `FoundryStock` (storage-key counts),
  `FoundryCount` (`Upgrades.PenAutomation` was already in `Upgrades`).
- **Open question for the owner (balance)**: Bellows (500…25K, -50% on every machine for 41K total) and the slot
  upgrades (1K, 5K) were kept as they were (brief), and machine copies cost a flat Price each. Next to the new
  exponential per-machine curves (one machine type's Speed L5 ≈ 3M for -48%) they are cheap: buying another Cleaning
  Plant (5K) beats any Speed level past L2 while slots last. Reviewer's proposal: Bellows ≈ 5K/40K/300K/2M/15M (or fold
  it into Speed), Slots ≈ 25K/250K, and/or each extra copy of a machine type costs `Price * 1.6^owned`.

## Packages
### WP-Belts: conveyors and the pen "Send"
Owns: src/server/Services/ConveyorService.luau (new), PenService (Send queue), PenView (Send buttons), tests.
ConveyorService as in docs/plans/STEP_D_PLAN.md "WP-Conveyor" (belt velocity, walk-through collision group, open rail
sides, jam nudges, cheap on mobile). Pen "Send": a queue of send intents per player (never items: every item stays in the pen
until the step that takes it out and spawns it, with no yield); one item every 0.5 s spawns on the PEN CHUTE cell and
rides the belts; "Send all dirty", "Send this", "Send unkept" (PenAutomation >= 1), "Stop". Sources only spawn onto a
belt with room that doesn't face off the grid (`BaseLayout.sourceFeeds`, see P0 details).
**WP-Belts also owns the pen sorting billboard (PenAutomation 1)**: the board model (`Yard.Pen.SortBoard`), the
auto-sort logic (`PenService.arrived`, the AUTO-SORT switch `data.AutoSort`) and Direct Unload (PenAutomation 2,
TrainService's small Direct Unload section + PenService's Train lane). Nobody else builds a board or sorts arrivals.
**Chutes must be visible** (two jobs, nobody else draws them): (1) in build mode, a plate in the chute's `Color` with
its `Label` on each chute cell (GridOverlay.plate from BaseLayout.Chutes; PlacementController/GridOverlay are yours
for this) and the `Hint` / "Only belts can go on a chute" toast, plus "Turn the belt away from the yard" on a Source
whose belt faces `SinkRotation`; (2) in the world, a small floor plate + sign per chute, spawned by ConveyorService per
plot (PlotBuilder is off limits). These plates ship in the same merge as P0 (the "Chute" toast points at them).

### WP-CleanerBox: Cleaning Plant upgrades + Iron Box + sorting billboard
Owns: ProcessingService (quality odds by upgrade level, speed by upgrade), MachineBuilder (Iron Box model in the
Factory Kit style of the restyled machines), IronBoxService (new), IronBoxView (keep-list: discovered ores as
toggles, defaults Rare+), tests. The pen sorting billboard (board + auto-sort) is WP-Belts'; this package only edits
`data.KeepMode` / `data.KeepList` (the billboard reads them through `MachineData.keeps`).
Iron Box: reveals (items are clean already), items `MachineData.keeps` keeps go to the pen (bounce out the front when
full), the rest leave the front onto belts (`MachineLogic.outputs` pass-through); dirty ore, crushed ore and ingots
always pass on. If the box runs on ProcessingService jobs, its jobs skip stats/Discovery/onProcessed (P0 gate). The model
(P0 first look, restyled in fix round 1: gunmetal strongbox, steel straps, belt slots, sorting flap) has a lit
`Screen` with `ScreenGui.Item` / `ScreenGui.Counter` labels for the last item and the counter. Keep-list view: mode
buttons (Rare+ / My list / Everything) + ore toggles showing `MachineData.keepsOre` (`SetKeep` stores the explicit
choice, `SetKeepMany` for presets, `ClearList` = back to Rare+). The Cleaning Plant sign already reads
"CLEANING PLANT".

### WP-Foundry: ingots → blasters
Owns: FoundryService (new), FoundryController + FoundryView (new), PlotBuilder Foundry building (replace the
placeholder: Factory Kit furnace with crucible, molten channel, anvil and a blaster rack), tests.
FOUNDRY CHUTE cell absorbs the owner's usable ingots into `Foundry.Stock` and sends everything else (and usable
ingots once the stock is full) to the pen; it also takes items lying on the cell when no belt stands there; "Ore Pen
full" hint at the receiver when an item has to wait (P0 details). Ingots can also be thrown into its hopper. FoundryService builds the receiver at `BaseLayout.FoundryIntake` (the ingot
flies into `Mouth`). UI shows the stock (with "Take" back to the pen) and the next level's recipe
(BlasterData.Levels[n].Recipe: N ingots of MinRarity+, coins); "Forge" picks the skin ore (default: the ore of the
most valuable usable ingot; the forge uses one ingot of it plus the lowest-value other usable ingots) and starts the
hammer moment (every tap counts; PERFECT/GOOD only changes the effect; server checks
the strike timing like the old anvil plan); success: on the final Strike the server re-checks and takes ingots + coins
in one step (no yield), BlasterLevel + 1, BlasterOre = skin, Stats.BlastersForged, stock ingots the new next level
can't use move to the pen, a big reveal of the new blaster; level 11 shows "Coming soon".

### WP-TechShop: buying machines and upgrades
Owns: ShopService (new, ShopBuy), TechShopController + TechShopView (new), the UpgradeCounter prompt, tests.
Catalog: Conveyor, Crusher, Clay/Blast Furnace, Cleaning Plant, Iron Box (+ counts), per-machine Speed/Quality upgrades,
Bellows, slot upgrades, PenAutomation; prices from EconomyConfig (exponential), EconomyService.spend, MachineInventory.
Levelled cards send `Level` (the level shown); the server prices with `EconomyConfig.techQuote` (refuses "Stale",
"MaxOwned" past 999 of a machine type), spends and writes in one step with no yield, and answers every request with
`ShopResult` (the card shows `EconomyConfig.TechShop.Reasons[Reason]`).

### Also in this step
- Direct Unload (PenAutomation 2): TrainService delivers raw cargo onto the TRAIN CHUTE cell instead of the pen (needs
  step 2's TrainService).
- Gear items and the Anvil stay retired; GAME_DESIGN.md gets the v2 machine table.

## Done when
A player can: buy belts + a Cleaning Plant + Iron Box + furnace in the Tech shop, place them, Send dirty ore from the pen,
watch it ride through cleaner → box (keep list) → furnace → Foundry chute, forge a level-2 blaster in the Foundry with
the hammer moment, and upgrade the cleaner to get better grades. QA: no item dup across pen/belts/box/foundry, no lost
items on leave, belts cheap on phones, all inputs. Pictures: a full factory line on a plot, the Foundry forging.
