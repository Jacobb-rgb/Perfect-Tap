# Server performance audit: a full server (2026-10-18)

Read-only audit of main bd6a277 (plus `integrate/steps67` for golems and leaderboards, `fix/save-safety` for the
autosave). It complements the phone/client audit in [PERF_AUDIT.md](PERF_AUDIT.md). Every number is estimated
from the code (rates in the configs, loop periods, payload fields), not measured; profile in Studio with
8 test clients (**Test → Clients and Servers**, MicroProfiler + Network stats) before and after each fix.

**Scenario.** 8 players (`GameConfig.MaxPlayers`, the 8 plots; COMPLIANCE.md section 3). Each has a busy factory
(~20 machines, ~45 belts, power poles: ~70 placed entries, ~560 on the server), a running ore train, mines with a
blaster, and later 3 golems (steps 6-7).

## Verdict

The server has **no per-frame loops** (no Heartbeat/Stepped on the server; every recurring job is a
`while true do task.wait()` loop) and no O(n²) over players. Trains and golems are animated on the clients and
cost the server nothing. The DataStore budget has wide headroom. The weak spots are all on the **factory item
pipeline**:

1. **The State snapshot**: every data change (10-20/s per busy player) re-sends the player's **whole** state,
   capped only by a 0.2 s coalesce, so 5 full snapshots/s per player (~6-9 KB each, ~35 KB/s per player).
2. **Items on belts**: every belt hop destroys an item model and builds a new one (4-8 parts + welds + 8
   attributes + a GUID), and up to 240 server-owned assemblies ride belts by physics, awake, replicated to
   every client (all 8 plots are inside `StreamingTargetRadius` 384).

Fix those two and the server is comfortable at 8 players.

## 1. Server CPU (loops and their work per second)

| Loop | Rate | Work at 8 busy players | Where |
|---|---|---|---|
| `DataService.changed` fan-out | every change | 100-150 changes/s × 6 listeners = **600-900 `task.spawn`/s** | DataService.luau:146-150 |
| State snapshots | 5 Hz per player (0.2 s coalesce) | **40 full snapshots/s**: `storageSummary` string builds over 40-300 pen entries (twice: Storage + FoundryStock), `BuildService.provide` (~70 tables), `PenService.sendCounts` (a second pass over Storage) ≈ 24k string builds + 3k tables/s | StateService.luau:33-102, BuildService.luau:247-256, PenService.luau:600-614 |
| `IntakeService` scan | 5 Hz | a fresh `looseList()` copy + a closure per item; **every item tested against ~22 town zones before the plot lookup**: 240 × 22 × 5 ≈ 26k box tests (~80k property reads)/s; `GetPivot` per belt item | IntakeService.luau:338-350, :403-446 |
| `MachineService.tickAll` | 10 Hz | walks all ~560 placed entries (≈5.6k iterations/s; ~400 are belts/poles with no hook), ~1.6k pcalls/s, idle processors allocate `{Working=false}` + `GetAttribute` every tick; each emit runs `looseCount` O(items) + a full `ItemService.create` | MachineService.luau:867-909, :968; ProcessingService.luau:544,566; LogisticsService.luau:251,420,439 |
| Pen boards | 10 Hz | `markBoard` listens to every data change, so every board recomputes `keepSummary` (sort + concat over 36 ores) and `sendCounts` on every tick: up to 80 recomputes ≈ 25k ops/s; sending lanes build `storageKey` strings per entry (~9.6k/s) | PenService.luau:1349, :997-1045, :727-740 |
| Conveyor jam index | per pass while any belt item is slow | a second `looseList` + ~1.2k `plotAt`/s + per-cell tables | ConveyorService.luau:200-233, :571-614 |
| `ItemService` maintenance | 4 Hz | ~300 records × 4 = 1.2k/s, a closure + `GetPlayerByUserId` + `FindFirstChild` per record | ItemService.luau:539, :611-623 |
| `MiningService.tick` | 10 Hz per shooter | 80 ticks/s; `BlasterBuilder.look` builds a ~15-field table every tick; `SetAttribute("Health")` every tick | MiningService.luau:208, :320, :425-475 |
| `CleaningService` intake | 3.3 Hz | scans all 560 placed entries to find the Cleaning Stations (~1.9k/s), resets `FilterDescendantsInstances` each pass, one `GetPartBoundsInBox` per idle station (~27/s) | CleaningService.luau:277-314 |
| Ore Magnet (steps 6-7) | 4 Hz | per magnet player ≤ 12 raycasts + 8 floor probes + 8 server `LinearVelocity` pulls: worst ~640 raycasts/s, 64 constraints | ItemService.luau:1215, :1303-1321 (integrate/steps67) |
| Podiums, trains, access, tutorial, autosave | 1 Hz or slower | trivial (`refreshLocks` writes properties unconditionally every 5 s: compare first) | PodiumService.luau:280-298, :787-802 |

Engine physics (below) is the largest single frame cost; the Lua side adds up to roughly **100-150k cheap
operations/s**, which the server can take, but items 1-4 of the fix list remove most of it.

## 2. Network (per receiving client)

| What | KB/s per client | Notes |
|---|---|---|
| Belt items' physics replication | **60-120 demanded** (engine-throttled) | up to 240 server-owned, awake assemblies (`MaxLooseItemsPerPlayer` 30 × 8), ~0.6 KB/s each; every client is in range of every plot (TargetRadius 384, plots ≤ ~270 studs apart). Far items will jitter rather than arrive |
| State remote | **25-45** (own player only; ~300 KB/s server egress) | whole snapshot ≤ 5×/s: `Placed` (every machine **and belt**, ~82 × 50 B ≈ 3-4 KB, changes only on layout edits), Storage summary (0.6-1.6 KB), Discovered, KeepList, MachineUpgrades, MachineInventory, FoundryStock (~0.4 KB each), ~1.6 KB fixed |
| New item models | 20-40 | ~1 KB per item (4-8 parts, welds, tag, 8 attributes incl. a 36-char GUID); 3-5 spawns/s per busy plot × 8 plots |
| Machine attributes | 5-10 | ~8 writes per item cycle (Queue, Working, WorkStart, WorkTime, WorkOre, OutCount, Cycles, Status); Status flips every 1 s retry while output is blocked |
| Mining | 2-4 | rock `Health` attribute at 10 Hz per shooter; BlastHit `fireNear` 4 Hz |
| Characters, everything else | ~4-5 | trains: one ~150 B TrainTrip per trip; toasts batched; client→server < 0.3 KB/s |

**Total ≈ 60-95 KB/s per client without the belt physics, 120-200 KB/s with it.** Roblox advises staying well
under ~50 KB/s of remote data per client; phones on mobile data will lag first. The State remote alone is near
that line.

## 3. Instance churn and physics

- **Every belt hop = destroy one item model, build a new one**, no pooling (`ItemService.create` :343-386:
  ItemBuilder, `setGroup` GetDescendants, 8 SetAttribute, AddTag, GenerateGUID, SetNetworkOwner,
  `enforceLooseLimit` O(n) + `table.sort` at the cap). Raw/Crushed/Alloy 6 parts + 5 welds, Ingot 4 + 3, Clean up to
  8 + 7, sparkle emitters on Pristine+/Epic+. Machines that touch hand over data with no instance
  (MachineService.luau:785-790).
- Rate: typical **25-40 models/s server-wide ≈ 150-250 parts + 125-200 welds created and destroyed every second**;
  ceiling ~120 models/s (~700 parts/s).
- **Physics**: belts push by `AssemblyLinearVelocity` (ConveyorService.luau:262); machine and chute spawns are
  server-owned from the first frame. Peak ≈ 240 item assemblies ≈ 1,450 unanchored parts, awake while on belts or
  queued against a full machine. Mining drops and throws go to the owner's client for 3 s, then back to the
  server for good (`SetNetworkOwner(nil)`). Carried items are welded to the character (the player simulates them).
- Mining: 88 anchored rocks (~12 parts each), crack parts and ≤ 3 debris pieces per break (removed after 1.6 s),
  ~1 rock/s server-wide typical (≤ 40 parts/s).
- Effects are client-side (Net Fx); the server creates only static machine emitters/lights, podium display
  emitters and the item sparkles. **Trains: 0 server parts** (client-built, BulkMoveTo). **Golems: 0 server parts,
  0 loops** (client-animated, one attribute string per change).

## 4. DataStore budget at 8 players

| Budget (per server per minute) | Limit | main (120 s autosave) | fix/save-safety (60 s) | + steps 6-7 leaderboards (worst) |
|---|---|---|---|---|
| Get (UpdateAsync counts too) | 60 + 10n = 140 | ~5 (4 %) | ~10 (7 %) | ~22 (16 %) |
| Set / Update | 140 | ~5 | ~10 | ~10 |
| Ordered-store writes | 30 + 5n = 70 | 0 | 0 | ≤ 16 (23 %) |
| GetSortedAsync | 5 + 2n = 21 | 0 | 0 | 4 (19 %) |

- Five boards since the player LEVEL (2026-10-22, review of feat/levels): worst case **20 of 70** ordered-store
  writes and **5 of 21** GetSortedAsync per minute at 8 players (the Level board writes on the same 120 s
  throttle as the others, never per level up).
- main saves one player every 5 s after a 120 s wait, so each player saves about every **160 s**;
  `fix/save-safety` (ec76d00) makes it exactly 60 s and is **not yet in main or in integrate/steps67**.
- Biggest save ≈ 120-140 KB (PlacedMachines with queued items ~85 KB, Storage 300 items ~20 KB, golems ~5 KB)
  of the 4 MB limit (fix/save-safety's SaveSize.spec guards 256 KB).
- Receipts (art/mine-floors MonetizationService): grant → record id → `saveNow` → PurchaseGranted only if the save
  worked: correct, 1 UpdateAsync per receipt.

## 5. Top 10 fixes (by owning chat)

| # | Fix | Saves | Chat |
|---|---|---|---|
| 1 | **State snapshot by sections**: send `Placed`, `Discovered`, `KeepList`, `MachineUpgrades`, `MachineInventory`, `Stats` only when they changed (a dirty flag or hash per section); coalesce at 0.5-1 s; coins/income as player attributes or a tiny event | State ~35 → < 3 KB/s per player; ~24k string builds/s | TERRA FORGE Roblox hra vývoj (StateService, BuildService/PenService providers) |
| 2 | **One `changed` flush per player per frame**: `DataService.changed` marks the player dirty and one deferred task calls the listeners once; `PenService.markBoard` reacts only to keep/send/layout changes | 600-900 spawns/s → ≤ 40; pen boards 80 → ~0 recomputes/s | TERRA FORGE Roblox hra vývoj |
| 3 | **Lighter belt items**: one colliding body + ≤ 2 decor parts on belts (full detail when carried / on podiums), a short numeric `ItemId` instead of the GUID, fewer attributes | ~2-3× fewer parts, welds and replicated bytes per hop | TERRA FORGE Roblox hra vývoj (ItemBuilder/ItemService) |
| 4 | **Reuse the item model across a hop** where the kind stays (re-dress the same model) and **pool** the rest; let items queued at a full machine sleep (anchor them in the queue) | most of the 150-250 parts/s churn; fewer awake assemblies | TERRA FORGE Roblox hra vývoj + Návrhy strojů (emit path) |
| 5 | **IntakeService**: `plotAt` first, then only that plot's zones + the town zones near it; cache zones' CFrame / half size; reuse one item list per pass | ~26k → ~2k box tests/s | TERRA FORGE Roblox hra vývoj |
| 6 | **`tickAll` over an active list**: only machines with a tick hook and work or pending outputs; idle processors skip the table + GetAttribute; `armTick` caches its cells | ~5.6k → ~1k iterations/s, ~1.6k allocations/s | Návrhy strojů |
| 7 | **Fewer machine attribute writes**: one packed job attribute (start, time, ore) at job start, `Cycles` server-side only, `Status` set only when it stays changed (not on every 1 s retry) | ~5-10 KB/s per client | Návrhy strojů |
| 8 | **Rock `Health`**: replicate at stage changes or quantized at 2-4 Hz; cache the shooter's `BlasterBuilder.look` | ~2 KB/s per client, 80 tables/s | Design zbraní a blasterů |
| 9 | **Merge fix/save-safety** (60 s autosave, stale lock 180 s) into main and steps 6-7 | each player saved every 60 s instead of ~160 s, still ≤ 7 % of the budget | TERRA FORGE Roblox hra vývoj (with the save audit) |
| 10 | Small loops: `ItemService` maintenance caches the owner root per pass and drops the per-record closure; `CleaningService` keeps a list of stations instead of scanning every machine; `refreshLocks` compares before writing; profile the Ore Magnet (≤ 640 raycasts/s) | ~3k lookups/s | TERRA FORGE Roblox hra vývoj (steps 6-7: the magnet) + Návrhy strojů (CleaningService) |

**Status (perf pass 1, map v27).**
- Fix 1 done: StateService throttles pushes to one per 0.5 s per player with a leading edge (a push
  after a quiet spell, e.g. a buy or a golem equip, goes out at once; changes within 0.5 s of the
  last push wait for the rest of it), sends only the
  sections whose fingerprint changed (Placed only after a layout edit), sends changed flat sections
  (Storage and Foundry summaries, Stats, Train, Build...) as `Patch { Set, Clear }`, lists vanished
  sections in `Removed`, marks the first push `Full` and keeps the steps 6-7 `Kept` list; the coin
  balance and podium income are the player attributes `Coins` / `IncomePerSec` (at most every
  0.25 s; 0 when the balance or income is not a finite number), which HudController reads. What the
  client has is saved only after `Net.fire` went through (a failed push makes the next one whole),
  and a client that gets a partial push before any whole one asks again with `StateSync`.
  Busy-player estimate (tests/StateService.spec.luau): ~34.5 KB/s -> ~1.3 KB/s per client (State
  plus every player's coin attribute).
- Fix 5 done: IntakeService asks `plotAt` first and tests only the town zones over that plot or in
  the item's 32-stud town square, from a cached index of zone boxes (rebuilt when a zone is added or
  its part moves, resizes or leaves): ~26k -> ~2k box tests/s.
- Fix 2 done (perf pass 2, branch `work/perf2`, 2026-10-20): `DataService.changed` only marks the player; one
  `task.defer` flush per player per frame runs every `onChanged` listener once, in registration order, on a
  reused runner thread (an error is warned with its traceback, a yielding listener gets its own thread, so
  neither stops the others) and skips a player whose data is gone (left and saved). Many changes in a frame ->
  one call per listener; the 600-900 `task.spawn`/s (one new thread per change per listener) become one
  deferred task per changed player per frame, with no new thread unless a listener yields. The one listener that
  needed the change at once, Bonuses' cache drop, moved to the new `DataService.onChangedNow` (runs inside
  `changed()`, cheap, never yields), so a read right after a change never sees old totals; the gear buy and
  golem equip already apply their effects directly. Specs: tests/DataChanged.spec.luau. Left: `PenService.markBoard`
  still reacts to every flush (not only keep / send / layout changes).
- #3, #4, #6, #7 and #10 are done by the machines chat (below).
- Phone audit ([PERF_AUDIT.md](PERF_AUDIT.md), branch `docs/perf-audit`; update its table when it lands):
  item 4 (plots) done: 0 see-through parts, small trim without shadows (the preview now honours
  `CastShadow`, so shadow cuts show in renders); item 3 done for the west-sea ShipA / ShipB only
  (the airship still bobs); **items 7-8 still open**: SPIN & WIN neon 177 -> 174 (one hidden rim chord
  and two stair studs), the 16 inner-edge rim chords, 8 dividers and 16 segment triangles are
  untouched; Districts neon only about -12 of 858 (the shared bay strips). A real fix for item 7 is
  fewer, longer rim / divider neon parts on the static frame, not on the turning disc.

### Status after the steps 6-7 landing (branch fix/post-steps67, 2026-10-18)
- **#3 done**: machine / chute spawns use `ItemBuilder.buildLight` (≤ 3 parts, 2 welds, no sparkles; same Body as
  the full look), pickup re-dresses the same model (`ItemService.dress`); ItemId is a short per-session number and
  no attribute; attributes: Kind, Owner, State (+ OreId, Grade, Recipe, Value for clean items).
- **#4 done (item side + emit side)**: an absorbed light item parks its model; the owner's next server spawn within
  14 studs wears it again (re-dress only when the look changes; 6 s, ≤ 8 per owner); `ItemService.sleep / wake /
  wakeNear` for queued items; MachineService counts loose items once per owner per tick pass. Left: calling
  `ItemService.sleep` from ConveyorService / IntakeService when a belt end answers Full / Busy (IntakeService is the
  integrator's).
- **#6 done**: `tickAll` walks an active list (busy rules per behaviour, `wake` on every input); the Robot Arm caches
  its neighbours per layout version. Benchmark (8 plots, 392 machines): busy factory 72 → 16 tick calls, 0.22 →
  0.07 ms per tick; idle factory 72 → 0 calls.
- **#7 done**: one `Job` attribute (`cycles|start|time|ore`, `ProcessingService.jobText`, read by
  `MachineBillboard.decodeJob`); Status shows a block at once and clears only when it stays clear (40 → 0 flips over
  40 alternating retries).
- **#10 done**: ItemService maintenance looks up each owner's root once per pass, no per-record closure;
  CleaningService keeps its station set; the Ore Magnet sets its ray filter once per pass and re-raycasts a blocked
  item only after it or the player moved (standing still with 4 items behind a wall: 52 → 20 rays in 12 s).

Not changed on purpose: `StreamingTargetRadius` 384 keeps every plot (and its belt items) in every client's
range. Dropping it to ~256 would cut far-plot replication, but the town would pop in on PCs; after fixes 3-4,
measure first.
