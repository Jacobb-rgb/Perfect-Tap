# Machines game plan: the roster machines working in the game

Owner (2026-10-17): "put the new look into the game, metal plot floor, then make the new machines work, power with
cables too". Looks and floor are done (KitMachines, PlotBuilder, merged in main). Step 3 (integrator session) already
built ConveyorService, the pen Send, chutes, the Iron Box, the Foundry and the Tech shop. This plan makes the rest of
the roster (docs/plans/MACHINES_PLAN.md) work. Claude's proposals (prices, times, power numbers) are in
src/shared/Config/MachineData.luau; the owner can change them.

## P0 (done, commit a4b1d1c on art/machines)
- MachineData: ExpressConveyor, Splitter, Sorter, BrickFurnace, Polisher, RobotArm, SellBox, CrystalExtractor,
  AlloyFurnace, PlasmaFurnace, PowerPole, SolarPanel, WindTurbine, FusionReactor (all Buildable, so the Tech shop sells
  them; Speed upgrades on the step 3 curve). New optional fields: Behaviour, NoIntake, SideOutputs, Inputs, Batch,
  GradeUpChance, ShardChance, SpeedMult, Power, PowerOut, IsPole. `MachineData.PowerRules`, `powerOut`, `powerSpeed`,
  `lookLevel`.
- Grid: `NO_FRONT_OUTPUT` has the roster machines without a front output; `Grid.sideOutputLocal(id, side)` /
  `Grid.sideOutputCell(id, x, z, r, side)` (side -1 = left, 1 = right = Grid.right). KitMachines puts `OutputL` /
  `OutputR` attachments there on the Splitter and the Sorter.
- ItemData kind `Alloy` (ValueMult 3.2, "<Ore> Alloy") + ItemBuilder model. `data.Shards` (number). PlacedMachines
  entries may carry `C` (the machine's own setting, a whole number 1..9).
- MachineService: the model gets the upgrade look (`MachineData.lookLevel(MachineUpgrades[id].Speed)`),
  `MachineService.refreshType(player, id)` rebuilds a player's models of a type, `addSpeedModifier(fn)` /
  `speedFactor(machine)` (job times are divided by it).
- Tech shop icons for the new machines; tests follow the roster.

## Rules (Claude's proposals)
| Machine | What it does |
|---|---|
| Brick Furnace | processor, 4 s, Clean/Crushed -> Ingot |
| Plasma Furnace | processor, 2.5 s, works `Batch` = 2 queued items per job (the fastest) |
| Polisher | Clean -> Clean, `GradeUpChance` 0.5: one grade better (Rough -> Clean -> Pristine -> Flawless, Flawless stays) |
| Crystal Extractor | Crushed -> Crushed (same item), `ShardChance` 0.15: data.Shards + 1 and a toast |
| Alloy Furnace | needs 2 ingots of DIFFERENT ores in its queue; one job takes both, gives 1 Alloy of the more valuable ore, grade = the lower of the two; while only one ore waits: Status "NeedsOtherOre" |
| Splitter | takes items (belt/hopper/hand), sends them out left and right in turn (OutputL / OutputR) |
| Sorter | Clean/Crushed/Ingot/Alloy: rarity >= its threshold (entry.C = a Rarity Order, default Rare) to the right, the rest to the left; MachineAction "SorterCycle" steps the threshold; attribute `Detail` shows it |
| Robot Arm | every 1.5 s (faster with Speed and power): takes the first finished item (Entry.Out) of the machine behind it and inserts it into the machine in front of it, if that one accepts it |
| Sell Box | sells every item that goes in at Tobin's price (SellService.priceOf), coins to the owner |
| Express Conveyor | a belt with `SpeedMult` 2 |
| Power | PowerRules: poles link within 6 cells, power machines/generators with a footprint cell within 3 cells; machine speed = 0.6 + 0.4 * min(1, supply / demand), 0.6 when on no powered network; generators make PowerOut * (1 + 0.25 * Speed level) |
| Upgrades | Speed level 1..5 (Tech shop): processors/arm/splitter/sorter faster, generators more power; the crystal look = min(4, level); after a Speed buy the player's models of that type are rebuilt |

## Packages (separate files, built in parallel worktrees, then integrated)
- **WP-Proc**: ProcessingService (new processors, Batch, GradeUpChance, ShardChance, the Alloy behaviour, job time /
  MachineService.speedFactor, ShopService.onBought -> MachineService.refreshType on Speed buys), MachineLogic (pure
  helpers + tests), MachineFxController (furnace glows/smoke for Brick/Plasma/Alloy, the Polisher wheel, the Wind
  Turbine blades), tests.
- **WP-Logi**: LogisticsService (new: Splitter, Sorter, Robot Arm, Sell Box), ConveyorService (SpeedMult), the side
  output emit in MachineService (only that function), tests.
- **WP-Power**: PowerLogic (new, pure: networks), PowerService (new), PowerController (new, client cables), the power
  line + "NeedsOtherOre" + `Detail` lines in MachineBillboard, tests.
- **Integration** (Claude): boot ORDER entries (server + client), check.sh, previews, QA.

## Done when
A player can buy any roster machine in the Tech shop, place it, and it works as above; power poles show cables and
slow/fast machines visibly; upgrades change the look; all checks pass; pictures of a working factory.
