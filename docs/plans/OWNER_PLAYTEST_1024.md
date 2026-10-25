# Owner playtest 2026-10-24: the five changes

The owner played the 10-24 test place in Studio and asked (in Czech, his words in the machines chat; picks made with
AskUserQuestion):

1. Build mode: no words like TRAIN. **Done** (feat/owner-playtest-1024 ecf24f90): the chute plates stay without
   labels (only "TURN THE BELT" warns), the train chip and boost chips hide (HUD attribute Building).
2. Podiums: 3 free + 2 for Robux (today 2 + 2).
3. No Foundry: "you earn money, come to the Vault and buy a better blaster"; blasters get better with enchants in the
   shop as today.
4. + 5. A backpack instead of carrying: "everything into the backpack", picked up by itself when you walk near;
   a backpack icon next to the Blaster slot opens the ore inventory; it starts at 5 ore, the biggest holds 1000; a
   backpack shop; the train grows to match.

Order (integrator): 1 now; 2, 3 and 4+5 after art/hoppers lands (it touches PodiumService, SellService, ItemService,
CarryService, FoundryService). Each piece: its own save Version when the save shape changes (gated on the loaded
Version), a map bump when the plot changes, balance_sim re-run (blaster 8 / 9 / 10, the ~8 h curve), check.sh, one
lean review.

## 2. Podiums 3 + 2
- EconomyConfig.Podiums Free 3, Max 5; the Podiums perk (same product) unlocks slots 4-5 (store text, COMPLIANCE,
  Step8Receipts if the grant changes).
- The plot gets a 5th podium pad (PlotBuilder / BaseLayout; WorldBuilder.Version bump).
- Migrations: podium arrays of 4 grow to 5 ("" slot); spec a v6 save with 4.
- balance_sim Podiums = 3.
- **Built** (feat/podiums-3): save Version 7 (a v6 save's 4 slots grow to 5, ores stay put), map v54. The 5th pad
  pushed the map over the phone budgets (StreamParts +85, LobbyParts +86): the locked slots now show only the padlock
  (no holo-ring, -12 parts a plot) and PodiumService copies podium 1's ring onto a slot the perk opens.
  balance_sim (Typical): blaster 8 / 9 / 10 at 2h53 / 4h27 / 7h15 (7h53 with 2 free podiums); piece 3 recalibrates
  the Vault prices for the whole curve anyway.

## 3. No Foundry
- FoundryService / FoundryBuilder / FoundryView / FoundryController and the Foundry chute (a Sink on the plot) go;
  ingots are sold or alloyed (Alloy Furnace).
- Vault: the only way to a better blaster; prices recalibrated in balance_sim (no ingots any more) so a typical
  player still reaches blaster 10 at about 8 h.
- Rebirth: "forged this run" (Stats.RunForged) becomes "reached this run" (bought in the Vault counts); the
  RebirthView text follows.
- Tutorial: the "A stronger blaster" step points at the Vault; quests / badges that say "forge" change.
- Old saves: the Foundry's ingot stock goes to the pen (or is sold), spec it.
- **Built** (feat/no-foundry, on top of podiums-3): FoundryService / FoundryBuilder / FoundryLogic / FoundryController /
  FoundryView, the FOUNDRY chute (ConveyorService's sink machinery), the yard placeholder, the Hammer move and the
  Net remotes are gone; map v55; save Version 8 (data.Foundry.Stock -> the pen once, data.Foundry goes).
  Blasters: `Recipe` -> `Coins` (the level's coin scale; everything that followed the Foundry prices keeps it), the
  Vault price = Coins x 1.15 (`balance_sim calibrate-vault`, Typical LV 10 at ~8 h). Rebirth: a coin level raises
  Stats.RunForged (it counts for the stars); the coin Vault never says "ForgeFirst" any more, the STORE still leaves
  LV 10 to the coins (topBlocked). New: the droppers and Podium Keeper keep their income through a rebirth, so a rebirth
  run's Vault prices have a floor: RunShare 0.5 x RunSeconds[level] of Stats.RunIncome (RebirthService writes it right
  after the reset). Tutorial step "A stronger blaster" points at the Vault; ingots: "sell or alloy".

## 3b. The yard Cleaning Station (owner 2026-10-25)
The owner, in Czech: "jo jenom tu faunery dej uplne pric a misto toho tak tam dej ten cistic rudy kterej pouzivas
individualne sam ne stroje" ("yes, just remove the Foundry completely and put there instead the ore cleaner you use
yourself, not machines"). Picked with AskUserQuestion: "Jen na dvoře" (only in the yard).
- Every owned plot gets a Cleaning Station at BaseLayout.CleaningStation (where the Foundry stood, facing the podiums),
  built by CleaningService when PlotService assigns the plot and gone when it is freed (vise ore stashed). Runtime only:
  no save entry, no grid cell, not in MachineService's index; tag "Machine", Owner, Fixed = true (build mode skips it).
- The starter kit drops its grid station (new players: Furnace + Crusher on the grid, the station in the yard); old
  saves keep their grid station; the Tech shop still sells more. TutorialConfig.StarterMachines 2, the Cleaning
  target's layout point is the yard station.

## 4 + 5. The backpack
Data: `data.Backpack` = counts by item key ("K|O|G|R" like the pen) and `data.BackpackLevel`; capacity per level
5 -> 1000 (Strong Back pass: x2). Every mined chunk, cleaned ore, crushed pile, ingot, relic is a backpack item.

Server:
- CarryService keeps its API for the consumers (takeTop / list / capacity / pickup / room) on top of the backpack:
  pickup = add the item's key and destroy the chunk; takeTop finds a matching item and gives a real record only
  where a physical one is needed (the Cleaning Station's vise); a new takeDesc gives the description (train, pen,
  sell, podium, machine queues).
- Auto-pickup: a server loop per player (owner-locked chunks within a range from the root, a few times a second;
  loose chunks per player are capped at 30, so it is cheap). Throwing and the hand stack go.
- The train: one press at the mine station loads all dirty ore that fits (server-checked range); train capacity
  levels grow to match the backpack (up to ~1000).
- The Cleaning Station takes a dirty ore from the backpack; the cleaned ore goes back into the backpack (full: the
  pen, then the tray).
- Machines' Put In, the pen (take / put), podiums, Tobin and the Sell Box read the backpack.
- Rebirth clears the backpack's ore like the pen. Old saves: the Gear shop's Ore Backpack level maps to the backpack
  level with at least its capacity (once, loaded Version); the Gear item leaves the Gear shop.

Client (plain, functional; styling hooks for the UI chat):
- A backpack button next to the Blaster slot (count n / capacity) opens the window: ore stacks with icon, name,
  grade, count and the actions that fit where you stand (put on the podium, sell, clean, put into a machine); the
  BACKPACKS tab sells the next sizes. Phone and gamepad work.
- The HUD's CARRYING chip becomes the backpack count.

balance_sim: carry capacity from the backpack level (walking trips), the train capacity, the backpack prices.
