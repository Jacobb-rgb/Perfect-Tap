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
