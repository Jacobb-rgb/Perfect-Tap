# Terra Forge – Build Plan (game-designer)

## What exists now
The repository was empty when work started (no code, no ores, no economy, no
subagent files). So nothing is being refactored. Terra Forge is built fresh,
with original lore, ores and art, around the brief's three inspirations:

| Inspiration | What we borrow (feel only) | What stays Terra Forge |
|---|---|---|
| The Forge (Roblox) | chunky low-poly look, warm forge glow, rarity-driven progression | our own world (Terra), town (Emberfall), ores, UI |
| Hydroneer (Steam) | ore as physical chunks you carry/throw, machines you place and chain | our machines, grid, conveyors, numbers |
| Fishing Chef (rib cutting) | step-by-step "cut along the marked line" tactile minigame | used for **cleaning ore**: chisel → scrape → polish |

No names, assets, UI layouts or branding are copied from any of them.

## Order of work (each step playable before the next)

| Step | Content | Main scripts |
|---|---|---|
| 0 | Rojo project, tooling, design docs, subagent files | `default.project.json`, `tools/`, `docs/` |
| a | Lighting pass + generated low-poly world (Emberfall hub, 8 plots, Greystone Quarry, Ember Caves, Deep Hollow, Glimmer Grotto) | `src/shared/Config/LightingConfig`, `src/server/World/*`, `src/client/Controllers/LightingController` |
| b | Physical ore chunks, node crack stages, pickaxe, pick up / drop / throw | `src/server/Services/ItemService`, `MiningService`, `CarryService`, `src/client/Controllers/MiningController`, `InteractController` |
| c | **Cleaning Station minigame** (chisel lines, scrape dirt, polish, reveal, grades) | `src/shared/Cleaning/*`, `src/server/Services/CleaningService`, `src/client/Controllers/Cleaning/*` |
| d | Machines (Crusher, Furnace, Anvil, Auto Cleaner, Storage, Sell Chute), grid placement, conveyors | `src/shared/Config/MachineData`, `src/server/Services/MachineService`, `PlotService`, `src/client/Controllers/PlacementController` |
| e | Coins, shop, upgrades, DataStore saving (session lock, retries, BindToClose) | `src/server/Services/DataService`, `EconomyService`, `ShopService`, UI |
| f | Tutorial, daily reward, group reward, badges, analytics, monetization, launch docs | `TutorialService`, `MonetizationService`, `AnalyticsTracker`, `PUBLISHING.md` |

After every step: qa-tester review (errors, exploits, DataStore safety, mobile
performance) + a short "what to test in Studio" list in `docs/QA_REPORTS.md`.

## Principles
- **Server-authoritative**: clients send intents ("I swung at this node",
  "here is my cleaning trace"); the server validates and changes money/items.
- **Data-driven**: every number lives in `src/shared/Config/*`, so balancing
  means editing one table.
- **Generated world**: the map is built by code (`WorldBuilder`) and also
  baked into `build/TerraForge.rbxl`, so there is very little hand-building.
- **Mobile first**: item caps per player, pooled particles, StreamingEnabled,
  no per-frame server loops over all parts.
