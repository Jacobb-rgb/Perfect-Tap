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

## Step c – Cleaning Station minigame

Four reviewers (server exploits, client/server scoring consistency, client runtime, mobile/input)
found the issues below. Full findings with reproduction steps: [docs/qa/step_c_findings.txt](qa/step_c_findings.txt).
The second-opinion (verify) pass and the design review could not run because the agent usage limit
was reached; every finding was instead re-checked against the code by hand before fixing.
`tools/check.sh` passes: strict types clean, 62 tests (7 new), place builds.

Fixed:

1. **Bot speed (high)**: the server now checks the whole timeline. Every timestamp must fit inside
   the real session time and the steps must come in order (`CleaningScoring.timeline`). *Second
   round:* this only capped the claimed time from above; the real client's pauses are now
   required too (see below), so a bot needs at least as long as a perfect player going through the
   real client.
2. **Crystals self-reported**: the server replays the brush positions with the shared
   `ScrapeTracker`, so the meter and the card agree on crystal hits. (A modified client can still
   leave out positions: see Accepted risks.)
3. **Sessions over 3 minutes rejected**: the 180 s cap is now the session timeout + 10 s.
4. **Fast honest scrubbing rejected** (Epic+ ores): the "too fast" rule now only catches a bot
   (whole-ore scrape in under DirtCount/200 s). A new test scrubs every ore at 4–12 face units/s.
5. **Fast polishing rejected**: the limit is now ~10 turns/s; fast hands just lose points, and the
   client shows "Too fast! Smooth circles".
6. **Tap near the screen edge voided the run**: the chisel ignores points far from the ore, and
   only records samples from the moment the cut starts.
7. **Chisel stuck after ~400 points**: pre-start samples are no longer recorded; a cut that still
   runs out of room restarts with "Try that line again!".
8. **Cut locked to the wrong end (touch)**: letting go before 30% of the line forgets the attempt
   (and its chips), so you can start again from either end.
9. **Station locked for 5 minutes**: a CleanBegin that arrives while the result card is still up
   is cancelled straight away, so the ore stays in the vise with its prompt.
10. **Camera snapped back on quick restart**: the delayed camera reset only runs when no new
    session took over.
11. **Reveal after leaving at the last moment**: no submit or reveal once the player left.
12. **Quality meter ≠ final grade**: the meter now uses the server formulas: chips during
    chisel, the slow-scrape penalty, the rub cap once used, and crystal hits are no longer
    counted twice as chips.
13. **Phone layout**: on small screens the step banner moves to the top-left (under Leave), and
    the camera fits the ore into the free area (`CameraFit`, unit tested for PC, laptop and two
    phone sizes).
14. **Big dust puffs in the close-up**: new small `FineDust` effect, throttled.
15. **Controller on PC**: the input type comes from the last input used, and the hint updates
    when it changes.
16. **Rub toggle unreachable on controller/keyboard**: R / gamepad Y toggles it.
17. **Small touch targets**: Leave, Rub and Collect are larger on touch screens, small text bigger.
18. **Backpack hotbar** is hidden during cleaning (and restored).
19. **Machines spawned before their behaviour registered** now catch up (station prompts in Studio
    without API access).

Accepted risks (cannot be verified by any server):
- **Input**: the client says which input it used (touch and controller get wider lines).
- **Easy polish** (was "Hold to rub"): the client says whether it was used.
- **Crystal hits**: a modified client can leave out the brush positions that snapped a crystal.
  This gains nothing over a fully made-up run.
- **Perfect synthetic runs**: a bot needs at least as long as a perfect player going through the
  real client (5.7 s for Copper to 10.3 s for Heartstone, was 3 s; every pause of the real client
  is required). It still gets Flawless every time, which no server can tell apart from a perfect
  player.

A cheater gains no more from any of these than from feeding a perfect synthetic trace.

### What to test in Studio

1. Clean one ore of each rarity carefully. The grade on the QUALITY meter at the end of POLISH
   should match the grade on the result card.
2. **Test → Device → iPhone SE (landscape)**: the step panel sits top-left under Leave and the
   whole ore is visible between it and the meter. Tap near the screen edge during CHISEL, then
   finish: you get a grade, not "Something went wrong".
3. Start a line from its middle, drag to one end, let go, then trace it from the other end. The
   cut works.
4. Leave the minigame open for 4 minutes, then finish. You get a grade.
5. On a Legendary/Mythic ore, scrub the dirt as fast as you can, and spin very fast when polishing.
   You get a (lower) grade, not an error.
6. Throw two raw ores onto the station; clean the first, wait 2 s on the card, press Collect.
   The station shows "Clean Ore" again right away.
7. Plug a controller into a PC: the hint talks about the stick, Y toggles "Easy polish", B leaves,
   A collects.
8. During cleaning the pickaxe hotbar is hidden; after leaving it is back.

### Second review round (12 confirmed findings, all fixed)

Full findings with reproduction steps: [docs/qa/step_c_round2_findings.txt](qa/step_c_round2_findings.txt).
`tools/check.sh` passes: strict types clean, Lune tests (new: `tests/CleaningPlay.spec.luau` and
four timeline tests in `tests/Cleaning.spec.luau`), place builds.

- **Lifting before 30% erased the cut (Gold+)** and **resume after a lift**: the chisel
  recording rules moved to the shared `CutRecorder`. Letting go keeps the groove. After an early
  lift the next press decides: near the groove tip the cut goes on, anywhere else (for example
  the other end) it starts over. The end the cut started from goes dark and a white "continue
  here" ball pulses at the groove tip while you are not cutting there. Scratch sound, dust and
  sparks only play when the groove moves or you are at its tip; otherwise "Continue from the
  glowing tip!". The server replays the kept samples, and the Lune tests check client == server
  for lifts, wrong-end starts and controller re-presses.
- **Quick restart saved a half-restored camera**: the camera from before cleaning is kept once
  (module level) until the camera is really handed back.
- **Bot lower bound**: `CleaningScoring.ClientPauses` holds the real client's fixed pauses; the
  client waits exactly these and the server's timeline requires them (`MinGaps`, 0.05 s slack):
  first cut after the intro, the crack after every cut, the step finishes, and
  `latest + 0.6 <= elapsed` (`CleaningScoring.fitsSession`). The fastest accepted bot went from
  3 s to 5.7 s (Copper) and 10.3 s (Heartstone).
- **Crystal omission**: documented as an accepted risk (above).
- **Phones got Rough on Legendary/Mythic**: `InputLeniency.Touch` 1.35 → 2.0 (Gamepad 1.25 →
  1.4). Lune model (phone at 105 pt per face unit, 8 pt wobble, 60 seeds): Mythic reaches Clean or
  better in 96% of runs (61% before).
- **Station prompts hid each other**: "Take Ore Back" uses G / gamepad B and always shows next
  to "Clean Ore" (F / Y). "Clean Ore" keeps the default exclusivity so one F press never fires
  two machines' prompts.
- **Polish speed**: the SPEED needle shows the real speed (angle covered in the last 0.3 s, same
  samples the server scores) and is green exactly inside the band; "Slower!" / "Faster!" pop up
  after 0.3 s / 0.5 s outside it; the ring's moving dot runs at a good speed (4 rad/s, mid-green);
  the instruction says to keep the needle in the green. `PolishBand.Max` 8.5 → 10.5: shaky hands
  now keep ≥ 0.98 polish from 0.5 to 0.8 turns per second.
- **Dirt look-alike under crystals**: replaced by a small pale base (smaller than the snap zone);
  the crystal is Neon and leans out toward the camera. The last 3 dirt patches pulse.
- **Leave**: hidden (and B unbound) during the reveal; the buttons say "Leave (B)" / "Collect (A)"
  on a controller; once a cut is done the first press asks to press again within 2 s ("Your ore
  stays in the vise.").
- **"Hold to rub"** is now "Easy polish (R/Y): ON/OFF"; the first time it counts it says
  "Easy polish: max 75% shine".
- **Chisel hid the dots ahead**: the chisel is see-through while you press, and on touch the tools
  disappear when the finger is lifted.

What to test in Studio:

1. Gold or rarer ore, CHISEL: trace a quarter of a line, let go, press again where the groove
   ends and finish the line. The cut finishes. Then on the next line: touch one end briefly, let
   go, trace the whole line from the other end. That works too.
2. Trace half a line, let go, then drag from the other end: no scratching, "Continue from the
   glowing tip!", and the white ball shows where to go on.
3. Start cleaning, press Leave twice, and press F on "Clean Ore" right away (spam it). Leave
   again and wait 2 s: Workspace.CurrentCamera.FieldOfView is back to 70.
4. Clean a Copper ore as fast as you can and a Heartstone normally; with Studio's incoming
   replication lag at 0.3–0.5 s too. You always get a grade card, never "Something went wrong",
   and no `[CleaningService] rejected` line in Output.
5. Put raw ore in the vise, start, Leave. At the station both "Clean Ore" (F / Y) and "Take Ore
   Back" (G / B) show, on keyboard, controller and touch.
6. POLISH: follow the moving bright dot: the needle stays green and Polish on the card is
   ≥ 90%. Circle fast (2 turns per second): "Slower!" appears.
7. Gold+ ore, SCRAPE: the crystals glow and stick out, there are no brown squares under them,
   and on an iPhone SE window they are easy to see.
8. Controller: B once after the first cut shows "Press again to leave"; B again leaves. On the
   result card there is no Leave button and B does nothing; A collects.
9. POLISH: turn "Easy polish" on, rub a moment, turn it off and finish: a message says the shine
   is capped and the card shows Polish ≤ 75%.
10. A line running from bottom-left to top-right: while you hold the button the chisel is
    see-through and the dots ahead stay visible.

## Quick teleports (2026-10-17, branch feature/teleport-bar)
Owner: "at the top in the middle an instant spawn to base, next to it the lobby, third the weapon vault; the
elevator by the icon on the side". TeleportService / TeleportController / TeleportView, TeleportConfig.
What to test in Studio:
1. PC: click BASE, LOBBY, VAULT. The screen goes dark for a moment and you land at the front of your plot,
   at the town spawn, and in front of the Blaster Vault's steps, facing them. Carried ore comes along.
2. Click again within 3 s: the buttons show a countdown and a "Wait a moment" toast; nothing moves.
3. Phone (Studio device emulator, iPhone SE): the three buttons are tall (icon over the name), easy to tap,
   and don't touch the coins panel.
4. Controller: D-pad down selects BASE; left / right moves; A teleports; B or D-pad down again leaves the bar.
   The D-pad glyph shows next to the bar only while you use a controller (Xbox and PlayStation glyphs).
5. Start cleaning ore and press a button: "Finish cleaning first", no teleport. Build mode hides the bar.
6. Sit on a seat (the train, a bench) and press LOBBY: you get up and land in the lobby.
7. The LIFT icon under BUILD stays hidden until the world has a mine elevator (art/mine-floors); with it,
   LIFT puts you in front of the lowest elevator stop.

## Blaster Vault shop + crate opening (2026-10-18, branch feature/vault-shop)
Owner: "click the cape (counter) and a menu of cases with blasters opens", then the approved crate-opening
animation in the game. VaultService / VaultController / VaultView / CrateOpeningView, Builders/CaseBuilder +
CrateOpeningStage (the preview video's animation rebuilt from parts), BlasterData.Vault (prices, case looks).
The Vault sells only your NEXT level, for coins only: 4x the Foundry's coin price (Lv4 60K ... Lv10 6B), in that
level's case look (Copper, Cobalt, Amethyst, Gold, Emberite, Sapphire, Obsidian, Royal Aurum, Heartstone).
The Foundry stays the cheaper way (ingots + coins) and lets you pick the ore look.
QA notes: buy is checked on the server in one step with no yield (level = yours + 1, at the counter within 30
studs, coins), so a double tap or a spammed remote buys one level (tests/VaultService.spec.luau fuzzes it);
every request gets one VaultResult; the prompt key is F / Y because E is the game's grab key.
What to test in Studio:
1. Walk to the vault counter: "Blaster Vault" prompt (F, gamepad Y). The window opens: your level's cards say
   OWNED, the next one has the gold outline, NEXT and a green BUY, the rest LOCKED, LV 11 SOON.
2. With too few coins the price is red; BUY says "Not enough coins" in the footer and nothing is sent.
3. BUY with enough coins: "..." then the screen fades into the dark room: the case drops, hums, bursts
   (flash, light pillar, shards), the blaster rises and spins; "NEW BLASTER!", rarity, name, LV, damage, then
   AWESOME!. Click / tap / A before the burst jumps to the burst; AWESOME!, A, B, Enter, Space or Backspace end
   it. Back in the vault you hold the new blaster and the coins went down by the price.
4. During the cinematic: no walking, no prompts, no HUD, no backpack, no touch buttons; after it all come back
   and the camera follows you again (FieldOfView back to 70).
5. Reset your character during the cinematic: it ends at once, the camera and HUD come back.
6. Walk 25 studs away with the window open: it closes. B / Backspace / the red X close it too.
7. Phone (iPhone SE emulator): one row of wide cards that scrolls sideways, the NEXT card in view, BUY and X
   are easy to tap. Controller: A on the selected card buys, the row scrolls with the selection.
8. The display cases behind the counter have the same colours as the shop's cases.

## Blaster shooting feel + sounds that play (2026-10-18, branch feature/blaster-feel)
Watcher task: a stronger beam with a muzzle flash, hit sparks and chips, a small recoil, satisfying hit and break
sounds, the Lv7+ effects visible while firing, light on phones. Config/BlasterFeel (all tuning), Effects/BlasterFx,
Vfx.setBeam style (width, light, the Lv7+ energy stream, the hit swell), CameraShake.kick (recoil), MiningController
hooks (start / stop / hit), FxController (other players' beams get their tier look; your own hit crackle is local).
Sounds: today's Roblox clients ship only 11 files in content/sounds, so most rbxasset://sounds/*.wav ids were silent.
Every SoundConfig id is now a shipped file or Roblox's own upload of the classic sound (same keys, ids only), and
tests/BlasterFeel.spec.luau checks every id. New keys: BlasterBeam, BlasterZap, BlastThud, RockBreak, ElevatorDing,
DoorThud. The rock chips use the rock's crust colour (the ores inside stay secret until cleaned).
What to test in Studio:
1. Fire at a rock (PC): a bright flash at the muzzle when you press, the gun jumps back a little and settles, the
   view tips up a hair; while the beam is on the rock: sparks in the beam's colour, small chips every third of a
   second, a crackle and a soft thud. Sounds play (UI clicks too: they were silent before).
2. A Lv7+ blaster: sparkles stream along the beam from the gun to the rock and swirl off the muzzle. Lv10: a shock
   ring at the hit with the chips.
3. A rock you can't mine yet (Needs Lv N): only dull grey sparks, no chips, no thud.
4. Phone (emulator): about half the sparks, no camera kick, the gun kick still shows; no stutter on an iPhone SE.
5. Another player fires near you: you see their beam in their level's thickness (Lv7+ with the energy stream).
6. Equip / unequip while firing, reset while firing: the gun is back in the hand normally, no stuck offset.
7. Listen to the new picks and swap any you dislike in SoundConfig: BlasterBeam (Roblox "UFO Beam" loop, quiet),
   BlasterZap (flashbulb), BlastThud (hit.wav), RockBreak (the shipped explosion, high pitch), ElevatorDing
   (Roblox pinball low bell), DoorThud (collide.wav, low pitch).

## Steps 6-7 integration (2026-10-18, branch integrate/steps67)
The six steps 6-7 branches (P0 contracts, Gear, Enchants + Boosts, Capsules + Golems, Wheel + Artifacts,
Leaderboards + Codex + Side menu + Settings) merged onto main (teleport bar, Blaster Vault, blaster feel, lobby).
Integration decisions:
- Golems for the coming 36-ore roster: Rose Knight (CrystalRose), Storm Titan (StormGem), Celestial Sovereign
  (CelestialCore), same rarities and bonuses. Until OreData has those ores they wear the colours of their
  FallbackOre (Ruby, Stormcore, Starmetal). Saves with the old ids (RubyKnight, StormcoreTitan,
  StarmetalSovereign) get the new ids on load (GolemConfig.Renamed, Migrations) and stay equipped / locked / paid.
- Side menu entries are data (Group Main / More, Order, IconName -> one emoji table) for the light-UI restyle:
  GOLEMS and SHOP are Main, the rest More; shown sorted by Group then Order (GOLEMS, SHOP, CODEX, ARTIFACTS,
  BOARDS, SETTINGS, STORE; STORE stays hidden until step 8's StoreController exists). The ARTIFACTS button shows
  the unread-chapter badge.
- One entry per panel: with the side menu in the game the HUD has no GOLEMS or BOOK button and the BOOSTS launcher
  chip is off (SHOP opens the boosts). Hotkeys stay: P / L1 golems, L / D-pad right boosts, J book.
- MenuPanels.Names is the one list of panels (VaultController and GearShopController added): opening any panel
  closes the others.
- D-pad: Left side menu, Right boosts, Down teleport bar, Up build mode (now only while no menu holds the gamepad
  selection, so D-pad Up moves inside the side menu instead of entering build mode).
- The wheel's capsule prize: CapsuleService.grantFree honours `quiet` (QuietFree), so the capsule opening plays
  after the wheel's prize card ("Reveal"), not while the disc turns.
- Camera shake OFF in Settings also stops the blaster recoil kick.
- State pushes: Discovered and CodexSeen are sticky (sent only when they change).
- Budgets: the 8 yard museums (~350 parts, built at server start) count toward MapParts (22,000 -> 22,400) and
  LobbyParts (fits, 12,800 unchanged); tests/LobbyBudget.spec.luau builds them.
What to test in Studio:
1. Side menu (PC): GOLEMS and SHOP on top, then CODEX, ARTIFACTS, BOARDS, SETTINGS. STORE is hidden until step 8
   (its StoreController isn't in the game). No GOLEMS / BOOK buttons in the right HUD menu, no BOOSTS chip under the
   coins while no boost runs.
2. Open the Blaster Vault, then press P: the vault window closes, the golems open. Open the Gear shop, then the
   Enchant table: only one window at a time.
3. Controller: D-pad Left jumps into the side menu; D-pad Up / Down move inside it (no build mode, no teleport
   bar); B leaves. Outside the menu D-pad Up still enters build mode on your plot.
4. Win a capsule on the daily wheel: the disc stops, the prize card shows, then the capsule opening plays once.
5. Settings: Camera shake off -> firing the blaster no longer tips the view.
6. An old save with a Ruby Knight: it is a Rose Knight now, still equipped.

### Steps 6-7 review fixes (db4db37) and final fixes
Review round: one receipts gate for every Robux product and pass (src/server/Receipts.luau), the Sell Box and the
pen-full sale pay the sell bonus, one Crystal Extractor shard roll per crushed pile (data.ShardRolls), MaxOreLuck =
both luck caps, one left column (coins, TRAIN chip, boost chips, side menu), panels close for cleaning and build
mode, the lobby SPIN & WIN disc lands on your prize, museum relics built on the client near the camera,
LeaderboardService.removeUser hides a user on every server. Final fixes: a server writes no leaderboard score
before it has read the saved hidden list once (a failed first read is retried after 10, 20, 30 s, not 5 min; the
round and leave writes wait for it; tests/Leaderboards.spec.luau), and COMPLIANCE 2.6a / section 3 / section 4 say
to keep every game pass Off Sale until step 8 (the gate only blocks in-game prompts; the Store tab sells passes).
bash tools/check.sh: ALL CHECKS PASSED (strict luau-lsp no problems, 1010 Lune tests, map v22 baked, 20,368 parts).
What to test in Studio:
1. Receipts gate: in MonetizationConfig give HexaLucky15 and EnchantStarbreaker a test id (any number, Studio only;
   put the 0 back afterwards) and leave Receipts as it is. SHOP -> Boosts -> Hexa Lucky: the Robux offer is greyed
   COMING SOON; the Enchant table's Starbreaker button reads "20 R$ • SOON", greyed. In the server command bar
   `require(game.ServerScriptService.Server.Services.BoostService).promptPurchase(game.Players:GetPlayers()[1],
   "HexaLucky15")` returns "ComingSoon" and no purchase window opens. Then
   `require(game.ServerScriptService.Server.Receipts).setReady(true)`: with the shop open the cards switch to the
   R$ price (close any test purchase window without buying; nothing would be granted before step 8).
2. Sell bonus: equip a Coal Chomper (+4 % sell value) or slot Midas. Sell one ore at Tobin's counter, then put the
   same kind of ore into a Sell Box: the Sell Box's popup and your coins show the same bonus price as the counter
   (base price x the bonus, not the bare base). Pen full: set GameConfig.MaxStoredItems to 2 for the test, fill the
   pen, then pick up a machine with ore still inside: that ore is sold at the same bonus price (source "PenFull").
3. Crystal Extractor: crush ore in a Crusher and feed the piles into the extractor: shards come now and then
   (15 %). Put the extractor's own output back in (Put In again, or a belt loop): no shard ever comes once
   `require(game.ServerScriptService.Server.Services.DataService).get(game.Players:GetPlayers()[1]).ShardRolls`
   is 0; each new pile from the Crusher adds one roll.
4. Left column, PC: coins, TRAIN chip, the running boost chips, then the side menu under them; nothing overlaps.
   Phone (device emulator 568 x 320, iPhone SE 1st gen landscape): the 44 pt MENU button sits first in the train
   chip's row, left of the TRAIN chip; tapping MENU opens the grid over the TRAIN and boost chips and MENU turns
   into CLOSE; the bottom-left thumbstick corner stays free. Also 667 x 375. TV (Xbox emulation): the column keeps
   clear of the left and bottom 5 %, the labels are bigger.
5. Boosts stay shut: start cleaning an ore and press L (or D-pad Right): Boosts doesn't open. Open Boosts (or the
   golems, the book, the wheel), then start cleaning or enter build mode: the window closes. In build mode L does
   nothing.
6. Lobby SPIN & WIN: stand within 160 studs of the lobby disc and spin the daily wheel: the lobby disc turns and
   stops on the same prize as the disc on your screen, rests there 15 s, then turns on. Its 8 segments
   match the screen wheel's prizes, clockwise. A second Studio player keeps seeing the idle turn.
7. Museums: with artifacts found, walk to your yard museum: the relics appear in their cases when the camera is
   within about 100 studs. Walk (or fly the camera) more than 130 studs away: the relics go; come back: they
   return. Sign and plaque texts disappear past 120 studs.
8. LeaderboardService.removeUser (a live test server, a test account of your own; Studio never writes the
   boards): while the test account plays, run
   `require(game.ServerScriptService.Server.Services.LeaderboardService).removeUser(<its UserId>)` in the
   Developer Console's server command line. Its rows leave the lobby boards and the BOARDS panel at once and don't
   come back after 3 more minutes of play (two write rounds), after it leaves and rejoins, or on a server started
   afterwards. The server output shows no "reading the hidden list failed" warning at start (if it does, the
   scores of everyone on that server reach the boards only after the retry, 10-30 s later).
9. Before publishing (Creator Dashboard, not Studio): every game pass stays Off Sale (Monetization -> Passes ->
   Sales) until step 8 is live and calls Receipts.setReady(true).

## Blaster gallery in THE GREAT FORGE (2026-10-18, branch feature/blaster-gallery)
V2_PLAN section 5 ("THE GREAT FORGE | landmark (blaster gallery: levels 1-10 + Coming soon)"), placed with the
Plaza owner's ok (option A: inside the hall, seen through the door from the porch and the stairs).
Plaza/BlasterGallery: a rack of two rows on each side wall of the hall, turned 12 degrees toward the door. Each
plaque has the real game gun (BlasterBuilder) in its level's case ore, a glowing rim in the ore's glow and two plates
(LV n, the blaster's name). The viewer's right wall has LV 1-3 below and LV 4-5 above (the forge's tool rack moved up
into the third slot). The left wall has LV 6-8 below and LV 9, LV 10 and LV 11 above (a dark silhouette, a violet
"?" and COMING SOON). The niche over the furnace hood was only 1.3 studs tall and hidden behind the z 5 beam, so
LV 11 went on the wall. 334 parts, one soft violet light (LV 11), no shadows, nothing collides or is raycast.
Budgets: MapParts 22,400, LobbyParts 13,200, Plaza 2,000 parts / 11 lights. Map v22.
What to test in Studio:
1. From the plaza and the stairs: the door still glows; inside you see the two racks with the guns and the plates.
2. Walk into the hall: you can walk through the gallery (no collision), the plates read (LV n, the name) and the
   LV 11 "?" glows violet. The tool rack hangs up at the back of the right wall.
3. Phone: no frame drop when you stand on the porch.

## Steps 6-7 on top of main 49c2bac (2026-10-18, branch integrate/steps67)
main (blaster gallery, the 36-ore roster, roster machine FX, night QA, hand-cleaning reveal, step 8 tutorial) merged
into the steps 6-7 integration. Decisions:
- One save chain: Migrations runs main's renameOres first (it now also renames the ORE CODEX's seen ores, so a
  renamed ore you had looked at gets no NEW badge), then the steps 6-7 sanitizers (gear, enchants, boosts, golems
  with GolemConfig.Renamed, wheel, artifacts, stats). Version stays 3. tests/Migration.spec.luau has a save with
  both the old ore ids and the steps 6-7 records.
- Golems: GolemConfig.FallbackOre is gone: Rose Knight wears Crystal Rose, Storm Titan Storm Gem, Celestial
  Sovereign Celestial Core (all in OreData now).
- The wheel's ore prize for a new player is the Quarry's Rare ore, Bronze (same 130 coins/s as the old Gold; no
  balance change). The codex counts 36 ores. The Forgemaster's Pass text lists the new Grotto odds (from the map).
- Map v25 (the steps 6-7 lobby wheel disc and yard museums on top of main's v24). Budgets: MapParts 22,800
  (22,000 + 400 gallery + 400 museums), LobbyParts 13,200, PhoneParts 18,000 (the lobby + always-streamed parts
  + the 8 yard museums = ~15,630).
- Phone side menu: with the grid open (MENU -> CLOSE) the TRAIN chip and the boost chips hide; they come back when
  the grid shuts (before, the grid half-covered the TRAIN chip and its SEND button stuck out).
- Artifact book on phones: the detail card puts the icon beside the name whenever the tall card would cut the text,
  so "Most often in ...: 1 in N" always shows (667 x 375 and bigger; on 568 x 320 the lore scrolls under it).
- Second sync with main (308d257: the security audit fixes in TeleportService / MachineService / Placement /
  CleaningService, docs/SECURITY_AUDIT.md, docs/SERVER_PERF_AUDIT.md, the mining network diet). MiningService keeps
  both sides: the steps 6-7 Bonuses notes and main's Network note in the header, and its test reset clears
  artifactCallbacks, glowCache and healthDirty. Rebaked (map v25, 20,668 parts).
- Tutorial vs the daily wheel: the wheel's ore prize (a dirty ore straight into the pen) counted as "ore came home by
  train", so a new player who won it jumped from step 1 to "Clean your ore". WheelService now counts these ores
  (Stats.WheelOres, sanitized by Migrations); TutorialConfig.home counts the pen only with more in it than the wheel
  gave, and the first four steps take a clean as "done before" only beyond the wheel's ores (cleanedMined).
- Touch: the tutorial bubble and the FREE SPIN! chip share the top row right of the teleport bar (568 x 320,
  667 x 375, 1024 x 768 all overlap). The chip waits while the bubble is there (TutorialController.inTopRow /
  onTopRowChanged -> WheelView.chipVisible) and chimes when it comes. PC and TV keep both (the bubble is bottom right).
  The chip also follows main's icon-only bar under 600 pt (WheelView.chipOffset / buildChip / placeChip take the
  screen width; on 568 x 320 it moved 57 units in, the same gap after the bar as on other screens), and so do the
  steps 6-7 phone previews (menus, wheel_artifacts with a new ui_chip_phone_small, yard).
- The tutorial bubble, its guide beam and R3 hide while a panel other than the steps' own is open (CODEX, GOLEMS,
  ARTIFACTS, BOOSTS, SETTINGS, HALL OF FAME, the wheel, the shops; the Ore Pen, Tobin's counter, the Tech shop
  and the Foundry keep it: TutorialView.StepPanels). Before, R3 twice inside a panel skipped the tutorial.
- ORE CODEX: "Blaster level N+" is the lowest gate of the zones that hold the ore (Bronze 1, Sapphire / Dragon Egg /
  Diamond 3), so it agrees with "Found in" (CodexView.levelOf; the ore's own Tier only when no zone holds it).
- BoostConfig's Deep Hollow example says factors now (Hexa Lucky: Mythic about x3.8, Legendary about x2.4), checked
  by tests/Step67Config.spec.luau. That spec's Quarry check still asked for Gold, which left the Quarry with the
  36-ore map, and passed on NaN: it checks Bronze now, and T.near fails on NaN (no other test relied on it).
- docs/BALANCE_SIM.md + tools/lune/balance_sim.luau: steps 6-7 are merged but not modelled yet (gear except the
  Backpack, golems, boosts, enchants, capsules, wheel, artifacts); re-run on the merged config (the Backpack prices),
  tables and chart refreshed.
- bash tools/check.sh: ALL CHECKS PASSED (strict luau-lsp no problems, 1059 Lune tests, map v25 baked, 20,668 parts).
Checks from the night QA list (docs/QA_NIGHT_2026-10-18.md, "Still to check"):
- Keys the steps 6-7 add, none taken twice:

  | Action | PC | Gamepad | Touch |
  |---|---|---|---|
  | Golems | P | L1 | side menu GOLEMS |
  | Boosts | L | D-pad right | side menu SHOP |
  | Artifact book | J | (side menu) | side menu ARTIFACTS |
  | Side menu | click | D-pad left (B leaves) | MENU button |
  | Daily wheel | FREE SPIN! chip / F at the Spin & Win chest | Y at the chest, the chip by UI selection | the chip / the chest prompt |
  | Ore Codex | F at the ROCK SCANNER / side menu | Y / side menu | prompt / side menu |
  | Panel tabs | click | L1 / R1 (only while the panel is open) | tap |

  next to main's T / L3 train, D-pad down teleport bar, D-pad up build mode (only while no menu holds the
  selection), R3 tutorial, E / X grab, Q / R1 throw, R2 blast. The golem toggle and the panels pass while build
  mode or the cleaning minigame has the controls.
- Net events: every event a script fires, sends or listens to is in Net.Events (GearAction, EnchantAction,
  BoostAction, CapsuleAction, GolemAction, WheelAction, ArtifactAction, SettingsSave, CodexSeen, ActionResult,
  CapsuleResult, WheelResult, ArtifactFound, PurchasePrompt, Leaderboards; main's TutorialAction / Tutorial).
  Tags: ShopCounter (gear), EnchantCounter, CapsuleStall, EmberChest, Spin, Leaderboard, OreCodex, Museum,
  ArtifactPrompt, MagnetPulled: none reuses one of main's.
- Sounds: every Sfx.play / Sfx.loop key (38) exists in SoundConfig.
- Budgets (map v25): map + ore nodes + 8 museums 22,336 parts (MapParts 22,800, 200 kept free), lobby 12,835 /
  13,200, phones 15,625 / 18,000.
Owner to-do (Creator Dashboard, not Studio): the Grotto weights changed with the 36-ore map. Paste
`MonetizationConfig.grottoOddsText()` into the Forgemaster's Pass description: "Glimmer Grotto ore: 19.0% Silver,
16.9% Gold, 14.8% Emberite, 14.8% Amber, 10.6% Jade, 8.5% Sapphire, 6.3% Dragon Egg, 4.2% Diamond, 3.2% Amethyst,
1.6% Crystal Rose." (COMPLIANCE.md: the Dashboard text must follow whenever the weights change.)
What to test in Studio:
1. Old save: in a test place give yourself data with Ruby / Skyglass ores (pen, podium, Discovered, the codex's
   seen list) and a Ruby Knight golem; join: Bronze / Storm Gem everywhere, the Rose Knight still equipped, the
   codex shows no NEW badge on Bronze.
2. Phone emulator 667 x 375: tap MENU: the TRAIN chip and the boost chips disappear, the grid stands in their
   place; tap CLOSE (or wait for the auto-shut): they are back. Same on 568 x 320.
3. Phone emulator: open the artifact book, tap several artifacts: the "Most often in ..." line is always in view.
4. The tutorial and the side menu together: the tutorial bubble (right side) never covers the left column. On
   touch (device emulator 568 x 320, 667 x 375 and an iPad 1024 x 768) with a new save, the free spin is ready at
   once: the FREE SPIN! chip does NOT show while the tutorial bubble is in the top right; skip or finish the
   tutorial and the chip appears there with its chime. On 568 x 320 the chip keeps the same small gap after the
   icon-only BASE / LOBBY / VAULT bar as on bigger screens (no extra hole the width of half a button). With the
   mouse (PC) both show: the bubble bottom right, the chip top.
5. Wheel ore during the tutorial: new save, spin the wheel at the Spin & Win chest until the Ore Prize comes (or set
   the roll in a test place): the tutorial stays on 1 / 8 "To the mine!" and later walks Mine -> Load -> Train as
   usual; the dirty ore waits in the pen. Clean that wheel ore before mining: still 1 / 8.
6. Gamepad: during the tutorial open the CODEX (or GOLEMS, the wheel...): the bubble and the guide beam go, R3 does
   nothing (no "SURE?"); close it: the bubble is back. In the Ore Pen (the Clean step) the bubble stays.
7. ORE CODEX: Bronze reads "Blaster level 1+", Sapphire, Dragon Egg and Diamond "Blaster level 3+".

## The owner-approved Kenney-shape blasters in the game (2026-10-18; owner's yes 2026-10-20, branch art/kenney-blasters)
The blasters the owner approved on 2026-10-17 (the Kenney Blaster Kit shapes, the Ore Glow lava / galaxy skins,
crystals from Lv 4, flames / sparks from Lv 7) as the game's held guns. The prototype
(tools/lune/lib/blaster_kenney.luau) had 139-408 parts per gun, so tools/kenney/blaster_lite.py traces lighter shapes
(Builders/KenneyShapes). Each region is covered by a few overlapping boxes and wedges instead of being sliced into
strips, which gives 22-62 parts for the shapes and 8-23 for the black silhouettes. Builders/KenneyBlaster adds the
skin (a glowing rim on the main panel, lava cracks or stars), the crystals, the Lv 7+ emitter, the MuzzleGlow and
the Muzzle. Every level in every ore stays within 90 parts (tests/KenneyBlaster.spec.luau; the classic guns had
25). BlasterBuilder.build makes the new guns; the classic guns (buildClassic, its kit pieces and the before /
after compare previews) are gone since the owner's yes. The held tool, the Vault's crate opening, the Great Forge
gallery and the Foundry's NEXT rack (BlasterBuilder.silhouette) all use them. Effects/BlasterFx still finds its
Muzzle.
With it (owner 2026-10-20): the Vault's case colours follow the rarity. BlasterData.Vault.Ores is LV 4 Emberite,
LV 6 Sapphire, LV 7 Amethyst (was Amethyst, Emberite, Sapphire), so the cases, the Vault's display cases and the
gallery guns go Common, Uncommon, Uncommon, Rare, Rare, Epic, Epic, Legendary, Mythic (tests/VaultService.spec.luau
pins "never a rarer ore below a commoner one"). Saves keep the BlasterOre a player already has.
Budgets (main 19e3303 + this): map v35, 28,435 baked parts with the mine floors (20,860 without them), Plaza 2,176 of
2,250 (the gallery's guns at display detail), LobbyParts 13,700 and MapParts 23,000 unchanged.
At join the tutorial bubble and its guide wait for the loading screen (Loading.wait; shown either way after it).
What to test in Studio:
1. Equip the blaster at levels 1, 4, 7 and 10 (Studio dev kit): the gun sits in the hand, the barrel points
   forward, the beam leaves the barrel's tip, the muzzle flash shows at the tip.
2. Lv 7+: slow flames (hot ores) or sparks around the gun. Lv 10: the crystal crown around the barrel.
3. Phone emulator with 10+ players holding guns: no frame drop.
4. The Vault's crate opening and the Great Forge gallery show the new guns; the Foundry's NEXT rack shows the
   new black silhouette.

## Platforms, Belt Lift and Slide (2026-10-20, docs/plans/PLATFORMS_PLAN.md phases 1-2)
Owner's YES: a second building level on the plot. Platform (a 2x2 deck 5 studs up), Belt Lift (items up), Slide
(items down); flat belts may run under a deck, other ground machines may not.
What to test in Studio:
1. Buy a Platform, a Belt Lift, a Slide and belts (Tech shop). Place the platform, then a belt and a Brick Furnace on
   it (over a deck cell the ghost jumps up onto the deck). A furnace under the deck is red: "Only belts fit under a
   platform".
2. Place a Belt Lift with its high end against the deck (the amber plate shows the deck cell it must reach), a ground
   belt into its low end and a deck belt where it arrives. Drop ore on the ground belt: it rides up the lift onto the
   deck belt (watch the 1-stud gaps at both ends and the slope's grip). The same down a Slide.
3. With a belt held over a deck cell press V (PC), D-pad Up (gamepad) or the DECK / GROUND button (touch): the ghost
   goes under the deck. B on a gamepad still leaves build mode.
4. Pack up a platform with something on it: "Clear the platform first". Empty, it packs up.
5. Rejoin: deck machines come back on the deck; a deck machine whose platform is gone waits in the Build menu.
6. Phone emulator: the DECK / GROUND button sits with the other big buttons and is easy to tap.

## Rebirth B "STAR FORGE" (2026-10-20, owner's pick, branch feature/rebirth)
Option B of the rebirth proposal: an optional restart that keeps the factory and pays Forge Stars for the Star Shop.
- Rules (Shared/Config/RebirthConfig): a rebirth needs blaster LV MinBlaster (top - 4 = 6). It resets coins, the
  blaster (LV 1, or Head Start's LV 2 / 3 / 4 in that level's Vault look), the floors with it and the elevator,
  Bellows and every Tech shop level, the train's levels, the Backpack, and every ore you own (pen, podiums unless
  Podium Keeper, the Foundry's ingots, the train cargo, the machines' queues, loose and carried items). It keeps the
  placed factory, machine slots, the pen size and automation, the other gear, golems, enchants, artifacts, codex,
  hoverboards, shards, stats, leaderboard totals and every Robux item (Purchases, PurchaseLog, Enchants.Passes,
  Golems.Pending, the session perks are never touched).
- Stars per rebirth follow the blaster prices: MinStars (2) at MinBlaster, MaxStars (10) at the top, the levels
  between by the log share of their total Foundry coins (today 2 / 3 / 6 / 7 / 10 for LV 6-10). tests/Rebirth.spec
  pins the relationships (x10 prices keep the curve, a dearer level never pays fewer stars, the whole shop is 8-25
  typical rebirths, its cheapest perk costs at most MinStars, Head Start never reaches MinBlaster, no perk outgrows
  its StatConfig cap), not the numbers.
- Star Shop: Golden Touch (+10 % podium income and sell value, 10 levels), Head Start (3), Lucky Rocks (+5 % ore luck,
  5), Deep Pockets (+1 carry, 3), Express Rails (train trips -10 %, 3: StatConfig TrainTimeCutPct through
  TrainConfig.tripSeconds), Podium Keeper (1). The stat perks reach the game through Bonuses' built-in "Rebirth"
  provider. Not built yet: the plot glow colour perk (cosmetic) and a prompt at THE GREAT FORGE's crystal.
- Server: RebirthService (RebirthAction Rebirth / Buy -> RebirthResult). The rebirth runs in one step:
  PlotService.reload takes the plot down and up on the same plot (machines respawn from the save with empty
  queues), items leave the world, TrainService.resetRun, the podiums redraw, saveNow, the character goes home after
  the moment. Saves: Rebirths, Stars, StarPerks, Stats.StarsEarned (Migrations keeps a newer build's perks and
  levels; the Migration newerSave guard covers them).
- Client: the STAR FORGE window (REBIRTH: YOU LOSE / YOU KEEP / YOU GET and REBIRTH! with a SURE? second press;
  STAR SHOP cards), the moment (flash, "REBIRTH n!", +stars, falling stars), a gold "⭐ n" over every player's name,
  REBIRTH in the side menu's More group with a badge while a rebirth is ready.
- Side menu: on a 568 x 320 phone, STORE and REBIRTH together (11 cells with MENU) fit no grid at 44 pt. STORE is
  hidden until its controller ships, so today's menu fits; decide when STORE lands.
- Review fixes: the welcome-back payout still waiting at a rebirth is settled first (PodiumService.settleOffline: it
  can't land in the new run), no rebirth during an elevator ride ("Busy"), other players' clients see the
  announced train empty and roll back (Fx TrainUnload, 0), a slotted enchant stays in a slot the blaster level hasn't
  opened (Migrations; EnchantConfig.stats reads open slots only, so a rebirth never unslots, paid ones included),
  a failure after the reset still reports the rebirth (each later step on its own), "Failed" when taking the plot
  down breaks, and the Golden Touch / Lucky Rocks cards say they count up to the bonus caps.
- Second review fixes (the integrator's reviewer): dusty relics are artifacts, never lost (a carried / loose relic is
  stashed through the relic keeper; relics in the pen, the train and machine queues such as the Restoration Table
  stay in the pen at the reset and go to the keeper); after the first rebirth the stars count only a blaster level
  FORGED at the Foundry in the run (Stats.RunForged; Vault cases + Podium Keeper made stars a few minutes of idle
  income), "NotForged" otherwise; Stats.BestBlaster keeps the highest level ever, and every coin price that grows
  with the blaster (capsules, coin boosts, the wheel's capsule fallback, their client cards via State.PriceLevel)
  follows BlasterData.priceLevel, so a rebirth never makes them cheaper; the enchants stay slotted with the paid
  ones (Enchants.Passes) moved first into the open slots, and YOU LOSE lists the closed enchant slots.
- Extras (2026-10-20, the watcher's list): the Plot Glow perk (5 levels, 1 star each: Bronze, Silver, Gold,
  Diamond, Prism; World/PlotGlow: a neon ribbon on the pad's side and front walls and a crystal beacon on each corner,
  8 parts, no lights, no shadows, nothing collides; built at runtime into the owner's plot, the pick in
  data.PlotGlow, the card's COLOR button cycles the unlocked colours and off) and a "Star Forge" prompt (F / Y) at
  THE GREAT FORGE plaza's fire crystal that opens the window (OpenUI "Rebirth"; an invisible anchor on the crystal's
  axis, no map change). The PC Star Shop fits all 7 cards (panel 650, cards 134 tall, buttons 46).
- Owner's answer (2026-10-20): Robux-bought coins that are still unspent stay through a rebirth (data.PaidCoins, spent last; earned coins reset).
What to test in Studio:
1. Studio dev kit, blaster LV 8: the REBIRTH tile shows its badge and a toast. Open it: the lists, "a rebirth now
   pays ⭐ 6", REBIRTH! asks SURE?, the second press plays the moment and sends you home.
2. After it: coins 0, blaster LV 1, the factory stands where it stood with empty machines, pen / podiums / Foundry /
   train empty, your carried ore gone, Robux items and golems still there, the star over your name.
3. STAR SHOP: buy Golden Touch (podium income +10 %), Deep Pockets (carry +1), Express Rails (the train panel's trip
   time drops), Head Start (the next rebirth starts at LV 2), Podium Keeper (the podium ores stay).
4. Phone emulator 568 x 320 and 667 x 375: the window fits, the tabs sit in the header, every button is easy to tap.
5. Buy Plot Glow: the ribbon shows on your plot's walls at once; COLOR cycles your colours and OFF; another player
   sees it; leaving frees the plot without it.
6. Walk to the plaza's fire crystal: "Star Forge" (F / Y) opens the window.

## Robux blaster levels for the STORE (2026-10-20, branch feature/blaster-robux)
The owner wants the Robux STORE to sell blasters. The UI chat's STORE card sells the NEXT blaster level as a developer
product in four price bands (MonetizationConfig entries, added on ui/store; Grant "BlasterLevel", MinLevel / MaxLevel =
the next levels a product covers). The owner's prices (2026-10-20):

| Product | Next level | Price (R$) |
|---|---|---|
| BlasterNextA | 2-4 | 49 |
| BlasterNextB | 5-7 | 99 |
| BlasterNextC | 8-9 | 199 |
| BlasterNextD | 10 | 399 |

(Bands, not one flat price: the Foundry curve runs from 330 coins at LV 2 to 35B at LV 10, so a flat price would make
LV 10 as cheap as LV 2 and skip the whole ~8 h curve for ~700 R$.)
- VaultService.grantNext is the one level setter for the coin Vault and Robux. A Robux level: the next level in that
  level's case look, Stats.BlastersPaid + 1, and the crate opening (VaultResult Paid). No coins ever (the
  no-Robux-to-coins rule, docs/COMPLIANCE.md).
- Rebirth: a run with a bought level pays stars only for Foundry-forged levels (Stats.RunPaid; also in the first run,
  whose grace otherwise counts the blaster as it is). No paid stars.
- Bought levels come back (the owner, 2026-10-20: "Vrátí se mu"; the store sells BlasterNext AND the star blasters):
  every Robux level (Stats.BlastersPaid) lifts the fresh blaster of EVERY later rebirth one level
  (RebirthConfig.startFor), up to MaxLevel - 1 so one level is always left to forge (otherwise the next rebirth could
  never be earned). The k-th Robux level is always LV k + 1 or higher, so the bands keep their prices across rebirths.
- The handler never refuses: MonetizationService never acknowledges a receipt without the item, and clients can
  prompt any product. At the top level, off the product's band, or while the top level waits (below), its Robux are
  banked (Stats.BlasterCredit) and buy start lifts only at the band price of the start level they make
  (VaultService.spendCredit: a client-made 49 R$ prompt never buys a LV 8 start). The store asks
  VaultService.paidStatus first ("Full" at the top / off band / topBlocked).
- The top level is never sold while the run has forged no rebirth level (RebirthConfig.topBlocked: the STORE says
  "Full", the coin Vault "ForgeFirst" with a FOUNDRY button): otherwise nothing is left to forge and the run could never
  rebirth. A save already stuck at LV 10 that way (the coin Vault, before this) may rebirth for 0 stars.
- A Robux level on the first run keeps the levels the first-run grace counted (RunForged = the level before it); only
  the bought levels pay nothing. Head Start is not sold once the Robux levels already start the blaster at LV 9.
- Integrator review 2026-10-20 (#1 high, #2, #3, #5, #6, #15) fixed; the crate opening closes every panel (the STORE).
What to test in Studio (with test product ids):
1. Buy BlasterNextA at LV 2: LV 3 with the crate opening, coins unchanged.
2. At LV 10: the card is hidden; a forced prompt is counted with a thank-you toast, and the next rebirths start one
   level higher.
3. After buying a level, rebirth needs a blaster forged at the Foundry (NotForged otherwise).
4. Buy two levels, rebirth twice: both rebirths start at LV 3 (the window's YOU LOSE row says "back to LV 3").

## Spray-washing replaces chisel / scrape / polish (2026-10-20, machines chat; ui/store #5)
The owner picked spray-only cleaning (his pressure-washer video). The machines chat built the mechanic and its server
side; the UI chat ("Nový UI design") builds the final look on top through `CleaningController.setLook`.
- Shared: `CleaningPatterns` makes the dirt from the seed (a 14×14 grid of cells over the clump, thicker in the
  middle and on rarer ores: `Rarity.DirtThickness`; glowing crystals: `Rarity.FragileSpots`; the last 2 % of the cells
  wash off by themselves). `SprayScoring.SprayTracker` replays the spray: a sample at most every 50 ms while the
  spray is on, the nozzle sprays along the line between two samples for their time (at most 0.1 s: a hitch never
  sprays longer), cells within 0.24 face units lose dirt, spray with no dirt in reach is wasted, a crystal sprayed
  point-blank for 0.35 s cracks. Score = 1 − slow (log scale over par, up to 0.4) − waste (over 25 %, up to 0.2) −
  0.12 per cracked crystal. Touch / gamepad get a wider spray and a matching shorter par.
- Server: `CleaningService` scores with `SprayScoring.score` + `fitsSession` (no spray before the intro, the
  recording after the finish pause), then `CleaningGuard` (hard: 25 equal intervals in a row or half of all of
  them → Flawless becomes Pristine; soft, logged only: an even nozzle speed). CleanResult now carries Speed, Aim,
  Cracks, Time (no Chisel / Scrape / Polish / Chips). The Polisher cap, relics, isCleaning / onSessionStart /
  onCleaned, Discovery and FlawlessCleans are unchanged.
- Client: `CleaningController` (camera, input, recording, Leave / Collect, the look hooks), `DefaultLook` (the clump
  from OreShellBuilder, the wand + jet + splash from SprayParts, thinning / popping dirt, cracked crystals, the
  "% CLEAN" bar and QUALITY meter, the rise-and-spin reveal and the card), `CleaningView` (banner, % CLEAN bar,
  meter, card; no step pips, polish gauge or chips any more).
- Tests: tests/Cleaning.spec.luau (patterns, scoring on every rarity with simulated players from
  tools/lune/lib/spray_players.luau, broken input, a hitch / compressed time, the timeline, the guard, the look's
  parts); CleaningPlay.spec (chisel / polish) is gone. Calibration: `lune run tools/lune/spray_calibrate.luau`.
What to test in Studio:
1. Clean a Coal chunk with the mouse: hold the left button and sweep the dirt in rows. The dirt thins and pops off,
   "% CLEAN" fills, at 100 % the ore rises and spins and the card shows the grade, Time and Aim. Collect (or E).
2. Spray with the button held over empty air next to the clump for a while: Aim drops on the card.
3. A Rare or better ore: hold the spray on a glowing crystal: "Crystal cracked!", the card says Cracked 1.
4. Phone emulator: drag a finger over the dirt; the wand shows only while the finger is down. Controller: the left
   stick moves the ring, A or R2 sprays, B leaves (twice once some dirt is off).
5. A dusty relic at the Cleaning Station: wash it, the relic rises, the card says RELIC CLEANED.
6. Leave half way: the ore stays in the vise; F starts again with new dirt.

## Daily / weekly quests + the 7-day login streak (2026-10-21, branch claude/daily-quests-streak-fe1830)
Retention plan (owner 2026-10-21). Design: docs/plans/DAILY_QUESTS_PLAN.md.
- Shared: `Config/QuestConfig` (pools, rewards, streak days), `Quests/QuestLogic` (pure: UTC day / Monday week,
  seeded roll per player + day, goals by blaster level / income, deltas from data.Stats, claims, the streak).
- Server: `QuestService` (QuestAction "Claim" / "Streak", Rate 2 Burst 4; the policy first, then check + mark claimed
  + grant with no yield; QuestReward + ActionResult; State provider `Quests`; a 30 s day check). Save: data.Quests,
  data.Streak (no Version bump; refresh repairs broken lists). Day 7's Crystal Capsule goes through
  CapsuleService.grantFree; a full golem inventory refuses the claim ("make room"), the day stays claimable.
- Client: `QuestView` (Pop window QUESTS + the DAILY REWARD popup, odds panel), `QuestController` (side menu QUESTS
  in the MORE flyout with a badge, "Quest done!" toasts, the popup once per session after the loading screen and
  never over the tutorial bubble / another panel / the minigame / build mode).
- Review: rewards are never Robux-only; the only random reward (day 7) shows exact odds; no rewards for likes or
  favorites; server os.time() only; capsule quests and Triple Lucky are swapped for coins where every capsule is a
  restricted paid random item.
What to test in Studio:
1. Join: after the loading screen the DAILY REWARD popup shows day 1 glowing (TODAY!). CLAIM: coins toast, the
   popup closes. Rejoin: no popup (claimed today), the QUESTS tile has no streak badge.
2. MORE > QUESTS: 3 dailies + 1 weekly with progress bars. Mine / sell / clean: the bars move, a finished quest
   toasts "Quest done!", the MORE tile shows a red badge, CLAIM pays and shows DONE. Rejoin: the same quests.
3. Change the server clock (or wait for 00:00 UTC): new dailies; Monday 00:00 UTC: a new weekly.
4. Streak day 7 with a full golem inventory: refused with "make room"; delete a golem, CLAIM: the capsule opening plays.
5. ODDS (window and popup): the Crystal Capsule's golems and chances in two columns; B / BACK closes it.
6. Phone emulator (568 x 320 and 844 x 390): every button is easy to tap, nothing overlaps; controller: the first
   thing to claim is selected, B closes.
## Player moves: procedural R15 animations (2026-10-21, branch anim/player-moves)
The owner wants "perfect and suitable animations" for the player's own movements (no avatar editor). No uploaded
animation assets: `Moves/MoveMath` poses go onto `Motor6D.Transform` on top of the default Animate script.
- Data: `Config/MoveConfig` (10 moves: Carry, Throw, Recoil, Spray, Hammer, Celebrate, BigCelebrate, CashToss,
  Wave, Shrug; keys per R15 joint in degrees, eases, blends, Override joints, MinGap, Priority).
- Pure code: `Moves/MoveMath` (evaluate / weight / layer, works for any rig: quest NPCs later),
  `Moves/MoveRig` (motor map, layering that never piles up when the Animator skips a joint, release),
  `Moves/MoveRules` (attribute format, whitelist, loops, blocks, celebrations).
- Client: `MoveController`, one RunService.Stepped for every R15 character within 70 studs and on screen; skips R6,
  seated / swimming / climbing / ragdolled / dead, hoverboard riders, and your own character in close-ups
  (Scriptable camera or PlayerControls claimed): a celebration of yours waits until the close-up ends (8 s max).
  Roblox "Reduce Motion" swaps BigCelebrate for Celebrate.
- Server: `MoveService`, Net "Move" (Rate 3, Burst 5; whitelist Throw / Wave / Shrug, Guard.string, Throw only while
  carrying), celebrations from the existing hooks (onCleaned + onDiscovered, onOpened, DataService.onChanged for the
  blaster level / rebirths, onSold), the MoveLoop attribute (Spray while cleaning, Hammer while forging).
- Hooks in other files: InteractController (one line before CarryThrow), the two ORDER lists, Net (one entry).
- Preview: docs/screenshots/animations/pohyby_hrace.mp4 + .jpg (`lune run tools/lune/export_moves.luau`, then
  `ANIM_PAGE=moves.html ANIM_OUT=pohyby_hrace.mp4 ANIM_BITRATE=3500000 node tools/preview/render_anim.mjs 30 1280 720`
  and `node tools/preview/moves_sheet.mjs`).
What to test in Studio (2 players, R15 avatars; also one R6 avatar):
1. Pick up ore: both arms hug it, the legs keep walking. Throw (Q / RB / Throw button): wind-up overhead, the throw,
   the follow-through; the other player sees it too. Throw the last chunk: the arms go back to the walk.
2. Hold the blaster on a rock (mouse, touch FIRE, R2): the gun arm kicks when the beam starts, then small kicks; the
   other player sees the kicks on you. Nothing jitters or drifts after you stop.
3. Clean an ore: the other player sees your arm spraying; a new ore or Flawless: you celebrate after Collect (your
   camera was in the close-up), the other sees it at once. A Legendary+: the spin jump.
4. Forge at the Foundry: the other sees the hammer pounding; the new level: the spin jump after the close-up.
5. Sell 5+ items at Tobin's: the money toss. Equip a golem: a wave. A refused action (e.g. too far from the stall):
   a shrug, not more than every 2.5 s.
6. On a hoverboard, seated, swimming or climbing: no moves. An R6 avatar: no moves, no errors.
7. Phones: FPS with 8 players moving nearby (the micro-profiler: MoveController stays well under 0.5 ms).
8. SETTINGS > Reduce motion on (or Roblox's own Reduce Motion): celebrations become the calm versions (a small
   bounce, no crouch, no spin; the money toss without the hop); no waves or shrugs on anyone; carry, throw, recoil,
   spray and hammer stay. A second player without the setting still sees your wave / shrug.
9. Hold fire on a rock your blaster can't mine yet (Deny toasts every 3 s): no shrug, the gun and the beam stay on the
   rock; the other player sees no shrug either. Equip a golem with the blaster in hand: no wave. A celebration while
   the beam is on: the body celebrates, the gun arm stays on target.

## World animations (2026-10-21, branch anim/world)
The owner wants "perfect animations in the game world" (his reels: a punch with a white impact flash, coloured cubes
and cash flying out). New `Controllers/WorldMotionController` (client ORDER after GolemController) with the pure math
in `Effects/WorldMotionLogic` (the showreel runs the same code):
- Golem followers: GolemController multiplies `WorldMotionController.golemOffset(pet, owner, now, walking, near)` onto
  every follower (one line in its step + the require): rounder hops with a wiggle and a nod while walking; a sway and
  now and then a little double hop in place, turning left and right ("waving"), while standing; the happy jump with
  one spin when a golem was just equipped (its kind appeared in the owner's EquippedGolems and the model was built
  within 3 s; golems built because you walk up to their owner don't jump). Premium golems keep their hover: they
  rise and spin, never hop. Far golems (beyond FollowerLodDistance) get nothing but the jump.
- Ore popping out of a rock: a Raw chunk that appears in Workspace.Items within 1.2 s and 16 studs of a NodeCrack /
  NodeShatter Fx pops: dust cubes puff out, the real chunk is hidden on this client (LocalTransparencyModifier, put
  back after) and a pooled look-alike follows it with an arc on top, one extra spin, a pop-in scale and a squash on
  landing (more dust). Physics are never touched; picking the chunk up ends the pop at once.
- Hit: a short white flash, a star of white spikes and cubes in the rock's crystal colour (the colour the rock shows,
  never the secret ore). Your hits: each Health drop of the rock you face while firing (RockLabels.onHealthDrop);
  other players' hits: their BlastHit Fx. BlasterFx keeps its sparks, chips, rings and sounds.
- Sell: Earned { Source = "Sell" } (SellService, LogisticsService): green banknotes flutter out of the sell spot,
  gold coins burst up and fly into you (within 45 studs); SellController keeps its +$ popup.
- Perf: all parts pooled (anchored, no collide / query / touch), one RenderStepped connection only while something
  moves, one BulkMoveTo a frame, no tables per frame; caps PC 64 bits / 6 pops / 3 flashes, phones 32 / 3 / 2;
  effects beyond 80-110 studs or off screen are skipped; Reduce motion (SettingsConfig ReduceMotion when it exists,
  else GuiService.ReducedMotionEnabled): half the bits, no look-alike, no spikes, no spins, golems only hop on equip.
- Tests: tests/WorldMotion.spec.luau (curves, plans, caps, pool reuse, the controller's hooks on a rig).
- Preview: `lune run tools/lune/export_world_motion.luau` + `node tools/preview/render_world_anim.mjs` ->
  docs/screenshots/animations/svet_animace.mp4 / .jpg.
What to test in Studio:
1. Equip a golem (GOLEMS panel): it appears behind you and does a jump with a full turn; a Legendary rises and turns.
   EQUIP BEST: every new one jumps once. Walk away and back (out of 120 studs): no jump when they are built again.
2. Walk: the golems hop with a little left-right wiggle; stand still: they sway and sometimes hop in place.
3. Blast a rock: every ~0.3 s a white flash with spikes and small cubes in the rock's crystal colour flies toward you.
   A second player blasting the same rock: their hits flash on their side.
4. Break a stage that drops an ore: the chunk pops up higher than before, spins once, squashes when it lands, dust
   puffs at both ends; pick it up right away: it is never invisible. Check with two players (the other one sees it).
5. Sell at Tobin's stall and at a sell box: notes flutter out, coins fly into you; spam SELL: never more than a few
   dozen pieces, FPS steady on the phone emulator.
6. Turn on Roblox's Reduce Motion (or the ReduceMotion setting when it lands): no spins, smaller bursts, no pop copy.

## Golem followers run (2026-10-21, branch anim/golem-run)
The owner: "the golems should really RUN after the characters". `Effects/GolemGait` (pure) + WorldMotionController:
- Limbs: GolemBuilder's names first (Leg1/2, Arm1/2 + Fist1/2, Head), then name families that stay on the body (Core,
  Vein, Boulder, Crystal*, Wing*, Tail*, Aura, Crack*), then geometry in golem units for any other gear (at or above
  the neck -> head, out at the sides below the shoulders -> that arm, e.g. the Dragonscale Knight's shield, low and
  off-centre -> that leg, else body). Pivots: hips, shoulders, neck. Wings stay on the body.
- Golems within 50 studs of the camera and on screen, nearest first, while their limb parts fit 160 a frame (phones
  60), have their limb welds switched off (anchored) and are moved every frame with the one BulkMoveTo; picked every
  0.25 s; the others keep the whole-body hop. Leaving the range puts the limbs back on their welds at rest.
- Gait: cadence and stride by speed and size (small golems quick little steps), legs and arms in opposition, a lifted
  knee, lean and a bounce per step (walk / run / catch-up sprint), a bank and a head turn into turns, a lean back when
  braking, idle breathing, looking around and a wave; Premium golems fly (arms back, legs trailing, a tilt into
  turns, a bob); the equip jump stays (arms up). Reduce motion: half the swing, no sprint lean, no bank.
- GolemController's hook line now also passes `speed`; with running limbs its own hop is taken out (GolemGait.
  controllerHop mirrors its numbers; a spec checks them against its source).
- Preview: docs/screenshots/animations/golemove_beh.mp4 / .jpg (`lune run tools/lune/export_world_motion.luau 30
  golem_run`, `node tools/preview/render_world_anim.mjs 1280 720 6000000 - golem_run golemove_beh`).
What to test in Studio:
1. Equip 3 golems (a Common, an Epic with a crown, a Legendary or Mythic). Walk slowly: they walk with quick little
   steps; walk normally: they run (arms pumping, leaning); jump down a ledge or ride ahead: they sprint to catch up.
2. Stop: they brake (lean back), then breathe, look around, and now and then one waves.
3. The Legendary / Mythic flies: arms back, legs trailing, it tilts into turns. The Dragon King's wings stay put.
4. Walk 60 studs away from another player's golems: they switch to the plain hop; come back: running limbs again,
   never a limb left floating. Watch FPS with 8 players and their golems on the phone emulator.
5. Reduce motion on: smaller swings, no lean into sprints or turns.

## Emotes live, player moves switched off (2026-10-21, branch anim/emotes-live)
The owner said yes to the emotes; the player moves stay built but off (AnimConfig.PlayerMoves = false).
- Switch: with PlayerMoves off MoveController makes no Stepped loop, no Fx / ActionResult / Notify listeners, no
  Move / MoveLoop / CarryCount listeners and sends nothing; MoveService registers no Net "Move" and no hooks.
- Emotes: the EMOTES menu (EmoteController + UI/EmoteView, Pop look, word cards): the N key (free: no other
  KeyCode.N, not a Roblox key), the EMOTES tile in the left HUD menu (touch; the gamepad reaches it with
  D-pad Left, then A; no new pad button). Net "Emote" (Rate 2, Burst 4; EmoteService: EmoteConfig whitelist,
  Guard, a 1 s cooldown per emote, never while carrying / cleaning / on a board / seated / dead, the Blaster
  Spin only with the blaster) sets the character attribute Emote = "<Name>:<seq>" ("" = stop). Every client
  plays it within 70 studs and on screen; the one loop runs only while an emote plays near you.
What to test in Studio (2 players, R15):
1. Press N (or tap EMOTES; on a pad D-pad Left, pick EMOTES, A): the menu opens, B / X / Backspace close it,
   another panel opening closes it. Pick ROBOT: you dance, the other player sees it. Pick ROBOT again: it stops.
2. Walk, jump, sit or ride a hoverboard while dancing: the dance stops (the finishing pose, quickly) for both.
3. Pick up ore: the menu says "Put the ore down first."; build mode / cleaning: no dance.
4. BLASTER SPIN is grey ("Hold your blaster") until the blaster is in hand; then the gun twirls; firing stops it.
5. GEM JUGGLE: three gems fly between the hands; they vanish when it stops; 8 jugglers at once stay smooth.
6. Phone: the EMOTES tile and the cards are easy to tap; the menu fits a small phone.
7. Carry / throw / recoil / celebrations: nothing happens (switched off), no errors in the output.

## Golems live, world effects off (2026-10-21, branch anim/golems-live)
The owner said yes to the golems running, not (yet) to the world effects. WorldMotionController reads
Config/AnimConfig when used:
- WorldFx = false (ships): init listens to no remote (Fx, Earned), start scans no Rock tag and watches no chunk, every
  world hook returns at once, no pool is made, the frame loop is never asked for by them, no chunk is ever hidden.
- GolemMotion = true (ships): the run / fly / idle / equip jump / hops of anim/golem-run. With false: golemOffset is
  identity (GolemController's own motion exactly as before), no player tracked, running limbs back on their welds.
- Tests: tests/AnimSwitches.spec.luau ("off" costs nothing: no listen, no Rock tag, no Players, no pool, no loop; the
  hook takes GolemController's hop out exactly; Reduce motion with the switches; no tables per frame in the gait).
What to test in Studio:
1. Mine a rock until it drops an ore: the chunk flies out as before (no pop, no dust, never invisible); blasting has
   BlasterFx's own sparks only (no white star); selling shows SellController's popup only (no notes or coins).
2. Golems: run / fly / idle / equip jump as in the anim/golem-run checks above.
3. Set AnimConfig.GolemMotion = false in Studio: golems hop like before, no limb moves.

## anim/ship review fixes (2026-10-21, branch anim/ship; build/reviews/anim_ship_review_findings.md)
- Emotes: picking any emote but the Blaster Spin puts a tool in hand away (Humanoid:UnequipTools, as cleaning and
  build mode do), so it never stops on its first frame; your stop is sent whenever its start was sent (also before
  the server's echo); a "" echo of your earlier stop that lands right after you picked the next emote
  (MoveController.EchoGrace) leaves it alone; switching away from the Gem Juggle gives the gems back; a stopped emote
  out of range is dropped (the slow check sleeps); the Blaster Spin twirls the blaster on the RightGrip weld's C0
  (BlasterFx's kick keeps C1) on every client and puts it back; the server's cooldown is 0.85 s (the menu's 1.0 s);
  N and the EMOTES tile do nothing in a close-up (cleaning, build mode, the Foundry, the vault).
- Golems: GolemGait.classify moves gear with what it is welded to (touching, or a builder's weld): the Dragonscale
  Knight's sword (blade, fire, guard, pommel) swings with its right fist, every Cape* piece follows the torso,
  pauldrons turn with their arm, the Dragon King's sceptre and orb stay in its hand, the crowns stay on the heads.
  The limb loop disconnects when the last running follower is destroyed.
- SETTINGS: with the UI motion off the Reduce motion row says "Calmer golems: no hops or lean" (what it changes now).
What to test in Studio:
1. Mine with the blaster, keep it in hand, press N, pick ROBOT: the blaster goes to the backpack and the robot plays
   (for the other player too). Pick BLASTER SPIN with the blaster: the gun twirls round the finger, then sits right.
2. Pick an emote and walk off at once: the other player never sees it keep dancing.
3. Equip the Dragonscale Knight and the Dragon King, run: the sword and the sceptre stay in the fist, the cape stays
   on the back, the pauldrons ride the shoulders. Unequip all golems: no errors, nothing keeps running.
4. Start cleaning / build mode / the Foundry and press N: no EMOTES menu.

## One Furnace (owner 2026-10-24, machines chat)
The owner kept two furnaces: the Alloy Furnace and ONE Furnace for everything, which changes as it is upgraded, and
the Crusher comes first (the Furnace takes crushed ore only).
- Data: the Furnace keeps the id `ClayFurnace` (every save has one), its name is "Furnace", it Accepts crushed ore
  only. `Tiers` (Brick 4 s / no power, Blast 2.5 s / 20, Plasma 2.5 s x2 / 60; review: Brick unpowered would be slower than clay) and the Tech shop's new upgrade kind
  `Tier` (Upgrades.Tier = the old machines' prices 6,000 / 30,000 / 5,000,000) turn every furnace of the player at
  once; `MachineData.info(id, tier)` is the machine as it works at a tier (MachineService sets machine.Info from it;
  ProcessingService / MachineLogic.batch / PowerLogic / PowerService / MachineInfo read it). The Brick / Blast /
  Plasma Furnaces are Retired (refunded and taken off plots by the v3 retired step); their KitMachines models are
  the tiers' looks (MachineBuilder.tierLook: the Blast look shrunk into 2 x 2, the Furnace's own attachments,
  attribute Look for MachineFx). A Tier buy rebuilds the player's furnaces (ProcessingService.onBought ->
  refreshType); a rebirth resets it with the other machine upgrades (owner: back to clay; Lose row says so).
- Starter kit: Cleaning Station, Furnace, and a Crusher behind the Furnace that drops its piles straight into it.
  Save Version 6: a save loaded with a Version below 6 gets a Crusher once if it has none (Migrations).
- Balance (tools/lune/balance_sim.luau, OneFurnace = true): typical blaster 8 / 9 / 10 at 3h11 / 4h55 / 7h53
  (old roster 3h13 / 4h57 / 7h56): the same curve.
- Tests: Migration v6 (refunds, queues to the pen, the Crusher once), KitMachines (every tier keeps the footprint
  and attachments), ProcessingService (a Tier buy turns every furnace: look, time, two at once), Power (the tiered
  Furnace on a network), MachineInfo (tier text and power), ShopService / TechShopView (the Furnace Upgrade card).
What to test in Studio:
1. A new player: the Cleaning Station, the Furnace and the Crusher behind it. Clean an ore, drop it into the
   Crusher: two piles fall into the Furnace and come out as two ingots.
2. Drop clean ore straight into the Furnace: refused with "Put clean ore through your Crusher first!".
3. Tech shop > UPGRADES: "Furnace Upgrade" shows the next furnace and its time. Buy Brick: every furnace turns into
   a Brick Furnace at once; Blast needs power (a pole and a solar panel); Plasma smelts two at once.
4. An old save with a Blast Furnace: it is gone, its price is back in coins, its items wait in the pen, and a
   Crusher waits in the Build menu.
5. Rebirth: the furnaces are clay again.
