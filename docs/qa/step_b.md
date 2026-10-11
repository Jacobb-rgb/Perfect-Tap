# QA report – step b

## Step b – Mining, items & carrying

I reviewed commit `989b793`. `tools/check.sh` passes on both a clean export of the commit and the current working tree: the strict type check is clean, 40/40 Lune tests pass, and the place builds (3,157 parts).

How I checked:
- I read every server, shared and client file in the commit and traced each remote handler, the item lifecycle and the leave/save flow.
- I checked every property and enum the new code sets against the current Roblox API dump.
- I replayed the ProfileStore cases below in Lune with a fake DataStore. I also ran the tool grip CFrame math in Lune.

### Issues (most important first)

1. **Saves started when a player leaves are not awaited at shutdown, so data is lost and the player can be locked out for about 5 minutes.** `src/server/Services/DataService.luau:200-213` and `:262-281`
   - **What goes wrong:**
     - `releasePlayer` sets `profiles[player] = nil` *before* its final `UpdateAsync` returns.
     - `BindToClose` only waits for profiles that are still in `profiles`. So if the last player leaves a server, or PlayerRemoving fires before BindToClose during a shutdown or a Studio Stop, BindToClose sees an empty table and returns at once. The server can then close while the final save is still in flight. A save slowed by `waitForBudget` (up to 20 s) or retries (1+2+4 s) is the most likely to be cut off.
     - When that save never lands, progress since the last autosave (up to 120 s) is lost. That includes the items `ItemService` just moved into Storage.
     - The dead server's lock also stays in the DataStore. In the Lune replay with the real settings, a new server got `"locked"` (and the player is kicked) right after the crash and still 4.5 minutes later. It loaded only after about 5 minutes (`ProfileStore.luau:133-135`, the half-stale takeover at 300 s).
     - A failed final save (`ok == false`) has the same effect and is never retried.
   - **Fix:**
     - Count in-flight releases (`releasing += 1` before the callbacks, `-= 1` after `save`, inside a pcall). Make BindToClose wait while `pending > 0 or releasing > 0`.
     - On a failed final save, retry in the background (for example 3 more times, 5 s apart) and count it as in flight.

2. **If a player rejoins the same server quickly, their data rolls back and the old session's release clears the new lock.** `src/server/Data/ProfileStore.luau:131` (same-JobId short-circuit) and `src/server/Services/DataService.luau:170-176`
   - **What goes wrong:**
     - `load()` treats a lock that holds this server's own JobId as free. If the same user rejoins this server while the old Player's final save is still running, the new session loads the *last autosave* and takes the lock. Then the old release lands and writes `Lock = nil`.
     - In the Lune replay: coins were 10 at the autosave and 50 at leave, and 1 item was stashed. The new session loaded 10 coins and 0 items. After its next autosave the store held 11 coins and 0 items, so 39 coins and the stashed item were lost.
     - This is likely in a small game with one or two servers, where rejoin and "Reconnect" often land on the same server. It needs the release to be slow (an autosave in progress, budget waits or retries), but those are exactly the slow cases.
   - **Fix:** Keep `releasing[userId] = true` in DataService until the final save returns. In `loadPlayer`, wait (up to about 30 s) while `releasing[player.UserId]` is set before calling `profileStore:load`.

3. **The pickaxe is very likely held backwards, along the arm with the head behind the player.** `src/shared/Builders/PickaxeBuilder.luau:21`
   - **What goes wrong:** `Tool.Grip = CFrame.new(0, 0, -1.6)` has no rotation. With the R15 `RightGripAttachment` (-90° on X) in the normal arm-forward tool pose, the handle's +Z (the head) maps to the hand's +Y, which runs back toward the shoulder. The Lune CFrame math puts the hand at z = -1.6 and the head at z = +1.8, which is behind the character's back. `docs/screenshots/mining.jpg` does not prove anything here, because `tools/lune/lib/dummy.luau` places the pickaxe by hand and ignores `Grip`.
   - **Fix:** `tool.Grip = CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(90), 0, 0)`. In the math check, the head then sits 3.5 studs above the hand with the pick tips pointing forward. Confirm with Studio test 1.

4. **Items that fall out of the world are usually not rescued. They become invisible "ghost" items, and dropping while facing a thin wall sends items outside the map.** `src/server/Services/ItemService.luau:280-286`, `:322-327`, `src/shared/Config/GameConfig.luau:26` (`ItemFallKillY = -200`) with `FallenPartsDestroyHeight = -250` in `default.project.json`, and `src/server/Services/CarryService.luau:157`
   - **What goes wrong:**
     - A falling item crosses the 50-stud band from -200 to -250 in about 0.17–0.19 s, but `maintenance` runs only every 0.5 s. About 2 out of 3 falling items are destroyed by the engine first.
     - The record then stays in `records` as "Loose" with a destroyed `Body`. `release()` moves nothing, but the item still counts toward the 40-item cap. The player sees it vanish, and it only reaches Storage later through the cap or when they leave.
     - `ItemService.start` runs the endless loop inside a single pcall, so one error in `maintenance` stops sleeping and rescue for the rest of the server's life.
     - One way in: `dropTop` places the item 3 studs ahead without a raycast. The island boundary walls are 2 studs thick and the sea strips have no collision, so dropping or throwing while facing the edge wall puts the chunk outside the map.
   - **Fix:**
     - Set `ItemFallKillY = -80` (the lowest floor is -40) and `FallenPartsDestroyHeight = -1000`.
     - In `maintenance`, treat `not body:IsDescendantOf(Workspace)` as fallen and stash the item.
     - pcall each record's work, not the whole loop.
     - In `dropTop`, raycast from the root to the drop point and place the item before the hit.

5. **Loose items are physically controlled by their owner's client and collide with everyone.** `src/server/Services/ItemService.luau:55-65`, `:223`, `:249`
   - **What goes wrong:** `SetNetworkOwner(owner)` lets that client set any position or velocity on its own loose items. An exploiter can:
     - pull all their items to themselves from anywhere ("vacuum"). The pickup range check reads the position the client reports.
     - teleport items into places they should not reach. This becomes a real money exploit in step c if machine intakes or sell zones accept items by `Touched` or position.
     - spin items fast to fling other players.

     Sleeping items are also anchored, and only the owner can pick them up, so other players cannot move or remove a pile someone leaves in their way.
   - **Fix:**
     - Put item bodies in an `Items` CollisionGroup that does not collide with a `Characters` group. Or at least set the server as owner (`SetNetworkOwner(nil)`) whenever an item is near another player or a machine.
     - In step c, accept items into machines only on the server: check that the item is Carried by the player (or sits in a server-side region check), never `Touched` alone.

6. **With full hands, E / "Grab" cannot drop while any of your items is nearby.** `src/client/Controllers/InteractController.luau:151-158`, `:85-118`, `:140-141`
   - **What goes wrong:** `grab` always tries a pickup when there is a target. `chooseTarget` ignores capacity. New players start with **1** slot (Bare Hands), and a node drops 3+ chunks in one spot. So after picking one up, pressing E only shows "Your hands are full!", and the hint keeps saying "[E] Pick up". Players must walk away or throw.
   - **Fix:** In `chooseTarget`, return nil when `CarryCount >= CarryCapacity` (both are player attributes already). The hint then shows "[E] Drop".

7. **The item name/value hint disappears for good after the first death or reset.** `src/client/Controllers/InteractController.luau:215-223`
   - **What goes wrong:**
     - The `BillboardGui` is created straight in PlayerGui, and `ResetOnSpawn` (a LayerCollector property, true by default) is not set. Roblox deletes it on respawn.
     - The controller keeps writing to the destroyed object without an error, so the hint never shows again. The Highlight survives because it lives in Workspace.
   - **Fix:** Add `ResetOnSpawn = false` to the props.

8. **Sleeping chunks hang in mid-air when what they rest on disappears.** `src/server/Services/ItemService.luau:287-294`, `:110-117`, `src/server/Services/MiningService.luau:166-171`, `:246-251`
   - **What goes wrong:**
     - Chunks pop out of the node and often land on its rocks or on other chunks. After 10 s at rest they are anchored.
     - When Rock2 and the shards break off (stage 2), when the node shatters (stage 3), or when the bottom chunk of a pile is picked up, the anchored chunks above stay floating.
     - With 1 carry slot, chunks wait around for a long time, so this will happen often.
     - `wake()` also does not restore the network owner after unanchoring.
   - **Fix:**
     - Add `ItemService.wakeNear(position, radius)` (`GetPartBoundsInRadius`, filtered to the Items folder). Call it from `breakOff`/`shatter` and after a pickup.
     - Call `setNetworkOwner` inside `wake`.

9. **Camera shake slowly turns the camera.** `src/client/Effects/CameraShake.luau:28-41`
   - **What goes wrong:** The shake is added to `camera.CFrame` after the default camera has updated. Next frame, the PlayerModule camera builds its new angle from `camera.CFrame.LookVector`, so every frame's random tilt is kept. The view drifts a few degrees after big hits and keeps creeping while you mine. This is most noticeable on gamepad and touch, where players rarely re-aim.
   - **Fix:** Remember the shake CFrame you applied. Undo it in a `BindToRenderStep` at `Enum.RenderPriority.Camera.Value - 1` (`camera.CFrame *= lastShake:Inverse()`). Or shake only the position through `Humanoid.CameraOffset`.

10. **The swing cooldown lets scripts mine 18% faster, and real swings get dropped on laggy mobile connections.** `src/server/Services/MiningService.luau:201-207`
    - **What goes wrong:**
      - The server accepts a swing 0.85 × cooldown after the previous *arrival*. A script that fires `MineSwing` every 0.51 s with the Stone Pick (0.6 s) gets +18% ore.
      - A real player on mobile with more than about 50–90 ms of jitter has two swings arrive close together. The second is silently dropped, but the client already showed sparks, sound and shake for it.
    - **Fix:** Use a per-player token bucket per pickaxe: rate = 1/Cooldown, burst = 2. That allows jitter but caps the average rate.

11. **A dropped or thrown item can be moved to Storage the moment you let go, and at the cap every new chunk shows a toast.** `src/server/Services/ItemService.luau:183`, `:211`, `:250`
    - **What goes wrong:**
      - `CreatedAt` is set when the item was mined. `release()` calls `enforceLooseLimit`, so at 40 loose items the item you just dropped is often the oldest one and vanishes from your hands into Storage. The same goes for items dropped on death.
      - Once at the cap, every chunk mined triggers "Too many loose items…".
    - **Fix:** Set `record.CreatedAt = os.clock()` in `release()`, so "oldest" means least recently touched. Show the cap toast at most once every 30 s per player.

12. **Small leak:** `src/shared/Net.luau:110-111`, `:172` – `Net.forget` is never called, so the rate-limit tables keep every Player object that ever joined for the life of the server.
    - **Fix:** Connect `Players.PlayerRemoving` to `Net.forget` in `Net.setupServer`.

### Mobile performance

- **The carry HUD rebuilds on every item anywhere.** `src/client/Controllers/HudController.luau:176-178` → `:92-111`
  - Every item that spawns or streams in runs `refreshCarry`. That scans all items and destroys and rebuilds every slot (Frame + UICorner + UIStroke + UIGradient each).
  - Walking into a quarry with 200 items streamed in means 200 full rebuilds in one frame.
  - Fix: react only if the new item's `CarriedBy` is the local player, and merge repeated refreshes into one `task.defer`.
- **Item part count.** A raw chunk is 10 parts and 9 welds (`src/shared/Builders/ItemBuilder.luau:78-127`). With `MaxLooseItemsPerPlayer = 40` and 8 players, that is up to 3,200 extra parts, about as many as the whole map (3,157). It is still 1 physics body per item, which is good.
  - Suggestion: use a cap of about 25, or merge each chunk's decoration into one MeshPart.
- **OK:**
  - InteractController's 10 Hz scan reads only the `Owner` attribute for other players' items. About 300–450 items costs well under 1 ms.
  - VFX use 10 pooled holders with `:Emit()`.
  - SFX use 8 pooled 2D and 10 pooled 3D sounds.
  - Rock chips are capped at 40.
  - There is 1 Highlight, and 1 PointLight on glowing pickaxes only, with no shadows.

### Checked and OK

- **Remote handlers:** Every `Net.on` handler validates its input.
  - `MineSwing`: the instance must be in Nodes and be a live node. The player needs an equipped Pickaxe, loaded data, a passed cooldown, range, VIP and tier.
  - `CarryPickup`: the item must be a Model in Items with a record. The player must own it, it must be Loose, within range, with free capacity, and the player must be alive with data loaded.
  - `CarryDrop`: takes no arguments.
  - `CarryThrow`: the direction must be a unit vector with no NaN or inf, power is clamped to 0..1, and pitch is clamped.
- **No item duplication path in step b:** The handlers never yield, so pickup and drop cannot interleave. `stash` always destroys the model in the same call, so an item cannot end up in Storage and in the world.
- **Leave order:** ItemService's `beforeRelease` is registered first and stashes Loose and Carried items. Then CarryService clears its list. CharacterRemoving is harmless before or after PlayerRemoving, and `dropAll` checks `State == "Carried"`, so nothing is stashed twice. BindToClose uses the same callbacks.
- **Carried items:** They are welded, `Massless`, with collision off, so they add no mass and do not change character movement. The HumanoidRootPart stays the assembly root.
- **Network owner calls:** `SetNetworkOwner` skips anchored parts and parts outside Workspace, and it is wrapped in a pcall.
- **DataStore budget:** `GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)` is the right enum for `UpdateAsync`. The API now also has `StandardRead/StandardWrite`. If Roblox retires the old budgets, use the smaller of those two.
- **Studio:** With `SaveInStudio = true` and API access, Studio uses the **live** DataStore and takes the live session lock. Because of issue 1, stopping a test can lock your own account out of the live game for about 5 minutes. Without API access, the probe correctly falls back to memory.
- **Streaming:** Item and node models stream as one piece (Atomic), and the client code checks for a missing `PrimaryPart` everywhere.
- **Slash animation:** The `toolanim` "Slash" StringValue matches what the default R15/R6 `Animate` script reads. It stops working if a custom Animate script or StarterCharacter replaces the default.
- **API properties:** Every property used on BillboardGui, Highlight, Tool, Model, Sound and ParticleEmitter exists in the API dump.

### What to test in Studio

1. **The pickaxe in your hand:** Press **Play**, then press **1** to hold the pickaxe. The head should be at the top, above your hand, and not lying along your arm or sticking out behind your back. Click a rock: your arm should swing.
2. **Breaking a rock:** Hit a grey quarry rock until it breaks. You should see cracks, then a piece flies off, then it shatters. One chunk should pop out at each step and fly smoothly, with no freezing in mid-air.
3. **Full hands:** With your starting hands (1 slot), press **E** to pick up a chunk. Stand next to the other chunks and press **E** again. It should drop the chunk you hold. A "hands are full" message here means issue 6.
4. **The label after a reset:** Look at a chunk: a name and coin value should float above it. Press **Esc → Reset Character**, walk back and look at a chunk again. If the label no longer appears, that is issue 7.
5. **Floating chunks:** Mine a rock so that chunks land on top of it or on each other. Wait 15 seconds, then finish breaking the rock, or pick up the bottom chunk of a pile. No chunk should be left floating in the air.
6. **Throwing and phone buttons:** Pick up a chunk, hold **F** and let go: the chunk should fly forward. Then choose a phone under **Test → Device** and play again. The **Grab** and **Throw** buttons should be visible and should not cover the jump button. Holding **Throw** should fill the power bar.
7. **Dropping at the edge of the map:** Walk to the edge of the island until the invisible wall stops you. Face the wall and press **E** to drop a chunk. The chunk should land on your side, not disappear.
8. **The camera does not drift:** Stand still and mine the same rock 10 times without touching the mouse or the thumbstick. The camera should still point at the same spot.
9. **Saving:** Turn on **Game Settings → Security → Enable Studio Access to API Services**.
   - Play and mine a **Copper** rock until "New ore discovered: Copper!" appears. Press **Stop** within 10 seconds.
   - Play again and mine Copper again. If "New ore discovered" appears a second time, or you are kicked with "still being saved on another server", the save was lost (issue 1).
10. **Two players:** On the **Test** tab, start a server with **2 Players**.
    - Player 2 must not be able to pick up Player 1's chunks.
    - Player 1 throws a chunk at Player 2: Player 2 should not be knocked far.
    - When Player 1 leaves, all of Player 1's chunks should disappear from the world.
