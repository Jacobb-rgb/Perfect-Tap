# Owner's clicker-sim video (2026-10-29): eggs, Golden Forge, profile, rebirth

The owner (Czech) sent two screen recordings of a Roblox clicker simulator and wrote (gist): "I'd make really huge
changes: look how the eggs open in this clicker simulator, I want them to open exactly the same, this clean, and glow
by rarity. Keep the skins we have on the eggs, just make it cleaner so it looks exactly like this game. Add the
machine for golden pets. The UI can look this nice too. Make the rebirth similar, just not bought, that's not our
style. Add the profile too." He saw the ideas (boards in `../obrazky/napady_z_videa_2026-10-29/`) and said
"Ano, začni" to the order: 1 eggs, 2 Golden Forge, 3 profile + quest pop, 4 rebirth.

Reference frames: `docs/art/clicker_video_2026-10-29/` (file names say what each shows; `hatch_seq_*_0.1s.jpg` are
contact sheets of the openings at 10 frames per second). We take the flow, the feel and the layout ideas and build
them from our own things (our eggs, golems, colours, sounds, names). Never copy the game's images, sounds, names or
exact UI art: Terra Forge is its own game.

> **2026-10-30 ~00:40, owner: packages B and C are cancelled.** After the in-progress pictures he wrote (gist): "don't
> add the golden things after all, not the machine and not the pets, so no rolling either; focus on the other things;
> the profile etc. you don't have to do like this either, nor the rebirth". Only package A (the eggs) continues. The
> unfinished work is parked and must never land: `feat/golden-forge` b9d3e420, `ui/side-panels` 9865dcb7.

## 1. What the video does

### The egg opening (Open 3 with Auto; t from the press)
| t (s) | What happens |
|---|---|
| 0.00 | The HUD hides; only the Auto Open button (bottom left) and the quest pop (top centre) stay. The world stays visible behind (softly blurred). 3 eggs pop in huge, right in front of the camera, side by side and overlapping, the middle one bigger; together ~70 % of the screen height. |
| 0.05-0.6 | They wobble (tilt about +-12 deg) and squash a little. |
| 0.4-0.8 | White shockwave rings out of each egg (2-3 thin rings that grow and fade) and a white puff: the first cracks. |
| 0.6-1.9 | Cracks glow in the rarity colour of the golem inside THAT egg (white for Common, green, blue, purple, gold; our Mythic a rainbow). They grow thicker; the eggs pulse a bit bigger in steps; soft blobs of the best colour drift behind. So you see early which egg holds the rare one. |
| 1.9-2.0 | Each egg turns into a solid glowing silhouette of its colour and bursts. |
| 2.0-2.3 | ONE full-screen flash in the best rarity's colour (white for Common), fading in ~0.3 s. |
| 2.1-2.6 | The golems stand where their eggs were, huge (~45 % of the screen height each for Open 3), on a soft white sunburst with a little confetti. A special one (the video: a Golden pet) is centred, pushed forward and bigger, with a small "Golden" pill. Under each: the NAME (big heavy white, thick dark outline) and "1 in N" in the rarity colour. Nothing else: no rarity word, no %, no NEW, no headline, no SKIP button. |
| 2.6-3.4 | A short hold with a gentle bob. |
| 3.4-3.8 | They spin and fly toward the player (shrinking to the bottom centre); the HUD comes back. Auto starts the next opening at once. |

Open 1 = one big egg in the centre. Open 10 (ours): 2 rows of 5, smaller, the same steps. A tap still skips.

### The egg panel (`egg_panel_cards.jpg`, `egg_panel_e_buttons.jpg`)
A white rounded card with a thin dark edge beside the egg, the egg's name above it as a big title. Top row: a price
chip (coin + price), a small mode chip, Auto (with its key) on the right. A grid of BIG cards: a rarity-colour
gradient, the golem picture big, the chance in big outlined text at the bottom ("46.33%", "6.5%", "0.1%", then
"1 in 2,000"), not yet found = a black silhouette, a small trash icon top right (auto-delete that pet). Around the big
E ("Buy Egg!" above it): left a green pill "Hatch 1 / price" (key E), below an orange pill "Hatch 3 / price" (R),
right a purple pill (their Hatch 8 game pass; ours: Open 10 / price, X).

### The Golden Machine (`golden_*.jpg`)
A world station ("Golden Crafting"); its window: a gold title over the top-left corner, a red X. Left: a search box,
"Auto-fill 6", "Craft All", a grid of your pets (blue cards with their power; picked ones get a green check; locked
ones dark with a padlock). Right (a blue panel): the golden result card with a "GOLDEN" ribbon, its name + "x3 Power"
pill, 6 slot circles, "Success Rate: 80%" with a bar, "+20% with 1 more Angel Bee", a big green "Craft!". 6 of the
same = 100 % ("Guaranteed!"), 1 = 13 %, about +17-20 % per extra one. Crafting: a "Crafting.." card, the success rate
on the left, a vertical reel of outcome cards on the right (GOLDEN gold-brown, FAIL red, sometimes "DIAMOND ???" as a
tease) that spins and stops between two arrows. Success: "Crafted! GOLDEN!" + the golden pet, "6 Angel Bees became 1
Golden", Continue. Fail: "So close! FAILED", a red X, a red screen tint, "Tip: 6 Angel Deers = 100%", Continue (the
pets are gone). A quest pop "Craft 50 Golden pets!" counts up.

### Side panels: rebirth, profile, quests (`rebirth_side_panel.jpg`, `profile_*.jpg`, `quests_side_panel.jpg`)
On the right, under a blue bar of 4 icons (rebirth, quests, backpack, crown) with the open panel's name above it, a
white panel with a dark edge: a title row (title + small icon buttons), contents in rounded light rows. The game stays
visible and playable beside it.
- Profile: avatar headshot + name + "Global Rank #399,543", View Ranks; 3 tiles (Pet Power, Rebirths, Click Power);
  Mastery button + level bar; Multipliers rows (icon, name, x2); Luck rows (+32 %); Lifetime rows (Rebirths, Eggs
  Opened, Total Taps, Quests Done, Time Played); Badges 4/29.
- Quests: cards with the quest title, Tier, a progress bar "250M / 10B" and the reward icon; hover shows the reward.
- Rebirth (theirs): "Auto" + "Rebirth", green rows "Rebirth! +10M  Cost 1.04QN"... BOUGHT in bulk with coins. The owner
  wants this LOOK but not the buying: our Star Forge rules stay.
- Quest pop: a white card at the top centre during the egg opening: icon + "Open 1,000 eggs!" + "Tier 1" + a progress
  bar "132 / 1,000 +3" + the reward icon; it counts up as eggs open.

## 2. What we build: three packages on separate branches, disjoint files

Shared base: branch `anim/clicker-base` (this plan, the frames, `src/shared/Config/BrightTheme.luau` + its spec: the
bright style's colours, paints, fonts, `chanceText` / `oneInText` / `rarityPaint` / `crackColour`). Every package
merges it; the new windows use BrightTheme so they match. FredokaOne for titles, buttons and numbers; for preview
renders copy `FredokaOne-Regular.ttf` from `/Applications/RobloxStudio.app/Contents/Resources/content/fonts/` into
`tools/preview/fonts/` (a local Roblox font, no download).

Rules for every package
- The owner sees preview pictures (+ a short video where it moves) BEFORE anything lands. Animace ve hře relays his
  OK; then the branch goes to the integrator (chat "TERRA FORGE Roblox hra vývoj"), one at a time.
- Skills: game-ui, all-platforms (PC, phone, tablet, Xbox, PlayStation: 44 pt touch targets, the thumbstick zone
  left 40 % / lower 2/3, the action buttons right, gamepad focus + glyphs, 18 px text at 1080p on TV), roblox-rules,
  preview-pictures. Reduce Motion gets a short calm version of every animation.
- Roblox rules: odds visible before every paid random open (names stay under silhouettes); the Golden Forge shows the
  success chance before every craft; flashes never strobe (one per opening, at most 2-3 per second ever).
- Budgets: phones first; the lobby part budget (`tests/LobbyBudget.spec.luau`); the owner allows a MEASURED raise when
  quality gains (phones still smooth).
- Code style of the file you edit; strict Luau; never start a line with `(`.
- Git: commit only your own files by name (never `git add -A`, never bare `git stash`, never push, never commit
  `build/TerraForge.rbxl`); `stylua` only on the files you touched (never `stylua src`); never `pkill -f`.
- Before reporting done: merge the newest main (`claude/keen-wozniak-mx7azn`), then the full raw check:
  `bash tools/check.sh > "<abs projekt>/build/reviews/<package>_check_<sha>.log" 2>&1; echo exit=$? >> <same log>`
  (raw, unedited); it must end with ALL CHECKS PASSED and exit=0.

### A. `anim/egg-redo`: the egg opening + the clean egg panel (the egg builder, Animace ve hře)
Starts from the hatch v2 work (worktree `ui-egg-look`: commit it first as it is), merges `anim/clicker-base`.
Owns: `src/client/Controllers/CapsuleController.luau`, `EggPanelController.luau`, `src/client/UI/CapsuleView.luau`,
`HatchFx.luau`, `EggPanel.luau`, `EggPrompt.luau`, `src/client/UI/Confetti.luau`, `src/client/Effects/RevealFx.luau`
(keep its API: Návrhy strojů will move its secret reveal onto it), `src/shared/Builders/CapsuleEggs.luau` (only if the
cracks are built on the egg models), `src/server/Services/CapsuleService.luau`, `src/shared/Config/CapsuleConfig.luau`,
the `Golems = {...}` line of `src/server/Data/DataTemplate.luau` (AutoDelete), its tests and export tools.
Not: GolemConfig, GolemBuilder, GolemView, GolemController (package B); HUD files; QuestController (package C).
- A1 the opening, exactly the flow of section 1 with our eggs (their skins unchanged) and our golems: no black stage
  (the world stays, blurred), huge eggs, wobble, white rings, cracks in the rarity colour (`BrightTheme.crackColour`;
  Mythic a moving rainbow), the silhouette burst, ONE flash in the best colour, huge golems with NAME + `oneInText`,
  fly to the player, the HUD back; only the Auto button (bottom left, our Auto keys) on screen; a tap skips. Drop the
  v2 headline words, rarity pills, NEW tags and the SKIP button. Keep: solid golems (never see-through), the auto-fast
  mode, skip-all, Reduce Motion. Leave the top centre free for the quest pop (package C draws it in its own
  ScreenGui "QuestPop" above the opening; do not hide it).
- A2 the egg panel in BrightTheme: a white card, big rarity-colour cards (`rarityPaint`, `chanceText`), silhouettes
  for golems not found yet WITH their names (paid random rule), price chip + Auto in the top row; around the big E:
  Open 1 left (E), Open 3 below (R), Open 10 right (X) with prices; a trash icon per card = auto-delete that golem
  kind (server: `data.Golems.AutoDelete = { [kind] = true }`, its own remote CapsuleTrash; an auto-deleted golem
  still shows in the opening, greyed with a trash mark, and does not fly to you; never auto-delete a paid golem
  (Robux eggs) or more than the save allows). Keep the touch placement rules (thumbstick zone, tutorial bubble,
  boost corner), D-pad Up focus, BigE.
- Pictures: Open 1 Common, Open 3 mixed (one Epic), Open 10 with a Legendary, a Mythic, Reduce Motion, phone; the panel
  on PC, phone and TV; a short video of an opening.

### B. `feat/golden-forge`: golden golems (CANCELLED by the owner 2026-10-30, parked b9d3e420)
Owns: new `src/shared/Config/GoldenForgeConfig.luau`, new `src/server/Services/GoldenForgeService.luau` (or new ops on
GolemAction in `GolemService.luau`), `src/shared/Config/GolemConfig.luau` (golden helpers), `GolemService.luau`, the
golem part of `src/server/Bonuses.luau`, `src/shared/Builders/GolemBuilder.luau` (the golden look),
`src/client/Controllers/GolemController.luau` (golden followers), `src/client/UI/GolemView.luau` (GOLDEN ribbon), new
`src/client/UI/GoldenForgeView.luau` + `src/client/Controllers/GoldenForgeController.luau`, the station in
`src/server/World/Lobby/Districts/Capsules.luau` (+ `WorldBuilder.Version`), the ORDER lines of the two init scripts,
`tests/GoldenForge.spec.luau` (+ budget tests).
- Up to 6 golems of one kind (not Locked, not equipped: shown dark with a padlock) -> chance 1: 15 %, 2: 30 %, 3: 45 %,
  4: 60 %, 5: 80 %, 6: 100 % (GoldenForgeConfig), shown before the craft with "+X% with 1 more <name>". The server
  rolls. Success: one golden golem of that kind (`Entry.Golden = true`, a scalar Migrations keeps; Paid if any input
  was paid); fail: the golems used are gone (like the video; `FailKeeps = false` is a one-line switch if the owner
  wants no risk). Where PolicyService says paid random items are restricted: only 6/6 crafts.
- A golden golem: its bonus x2 ("x2 Power"), a gold body + shine (same part budget), "Golden <Name>", a GOLDEN ribbon
  on its cards, its followers golden for everyone (the equipped attribute marks it). Stats.GoldenCrafted counts them.
- Window (BrightTheme, frames `golden_machine_*.jpg`): title "Golden Forge" over the corner, search, Auto-fill 6, Craft
  All (every kind with 6+ eligible, guaranteed only, one confirm listing them), the grid, the right blue panel, Craft!.
  The crafting card with the GOLDEN / FAIL reel (cards in proportion to the chance) that slows and stops on the
  server's result; "GOLDEN!" with confetti or "So close!" with a red X and "Tip: 6 = 100%"; Continue.
- World: a Golden Forge station by the eggs in our forge style (a gold anvil / crucible with molten gold, a sign, an
  E prompt), inside the lobby budget (measure).

### C. `ui/side-panels`: profile + quest pop, then the rebirth in the side-panel look (CANCELLED by the owner 2026-10-30, parked 9865dcb7)
Owns: new `src/client/UI/DockPanel.luau` (the right-side panel + its icon bar, BrightTheme), new
`src/client/UI/ProfileView.luau` + `src/client/Controllers/ProfileController.luau` (its button: a MORE flyout entry
through `HudBubble.addMore`, no HudBubble edits), the quest pop (new `src/client/UI/QuestPop.luau`, hooked from
`QuestController.luau`), `src/client/UI/RebirthView.luau` + `src/client/Controllers/RebirthController.luau`, a
read-only profile field in the State push if needed, their tests.
- Profile: avatar headshot, name, leaderboard rank (LeaderboardService's own rank when known, else nothing), 3 tiles
  (golem power = the equipped golems' total bonus, Forge Stars / rebirths, blaster level), Bonuses (income, mining
  speed, ore luck, sell value, walk speed: the Bonuses totals), Lifetime (ores mined, rocks broken, ores cleaned, eggs
  opened, rebirths, time played, quests done; golden golems once B lands), Badges x / y.
- Quest pop: when a daily or weekly quest's counter moves, a white card slides in at the top centre (the quest text,
  "32 / 50", a bar, the reward icon) for ~2.5 s; its ScreenGui "QuestPop" sits above the egg opening.
- Rebirth: the dock look, our rules unchanged (RebirthConfig: earned by the blaster, never bought, no Auto, no bulk
  rows): a big green "Rebirth!" row with "+N Forge Stars" and the need (blaster level, a bar), what you keep / lose as
  short rows, the Star Shop perks as green rows with "BUY n STARS", the star blasters.
- Touch: the dock never covers Jump / Grab / Fire (phones: above them with a capped height, or centred); gamepad
  focus + B closes; TV sizes.

### D. Later
The bright look for every other window, only after the owner likes the new ones. The Vault cases' opening in the new
egg style (the crate background stays as it is: owner 10-28).
