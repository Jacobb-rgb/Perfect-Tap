# QA reports

## Step a – World & lighting

Reviewed commit `ee49bdd`. `tools/check.sh` passes: strict type check clean, 26/26 Lune tests pass, place builds (3,157 parts).

How this was checked: I read the code, then loaded the baked `build/TerraForge.rbxl` in Lune. A 2.5D walk simulation ran over every collidable part, using a 2×2-stud footprint, a 5-stud-tall body, steep faces counted as not standable and a 6–7 stud jump. I also checked every property and enum the scripts set against the current Roblox API dump.

### Issues (most important first)

1. **Players get trapped in Deep Hollow and can fall out of the world from its ramp.** `src/server/World/Land.luau:146`, `:365-366`
   - **What goes wrong:**
     - The Ember Caves floor slab runs 8 studs past the room (to z = -360). It covers the top of the Deep Hollow ramp. Climbing back up, players meet a ledge of about 6 studs (ramp y ≈ -18 up to floor y = -12).
     - This place does not set a jump value. The default jump is about 6.4 studs (JumpPower 50) to 7.2 studs. If the jump is below 5.95 studs, the walk simulation marks all of Deep Hollow as one-way: players must reset to get out.
     - The ramp is 16 studs wide inside a 22-stud tunnel, and the tunnel has no floor. That leaves 3-stud gaps on both sides (x ±8..±11, z -361..-371) with nothing below them. A player who steps off the side falls into the void and dies.
   - **Fix:**
     - Make the ramp 22 studs wide.
     - Add a floor under this tunnel, like the one at `:319`.
     - Start the ramp at `ember.Min.Z - 8` so it meets the floor edge with no ledge.

2. **A hole under the town opens next to the quarry ramp.** `Land.luau:210` (ground slab only 6 thick), `:285`, `:295`
   - **What goes wrong:** The south rock wall has a gap about 24 studs wide (rocks skipped for |x| < 16.5), but the ramp is only 16 wide. On both sides of the ramp's foot (x ≈ 8..12 and -12..-8) there is a 6-stud-tall opening under the grass slab (y -6..0), with nothing below it. Walking in from the quarry floor means falling into the void.
   - **Fix:** Make the town ground slab go down to y = -18 (`townMin` Y = -18). Or fill x ±8..±16, y -12..0, z -122..-116.

3. **Two holes sit beside the Grotto tunnel mouth.** `Land.luau:297` (gap ±13.5 along the wall), `:419` (tunnel floor only covers z -190..-174)
   - **What goes wrong:** The quarry east-wall gap is wider than the tunnel walls (z -192..-172). Just beside them, at x > 76, z -172..-169 and z -194..-192, there is no floor. A player walking into those corners from the quarry floor falls into the void.
   - **Fix:** Extend the tunnel floor at `:419` to cover z -198..-166. Or cut the wall gap's half-width from 7 to 3.5.

4. **A bottomless trench runs along the north-east edge.** `Land.luau:216`, `:489-491`
   - **What goes wrong:**
     - Mountain columns stop at x ≈ 162 because the grid starts at -178 in steps of 40. The invisible wall is at x = 172, and the east grass strip ends at z = -150.
     - This leaves a hole 8–10 studs wide from z = -150 to the north end of the map.
     - The walk simulation reaches it by just walking north along the east edge of town (x ≈ 163–171), where players fall and die.
   - **Fix:** Change the loop to `while gx - cell / 2 <= island.Max.X + 8 do`, which adds one more column row. Or run the east strip to z = -500.

5. **The forge glow and lava fade to black after about 2 minutes on every client.** `src/client/Controllers/DecorController.luau:27` (rescan at `:46`)
   - **What goes wrong:** `scanPulsers` runs every 5 seconds and replaces `base` with the part's current colour, which is already dimmed. It never checks whether the part is already tracked. In a simulation, ForgeGlow went from (255,128,36) to (49,24,7) at 60 s and to black at about 120 s. The same happens to the lava pools, the molten channel and the forge mouth.
   - **Fix:** Use `if not pulsers[d] then ... end`. Better, tag the parts (for example a "Pulse" tag) and use `GetInstanceAddedSignal`. That also removes the `GetDescendants()` call over about 3,500 instances every 5 s.

6. **The loading screen never closes if the character never spawns.** `src/first/LoadingScreen.client.luau:87`
   - **What goes wrong:** `player.CharacterAdded:Wait()` has no timeout. If CharacterAutoLoads is turned off later or LoadCharacter fails, a full-screen GUI (DisplayOrder 1000) stays forever.
   - **Fix:** Wait at most about 15 s, then fade out anyway.

7. **Two signs face the wrong way.** `Land.luau:309`, `:429`
   - **EMBER CAVES:** Its text faces north, into the tunnel, so the quarry only sees the blank back. `docs/screenshots/quarry.jpg` shows a blank board. Fix: use `CFrame.Angles(0, math.pi, 0)`.
   - **GLIMMER GROTTO - VIP:** Its text faces +X, toward the door rather than the players. Its top half (y -1..0.2) is also buried in the tunnel roof (y -1..3). Fix: use `CFrame.Angles(0, math.pi / 2, 0)` and y = `grotto.Min.Y + 9`.

8. **The VIP Grotto has no crystals and no lights.** `Land.luau:420-424`
   - **What goes wrong:** 0 of the 5 crystal clusters are built. Every random spot fails `clearOfNodes(p, 9)` because 12 node spots fill the 58×64-stud room, and the code does not retry. The paid area ends up with 0 PointLights and only the ore glow. Ember Caves also got 4 of 5 lava pools and Deep Hollow 8 of 9 clusters.
   - **Fix:** Retry until the count is reached, as the lava loop does. Place the Grotto clusters along the walls, the way Deep Hollow sides 1–3 do.

9. **The one shadow-casting light is in the busiest area.** `src/server/World/Town.luau:120`
   - **What goes wrong:** The ForgeGlow PointLight has `Shadows = true` with range 40, in the hub where everyone stands. Shadow-casting point lights are the most expensive Future-lighting feature on phones.
   - **Fix:** Pass `false`.

10. **The Heartstone crystal visibly comes apart.** `Town.luau:89-90`, `:93`
    - **What goes wrong:** Only the shard body has the "Spin" tag. Its two Neon tip wedges stay still while the body turns and bobs ±0.4 studs.
    - **Fix:** Move the tips with stored offsets in DecorController, or put the three parts in a Model and use `PivotTo`.

11. **Two sea parts are too big for Roblox (works in Lune only).** `Land.luau:232-240`
    - **What goes wrong:** The north and south sea strips are 2,352 studs wide. Roblox limits a part to 2,048 studs per side, so in Studio those strips shrink and the far corners of the sea go missing. Lune does not check this.
    - **Fix:** Set `far = 850`.

12. **Hardening for the VIP door.** `Land.luau:418`
    - **What goes wrong:** There is a 7-stud slot from x = 78 to 92 between the tunnel roof top (y = 3) and the Grotto ceiling (y = 10). It leads into the Grotto behind the door. Normal walking and jumping cannot reach the roof (the simulation confirms the door is the only way in). A future jump boost or a flying exploiter could go around the door.
    - **Fix:** Fill x 68..92, y 3..10, z -192..-172. When VIP is built, the server should also check VIP status by player position, not rely on the door alone.

### Fixed after review
All 12 issues above were fixed in the next commit:
1. Deep Hollow ramp now starts where the Ember Caves floor ends and is 22 wide (no ledge, no side gaps); jump height set to 7.5.
2. Ground slabs go down to y = -18 (no hole under town beside the quarry ramp).
3. Tunnel walls are 8 thick and the Grotto tunnel floor covers z -200..-164.
4. Mountains now reach the east edge (no trench).
5. Forge glow / lava pulse keeps its original color (no fade to black).
6. Loading screen fades out after at most 15 s.
7. EMBER CAVES and GLIMMER GROTTO signs face the quarry.
8. Crystal clusters retry placement (Grotto has its crystals and lights).
9. Great Forge light: Shadows off.
10. Heartstone shard spins as one model (streams atomically).
11. Sea strips are under the 2048-stud part limit.
12. Rock fill above the Grotto tunnel + server-side VIP position check (AccessService).
Also: ore-node PointLights only on Epic+ (fewer lights in Deep Hollow).

Re-ran the walkability simulation on the rebuilt place: **0 void falls**, Ember Caves,
Quarry and Deep Hollow reachable and walkable back to spawn, Grotto not reachable without
the pass. Only "stuck" spots left: standing on top of the shop counters (harmless, Reset works).

### Mobile performance (numbers from the baked place)

- **Parts:** 3,157 in total: 3,059 visible plus 98 hidden markers. 2,770 can be collided with, 2,196 cast shadows, and all are anchored. Each ore node is 11–16 parts, plus 6–10 per crack stage, so about 1,400 for 98 nodes. This is fine with StreamingEnabled.
- **PointLights:** 52 static (Town 30, Ember Caves 10, Deep Hollow 8, Quarry 4, Grotto 0). Only one has shadows (issue 9).
  - Every Rare-or-better node adds a light. All 26 Deep Hollow nodes are Rare or better, so that one room will have about 34 lights, and Ember Caves about 18.
  - Suggestion: give lights only to Epic and better ores, or shorten their range.
- **Particles:** 34 emitters, about 253 particles/s and about 380 alive at once. Brazier fire (11 × 14/s) is about 60% of that. This is acceptable.
- **Per-frame client work:** DecorController moves 1 spinner and 7 pulsing parts per frame, which costs almost nothing. The only real cost is the 5-second rescan in issue 5. LightingController checks the zone every 0.4 s, which is fine.

### Checked and OK

- **Scripts:** Every property and enum the scripts set exists and can be set by scripts at runtime. `Lighting.Technology` is RobloxScriptSecurity, so scripts cannot set it, and correctly no script tries.
- **Rojo 7.4.4:** Every Lighting, Atmosphere, Sky, effect, Workspace and StarterPlayer value in `default.project.json` ends up in the built place.
  - `"Technology": "Future"` is written as token 4, which is Future.
  - Workspace has `StreamingEnabled` = true, `StreamingMinRadius` = 96, `StreamingTargetRadius` = 384 and `FallenPartsDestroyHeight` = -250.
  - `ClockTime` is CanLoad, so Studio reads it.
- **StreamingEnabled:** No client code depends on map parts having already streamed in.
- **Reachability:** Every zone can be reached from spawn. Apart from Deep Hollow (issue 1), no area traps players.

### What to test in Studio

1. Open `build/TerraForge.rbxl` and press **Play**. The loading screen should fade within a few seconds and you should stand on the plaza. The Output window should show no red errors.
2. Stand in front of the Great Forge for 3 minutes. The glowing doorway, the round lava basin and the lava channel should still glow. If they turn dark, that is issue 5.
3. Look at the floating pink crystal above the plaza monument. Its top and bottom points should turn and bob with it.
4. Walk from the town into the quarry, then the Ember Caves, then Deep Hollow. The light should change smoothly each time: warm, dusty, dark orange, dark blue.
5. Walk down the ramp into Deep Hollow, then walk back up **without** pressing reset. Note whether you had to jump at the top and whether it worked. Also try to walk off the sides of the ramp; you should not fall into darkness.
6. At the bottom of the quarry ramp, walk along both sides of the ramp toward the cliff. You should not be able to walk under the grass or fall forever.
7. In the quarry, read both signs from the quarry floor: "EMBER CAVES" (north) and "GLIMMER GROTTO - VIP" (east). Then walk into the corners just left and right of the green Grotto tunnel; you should not fall.
8. Walk into the glowing VIP door. It should block you, because VIP is not built yet.
9. From the town, go to the far north-east corner, behind the east plots, and walk north along the invisible wall. You should not fall into a hole.
10. On the **Test** tab, choose a phone in **Device**, press Play and turn on **View → Stats** (or press Shift+F5). Write down the FPS in the plaza, Ember Caves and Deep Hollow; it should stay at 30 or more.

## Step b – Mining, items & carrying

Full review: [docs/qa/step_b.md](qa/step_b.md). `tools/check.sh` passed; 12 issues found, all fixed:

1. **Shutdown saves**: BindToClose now waits for every final save in flight (also players who left
   just before), and a failed final save is retried up to 4 times.
2. **Quick rejoin rollback**: a player rejoining the same server waits until their previous final
   save has finished before loading.
3. **Pickaxe grip**: rotated so the shaft points forward out of the fist (confirm in Studio).
4. **Falling items**: rescue line is now y = -60 (checked 4x per second), items destroyed by the
   engine go to storage instead of becoming ghosts, one bad item can't stop the loop, drops raycast
   so they never appear behind a wall.
5. **Item physics exploits**: items are in an "Items" collision group that doesn't hit characters
   (no flinging), the owner's client only simulates an item for 3 s after a drop/throw, and the
   server tracks `LastNearOwner` for machine intake checks (step d).
6. **Full hands**: E / Grab drops when your hands are full.
7. **Item hint** survives respawning (ResetOnSpawn = false).
8. **Floating chunks**: items are no longer anchored to "sleep" (Roblox physics sleeps them itself).
9. **Camera shake drift**: the shake offset is removed before the camera scripts run each frame.
10. **Swing rate**: per-player token bucket (2-swing burst, refills at the pickaxe cooldown).
11. **Dropped item vanishing at the cap**: dropping/ejecting resets the item's age; the cap toast is
    shown at most every 20 s. Loose-item cap lowered to 30.
12. **Net memory**: rate-limit tables are cleared when a player leaves.

Performance: raw chunks are now 6 parts (was 10); carry slots only rebuild when your carry count changes.
