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

## 4 + 5. The backpack (built on feat/backpack, from feat/no-foundry)
Owner picks: "Ano, vše do batohu" (everything goes into the backpack), "Sám, když jdeš blízko" (auto-pickup when you
walk near), start 5 / top 1000, a backpack shop, a bigger train, cleaned ore into the backpack; 2026-10-25 "Batohy
zůstanou" (owned packs stay through a rebirth, the ore inside goes like the pen's).
Split (agreed with "Styl a obchod batohu" + the integrator): they own src/shared/Config/BackpackData.luau (10 packs,
BackpackData.capacity(id); copied here from art/backpacks b4f1ade1), the worn models (player attribute "Backpack"),
the BACKPACKS shop building (part tagged "BackpackCounter", Attachment "BackpackPromptPoint") and the shop window
(client: OpenUI "Backpacks" { Counter }, Net BackpackAction / BackpackResult, State.Backpacks). We own everything below.

Data (save Version 9):
- data.Backpacks = { Equipped = "RookiePack", Owned = { RookiePack = true } } (unknown ids kept: a newer build's).
- data.BackpackItems = { [ItemData.storageKey] = whole count } (key-shaped unknown keys kept), total <= MAX.
- v9 once (loaded Version < 9): the Gear shop's old Ore Backpack level (capacities 1/2/3/5/8/12 by level) becomes the
  smallest pack holding at least as much (Owned + Equipped; RookiePack 5 covers levels 0-3, TrailPack 15 the rest);
  data.Gear.Backpack goes. The Gear shop sells four lines (the Backpack line left GearConfig).

Server:
- CarryService = the backpack's contents: pickup(player, record) absorbs your own loose item (never a Drop) into
  data.BackpackItems while there is room (manual: Net CarryPickup; automatic: a 4 Hz loop over each player's own
  loose items within reach, at most GameConfig.MaxLooseItemsPerPlayer each); count / capacity / room / items /
  has(predicate) / take(predicate, max) -> { Desc } / add(desc, n). No drops or throws (CarryDrop / CarryThrow go),
  nothing welded to the character, no carry slowdown on the walk speed; the backpack is saved, so death, leaving and
  teleports keep it. Attributes CarryCount (items inside), CarryCapacity, PickupRange stay.
  Capacity = Bonuses.carryCapacity: the equipped pack (Bonuses' "Backpack" source sets CarryCapacity's base), the
  CarryCapacity bonuses on top (Deep Pockets, golems), x2 with the Strong Back perk (StatConfig cap raised).
- BackpackService = the packs: prompt on every "BackpackCounter" -> OpenUI "Backpacks" { Counter }; BackpackAction
  ("Buy" | "Equip", { Id }) -> BackpackResult { Id, Ok, Reason? } (TooFar 16 studs | NoCoins | Owned | NotOwned |
  BadId | Locked); any pack you can afford, a bigger buy auto-equips; player attribute "Backpack" = Equipped;
  BackpackService.refresh(player). State.Backpacks = { Equipped, Owned = { ids }, Count, Capacity, Items }.
- Consumers read the backpack: the train ("Load Train": all dirty ore that fits, one press), the Ore Pen (Put In:
  everything but relics while it has room; Take: into the backpack), Tobin (sells backpack + pen items), podiums
  (Put On Podium: the best clean ore), machines' Put In (what the machine accepts), the Cleaning Station (the vise
  takes a dirty ore / relic from the backpack; Take Ore Back puts it back; a cleaned ore goes into the backpack, else
  the pen, else its tray as before), the Ore Magnet (fetched ore goes into the backpack).
- Rebirth: the backpack's ore goes (relics wait in the pen for the keeper); the packs stay.
- The train's capacity levels grow to ~1000 (balance_sim).

Client (one agent, plain look + named frames for the style chat): the hotbar's carried-item squares become one
backpack button next to the Blaster slot (icon + "n / cap") that opens the inventory window (the ore stacks with
picture, name, grade, count; a line about the BACKPACKS shop); InteractController keeps F / tap pickup, no drop /
throw; prompts that waited for carried items read State.Backpacks.Items; the tutorial's "Hopper" step says load the
train at the station; the Gear shop shows four lines.
