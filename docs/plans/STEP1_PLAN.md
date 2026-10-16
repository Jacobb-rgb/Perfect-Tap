# Step 1 plan (design v2): core loop – ores, rocks, blasters, pen, podiums, Sell stall

Part of docs/plans/V2_PLAN.md. Design source: docs/DESIGN_V2_NOTES.md.
Player loop after this step: blast a rock (hold fire) → 1–3 **dirty ore** chunks drop → carry them home →
throw them into the **Ore Pen** or clean them at the Cleaning Station → put the best **cleaned** ore on a
**podium** → coins every second (also offline, 50 %) → sell what you don't need to **Tobin** at the Sell stall.
(Trains arrive in step 2; the Foundry and new blaster levels in step 3.)

## P0 contracts (done, commit "Step 1 P0")
| File | What |
|---|---|
| src/shared/Config/OreData.luau | 30 ores: Income (coins/s on a podium), Value (= Income × SellSeconds 30), Hardness, Color/Glow/Crust, **Shape (unique per ore)**, Material, Lore |
| src/shared/Config/WorldLayout.luau | zone ore weights for rocks, `MinBlaster`, `RockHealth` |
| src/shared/Config/BlasterData.luau | levels 1–10 (+11 "Coming soon"), Damage per second, Range, Foundry recipes, rarity bonus, skins, Beam limits, rock rules (`rockHealth`, `oreCount`) |
| src/shared/Config/EconomyConfig.luau | income tick, podiums (2 free, 4 max, Clean only), offline (50 %, 5 h / 12 h), pen capacity + upgrade prices, sell limits |
| src/shared/Config/BaseLayout.luau | the yard behind every plot (plot-local): Pen, 4 Podiums, Foundry, TrainStop, RailZ, Museum, YardGate |
| src/shared/Config/ItemData.luau | `income(desc)`, Raw shows as `DirtyName` "Dirty Ore" |
| src/shared/Config/MachineData.luau | `Retired` (StorageCrate, SellChute, Anvil: not sold, migrated away), `Buildable`, StarterKit = Cleaning Station + Clay Furnace |
| src/shared/Util/Format.luau | `big` (K…Dc), `money`, `perSecond` |
| src/shared/Net.luau | `MineBlast`, `PenAction`, `PodiumAction`, `SellAction`, server→client `Earned` |
| src/server/Data/DataTemplate.luau | Version 3: BlasterLevel, BlasterOre, Upgrades.PenLevel, Storage (= the Ore Pen), Podiums {4 strings}, LastSeen, new Stats |
| src/server/Data/Migrations.luau | v3: retired machines refunded (items to the pen), pickaxes removed, podiums sanitized, money finite |
| src/server/Services/EconomyService.luau | `award` (fractions ok, `quiet` flag), `spend`, `canAfford`, `balance`, `onEarned`, `onSpent` |
| src/server/Services/StateService.luau | snapshot has BlasterLevel, BlasterOre, Podiums, Perks.Podiums/OfflineExtension (other fields via addProvider) |
| src/shared/Builders/OreNodeBuilder.luau | **`buildRock(zoneId, oreIds, base, seed)`** (stub) |
| src/shared/Builders/ItemBuilder.luau | **`display(desc, cf, seed?)`** anchored display copy (stub) |
| tests/V2Config.spec.luau, tests/Migration.spec.luau | contracts are tested |

Perk ids (player attributes `Perk_<id>`, set by MonetizationService in step 8; Studio testers can set them by hand):
`Podiums` (podiums 3–4), `OfflineExtension` (12 h), `TrainExpress` (step 2), plus the old StrongBack/ForgeVip/Workshop.

## Work packages (parallel, each owns its files; nobody else edits them)

### WP-Ores: 30 beautiful ores and rocks (art)
Owns: src/shared/Builders/ItemBuilder.luau, src/shared/Builders/OreNodeBuilder.luau,
src/shared/Builders/OreShellBuilder.luau, src/shared/Cleaning/CleaningPatterns.luau (only if an ore needs it),
tools/lune/export_scene.luau (new scene `ores`), tools/preview/ore_shots.json (new), tests/Ores.spec.luau (new),
tests/World.spec.luau (node part only), tests/CleaningPlay.spec.luau (only ore-list related lines).
1. Every ore gets its own silhouette from its `Shape` (30 shapes: Lump, Branch, Slab, Block, Spike, Drop, Cluster,
   Pebble, Shard, Banded, Nugget, Gem, Twin, Barrel, Prism, Octa, Moss, Blade, Orb, Disc, Speckled, Star, Geode,
   Blob, Halo, Crown, Rainbow, Wisp, Meteor, Heart) for **Clean** items (≤ 8 parts, one colliding Body) and for
   `display` (≤ 14 parts, anchored, 1 PointLight for Legendary/Mythic, Epic+ sparkles, Mythic pulse/orbit look).
   Rarity readability per .claude/skills/ore-design. Ingot (≤ 4 parts) and Crushed in the ore's colors.
2. **Raw = Dirty Ore:** a dull rock chunk (≤ 6 parts) with only a tiny colored glint; it must NOT reveal the rarity
   (same size/shape/sound for every ore; the glint color is the only hint).
3. `buildRock`: zone-styled boulder (quarry grey, cave dark red-brown, deep blue-black, grotto purple) with small
   glints of the contained ores, bigger with more ores (1–3), ≤ 20 parts, crack stages via `applyStage` (stage 2
   drops pieces), attributes Zone + OreCount, PrimaryPart, Stage = 0. Keep `build(oreId, ...)` working (tests).
4. The cleaning close-up (OreShellBuilder + patterns) must work for all 30 ores (CleaningPlay tests run per ore).
5. Preview: scene `ores` (all 30 Clean + display + Raw + ingots on a grid, labels) and rock samples; render, look,
   fix look-alikes; add `tests/Ores.spec.luau` (all kinds build for every ore, part budgets, display anchored,
   raw chunks of all ores have the same size, rocks for 1–3 ores in every zone).

### WP-Blaster: laser blasters and rock mining
Owns: src/shared/Builders/BlasterBuilder.luau (new), src/shared/Builders/PickaxeBuilder.luau (delete),
src/shared/Config/ToolData.luau (remove pickaxes, keep carry levels), src/server/Services/ToolService.luau,
src/server/Services/MiningService.luau, src/client/Controllers/MiningController.luau,
src/client/Controllers/FxController.luau, src/client/Effects/Vfx.luau (beam/impact additions),
src/shared/Config/SoundConfig.luau (blaster sounds), tests/Config.spec.luau (pickaxe tests → blaster),
tests/Mining.spec.luau (new).
1. `BlasterBuilder.build(level, oreId): Tool` named "Blaster": chunky toy-like laser gun (Kenney Blaster Kit feel,
   ≤ 25 parts), body/core/barrel rings in `BlasterData.skin(oreId)` colors, more parts per level (fins, coils,
   crystal core); a `Muzzle` attachment for the beam. Rusty look for level 1.
2. ToolService gives the Blaster for data.BlasterLevel/BlasterOre (refresh on change); no pickaxes anywhere.
3. MiningService: rocks at every NodeSpawn with `BlasterData.oreCount` ores rolled by zone weights;
   HP = `BlasterData.rockHealth`; `MineBlast(rock | nil)` sets/clears the player's target; a server tick
   (`BlasterData.Beam.ServerTick`) applies `BlasterData.damage(level, ore) × dt` (dt capped by MaxTickGap) while the
   Blaster is equipped, the rock is alive, within Range + RangeSlack, and the zone's MinBlaster ≤ level (else one
   "Needs a Level N blaster" toast + bounce Fx). VIP zones need ForgeVip. Stages at 1/3, 2/3, 3/3 of HP: each
   crossed stage drops the next rolled ore as a **Raw** chunk (1 ore → drops at shatter; 2 → stages 2 and 3;
   3 → stages 1, 2, 3). Discovered/notifications only happen on cleaning now (dirty ore is unknown) – keep
   Stats.OresMined and add Stats.RocksBroken. Respawn uses the rarest ore's RespawnTime. Keep onChunkMined and
   nearestNode (tutorial). Remove MineSwing (Net entry too).
4. MiningController: hold to fire on PC (left mouse), touch (a big FIRE button bottom-right + hold on a rock),
   gamepad (R2, aim assist to the nearest rock in front within range). Beam VFX from the Muzzle to the hit point in
   the ore glow color (rusty = orange), impact sparks, crack shake, sound loop; only the local player's beam is
   simulated locally; other players see beams via a light server→client Fx at most a few times per second.
   Shows "Needs Lv N" over gated rocks.
5. Tests: damage per tick math, range/gate/VIP refusals, stage drops for 1/2/3 ores, NaN/foreign instance input.

### WP-Base: Ore Pen, podiums, money per second, offline earnings, HUD
Owns: src/server/World/PlotBuilder.luau, src/server/Services/PenService.luau (new),
src/server/Services/PodiumService.luau (new), src/server/Services/EconomyService.luau (may extend, keep the API),
src/server/Services/ItemService.luau (storeDesc → pen capacity + "Ore Pen" text; Value attribute 0 for Raw),
src/server/Services/BuildService.luau (remove the crate-access rule), src/client/Controllers/PenController.luau (new),
src/client/Controllers/PodiumController.luau (new), src/client/UI/PenView.luau (new),
src/client/Controllers/HudController.luau, src/client/UI/HudView.luau, src/server/init.server.luau and
src/client/init.client.luau (ORDER lists only: add PenService, PodiumService, SellService / PenController,
PodiumController, SellController; remove StorageService, StorageController, AnvilService, AnvilController),
src/server/World/TownLegacy.luau + src/server/World/Land.luau (only to keep decorations out of the yards),
tests for these (PenService.spec, PodiumService.spec, ItemService.spec/BuildService.spec updates).
1. PlotBuilder: the yard from BaseLayout (ground pad, low fence, gate in the back rail, the pen fence with a gate,
   4 podium pedestals (3–4 with a lock + "100 R$" sign), a Foundry placeholder (simple building, "Coming soon"),
   a train-stop placeholder platform). Name parts so services find them (Pen.Intake, Podium1..4 with an
   `OrePoint` attachment and a Prompt attachment).
2. PenService: capacity = EconomyConfig.penCapacity(Upgrades.PenLevel, GameConfig.MaxStoredItems); items dropped or
   thrown into the pen intake box (IntakeService.addZone) go into data.Storage (owner only, foreign items bounce);
   a "Put In" prompt for carried items; "Open Pen" prompt → PenView. PenAction "Take" {Key, Count ≤ StorageTakeMax}
   spawns items into the hands (reuse the StorageSell WIP logic: branch stepd/wp-storagesell-wip,
   StorageService.takeItems); "ToPodium" {Key, Slot}. Pen upgrades come with the shops (step 6): only the data.
3. PodiumService: slots 1–2 always, 3–4 with Perk Podiums; "Place" {Key} from the pen (Clean only), "Remove" back to
   the pen (refuse when the pen is full); a carried clean ore can be put on a free podium with the podium's prompt.
   Shows the ore with `ItemBuilder.display` on the OrePoint (server-side, anchored, CanQuery false) + a
   BillboardGui "+$1.3K/s". Income: every IncomeTick, award(sum of ItemData.income(podium) × multiplier) quietly,
   push the HUD at most once a second; Stats.PodiumEarned; LastSeen = os.time(). Offline: on load,
   `EconomyConfig.offlineEarnings(income, now − LastSeen, Perk OfflineExtension)` → award + "While you were away:
   +$X" popup (OpenUI "Offline" {Amount, Seconds}). LastSeen also written in beforeRelease.
4. Client: PenView (list grouped by key: icon in ore color, name – "Dirty Ore" for raw – grade chip, count,
   "+$X/s", Take and "Podium" buttons; sorted by income; capacity bar; works with mouse, touch and gamepad; B/close),
   PodiumController (mouse hover over a podium → a "Remove" button next to it; touch/gamepad → ProximityPrompt
   "Remove" / "Place Ore"), PenController (pile of up to BaseLayout.Pen.ShowMax display items inside the pen,
   client-side, from the State snapshot), HUD: coins with Format.money + "+$X/s" under it, offline popup, coin
   tick-up.
5. StateService providers: PenCapacity, Income (per second), PodiumSlots (2 or 4).

### WP-Sell: Tobin's Sell stall
Owns: src/server/Services/SellService.luau (new, start from the WIP branch file), src/client/Controllers/SellController.luau
(new, from WIP), src/client/UI/SellView.luau (new), src/server/World/TownLegacy.luau (trading post only: rename
Pell → **Tobin the miner**, sign "TOBIN'S ORE STALL" / "SELL"), tests/SellService.spec.luau (new).
1. At the SellCounter (tag) a prompt "Sell Ore" opens SellView: your pen items and carried items grouped by key with
   Tobin's price (`ItemData.value`; Dirty Ore shows "?" until sold, and pays the raw price), buttons Sell 1 /
   Sell all of this / "Sell all dirty ore" / "Sell everything except podium-worthy"; SellAction validated on the
   server (range to the stall ≤ 20 studs, counts, keys via ItemData.parseKey, at most EconomyConfig.Sell.MaxPerRequest).
2. The SellBin (tag, child part Intake) still sells items thrown into it (owner gets paid).
3. Coins via EconomyService.award(player, amount, "Sell"); Stats.ItemsSold; `Earned` popups (+$ burst, combo).
4. Tests: price math, pen vs hands, bad keys/counts, too far, foreign items in the bin pay their owner.

## Integration (after all four)
Merge WP-Ores, WP-Blaster, WP-Base, WP-Sell; `bash tools/check.sh`; rebake (WorldBuilder.Version + 1 for the yards);
QA review (exploits: podium/pen dup, sell dup, beam damage rate, offline time travel; DataStore; mobile);
docs/QA_REPORTS.md + STUDIO_CHECKLIST.md; preview pictures: ore gallery, a rock being blasted, the yard with pen and
podiums, the HUD with income, the Sell view.
