# Save-data robustness audit (2026-10-18)

**What was read:**
- main 49c2bac: `src/server/Data/ProfileStore.luau`, `Data/Migrations.luau`, `Data/DataTemplate.luau`, `Services/DataService.luau` and the beforeRelease callbacks
- `integrate/steps67` db4db37 for what lands next: its Migrations, `Receipts.luau` and `LeaderboardService`

This audit only reads. Nothing in the game was changed. DataTemplate, Migrations and DataService belong to the integrator ("TERRA FORGE Roblox hra vývoj").

**How:** reading the code plus small Lune runs:
- the real ProfileStore with a fake store, for #3 and #6
- a save filled to every cap, measured in JSON, for #11
- `OreData.Renamed` and `ItemData.parseKey` checked for #1

## Status (branch fix/save-safety)

| # | Status |
|---|---|
| 1 | **Gate done:** a save with a Version above the server's (`DataService.latestVersion()`: the higher of `DataTemplate.Version` and `Migrations.Latest`) is refused untouched (no lock taken), and the player sees "The game just updated, please rejoin". A spec requires the two constants to be equal. PUBLISHING.md step 12 says: bump them together for anything a save can name, always Migrate To Latest Update, and fix a broken update forward. An older build never runs on newer saves; a forced rollback keeps the old build's lower version, so the gate refuses those saves untouched. **#1(b) done** (fix/migrations-keep-unknown): what a newer build wrote and this server doesn't know is kept, never "repaired" away. That covers BlasterLevel and the train levels up to GameConfig.MaxLevelKept (TrainService keeps them too), BlasterOre, unreadable podium keys, podium and enchant slots past this build's count, KeepMode, KeepList ids, unknown Foundry ingots, Sorter thresholds, equipped golems of unknown kinds, a tutorial step past this build's list, the ORE CODEX's seen ids and extra settings. The steps 6–7 sanitizers already kept unknown golem kinds and enchant, gear, boost and artifact ids. Unknown items in machine queues and on the train wait in the pen, because the runtime drops queue items it can't read. PodiumService never covers an unreadable key; Remove moves it into the pen as it is (pen room needed) and frees the slot. Specs: Migration.spec runs a future save through Migrations, and again through the load hooks (codex, settings, golems, gear, artifacts, podiums, train, tutorial) and a State snapshot with its providers, and requires it unchanged. |
| 2 | **Done:** `ProfileStore.storable` / `repair` (pure). Repair runs **inside the UpdateAsync transform**, on exactly what is written, so a value changed while the request waits is repaired too. `OnRepair` warns with the paths, and the rest is saved. |
| 3 | **Done:** a SessionId per load in `Lock`. `save()` writes only to its own session; a nil lock means the session is lost. A session stays live on its server until its release succeeds, it is lost or DataService forgets it, and a live one blocks a second load of the key there, whatever its age. A session counts as live from the moment its lock is written. One load per UserId per server, a load stops (and takes no lock) once its player left. A rejoin never loads past a final save still running: it waits up to 40 s, then is told to rejoin. A final save that has hung for longer than StaleLockSeconds is given up, and load's lock rules decide. |
| 4 | **Done:** reconcile and Migrate run in a pcall. On an error only our own lock is cleared, the data is untouched, and the player is kicked. `Purchases` that isn't a table is reset (with a warn) instead of throwing. |
| 5 | **Done:** `AutosaveInterval` 60 s, `StaleLockSeconds` 180 s (both in GameConfig). Each profile saves 60 s after its last save (checked every 5 s). A failed refresh warns and is tried again after 15 s. Old-format locks (no SessionId) stay live for 600 s. A lock's age comes from the key's DataStoreKeyInfo.UpdatedTime (Roblox's clock), so a writer's clock skew doesn't count. A lock dated ahead of us is fresh, unless it is absurdly far ahead. A younger lock is never taken over, so the old "half the stale time on the last try" shortcut is gone: a slow final save keeps its session. |
| 6 | **Done:** the template is used only when nothing is stored. Any other shape gives "malformed" and nothing is written. |
| 7 | **Done:** Studio uses `TerraForge_PlayerData_Studio` unless `GameConfig.StudioLiveData`. Test players (UserId <= 0) live in memory only. |
| 8 | **Rules sent** to the mine-floors chat (MonetizationService already follows them). DataService now never trims purchase ids younger than 30 days. |
| 9, 13 | **Done:** loads and releases count in `inFlight` from their first step, so BindToClose waits for each of them. A release blocks the autosave from its first step; the beforeRelease callbacks get 5 s, then the final save starts anyway. A load still waiting at shutdown stops at once. Any save that finds the session lost kicks the player (no zombies). |
| 10 | **Done:** at shutdown the stores go urgent (2 attempts, 0.5 s pauses), the budget wait is at most 3 s, and the final save makes 2 attempts. |
| 11 | **Done:** tests/SaveSize.spec.luau measures 134 KB at every cap (limit 256 KB). |
| 12 | **Done** together with #5. |
| 14 | **Done:** docs/SUPPORT.md. |

Every scenario has a spec in tests/SaveSafety.spec.luau (45): the audit's, plus the adversarial reviews' R1–R4, A,
C, S1, S2, S4, S6, H2, H3, H6, Z1–Z5, the shutdown load and the real autosave schedule. They run on a fake store that
rejects what Roblox rejects and can yield before or after the transform, hang, run a transform twice or pass a
DataStoreKeyInfo. Against the old code (49c2bac), 16 of the first 17 failed; against the round-1 commit (ec76d00),
the 12 review specs failed. Mutation check: removing any one fix (retry, put-back, autosave kick, forget,
live-inside-transform, same-server-by-live, UpdatedTime age, the hung-release give-up and its forget loop,
releaseHung itself, closing for put-backs, endSession after a failed write) fails at least one spec. Round 3 found
that the first H6 spec cleared a global hang too early, so releaseHung and the forget loop could be removed with
everything green. Z1/Z2/Z3 now hang one request at a time, and Z4/Z5 pin the live-entry cleanup.

Rollback rule (review round 2): a broken update is fixed forward. An older build must never run on saves a newer
build wrote, because its Migrations drop unknown ids until #1(b) lands. PUBLISHING step 12 and SUPPORT 5.2 say so.

## What is already solid

- **Session lock:** every write is an `UpdateAsync` holding a lock with `JobId` and `Time`. A second server waits 6 × 5 s and then kicks with a clear message. It never plays on a copy.
- **A failed load never plays:** the player is kicked, so nobody plays on the default template and saves it later.
- **Retries:** every DataStore call retries up to 4 times with exponential backoff (1, 2, 4 s) and waits for request budget (`GetRequestBudgetForRequestType`, at most 20 s).
- **Leaving:**
  - beforeRelease callbacks write the last changes first (loose items to the pen, plots, podium offline pay).
  - The final save tries 4 times.
  - A rejoin to the same server waits for that save (`releasing`).
- **Shutdown:** BindToClose releases every profile in parallel and waits up to 27 s for them.
- **Autosave:** every 120 s, spread over the interval so not everyone saves in the same second. A lost session kicks the player.
- **Migrations:**
  - idempotent (`Migration.spec` "running it twice gives an identical result")
  - money is checked to be finite, damaged lists are rebuilt in order, retired machines are refunded
  - the ore rename works in one hop (12 renames, no chains, every target exists)
  - steps 6–7 keep well-formed entries this server doesn't know (golems, enchants, gear)
- **Purchases:** the id history stays bounded (the last 100). The `Receipts` gate keeps every Robux prompt on "Coming soon" until step 8's ProcessReceipt exists, so nobody can pay for nothing today.
- **Leaderboards (steps 6–7):**
  - growing boards are written with UpdateAsync keeping the bigger number, so out-of-order writes never lower a score
  - writes leave a request-budget reserve for player saves; BindToClose waits for the last writes
  - Studio never writes; RemoveAsync and a hidden list handle bans and data-erasure requests; values stay below 2^53

## Findings, ranked by risk

| # | Risk | Finding | Where |
|---|---|---|---|
| 1 | **High** | Old servers damage newer saves after an update (no version gate) | Migrations, DataService |
| 2 | **High** | One unstorable value makes every save fail, so the whole session is lost | ProfileStore.save |
| 3 | **High** (rare) | A late save writes over a newer session when the lock was cleared | ProfileStore.save |
| 4 | Medium | A migration error leaves the player stuck with no data and holds the lock | ProfileStore.load, DataService.migrate |
| 5 | Medium | After a server crash, players are locked out for 5–10 minutes | ProfileStore (StaleLockSeconds 600) |
| 6 | Medium | A malformed stored value is replaced with the template on load | ProfileStore.load |
| 7 | Medium | Studio writes to the live DataStore | DataService (SaveInStudio, STORE_NAME) |
| 8 | Medium | Robux receipts: rules for step 8's ProcessReceipt (not built yet) | step 8 MonetizationService |
| 9 | Low | A player who left while loading during shutdown isn't waited for | DataService.loadPlayer / BindToClose |
| 10 | Low | Shutdown saves can run past the 30 s limit under throttling | DataService.finalSave, waitForBudget |
| 11 | Low | Save size: about 120 KB at every cap (3 % of 4 MB), but nothing guards it | DataTemplate (guard test) |
| 12 | Low | Autosave every 120 s means up to 2 minutes of rollback after a crash | GameConfig.AutosaveInterval |
| 13 | Low | BindToClose counts a save only after the callbacks; a yielding callback could end the wait early | DataService |
| 14 | Low | Support playbook: restoring a save and data-erasure (RTBF) requests | docs |

### 1 · High · Old servers damage newer saves after an update

**Why it matters:** after a publish, Roblox keeps old servers running until they empty, unless you shut them down. A player who hops new server → old server has their save "repaired" by the old Migrations. The old server then saves the damage for good. It drops or flattens what it doesn't know yet:
- `BlasterLevel` is clamped to `BlasterData.MaxLevel`. The gallery already shows "Coming soon" past LV 10, so a future LV 11 would fall back to 10.
- Train `CapacityLevel` and `SpeedLevel` are clamped to today's `TrainConfig.maxLevel`.
- A podium with an ore this server doesn't know is **dropped** (checked: `ItemData.parseKey("Clean|<new ore>|…")` returns nil). `BlasterOre` becomes `""`. `KeepList` entries for unknown ores are dropped.

Machines, upgrades and the steps 6–7 records already keep unknown entries. These fields don't.

**Fix:**
- (a) A **version gate:** bump `DataTemplate.Version` whenever an update adds ids or levels. A server that loads a save with `Version > Migrations.Latest` writes nothing: it clears only its own lock and kicks with "Terra Forge just updated – please rejoin".
- (b) Clamp to a generous `MAX_LEVEL_KEPT` instead of today's maximum, and keep unknown ore ids on podiums and in BlasterOre and KeepList. The readers already clamp.
- (c) Publishing checklist (docs/PUBLISHING.md): always use **"Migrate To Latest Update"**, never leave old servers running.

**Test ideas:**
- Migration.spec: a save with `BlasterLevel = 12`, `Train.SpeedLevel = 99`, the podium `"Clean|Zzzium|Pristine|"` and `BlasterOre = "Zzzium"` comes out of `Migrations.run` unchanged.
- ProfileStore.spec: a save with `Version = Latest + 1` makes load return nil ("newer") and leaves the stored Data byte-for-byte unchanged.

### 2 · High · One unstorable value makes every save fail

**Why it matters:** `ProfileStore.save` writes `profile.Data` as it is. Roblox rejects a write that contains, for example:
- an Instance, Vector3 or CFrame
- a dictionary with non-string keys, or a list with holes
- NaN or infinity

Once one service writes such a value anywhere in the save, **every** autosave and the final save fail for that player. The only sign is a `warn`. When they leave, the whole session since the last good save is gone. Migrations clean these at **load** (finite money, rebuilt lists), but nothing checks at **save**. The code has dozens of writers (pen, machine queues, trains, steps 6–7 records). I found no such write on main today, but a single future slip is enough.

**Fix:** a pure `ProfileStore.storable(data)` check before every write. It walks the save and returns the path of the first bad value. Bad values are repaired where that is safe (NaN or inf → 0, holes closed up) or the field is dropped. The rest is saved, and the path is logged to analytics.

*Correction (review, 2026-10-18):* Roblox's engine DataStores **do** store NaN and inf (Open Cloud returns them
tagged). So NaN alone never blocked a save. Repair still turns them into 0, because no reader can use them, and
Migrations zeroes Coins and TotalEarned on load anyway. The blocking cases are the others: userdata, functions, bad
keys, gapped or mixed tables and loops.

**Test ideas:**
- ProfileStore.spec with a fake store that JSON-encodes like Roblox (`serde`) and throws on NaN, userdata and mixed keys: a save with `Coins = 0/0` and `Storage[5]` but no `Storage[4]` still saves, with those two fields repaired.
- A "fuzz" spec that runs the item, machine, train and pen paths and checks that the save survives a serde round trip.

### 3 · High (rare) · A late save writes over a newer session

**Why it matters:** `save()` refuses only when `Lock.JobId` is another server's. It **writes when Lock is nil.**

Reproduced with the real ProfileStore:
1. Server A holds the player.
2. A's saves fail for more than 10 minutes (a DataStore outage), so its lock goes stale.
3. Server B takes the lock over. The player earns 500 coins there and leaves, and B clears the lock.
4. A's final save finally gets through. **The store now holds A's old 11 coins.** B's progress is gone.

Also, two sessions on the **same** server (a rejoin after a failed final save) share one JobId, so they can't be told apart.

**Fix:** a SessionId per load (`JobId .. "-" .. counter` or a GUID) is stored in `Lock`. `save()` writes only when `old.Lock.SessionId` is ours. A nil lock counts as lost.

**Test idea:** ProfileStore.spec runs exactly the steps above. It expects A's late save to return false, `SessionLost = true`, and B's 500 coins to stay.

### 4 · Medium · A migration error leaves the player stuck with no data and holds the lock

**Why it matters:** `Migrate` (DataService.migrate: the Purchases trim, then `Migrations.run`) runs inside `load()` with no pcall, **after** the lock was written. If it throws, for example `data.Purchases` being a string makes the `for id, time in data.Purchases` loop error:
- `loadPlayer` dies with `loading[player] = true` stuck
- the player stays in the server with no data, and nothing saves for them
- the lock stays until it goes stale, so they are locked out for 5–10 minutes after leaving

**Fix:** pcall the Migrate step. On an error, clear only our lock (data untouched), kick with "We hit a problem with your save, please rejoin", and report it. Also check `type(data.Purchases) == "table"` before trimming.

**Test idea:** ProfileStore.spec with `Migrate = function() error("boom") end`: load returns nil ("error: migrate"), the stored Data is unchanged and the lock is cleared.

### 5 · Medium · After a server crash, players are locked out for 5–10 minutes

**Why it matters:** `StaleLockSeconds = max(600, AutosaveInterval × 5) = 600`. A crashed server (no BindToClose) leaves a lock that was refreshed at most 120 s before the crash. A rejoining player waits 30 s and is kicked ("still being saved on another server") until the lock is 300 s old (the last-attempt rule) or 600 s. To players this looks like "my data is broken".

**Fix:** save, and so refresh the lock, every 60 s, with `StaleLockSeconds = 3 × 60 = 180`. Optionally a force-release request over MessagingService ("release Player_X"): the live owner saves and releases at once, and silence means the owner is dead, so the lock is taken.

**Test idea:** ProfileStore.spec with a fake clock: a lock last refreshed 181 s ago is taken over on the first attempt, and one refreshed 30 s ago is not.

### 6 · Medium · A malformed stored value is replaced with the template on load

**Why it matters:** `load()` uses `old.Data` when it is a table, and **otherwise the template**, which it writes at once. Reproduced: a stored `{ Data = "oops" }` came back as a fresh template with 0 coins.

There is no older save format today (`TerraForge_PlayerData_v1` is the first). Still, a manual edit in the DataStore editor, or a future format change, would wipe saves without a sound.

**Fix:** use the template only when `old == nil` (a new player). Any other shape: write nothing, return nil ("malformed"), kick and report.

**Test idea:** ProfileStore.spec: `old = "garbage"`, `{ Data = 5 }` and `{}` with a lock all give nil, and the store keeps its old value.

### 7 · Medium · Studio writes to the live DataStore

**Why it matters:** `GameConfig.SaveInStudio = true` with the same `STORE_NAME`. A Studio test with API access reads and **writes the developer's real save**, so command-bar experiments ("Coins = 1e12", clearing tables) stay on the live account. Studio test players (UserId ≤ 0) also create keys.

The leaderboards already avoid this (`WriteInStudio`). The player save doesn't.

**Fix:** in Studio use `TerraForge_PlayerData_Studio`, unless a deliberate `GameConfig.StudioLiveData = true` is set. Never load or save UserId ≤ 0 to a real store.

**Test idea:** a pure `DataService.storeName(isStudio, liveFlag)` helper with a unit test.

### 8 · Medium · Robux receipts: rules for step 8's ProcessReceipt

**Status (step 8):** done in `MonetizationService` with a handler for every `MonetizationConfig` entry (`Grant`); each grant also writes `PurchaseLog[PurchaseId] = { Product, At }` (trimmed with `Purchases`). Specs: tests/MonetizationService.spec.luau and tests/Step8Receipts.spec.luau (every grant kind: first grant, duplicate, failed save then one grant on the retry, player not in the server, passes on join and on purchase). The rules it follows:
1. The player isn't in the server, or `DataService.get` is nil (not loaded, Released or SessionLost): return **NotProcessedYet**.
2. `data.Purchases[receipt.PurchaseId]` is already set: return **PurchaseGranted** and grant nothing.
3. Grant **and** set `Purchases[PurchaseId] = os.time()` (plus `PurchaseCount += 1`) in the same synchronous step, with no yield between them.
4. `DataService.saveNow(player)`. Return PurchaseGranted **only** when it returned true; else NotProcessedYet. Roblox retries later, and the mark from step 3 stops a second grant if this server autosaved meanwhile.
5. Paid golems or boost time over a cap are still granted (steps 6–7 already allow this).
6. The trim to the last 100 ids is safe only because trimmed receipts were acknowledged. Also never trim ids younger than about 30 days.

Game passes: Roblox is the source of truth (UserOwnsGamePassAsync on join and PromptGamePassPurchaseFinished). Never store them as the only record.

**Test ideas** (MonetizationService.spec, fake DataService and Market):
- the same receipt delivered twice grants once
- a failed saveNow returns NotProcessedYet, and the retry returns PurchaseGranted with no second grant
- a delivery before the data loaded returns NotProcessedYet
- a SessionLost profile never grants

### 9 · Low · A player who left while loading during shutdown isn't waited for

**Why it matters:** in `loadPlayer`, a player who left (or `shuttingDown`) while loading is released by `profileStore:save(profile, true)`. That save isn't counted in `inFlight`, so BindToClose can end before it lands. Their lock then stays for up to 10 minutes (#5).

**Fix:** count it in `inFlight` like finalSave, or call finalSave.

**Test idea:** a refactor that moves the lifecycle into a pure function with fake Players, then a spec where shutdown starts during load and must wait for the release.

### 10 · Low · Shutdown saves can run past the 30 s limit under throttling

**Why it matters:** during BindToClose, one `save()` can wait up to 20 s for budget plus 1 + 2 + 4 s of retries, and `finalSave` adds 2, 4 and 6 s between its 4 attempts. A throttled server can pass Roblox's 30 s, and that player falls back to the last autosave.

**Fix:** while `shuttingDown`, wait at most ~3 s for budget, make at most 2 attempts, and start every final save at the same time (already done).

**Test idea:** a fake-clock spec where every attempt fails slowly: the total shutdown time stays under 28 s.

### 11 · Low · Save size: about 120 KB at every cap, but nothing guards it

**Measured** (serde JSON of the wrapped save) at every cap: 300 pen items, 144 placed machines with full In and Out queues, 60 Foundry ingots, 80 train cargo, all machines ×999 with upgrades, 36 ores in Discovered and KeepList, 100 purchase ids, 70 golems. That comes to **≈ 120 KB**, against Roblox's 4 MB per key, so about 3 %. Safe today. Caps such as MaxStoredItems, MaxFoundryStock, MaxCargoSaved, MaxInventory and GolemConfig.MaxSaved keep it bounded.

**Test idea:** a SaveSize.spec that builds this maxed save from the real configs and checks it stays under 1 MB. Each new feature adds its maxed record there.

### 12 · Low · Up to 2 minutes of rollback after a crash

**Why it matters:** a crash loses at most 2 minutes of progress. Purchases save at once with saveNow.

**Fix:** 60 s autosaves (see #5). That is 1 UpdateAsync per player per minute, against a budget of 60 + 10 × players per minute, so there is plenty of room.

**Test idea:** none needed (config).

### 13 · Low · A yielding beforeRelease callback could end the shutdown wait early

**Why it matters:** BindToClose waits while `inFlight > 0`, but `inFlight` only goes up inside finalSave, **after** the beforeRelease callbacks. All callbacks are synchronous today (ItemService, CarryService, PlotService, PodiumService, LeaderboardService). One future callback that yields would let BindToClose end before that player's save started.

**Fix:** add 1 to `inFlight` before running the callbacks.

**Test idea:** in the lifecycle spec from #9, a callback that yields for 1 s must still be waited for.

### 14 · Low · Support playbook

Write a short `docs/SUPPORT_DATA.md` with three entries:
- **Restore a player's save:** the DataStore keeps versions for 30 days (`ListVersionsAsync`, `GetVersionAsync`). A command-bar snippet restores a version while the player is offline. It must respect the lock: write only with `Lock = nil`.
- **Data-erasure (RTBF) request:** RemoveAsync on `Player_<id>` plus `LeaderboardService.removeUser(id)`.
- **Bans:** the same removeUser call.

## Suggested order

1. #3 and #6: small ProfileStore changes, with specs that reproduce them.
2. #2: the storable check.
3. #1: the version gate and keeping unknown values, plus the publishing checklist line.
4. #4, #5 (+ #12) and #7.
5. #8: the receipt rules, when step 8 MonetizationService is written.
6. The low ones.

All of these touch files the integrator owns (ProfileStore, DataService, Migrations, GameConfig). This document only proposes them.
