# Security audit of the client → server remotes (2026-10-18)

Read-only review of every RemoteEvent on main (claude/keen-wozniak-mx7azn at 49c2bac) before launch, in three areas:
economy and shops; machines, building, cleaning and teleport; the Net layer, mining, carrying, items and saves.
**Steps 6–7 (gear, enchants, golems, boosts, capsules, wheel, artifacts) were not on main yet and need the same pass
when they land.**

**Bottom line: nothing lets a client mint coins, items or blaster levels, double-sell, skip a price, or touch another
player's things.** Every coin and item path checks and writes in one step with no yield in between, clients only send
keys, counts and levels (never prices), every remote goes through the per-player rate limiter and a pcall, there are no
RemoteFunctions, and every client value that reaches a save is validated. The findings below are design loopholes,
hardening and one real functional bug.

## Findings, most serious first

| # | Risk | Where | What | Fix | Owner | Status |
|---|---|---|---|---|---|---|
| 1 | **High (bug, not security)** | TeleportService.isCleaning → CleaningService.stationOf | Every player owning a Cleaning Station (the starter kit: everyone) got "Finish cleaning first" on every teleport. | Ask whether a cleaning **session** runs: new `CleaningService.isCleaning`. Test against the real module. | machines | **Fixed** (fix/security-machines) |
| 2 | Medium | MachineService.pickup, ItemService.storeDesc / enforceLooseLimit / beforeRelease, IntakeService foreign return, Placement repair | System moves put items into the Ore Pen up to the save cap (300) instead of its paid capacity (40–180): packing up machines, more than 30 loose items, leaving the game, items left on a neighbour's plot. The pen upgrades (up to 150M) become pointless. | Packing up a machine is refused with "PenFull" while its contents don't fit (nothing lost, the player makes room). The other system stashes should respect `penCapacity` too (or sell the extra at Tobin's price, as the header says). | machines / items, pen | **Pickup fixed**; rest → integrator |
| 3 | Medium | MiningService range, CarryService pickup range, ItemService "owner close", AccessService | Every distance check trusts the client's character position; nothing checks movement speed. A bot can teleport between rocks and chunks (mining is still capped by server damage, it only skips walking). | A light server movement check (last position every 0.25–0.5 s; flag or pull back moves faster than possible, except right after server teleports); use that position for range checks. | net / mining | → integrator |
| 4 | Medium | CleaningService / CleaningScoring | A scripted client can submit perfect traces at the minimum pace (the seed and ore come with CleanBegin, the line tolerance comes from the client's claimed input type), so every dirty ore becomes Flawless (2.4×). | Don't trust `Input` (one tolerance, or decide it server-side), flag inhumanly regular submissions, cap Flawless results per hour. Can't be closed completely (it's a client minigame). | cleaning | Open (proposal) |
| 5 | Medium (design) | MachineData Polisher (GradeUpChance 0.5, Flawless stays) | A belt loop back into the Polisher re-polishes any Clean ore until it is Flawless. | Owner decision: e.g. the Polisher stops at Pristine (keeps Flawless for hand cleaning) or one grade-up per item. | machines | Open (owner) |
| 5b | Medium (design) | Crystal Extractor loop | Feeding the extractor its own output farmed shards forever. | Already fixed on integrate/steps67: every crushed pile gives one shard roll (`data.ShardRolls`). | integrator | Fixed in steps 6–7 |
| 6 | Medium/Low | ItemService (Raw `OreId` attribute, model name "Raw_Gold"), StateService / SellService keys "Raw\|Gold\|\|", CleanBegin ore id, rock glint colours | The dirty ore's hidden identity reaches clients, so a cheat can tell which dirty chunks are rare before cleaning (an advantage, not free coins). | No OreId / ore in the name on Raw items; one masked dirty key in State; Sell / Take / Send address dirty ore by kind (server picks which); derive the cleaning pattern from a server key. | items, sell, pen, cleaning | → integrator |
| 7 | Low | TrainService "Upgrade" | No expected-level check: a double click buys two levels (each at its correct price). | Require `Level == current + 1`, answer "Stale" otherwise (like ShopBuy / VaultBuy). | train | → integrator |
| 8 | Low | CarryService drop/throw velocity, ItemService ownership hand-back | A client can give its own items any speed and through walls while it owns their physics; the server only checks 90 studs in 3D on hand-back. Griefing (knock others' loose items into the SellBin), no gain. | Cap the character speed added to drops/throws; zero or cap the speed on hand-back and test reachability with height. | items | → integrator |
| 9 | Low (suspected) | Net.on, MiningService | An event arriving after PlayerRemoving would recreate per-player state that is never cleared again. | Ignore events from players no longer in Players; weak-keyed buckets. | net | → integrator |
| 10 | Low | Net.luau | 26 remotes have no server listener (server→client events plus CleanStart, AnvilSubmit/Cancel, DailyClaim, GroupClaim, SetForgeName): clients can spam "invocation queue exhausted" warnings. | Connect a no-op (counting) listener to every unregistered remote; drop unused entries. | net | → integrator |
| 11 | Low (suspected) | ItemService.maintainOne, CarryService, CleaningService.takeTop | A "Consumed" item still in the carried list could be cleaned into a duplicate; no reliable trigger found. | takeTop skips non-Carried items; mount/release/setState refuse Consumed; tell CarryService when a carried item is consumed. | items | → integrator |
| 12 | Low | MiningService | The beam has no line-of-sight check (mine through walls within ~53 studs; level and VIP gates still hold). | A cached raycast every ~0.5 s per player and rock. | mining | → integrator |
| 13 | Low | BuildPlace / BuildPickup rate (8/s, 6/s) | Place/pick-up churn of big machines floods nearby clients with model replication. | A lower rate for non-belt machines or a per-player model build budget. | building | Open (later) |
| 14 | Low | LogisticsService Sell Box insert | Coins are paid before the attribute / popup steps; today nothing after the payment can fail, but a future change could duplicate the item. | Pay as the very last step. (The steps 6–7 version of this function changed: the owner of that version applies it.) | integrator | → integrator |

## Notes (no change needed now)
- **Monetization isn't built yet** (no ProcessReceipt, `Perks.set` never called). When it is: idempotent receipts on
  `data.Purchases[PurchaseId]`, save before returning PurchaseGranted, NotProcessedYet while data isn't loaded,
  game passes checked server-side with `UserOwnsGamePassAsync` (pcall, at join and after a purchase prompt).
- **SetForgeName has no handler yet.** When added: UTF-8 check (`utf8.len`), length in characters and bytes,
  `TextService:FilterStringAsync` in a pcall, show others only the broadcast string, never unfiltered text.
- Some coin writes skip EconomyService (Placement refunds, Migrations refunds): route them through one award helper.
- Offline earnings pay from the podiums at login, not from what stood there while away (no practical effect today).
- Prompt handlers rely on the engine's prompt range and all check ownership: fine (worst case: your own machine from
  a bit further away).
- The VIP Grotto door is a once-per-second server teleport; VIP rocks are gated on the server, so fighting it gains nothing.

## Checked and OK
ShopBuy, SellAction, SellBin, Sell Box, VaultBuy, PodiumAction, PenAction, TrainAction (apart from #7),
TutorialAction, EconomyService award/spend, offline earnings, BuildPlace / BuildMove / BuildPickup (bounds, chute
cells, overlap, slots, inventory ledger, ownership, range, Busy, queues drained once), MachineAction (SorterCycle only,
coerced ±1), item intake everywhere (Foreign refused, server plausibility check, no yield between check and insert),
emit / side outputs / Robot Arm (same plot, same owner), power speed clamped 0..1, FoundryAction (per-player session
GUIDs, one Strike per session, server clock, level re-check, ingots and coins taken in one step), IronBoxAction
(settings only, tables capped, known ores), cleaning (single-use session bound to the server's own item, score
recomputed server-side with capped samples), Teleport (whitelist, cooldown, character re-checked after streaming),
MineBlast (client sends only the target; damage, ore rolls, rock HP and drops server-side), carrying (owner, loose,
range, capacity, validated throws, drops raycast out of walls), saves (session lock, Migrations type clean-up, every
client value validated before it reaches the save), Guard validators, Net rate limiter and pcall wrapping.
