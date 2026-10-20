# The light UI is ON (2026-10-20)

**Pro majitele:** Nové světlé UI je zapnuté (`ui/light`, čeká na sloučení do hlavní verze hry). Ikonky zatím ukazují smajlíky, dokud nenahraješ 5 obrázků ze složky `NAHRAJ_DO_ROBLOXU/ikony_ui` a nepošleš mi jejich čísla. Kdyby se ti něco nelíbilo, vypnu ho zpátky během pár minut a hra bude vypadat jako předtím.

Branch `ui/light` (worktree `projekt/.claude/worktrees/ui-light`). The switch is `UIConfig.Default`
(`src/shared/Config/UIConfig.luau`), **true** since the owner's go (2026-10-20, relayed by the
watcher). The test runner pins `LightUI = false` (`tools/lune/test.luau`) so the old-path specs keep
testing the dark UI; `tests/LightUI.spec.luau` switches it on itself. Overview picture:
`docs/screenshots/ui_light_game/prehled_zapnuto.jpg`.

## What the switch changes
- HUD (`HudView` → `HudBubble`, same refs), teleport tabs (BASE / LOBBY / VAULT), the left tiles
  (BACKPACK, GOLEMS, BUILD, SHOP, ELEVATOR + MORE flyout from `SideMenuView.Entries`; the old side
  column hides), offline popup.
- Windows: Blaster Vault, build mode (incl. the DECK / GROUND toggle), Ore Pen (own light code);
  Sell, Tech Shop, Train, Iron Box, Foundry, Cleaning (incl. the relic card), Tutorial, the steps 6-7
  windows, MenuPanel windows (Codex, Settings, Boards, STAR FORGE rebirth) wear `LightSkin`.
- Icons: 3D pictures from `IconAssets` once the 5 sheet ids are in; until then `Bubble.icon` shows
  an emoji (`IconAssets.fallback`).
- World: every BillboardGui gets the navy-edged light labels; every ProximityPrompt shows the light
  pill (`LightWorldController`). The mine floors' `RockLabel` is skipped (its owner styles it).
- Devices: gold gamepad selection outline, D-pad order in the left menu and the tabs, safe insets,
  touch controls hidden while a light window is open.
- Stay in their own look on purpose: the elevator window and its ride (owner), the hoverboard panel
  (the elevator's neon sibling), the crate opening and the loading screen.

## Still to do
1. **Icons**: the owner uploads `ikony_1_ui.png` … `ikony_5_artefakty.png` (guide:
   `NAHRAJ_DO_ROBLOXU/ikony_ui/NAVOD.md`) and sends 5 ids → paste them into `IconAssets.Sheets[*].Id`
   (in the sheet order: Ui, Golems, Machines, Menus, Artifacts). The emoji stand-ins go away by
   themselves.
2. Landing: the integrator ("TERRA FORGE Roblox hra vývoj") merges `ui/light` into
   `claude/keen-wozniak-mx7azn`, re-runs check + rebake. `build/TerraForge.rbxl` is committed only on
   the main branch, never on `ui/light`.

## What to watch for (first Studio play with the switch on)
- Phone (Device emulator 667x375 and 568x320): coins, tabs and the left tiles don't meet; the
  tutorial bubble sits right of the tabs; windows hide the thumbstick and bring it back on close.
- Gamepad (Xbox / PS emulator): the gold outline shows, D-pad walks the left menu and the tabs,
  B closes every window.
- Prompts: F / tap / gamepad button on stalls and machines; holding fills the green bar; prompts
  hidden in build mode and the cleaning close-up stay hidden.
- Labels: podium income tags and machine signs readable from a distance (bold navy edge).
- Old dark windows that LightSkin dresses: a colour a controller sets later is re-mapped live; if
  some text ends up white on white, that colour is missing from `LightSkin` BACKGROUNDS / INK.

## Turning it back off fast
- One line: `UIConfig.Default = false` in `src/shared/Config/UIConfig.luau`, commit, publish. Every
  light path is behind that flag, so the game looks exactly like before the switch.
- With it off, the Workspace attribute `LightUI = true` turns it on for a single test server / Studio.
- Nothing in the save data depends on the light UI, so switching back and forth is safe.
