# Phone performance audit (2026-10-18, main 417c7c9, map v23)

Measured from the built map under Lune (`WorldBuilder.build`, the same map the place bakes), plus a read
of the client code. Numbers are for the map only (no players, no ore nodes, no placed machines).
Tooling: the counting scripts are one-offs; `lune run tools/lune/lobby_stats.luau` gives the budget view.

## Totals

| What | Count | Budget / note |
|---|---|---|
| Parts in the map | **20,716** | MapParts 22,400 (map + ~1,320 ore nodes + 200 reserve must fit) |
| Parts inside the lobby area | **12,531** | LobbyParts 13,200 |
| Lights (Point/Spot/Surface) | 76 (41 in the lobby) | LobbyLights 45; **0 with shadows** (good) |
| Particle emitters | 45 | EmberCaves 14, Vault 10, Plaza 9, Districts 6 |
| Beams / Trails | 0 / 0 | |
| SurfaceGuis / BillboardGuis | 160 / 2 | 176 TextLabels; the builders set `MaxDistance` 60-260 (good) |
| Semi-transparent parts | 619 | Plots 192, Backdrop 136, Vault 120, Sky 100 |
| Neon parts | 3,043 | big neon areas are far away (planets, horizon) |
| Collidable parts | 5,074 | Land 1,838, Plots 1,400 |
| Shadow-casting parts | 5,622 | Plots 1,304, Land 1,494 (Mountains 742), ForgeMountain 713, Flora 784 |
| Unanchored parts | 0 | |
| Parts longer than 400 studs | 16 | the sea strips (one draw each, fine) |
| Unions / MeshParts | 0 | everything is plain parts |

## Streaming

- `StreamingEnabled = true`, `StreamingMinRadius = 96`, `StreamingTargetRadius = 384` (default.project.json).
- Persistent models (always loaded on every phone): 14 after the fix below. The big one is
  **Backdrop/Horizon, 2,542 parts** (outer sea, isles, fleet, planets, constellations, clouds), plus the Sky
  package's planets and clouds (~850 parts). They are Persistent on purpose: past 384 studs they would
  otherwise never stream in (Sky/Planets note).
- Atomic models: 16 (the turning decorations, vault pieces, railway).

## Per-model parts (the biggest)

| Model | Parts | Lobby | Lights | Emitters | Transparent | Shadow |
|---|---|---|---|---|---|---|
| Lobby/Backdrop/Horizon | 2,542 | 0 | 0 | 0 | 96 | 0 |
| Plots (8 x 292) | 2,336 | 2,336 | 8 | 0 | 192 | 1,304 |
| Land | 2,133 | 159 | 24 | 14 | 1 | 1,494 |
| Lobby/Vault/BlasterVault | 2,087 | 2,087 | 5 | 10 | 120 | 101 |
| Lobby/Flora/Meadow | 1,768 | 1,292 | 0 | 0 | 6 | 0 |
| Lobby/Backdrop/ForgeMountain | 1,393 | 0 | 2 | 0 | 15 | 713 |
| Lobby/Sky | 853 | 29 | 3 | 2 | 100 | 22 |
| Land/Mountains | 846 | 2 | 0 | 0 | 0 | 742 |
| Lobby/Plaza/GreatForge (+ gallery) | 800 | 800 | 5 | 6 | 4 | 93 |
| Lobby/Flora/HeroTrees | 649 | 649 | 0 | 1 | 0 | 463 |
| Railway | 457 | 190 | 3 | 0 | 0 | 103 |
| Lobby/Districts/Upgrades | 444 | 444 | 2 | 2 | 8 | 92 |
| Lobby/Districts/Shop | 427 | 427 | 1 | 0 | 8 | 90 |
| Lobby/Vault/VaultTrees | 407 | 299 | 0 | 0 | 0 | 197 |
| Lobby/Districts/SpinWheel | 334 | 334 | 2 | 1 | 0 | 68 |

## Client work every frame

- 16 client files connect `RenderStepped` / `Heartbeat`. Most return at once when their feature is idle
  (Pen, Sell, IronBox, TechShop, Podium, Foundry, Vault, Cleaning, Placement).
- Always running: **DecorController** (turns and bobs every part of every `Spin` model and recolours the
  pulsing glows), **MachineFxController** (active machines), **MiningController** (the blaster),
  **InteractController** (prompts), **BlasterFx**.
- **DecorController moved 991 parts every frame**, whether or not anyone could see them: the horizon fleet
  621 (Galleon 239, CargoShip 115, Tug 65, SailBoatB 65, HouseBoat 54, SailBoatA 46, Liner 37), the SPIN & WIN
  wheel 111, the airship 69, the west-sea ships 79, the balloon 33, the vault hologram 25, the fire crystal
  17. Plus 33 pulsing glow parts recoloured per frame. **After fix 1: 370 parts.**
- Server: no per-frame loops over parts (good; the rule in CLAUDE.md holds).

## Top 10 fixes

| # | Fix | Gain | Owner chat | Status |
|---|---|---|---|---|
| 1 | Horizon fleet lies still (no `Spin` bob 400+ studs out) | -621 parts moved per frame | mountains / horizon | **done** (branch `docs/perf-audit`) |
| 2 | DecorController: skip spinners farther than ~250 studs from the camera or not streamed in; update far ones every few frames | the wheel, airship, ships, balloon (~290 parts/frame) mostly idle | TERRA FORGE Roblox hra vývoj (DecorController) | proposed |
| 3 | Sky: the west-sea ShipA/ShipB and the airship bob is barely visible at 240+ studs: drop the bob or cull it | -148 parts/frame | TERRA FORGE Roblox hra vývoj (Sky) | proposed |
| 4 | Plots: 192 semi-transparent parts (24 per plot) and 1,304 shadow casters; make small glass bits opaque, shadows off on trim | fewer overdraw layers on every base | TERRA FORGE Roblox hra vývoj (PlotBuilder) | proposed |
| 5 | Blaster Vault: 120 semi-transparent parts (glass cases, light shafts) in one view + 10 emitters | the heaviest single view for overdraw | blaster chat (Vault) | proposed |
| 6 | Far mountains cast shadows: Land/Mountains 742 + ForgeMountain 713 + Cliffs 236; turn CastShadow off for columns > ~200 studs from the plaza (their shadows fall far from the town; check the look first) | ~1,200 fewer shadow casters | mountains / horizon | proposed (needs a visual check first) |
| 7 | SPIN & WIN: 184 neon parts (2,248 stud² of neon) bloom hard; merge the small neon segments | bloom and draw calls in the spawn view | TERRA FORGE Roblox hra vývoj (Districts) | proposed |
| 8 | Districts as a whole: 858 neon parts; group tiny neon trims into fewer, longer strips | draw calls | TERRA FORGE Roblox hra vývoj (Districts) | proposed |
| 9 | Persistent horizon: 2,542 parts always loaded; if phones struggle in the field, switch the isles (not the planets) to `StreamingMesh` LOD | memory on low-end phones | mountains / horizon | only if a device test shows it is needed |
| 10 | Device test with the MicroProfiler (Ctrl+F6) on a low-end phone in the spawn view and in a full base, to confirm 1-8 | real numbers instead of estimates | owner (Studio) | to do |

Good already: no shadow-casting lights, 41/45 lobby lights, every far decoration non-collide and without
shadows (Horizon, Meadow, RoadEdges), SurfaceGuis with MaxDistance, no unions or meshes, no unanchored parts,
no server per-frame loops.
