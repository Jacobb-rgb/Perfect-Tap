# Turning the light UI on (after the owner's ANO)

**Pro majitele:** Nové světlé UI je hotové a schované ve hře za vypínačem, který je zatím vypnutý. Až napíšeš „ano“, zapnu ho jedním přepínačem a sloučím ho do hlavní verze hry. Ikonky se ukážou, až nahraješ 5 obrázků ze složky `NAHRAJ_DO_ROBLOXU/ikony_ui` a pošleš mi jejich čísla. Kdyby se ti po zapnutí něco nelíbilo, vypnu ho zpátky během pár minut a hra bude vypadat přesně jako dnes.

Branch `ui/light` (worktree `projekt/.claude/worktrees/ui-light`), everything behind
`UIConfig.LightUI` (`src/shared/Config/UIConfig.luau`), which ships **false**. While it is false every
player sees today's UI (`tests/LightUI.spec.luau` checks it). Studio test without code changes:
`NoveUI_TEST.rbxl` in the KIT folder (Workspace attribute `LightUI = true` baked in), or set that
attribute on Workspace in any place before Play.

## What the switch changes
- HUD (`HudView` → `HudBubble`, same refs), teleport tabs + LIFT tile, BUILD tile, offline popup.
- Windows: Blaster Vault, build mode, Ore Pen (own light code); Sell, Tech Shop, Train, Iron Box,
  Foundry, Cleaning, Tutorial (`LightSkin` on the same windows).
- World: every BillboardGui gets the navy-edged light labels; every ProximityPrompt shows the light
  pill (`LightWorldController`). The mine floors' `RockLabel` is skipped (its owner styles it).
- Devices: gold gamepad selection outline, D-pad order in the left menu and the tabs, safe insets,
  touch controls hidden while a light window is open.
- Not converted yet: the steps 6-7 windows (capsules, golems, wheel, codex, artifacts, boards,
  settings, gear, enchants, boosts, Robux store). They keep the dark look until converted.
  The elevator window stays dark on purpose (owner).

## Order after the ANO
1. **Merge main into `ui/light`** (`git fetch origin && git merge origin/claude/keen-wozniak-mx7azn`), fix
   conflicts (expect small ones at the top of `HudView`, `TeleportView`, `TechShopView`, `render.mjs`:
   keep both sides; the light paths are always `if UIConfig.lightUI() / if topBar:GetAttribute("Bubble")`
   branches next to the old code), `bash tools/check.sh` → ALL CHECKS PASSED.
2. **Icons**: the owner uploads `ikony_1_ui.png` … `ikony_5_artefakty.png` (guide:
   `NAHRAJ_DO_ROBLOXU/ikony_ui/NAVOD.md`) and sends 5 ids → paste them into `IconAssets.Sheets[*].Id`
   (`src/shared/Config/IconAssets.luau`, in the sheet order: Ui, Golems, Machines, Menus, Artifacts).
   Without ids the UI still works (tiles show their labels, no pictures).
3. **Flip the switch**: `UIConfig.LightUI = true`. Answer the owner's LIFT question first if it came
   (4th tab or left tile; today it is a left tile, `HudBubble.GameMenu`).
4. `bash tools/check.sh`, rebuild the place (`bash tools/build.sh`, commit `build/TerraForge.rbxl`
   only on the main branch, never on `ui/light`), render `docs/screenshots/ui_light_game/` again
   (`LIGHT_UI` is now the default, so the normal preview commands show the light UI).
5. **Ping "TERRA FORGE Roblox hra vývoj"** (the integrator) and wait for its "ok" before merging
   `ui/light` into `claude/keen-wozniak-mx7azn`; it re-runs check + rebake. Then push.
6. Tell the chats that wait for this: "Úrovně a vzhled min" (RockLabel, ElevatorRideView,
   HoverboardView in style A), "Design zbraní a blasterů" (Vault / crate opening already light),
   "Zlepšení hor v pozadí" (loading screen in style A).
7. Convert the steps 6-7 windows once they are on main (`docs/plans/UI_LIGHT_PLAN.md`: the preview
   builders `CapsuleBubble`, `GolemsBubble`, `WheelBubble`, `CodexBubble`, `ArtifactsBubble`,
   `BoardsBubble`, `GearBubble`, `EnchantBubble`, `ShopBubble` already exist).

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
- One line: `UIConfig.LightUI = false` in `src/shared/Config/UIConfig.luau`, commit, publish. Every
  light path is behind that flag, so the game looks exactly like before the switch.
- For a single test server or Studio: remove / untick the Workspace attribute `LightUI`.
- Nothing in the save data depends on the light UI, so switching back and forth is safe.
