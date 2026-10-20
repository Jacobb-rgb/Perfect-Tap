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
| 2 | Medium | MachineService.pickup, ItemService.storeDesc / enforceLooseLimit / beforeRelease, IntakeService foreign return, Placement repair | System moves put items into the Ore Pen up to the save cap (300) instead of its paid capacity (40–180): packing up machines, more than 30 loose items, leaving the game, items left on a neighbour's plot. The pen upgrades (up to 150M) become pointless. | Packing up a machine is refused with "PenFull" while its contents don't fit (nothing lost, the player makes room). The other system stashes should respect `penCapacity` too (or sell the extra at Tobin's price, as the header says). | machines / items, pen | **Fixed** (fix/post-steps67): only rescue moves overfill; while over capacity the pen takes nothing new ("PenOver": Put In, train unload, Iron Box, Podium Remove), the loose cap holds the rock instead of stashing |
| 3 | Medium | MiningService range, CarryService pickup range, ItemService "owner close", AccessService | Every distance check trusts the client's character position; nothing checks movement speed. A bot can teleport between rocks and chunks (mining is still capped by server damage, it only skips walking). | A light server movement check (last position every 0.25–0.5 s; flag or pull back moves faster than possible, except right after server teleports); use that position for range checks. | net / mining | **Rollout step 1** (MovementService logs; `Enforce` off, docs/plans/MOVEMENT_CHECK_PLAN.md) |
| 4 | Medium | CleaningService / CleaningScoring | A scripted client can submit perfect traces at the minimum pace (the seed and ore come with CleanBegin, the line tolerance comes from the client's claimed input type), so every dirty ore becomes Flawless (2.4×). | Don't trust `Input` (one tolerance, or decide it server-side), flag inhumanly regular submissions, cap Flawless results per hour. Can't be closed completely (it's a client minigame). | cleaning | Open (proposal) |
| 5 | Medium (design) | MachineData Polisher (GradeUpChance 0.5, Flawless stays) | A belt loop back into the Polisher re-polishes any Clean ore until it is Flawless. | Owner decision: e.g. the Polisher stops at Pristine (keeps Flawless for hand cleaning) or one grade-up per item. | machines | Open (owner) |
| 5b | Medium (design) | Crystal Extractor loop | Feeding the extractor its own output farmed shards forever. | Already fixed on integrate/steps67: every crushed pile gives one shard roll (`data.ShardRolls`). | integrator | Fixed in steps 6–7 |
| 6 | Medium/Low | ItemService (Raw `OreId` attribute, model name "Raw_Gold"), StateService / SellService keys "Raw\|Gold\|\|", CleanBegin ore id, rock glint colours | The dirty ore's hidden identity reaches clients, so a cheat can tell which dirty chunks are rare before cleaning (an advantage, not free coins). | No OreId / ore in the name on Raw items; one masked dirty key in State; Sell / Take / Send address dirty ore by kind (server picks which); derive the cleaning pattern from a server key. | items, sell, pen, cleaning | **Server part fixed** (no OreId / Value attribute, models named "Raw"); masked State key, CleanBegin ore and rock glints still open |
| 7 | Low | TrainService "Upgrade" | No expected-level check: a double click buys two levels (each at its correct price). | Require `Level == current + 1`, answer "Stale" otherwise (like ShopBuy / VaultBuy). | train | **Fixed** |
| 8 | Low | CarryService drop/throw velocity, ItemService ownership hand-back | A client can give its own items any speed and through walls while it owns their physics; the server only checks 90 studs in 3D on hand-back. Griefing (knock others' loose items into the SellBin), no gain. | Cap the character speed added to drops/throws; zero or cap the speed on hand-back and test reachability with height. | items | **Fixed** (30 studs/s from the character, 20 on hand-back, rise limit) |
| 9 | Low (suspected) | Net.on, MiningService | An event arriving after PlayerRemoving would recreate per-player state that is never cleared again. | Ignore events from players no longer in Players; weak-keyed buckets. | net | **Fixed** |
| 10 | Low | Net.luau | 26 remotes have no server listener (server→client events plus CleanStart, AnvilSubmit/Cancel, DailyClaim, GroupClaim, SetForgeName): clients can spam "invocation queue exhausted" warnings. | Connect a no-op (counting) listener to every unregistered remote; drop unused entries. | net | **Fixed** (counting sink, `Net.unhandledCount`; entries kept: tests and COMPLIANCE plans use them) |
| 11 | Low (suspected) | ItemService.maintainOne, CarryService, CleaningService.takeTop | A "Consumed" item still in the carried list could be cleaned into a duplicate; no reliable trigger found. | takeTop skips non-Carried items; mount/release/setState refuse Consumed; tell CarryService when a carried item is consumed. | items | **Fixed** |
| 12 | Low | MiningService | The beam has no line-of-sight check (mine through walls within ~53 studs; level and VIP gates still hold). | A cached raycast every ~0.5 s per player and rock. | mining | **Fixed** (BeamSight, `MovementConfig.BeamLos`) |
| 13 | Low | BuildPlace / BuildPickup rate (8/s, 6/s) | Place/pick-up churn of big machines floods nearby clients with model replication. | A lower rate for non-belt machines or a per-player model build budget. | building | Open (later) |
| 14 | Low | LogisticsService Sell Box insert | Coins are paid before the attribute / popup steps; today nothing after the payment can fail, but a future change could duplicate the item. | Pay as the very last step. (The steps 6–7 version of this function changed: the owner of that version applies it.) | integrator | **Fixed** |

## Steps 6–7 pass (2026-10-18, main at 9be848a)

Read-only review of everything steps 6–7 added: GearAction, EnchantAction, BoostAction, CapsuleAction, GolemAction,
WheelAction, ArtifactAction, SettingsSave, CodexSeen (client → server, all with Net.on handlers); ActionResult,
CapsuleResult, WheelResult, ArtifactFound, PurchasePrompt, Leaderboards (server → client); the new ProximityPrompts
(they only open views; Gear / Enchant re-check the range); Bonuses / StatConfig, Shards, Policy, Receipts gate,
leaderboards.

**Bottom line: nothing lets a client get coins, shards, gear, enchants, golems, boosts, capsules, wheel spins,
artifacts or collection rewards for free or twice.** Every random roll is server-side, the client never says which
prize it got, every buy quotes, spends and writes in one step with no yield, and the one yield (PolicyService) always
comes before that step, which re-reads the save. No ProcessReceipt exists yet (step 8): every product id is 0 and the
Receipts gate turns every prompt into "ComingSoon".

| # | Risk | Where | What | Fix | Owner | Status |
|---|---|---|---|---|---|---|
| S1 | Low | Policy.luau fetch, WheelService.spin | While the policy answer is unknown (a failed call) every Spin / Royal capsule / Robux boost / Starbreaker buy calls GetPolicyInfoForPlayerAsync again and warns; Spin asks before its cheap ready check. During an outage a spamming client multiplies API calls and log lines. | Keep the strict cached answer until the scheduled retry; check `WheelConfig.ready` before asking Policy (and again after the yield). | wheel / policy | **Fixed** (`Policy.RefetchSeconds`, ready check first) |
| S2 | Low | LeaderboardService markActive (listens to every remote) | Any remote counts as activity (junk WheelAction "Reveal", `MineBlast(nil)`, `CodexSeen({})`, remotes without handlers), even when the rate limiter drops it, so an AFK script climbs HOURS PLAYED. | Credit time only for real server-checked work (rock damage, pickup, sale, cleaning, build), or mark from inside Net.on after a handler did something. | leaderboard | **Fixed**: activity = mined chunk, pickup, cleaning, machine placed, shop / gear / enchant buy, capsule, or a real move (`LeaderboardService.ActivitySources`) |
| S3 | Low | WheelService ore prize → State Storage keys | The State push shows which dirty ore the wheel gave (same root as #6). | The masked dirty key of #6. | wheel / integrator | With #6 |
| S4 | Low (process) | Receipts gate, MonetizationConfig | Once real ids are pasted, a client-made prompt or the Store tab could take Robux with no ProcessReceipt / pass grant to answer it. | Keep every id at 0 (not only Off Sale) until the step 8 handlers ship in the same release. | receipts | Rule for step 8 |
| S5 | Info | LeaderboardService activity listeners | They bypass Net's rate limiter and pcall (tiny work). They also gave the 5 handler-less remotes of #10 a listener. | One hook inside Net.on after `allow()` (with S2). | net / leaderboard | **Fixed** with S2 (the per-remote listeners are gone) |
| S6 | Info | ArtifactService.equip | Every "Equip" repaints the podiums for every client, even when nothing changed (2/s toggling = bandwidth). | Apply only when the value changed. | artifact | **Fixed** |
| S7 | Info | CapsuleService LuckyGrace / PurchaseGrace | Triple Lucky odds hold 3 s after the boost ends for coin capsules and up to 120 s for a Royal prompt shown with it; the client's Lucky flag can only lower odds or get "OddsChanged". | By design. | capsule | OK |
| S8 | Info | ArtifactConfig.rarityOpen | Counts the VIP Grotto for players without the pass; no effect today (same rarities as Ember Caves). | Skip VIP zones without the pass. | artifact | **Fixed** (`rarityOpen` / `restoreQuote` take `vip`) |

Step 8 receipt checklist (from this pass): one ProcessReceipt; NotProcessedYet while `DataService.get` is nil
(released / lost session); write `data.Purchases[PurchaseId]` and grant in one step with no yield
(`CapsuleService.grantProduct`, `BoostService.add(..., false)`, `EnchantConfig.grant`); PurchaseGranted only when
`DataService.saveNow` returns true, and on a retry with the id already saved: saveNow then Granted without granting
again. Game passes: `UserOwnsGamePassAsync` in a pcall at join and after `PromptGamePassPurchaseFinished` (never trust
`wasPurchased`), then `Perks.set` and `Bonuses.invalidate`. `data.Golems.Pending` (MonetizationConfig contract) needs a
Migrations clean-up. Movement check: per-player walk speed reaches ~43.5 studs/s (Boots V + Swift III + golems).

Checked and OK (steps 6–7): GearAction (next level only, "Stale", range, no yield), EnchantAction Buy (next tier,
shards only for Epic / Legendary, Robux = prompt only, Policy before the re-read) and Slot (owned, open slots, no
duplicates), BoostAction BuyCoins (NoEffect / CoinLimit / Full, capped extend, fixed multipliers, StatConfig caps) and
BuyRobux (prompt behind the gate), CapsuleAction (counts, room before the roll, server Random per open, odds sum 1,
Royal odds remembered only after a successful prompt), GolemAction (owned ids, capped Delete list, locked / unknown
skipped, at most 3 count), WheelAction Spin (one step after the Policy read, capped boost prizes, free capsules via
grantFree, ore via PenService.store) and Reveal (grants nothing), ArtifactAction Restore / ReadChapter / Equip,
artifact finds (server roll per shattered rock), ore luck and Twin Drop (server, capped), the Crystal Extractor
(ShardRolls), the Ore Magnet (own items only, off bases), Gloves (raycast past the base reach, throw allowance ≤ 2×),
SettingsSave (sanitized), CodexSeen (discovered ores only), Bonuses (every total capped, failing providers count as
nothing), Shards / EconomyService helpers, server-only attributes (Perks, Policy, Title, LampLevel, EquippedGolems),
Migrations for every new field, leaderboards (server-derived values, write budgets, UpdateAsync keeps the larger
value, hidden list first), compliance (odds everywhere, paid random items hidden where restricted and while the
policy is unknown, no rewards for likes / favorites / groups, coin packs off).

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
