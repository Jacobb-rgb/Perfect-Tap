# TERRA FORGE – handoff (state on 2026-10-16)

This file lets a new Claude Code session (or a new account) continue exactly where the last one stopped.
Read CLAUDE.md first (project rules and commands), then this file.

## 1. The request (owner's brief, summarised)
Build **TERRA FORGE**, a Roblox mining/crafting game in Luau via Rojo, all the way to a **published, public** game.
- Mix: The Forge (stylized low-poly, warm forge lighting, progression feel) + Hydroneer (physical ore chunks you carry
  and throw, placeable machines, conveyors) + Fishing Chef rib cutting, used for **cleaning ore** (chisel along guide
  lines → scrape → polish, grades Rough/Clean/Pristine/Flawless, chips when off the line but never a hard fail, juice,
  a reveal, PC/mobile/controller, harder for rarer ores, later an Auto Cleaner capped at a lower grade).
- Technical: server-authoritative, rate-limited remotes, modular ModuleScripts + data configs, DataStore with retries,
  session locking and BindToClose, mobile performance, StreamingEnabled, simple Rojo setup, git commits after each step,
  a checklist of manual Studio steps.
- Publishing: game settings, Roblox rules (TextService filtering), Maturity questionnaire answers, fair monetization
  (game passes: 2x carry, VIP area, extra machine slots; coin developer products) with a safe ProcessReceipt and
  placeholder IDs in one config file, daily login reward, tutorial under 3 minutes (first ore → clean → smelt → sell),
  milestone badges, optional group reward, AnalyticsService (tutorial funnel + economy), store page EN + CZ with
  icon/thumbnail ideas, and a final PUBLISHING.md with launch steps and a post-launch update plan.
- Process: game-designer plans, luau-dev implements, qa-tester checks after every step; build order a → f (below);
  after each step explain the changes simply (in Czech) with script paths, and **send pictures from the game**.
- Later owner requests:
  1. The lobby must look like **docs/art/lobby_concept.webp** ("exactly like this").
  2. Smelters, furnaces, pipes, fuel tanks, conveyors, cleaning stations "and everything" in the style of the
     **Kenney Factory Kit** (see docs/KENNEY_FACTORY_KIT.md), so the game looks better than all others.
  3. The owner has a "my games" folder with more reference material; ask them to upload it (zip) if it isn't here.

## 2. What is done (all on branch `claude/keen-wozniak-mx7azn`, checks pass: strict types clean, 197 Lune tests, place builds)
| Step | Status | Where |
|---|---|---|
| 0 setup | ✔ Rojo project, tooling, docs, subagents | default.project.json, rokit.toml, tools/, .claude/agents/ |
| a world + lighting | ✔ generated low-poly island: Emberfall town, 8 plots, Greystone Quarry, Ember Caves, Deep Hollow, Glimmer Grotto (VIP) | src/server/World/*, src/shared/Config/{WorldLayout,LightingConfig}.luau |
| b ore + carrying | ✔ node crack stages, physical chunks, pick up/drop/throw (E/Q, X/RB, touch buttons), fall rescue, item caps | Services/{ItemService,MiningService,CarryService,ToolService}, Controllers/{MiningController,InteractController} |
| c Cleaning Station | ✔ + two QA rounds: deterministic patterns, server re-scores the client recording (CutTracker/CutRecorder, ScrapeTracker, timeline + ClientPauses lower bound), phone layout (CameraFit, compact banner), touch tolerance 2.0, chisel resume, polish gauge, Easy polish, reveal | src/shared/Cleaning/*, src/client/Cleaning/*, Controllers/CleaningController, UI/CleaningView, Services/CleaningService |
| data | ✔ ProfileStore (session lock, retries, stale-lock takeover), DataService (autosave 120 s, BindToClose waits, quick-rejoin), Migrations (save Version 2) | src/server/Data/*, Services/DataService |
| d machines | **partly**: P0 contracts ✔, P1 core ✔, WP-Build (build mode) ✔, WP-Process (furnaces, crusher, auto cleaner + juice) ✔. Missing: StorageSell (WIP branch), Conveyor, Anvil, integration QA | see §4 |
| lobby | art direction ✔ (style bible, layout, style kit, loader); the 5 builder packages are NOT built yet, so the town still looks like the old one | docs/ART_DIRECTION.md, docs/plans/LOBBY_PLAN.md, src/server/World/Lobby/Style.luau, src/shared/Config/LobbyLayout.luau |
| store page + compliance | ✔ reviewed against current Roblox rules | docs/STORE_PAGE.md (EN+CZ), docs/COMPLIANCE.md |
| e economy / shop | not started (EconomyService exists only in the StorageSell WIP) | |
| f tutorial, monetization, badges, analytics, PUBLISHING.md | not started (save fields exist in DataTemplate) | |
| Kenney machine restyle | not started; spec in docs/ART_DIRECTION.md "Machines" + docs/KENNEY_FACTORY_KIT.md | |

Nothing has been tested in real Roblox Studio yet: verification so far = luau-lsp strict analysis, Lune unit/simulation
tests (tests/*.spec.luau) and three.js preview renders. Studio test lists are in docs/QA_REPORTS.md.

## 3. Branches
- `claude/keen-wozniak-mx7azn`: main line, everything above merged. **Pushed to GitHub**
  (https://github.com/Jacobb-rgb/Perfect-Tap, this branch). Continue on it (or merge it into `main` first).
- `stepd/wp-storagesell-wip`: unfinished WP-StorageSell (EconomyService, SellService, StorageService,
  SellController, StorageController, StorageView). Never checked; continue from it or rebuild from the plan.
- Already merged (kept for history): `stepd/wp-build`, `stepd/wp-process`, `lobby/art-direction`.
All branches above are on GitHub too.

## 4. Next steps, in order
1. **Finish step d** from docs/plans/STEP_D_PLAN.md (contracts are in force; P0/P1 deviations and requests are listed
   in docs/handoff/agent_reports_step_d_and_lobby.txt, read them):
   - WP-StorageSell: Storage Crate (shared pool 60 per crate, max 300, count sign, take-out UI), selling at Pell's
     SellBin/SellCounter in town (tags kept in TownLegacy/Lobby), Sell Chute pays the item owner, EconomyService.award,
     "+N" popups and coin burst. Start from `stepd/wp-storagesell-wip`.
   - WP-Conveyor: ConveyorService (belts move loose items, hand-off through IntakeService belt handler, players walk
     through, corners don't snag, cheap on mobile).
   - WP-Anvil: AnvilService/AnvilController/AnvilView (ingots on the anvil, Forge prompt, pick a recipe, tap to hammer:
     every tap counts, timing only changes the PERFECT/GOOD effect; server validates strikes; gear pops out).
   - The init ORDER lists already contain these modules (missing ones are skipped with a warning).
   - Then integrate, `bash tools/check.sh`, rebake, QA review (errors, exploits/dup, DataStore, mobile), fix,
     update docs/QA_REPORTS.md + docs/STUDIO_CHECKLIST.md + docs/PLAN.md.
2. **Lobby** from docs/plans/LOBBY_PLAN.md: five packages (Sky, Backdrop, Plaza, Districts, Flora) with owned files
   and detailed briefs (their text says "start from branch lobby-direction (70dd8ba)": that commit is now merged,
   so start from the main branch). Hero shot `lobby_hero` in tools/preview/lobby_shots.json matches the concept angle.
   After building: integrate, render all lobby shots, compare with docs/art/lobby_concept.webp, fix (2 rounds),
   bump WorldBuilder.Version, rebake, send the owner pictures. Gameplay hooks to keep: SellCounter, SellBin (+ part
   "Intake"), ShopCounter (SHOP), UpgradeCounter (UPGRADES), EmberChest (SPIN & WIN wheel = free daily reward),
   OreCodex (ROCK SCANNER), FossilDig, GuildBoard, Spin, TownSpawn.
3. **Kenney-style machine restyle** (after step d): rebuild MachineBuilder visuals keeping every attachment/tag/footprint
   (docs/KENNEY_FACTORY_KIT.md has the mapping), render machines on a plot, send pictures.
4. **Step e**: economy and shop: pickaxes (Tool Smithy at UPGRADES), carry levels, machines (SHOP), Bellows, slot
   upgrades, Ore Codex UI at the ROCK SCANNER, coins in the HUD, balance check (first sale is ~10 coins vs a 200-coin
   pickaxe: tune).
5. **Step f**: tutorial (< 3 min: mine → carry → clean → smelt → sell, guide beam, skip), daily reward wheel (free, show
   odds), group reward (PromptJoinAsync + server IsInGroupAsync on Claim; no like/favorite rewards), forge name
   (TextService, 1-minute rate limit), MonetizationService (passes StrongBack / ForgeVip / Workshop as Perk_ attributes,
   coin pouch dev products, ProcessReceipt: record purchaseId in the profile, save, grant only on the session-lock
   holder, then PurchaseGranted), MonetizationConfig with placeholder IDs, BadgeConfig (9 badges; only 5 free per day),
   AnalyticsService (onboarding funnel + economy events), PUBLISHING.md (README already links it), final
   STUDIO_CHECKLIST, icons/thumbnails from real captures (docs/STORE_PAGE.md has concepts and AI prompts).
6. Owner testing in Studio (docs/QA_REPORTS.md lists), then publish.

## 5. Important design decisions already made
- Step d plan items A–K are approved (machine contents saved in the placed entry, Version 2 migration, 1-stud plot border,
  shared storage pool, intake = hopper on top or belts into any side except the output front, machines hand output to
  the machine in their front cell, Auto Cleaner 60% Rough / 40% Clean, every anvil tap counts, players walk through
  belts, 2-wide machines output from the right front cell, Studio-only dev kit when saves are in memory).
- Cleaning accepted risks: the client says which input it used (tolerance) and whether Easy polish was used, and a
  modified client could omit crystal hits; none of this gains more than a perfect synthetic run, which no server can
  detect. The timeline lower bound makes bots take as long as a perfect player through the real client.
- Kenney models: rebuilt from parts, not imported as meshes (see docs/KENNEY_FACTORY_KIT.md).
- Fossil Dig and Rock Scanner from the concept: Rock Scanner = Ore Codex terminal; Fossil Dig is decoration first,
  a possible post-launch minigame (reuse the scrape step).

## 6. Pictures for the owner
Preview renders (tools/preview, see CLAUDE.md) are three.js approximations of Roblox lighting; always say so.
Existing pictures: docs/screenshots/*.jpg; art references docs/art/*.

## 7. Moving to a new account / machine
1. Get the code: clone https://github.com/Jacobb-rgb/Perfect-Tap and check out `claude/keen-wozniak-mx7azn`
   (or use the handoff zip's `projekt/` folder, which is the same git repo with all branches).
2. For Claude Code on the web, the new account needs GitHub connected (https://claude.ai/connect-github) and the
   Claude GitHub App installed on the repo (https://github.com/apps/claude/installations/select_target).
   For Claude Code on the owner's computer, just open the project folder.
3. Tools: install Rokit (https://github.com/rojo-rbx/rokit) and run `rokit install` in the project; Node.js for the
   preview renderer (`cd tools/preview && npm install && npx playwright install chromium`).
4. Run `bash tools/check.sh`: it must end with ALL CHECKS PASSED.
5. Tell Claude: "Read CLAUDE.md and docs/HANDOFF.md and continue with the next step."

## 8. Workflow notes for Claude
- Big steps used multi-agent workflows (example scripts with placeholders in docs/handoff/workflows/): a plan with work
  packages that own disjoint files → parallel luau-dev agents in git worktrees → an integrator that merges and runs
  checks → qa-tester review with an adversarial verify pass → fixes. Workers must not commit build/TerraForge.rbxl
  (binary merge conflicts); only the integrator rebakes it.
- Usage limits interrupted long workflows several times; commit work in small, checkable steps.
- In git worktrees copy build/globalTypes.d.luau or let tools/check.sh download the definitions pinned to luau-lsp 1.53.0.
