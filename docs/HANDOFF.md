# TERRA FORGE – handoff (state on 2026-10-20)

This file lets a new Claude Code session (or a new account) continue exactly where the last one stopped.
Read CLAUDE.md first (project rules and commands), then this file, then **docs/DESIGN_V2_NOTES.md** (the owner's v2
design; it overrides GAME_DESIGN.md) and **docs/plans/V2_PLAN.md** (order of work, status block at the top).

**Main** = branch `claude/keen-wozniak-mx7azn` (there is no branch called `main`; "main" in every chat means this
branch), at **b68dd28** on 2026-10-20, pushed to https://github.com/Jacobb-rgb/Perfect-Tap.
`bash tools/check.sh` on b68dd28: strict luau-lsp "no problems found", **1433 Lune tests passed** (~1430),
map **v39** baked with 29,860 parts, ALL CHECKS PASSED. Save `Version` = 3 (`DataTemplate.Version` =
`Migrations.Latest`). CLAUDE.md's opening loop text and "Version = 2" are from v1: this file wins.

## 1. The owner's brief (short)
Build TERRA FORGE, an original Roblox mining/crafting game in Luau via Rojo, all the way to a **published, public**
game: server-authoritative, rate-limited remotes, safe saves, mobile performance, PC / phone / Xbox / PlayStation,
fair monetization with placeholder ids, Roblox rules (docs/COMPLIANCE.md). The owner speaks Czech (answer in Czech,
simple words), wants **pictures** often, and drives the look with concept images (docs/art/, the lobby concept, the
Kenney kits rebuilt from parts, the 36-ore picture). Code, comments, docs and commits stay in English.

## 2. What the game is now (design v2, all on main)
Loop: blast rocks with a laser blaster → dirty ore drops → throw it into the hopper at the mine station → your train
brings it home → Ore Pen → clean it (by hand or machines) → best ores on podiums earn coins per second (also offline)
→ machines, gear, upgrades → ingots → the Foundry forges the next blaster → deeper floors, rarer ores, relics.

| Area | What is in | Where / landed |
|---|---|---|
| Blasters | LV 1-10 (+ LV 11 "Coming soon"), hold to fire, Kenney-shape guns (owner's yes), shooting feel (flash, recoil, sparks, sounds that play) | BlasterData, BlasterFeel, MiningService, Effects/BlasterFx; 04bb2e9, 274f77f |
| Ores | 36 ores from the owner's picture; rocks hold 1-3 hidden ores; `OreData.Renamed` maps old saves | OreData; 9b6235a |
| Trains, pen, podiums | per-player train (mine hopper → base station → Ore Pen), podiums with income/s and offline earnings | TrainService, PenService, PodiumService |
| Machines | 24 roster machines in the owner's Soft style, belts, power poles + cables, Iron Box, Sell Box; Polisher stops at Pristine | MachineData, MachineService, LogisticsService, PowerService; df5171d, 417c7c9, 25a184c |
| Platforms | Platform deck 5 studs up, Belt Lift (items up a 26.6° slope), Slide; Deck / Ground toggle in build mode | docs/plans/PLATFORMS_PLAN.md phases 1-2; ee3f4d3 |
| Foundry + Vault | Foundry forges the next level from ingots + coins; Blaster Vault sells the next level for coins (4x the Foundry price) with the crate-opening cinematic; blaster gallery in THE GREAT FORGE's hall | FoundryService, VaultService, UI/CrateOpeningView; 6090647, 32616e9, a671e5a |
| Steps 6-7 | gear, enchants, boosts, golem capsules, daily wheel, artifacts + story + yard museums, leaderboards, codex, settings, the left side menu | GearService, EnchantService, BoostService, CapsuleService, GolemService, WheelService, ArtifactService, LeaderboardService, CodexService, SettingsService, UI/SideMenuView; 9be848a |
| Relics | rocks drop a **dusty relic**: clean it at a Cleaning Station or put it into a **Restoration Table**; never sold or lost | ArtifactService (DustyRelics), MachineData RestorationTable; 35e7eab |
| Tutorial | 10 steps: Station, Mine, Load, Train, Clean, Podium, Grow, Blaster, then GOT IT hints Golems and Wheel; 250 coins for finishing; waits for the loading screen | TutorialConfig, TutorialService, TutorialController; 49c2bac, a2d2650, ac43977 |
| Rebirth | option B **STAR FORGE**: optional reset from blaster LV 6, keeps the factory, pays Forge Stars for the Star Shop (6 perks) | RebirthConfig, RebirthService, RebirthController, tests/Rebirth.spec.luau; b68dd28 |
| Mine floors | 6 floors: Greystone Quarry, Ember Caves, Deep Hollow (walk in); Sunken Palace, **Stormglass Rift** (blaster 8), Heartstone Core (by elevator); floor 7 "Coming soon"; elevator; 5 hoverboards (3 coins, 2 Robux; H / L2); mine ambience | MineFloors, src/server/World/Mine/*, ElevatorService, HoverboardService, MineAmbience; cf5089c, 91ca653, bec327b |
| Lobby | candy mountains, horizon, meadow + paved roads, forest, plaza life, koi + butterflies, lobby ambience (follows the SETTINGS sound slider), teleport bar BASE / LOBBY / VAULT + LIFT | src/server/World/Lobby/*, AmbienceConfig, TeleportService; 70cd6c5 … 1e6f696 |
| Loading screen | logo on dark stone and lava, progress from streaming, tips, Skip; join popups and the tutorial wait for it (`Loading.wait`, 15 s time-out) | src/first/*, src/client/Util/Loading.luau; 1e6f696, 19e3303 |
| Music, badges, analytics | MusicController (zones, crossfades), BadgeService, AnalyticsService (tutorial funnel + economy); **every music and badge id is 0** until the owner uploads (ambience plays shipped sounds; 2 owner slots are 0) | MusicConfig, BadgeConfig, AmbienceConfig; 1e6f696 |
| Step 8 monetization | one `ProcessReceipt` (grant + Purchases + PurchaseLog, save, then PurchaseGranted), game passes checked on join and after purchase, a grant handler per entry, receipts gate; **every pass / product id is 0** = "Coming soon"; `CoinPacksEnabled = false` | MonetizationService, MonetizationConfig, src/server/Receipts.luau; c309076 |
| Save safety | SessionId locks, storable repair inside UpdateAsync, newer / malformed saves refused untouched ("The game just updated, please rejoin"), keep-unknown migrations, Studio uses `TerraForge_PlayerData_Studio`, test players in memory only | DataService, Data/*, tests/SaveSafety.spec.luau; 953b542, 66867ba; docs/SAVE_AUDIT.md |
| Security | audit + fixes; movement check **rollout step 1 = logging only** (`MovementConfig.Enforce = false`, `PullBack = false`, beam line of sight on); FLAWLESS guard: synthetic timestamps cap a run at Pristine, soft signals only logged (`CleaningGuard` `SoftEnforce = false`) | bd6a277, 2480d0f, 25a184c; docs/SECURITY_AUDIT.md, docs/plans/MOVEMENT_CHECK_PLAN.md |
| Performance | phone budget spec (18,000 parts), mining network diet, perf pass 1 (State pushes by section, ~34.5 → ~1.3 KB/s per busy client, estimate), perf pass 2 (one `DataService.changed` flush per player per frame), floor trims, Rift lights 21 → 11, gradient keypoint rules | 54b13c8, 308d257, fc224a5, dc38f52, bec327b, 9ca2270; docs/PERF_AUDIT.md, docs/SERVER_PERF_AUDIT.md |
| Balance | pass 1 (blaster curve ~8 h to LV 10), option 3 (pricier Tech Speed / Quality upgrades, owner's yes), Vault prices follow the Foundry | 38393e6, aa0077e, 39ab5d4; docs/BALANCE_SIM.md, tools/lune/balance_sim.luau |

## 3. How to verify
```bash
bash tools/check.sh > /tmp/check.log 2>&1; echo "exit $?"   # must be 0 and the log must end with ALL CHECKS PASSED
```
Save the **full, unfiltered** log and gate every commit or merge on its exit code (a flaky run once left no log).
`bash tools/build.sh` rebakes `build/TerraForge.rbxl`; the branch's owning chat rebakes once after merging main,
workflow workers never commit it (binary merge conflicts). Pictures: tools/preview (three.js approximations of
Roblox lighting; always say so).
Owner tests in Studio: docs/STUDIO_CHECKLIST.md "What to test in Studio (state 2026-10-20)" + docs/QA_REPORTS.md.

## 4. Parallel chats and who owns what
The owner runs several Claude chats at once. Each works in its own worktree / branch and touches only its files.

| Chat | Owns |
|---|---|
| **TERRA FORGE Roblox hra vývoj** (integrator) | landing on `claude/keen-wozniak-mx7azn`, the push, DataTemplate / Migrations / DataService, IntakeService, cross-chat decisions |
| **Zlepšení hor v pozadí** | lobby, backdrop mountains, horizon, flora, sky, lobby ambience, loading screen |
| **Úrovně a vzhled min** | mine floors, elevator, hoverboards, MonetizationService |
| **Design zbraní a blasterů** | blasters, Blaster Vault, gallery, tutorial, save safety, rebirth |
| **Návrhy strojů** | machines, belts, platforms, relic flow, security, balance sim |
| **Nový UI design** | light UI (style A) on branch `ui/light` |
| **Terra Forge Roblox hlídač ostatních chatu** | the watcher: reads all chats overnight, sends pictures, hands out next tasks |

### Landing protocol
1. The owning chat merges main into its branch, runs `bash tools/check.sh`, saves the **full log** and rebakes.
2. It pings the integrator with the branch, the commit id and the log path.
3. The integrator checks that main fast-forwards to that commit and that the log ends with ALL CHECKS PASSED
   (exit 0), says ok, fast-forwards `claude/keen-wozniak-mx7azn`, pushes, and answers "done".
4. Never push from a feature chat, never `git add -A`, never a bare `git stash`; ping the other chats before main
   moves under them.

## 5. What is still open
1. **Light UI flip** (in progress, chat "Nový UI design"): branch `ui/light` (a1a240d, 31 commits not on main) has a
   light path for every window behind the switch `UIConfig.Default = false` (flip prep c27abc4; the Workspace
   attribute `LightUI` = true previews it in Studio); flip it after the owner's "ano" (that branch's
   docs/handoff/UI_LIGHT_SWITCH_ON.md and docs/plans/UI_LIGHT_PLAN.md).
2. **Final Foundry price curve**: docs/BALANCE_SIM.md "Option 3 … and the 6-floor tables" must be re-run on the
   Stormglass Rift's real tables, then the Foundry L2-L10 coins set (machines chat, branch `balance/foundry-6floors`).
3. **Owner uploads** (guides in `Terra Forge Roblox game KIT/NAHRAJ_DO_ROBLOXU/`, steps in docs/PUBLISHING.md
   section 3 and docs/COMPLIANCE.md 2.6). Paste each id into its config:
   - skybox, 6 images → `LightingConfig.Skybox` (`obloha_mlecna_draha/`)
   - music, 4 tracks → `MusicConfig` (`hudba/`, docs/handoff/HUDBA_NAVOD.md)
   - 2 lobby ambience slots (frog croak, plaza murmur) → `AmbienceConfig` (`zvuky/`, docs/handoff/ZVUKY_LOBBY.md)
   - badges → `BadgeConfig` (`odznaky/`, docs/handoff/ODZNAKY_NAVOD.md)
   - 5 UI icon sheets → `IconAssets.Sheets[*].Id` (file on `ui/light`; `ikony_ui/`)
   - game passes (incl. the 2 Robux hoverboards) and Robux products → `MonetizationConfig` (`robux_produkty/`);
     keep coin packs at 0 while `CoinPacksEnabled` is false; passes On Sale only after that build is live
   - logo, icon, thumbnails, store text → Creator Dashboard (`obchod/`, docs/STORE_PAGE.md); paste
     `MonetizationConfig.grottoOddsText()` into the Forgemaster's Pass description
4. **Movement check rollout steps 2-3** (enforce, then pull back) only after real server logs
   (docs/plans/MOVEMENT_CHECK_PLAN.md; branch `docs/movement-check` has the integrator's review notes).
5. **FLAWLESS guard soft signals** stay log-only until real logs show no false positives.
6. **Studio checks** by the owner: docs/STUDIO_CHECKLIST.md, then Playtesters → Public (PUBLISHING.md section 3, items 10-11).
7. Smaller: trading (V2_PLAN step 8) is not built; the side menu's STORE stays hidden until a StoreController
   exists (on a 568 x 320 phone STORE + REBIRTH need a menu decision); rebirth's plot glow perk and a crystal
   prompt at THE GREAT FORGE are not built; perf leftovers (`PenService.markBoard`, PERF_AUDIT items 7-8 and the
   device test, item 10); the owner decides whether Robux coin packs are ever enabled.
8. Preview / proposal branches kept for reference, not to merge: `art/plot-style-a`, `art/relic-flow-preview`,
   `art/platforms-preview`, `docs/rebirth-proposal`, `mock/rebirth`.

## 6. Key docs
| Doc | What |
|---|---|
| docs/plans/V2_PLAN.md | v2 order of work (steps 1-9) + status block |
| docs/DESIGN_V2_NOTES.md | the owner's v2 design (wins over GAME_DESIGN.md) |
| docs/PUBLISHING.md | launch steps, where every uploaded id goes, update rules (save version bump, fix forward) |
| docs/COMPLIANCE.md | Roblox rules, questionnaire, place settings, product table (2.6) |
| docs/SAVE_AUDIT.md | save safety findings and status |
| docs/SUPPORT.md | helping a player's save after launch (Studio command bar) |
| docs/SECURITY_AUDIT.md | exploit audit and fixes |
| docs/SERVER_PERF_AUDIT.md, docs/PERF_AUDIT.md | 8-player server audit, phone / client audit |
| docs/BALANCE_SIM.md | the 10-hour player model, price calibration |
| docs/QA_REPORTS.md, docs/QA_NIGHT_2026-10-18.md | QA per feature with "What to test in Studio" lists |
| docs/STUDIO_CHECKLIST.md | manual Studio steps + the 2026-10-20 test list |
| docs/STORE_PAGE.md | store text EN + CZ, icon / thumbnail ideas |
| docs/plans/* | LOBBY, MACHINES, MACHINES_GAME, MINE_FLOORS, MINE_STEP, STORM_FLOOR, PLATFORMS, MOVEMENT_CHECK, VISUAL_UPGRADE, STEP1-3, STEP_D |
| docs/ART_DIRECTION.md, docs/KENNEY_FACTORY_KIT.md | style bible, Kenney look rebuilt from parts |
| docs/handoff/* | Czech owner guides (music, badges, lobby sounds), night review notes, example workflow scripts |

## 7. Decisions to keep
- Kenney models are rebuilt from parts, never imported as meshes (uploads would need the owner's account).
- Flawless comes only from cleaning by hand; machines stop at Pristine. Any paid random item shows its odds first.
- Floor logic keys on a floor's `Id`, never its index, so a floor can go in between (the Rift did).
- A save a newer build wrote is never opened by an older build; every update that adds anything a save can name bumps
  `DataTemplate.Version` and `Migrations.Latest` together, and broken updates are fixed forward (PUBLISHING.md section 3, item 12).
- After publishing an update: "Migrate To Latest Update" so no old servers keep running.

## 8. Moving to a new account / machine
1. Clone https://github.com/Jacobb-rgb/Perfect-Tap and check out `claude/keen-wozniak-mx7azn` (or use the KIT
   folder's `projekt/`, the same git repo with all branches).
2. Claude Code on the web needs GitHub connected (https://claude.ai/connect-github) and the Claude GitHub App on the
   repo; on the owner's computer just open the project folder.
3. Tools: Rokit (`rokit install`: rojo, lune, luau-lsp, stylua from rokit.toml); Node.js for the preview renderer
   (`cd tools/preview && npm install && npx playwright install chromium`).
4. `bash tools/check.sh` must end with ALL CHECKS PASSED.
5. Tell Claude: "Read CLAUDE.md and docs/HANDOFF.md and continue with the next step."

## 9. Workflow notes for Claude
- Big steps use multi-agent workflows (examples in docs/handoff/workflows/): a plan with packages that own disjoint
  files → parallel workers in git worktrees → an integrator merges and runs checks → QA review with an adversarial
  verify pass → fixes. Workers never commit `build/TerraForge.rbxl`; the chat rebakes after its merge.
- Usage limits can cut long runs: commit in small, checkable steps.
- In a git worktree copy `build/globalTypes.d.luau`, or let tools/check.sh download it (pinned to luau-lsp 1.53.0).
