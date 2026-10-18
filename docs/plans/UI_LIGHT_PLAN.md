# Light UI ("Bubble", owner's style A): plan

Branch `ui/light` (worktree `projekt/.claude/worktrees/ui-light`). Everything below is **preview only**:
nothing is wired into the game until the owner approves style A.

## Owner decisions (2026-10-18)
- Light and playful like Pet Simulator 99 / "Steal an Egg"; the owner picked variant **A "Bubbles"**:
  white rounded panels, thick navy outline, a darker lip and soft shadow, gloss, **a colour per window**.
- **3D picture icons** (uploaded by the owner), phone and PC equally, menu **left** with only the main
  buttons + **MORE**, BASE / LOBBY / VAULT stays **top centre**, own **hotbar** bottom centre.
- The elevator window **stays dark** (owner's own mock).

## What exists
| Piece | File | Preview |
|---|---|---|
| Tokens, colour Roles per window | `src/shared/Config/BubbleTheme.luau` | |
| Icon sheets (3 uploads) | `src/shared/Config/IconAssets.luau` | `NAHRAJ_DO_ROBLOXU/ikony_ui/` |
| Kit: body, tile, icon, text/ink, badge, button (+price), chip, card, tabs, grid, inset, window | `src/client/UI/Bubble.luau` | |
| HUD + MORE flyout | `src/client/UI/HudBubble.luau` | `hud_a_*`, `more_*` |
| Golem Capsules | `src/client/UI/CapsuleBubble.luau` | `capsules_*` |
| Capsule opening reveal | `src/client/UI/OpeningBubble.luau` | `open1_*`, `open10_*` |
| MY GOLEMS | `src/client/UI/GolemsBubble.luau` | `golems_*` |
| Backpack (Ore Pen) | `src/client/UI/BackpackBubble.luau` | `backpack_*` |
| Robux Shop | `src/client/UI/ShopBubble.luau` | `shop_*` |
| Build mode | `src/client/UI/BuildBubble.luau` | `build_*` |
| Wheel (SPIN & WIN) | `src/client/UI/WheelBubble.luau` | `wheel_*` |
| Ore Codex | `src/client/UI/CodexBubble.luau` | `codex_*` |
| Artifacts + Journal | `src/client/UI/ArtifactsBubble.luau` | `artifacts_*`, `journal_*` |
| Hall of Fame + Settings | `src/client/UI/BoardsBubble.luau` | `boards_*`, `settings_*` |
| Gear Shop | `src/client/UI/GearBubble.luau` | `gear_*` |
| Enchants + Luck Boosts | `src/client/UI/EnchantBubble.luau` | `enchants_*`, `boosts_*` |
| **The game HUD behind the switch** | `HudBubble.buildGame` + `HudView` / `TeleportView` / `BuildView` | `game_*` |

The steps 6-7 windows take their content from `integrate/steps67` (89eb9d9); diff against the final
commit on main before coding their controllers onto them.

## The switch (already in the code, OFF)
`src/shared/Config/UIConfig.luau`: `LightUI = false`. While it is off every player sees today's UI
(tests/LightUI.spec.luau checks it). On (the flag, or the Workspace attribute `LightUI = true` for a
Studio test): `HudView.build / slot / floater / toast / buildOffline` forward to `HudBubble` (the same refs,
so HudController and the other controllers are unchanged), `TeleportView.build` fills the light top bar with
bubble tabs and a LIFT tile, `BuildView.menuButton` claims the BUILD tile. Menu tiles start hidden and show
only when a controller claims them (`HudBubble.claimTile`), so there are no dead buttons.

Pictures: `docs/screenshots/ui_bubble/` (overview: `prehled_styl_a.jpg`). Re-render:
`lune run tools/lune/export_ui_bubble.luau` then
`SHOTS_EXTRA=tools/preview/ui_bubble_shots.json node tools/preview/render.mjs world <shot>`
(`factory` scene for `ui_bubble_build_*`). Icons: `tools/preview/render_icons.mjs`
(+ `tools/lune/export_icon_parts.luau` for game models), sheets: `export_icon_sheets.luau` + `icon_sheets.mjs`.

All builders are pure and take plain data, so the controllers fill them from configs; specs in
`tests/*Bubble.spec.luau` check the content and the >= 44 pt touch sizes at uiScale 0.62.

## Game windows already converted (behind the switch)
| Window | How | Preview (`docs/screenshots/ui_light_game/`) |
|---|---|---|
| HUD, teleport bar, BUILD / LIFT tiles, offline popup | `HudView` → `HudBubble` (same refs) | `hud_*`, `base_offline_light` |
| Blaster Vault shop | `VaultView`: light header band + 3D icon, X on the corner (layout leaves room) | `vault_ui_*_light` |
| Build mode | `BuildView.build` → own light refs; `setInventory` / `setCounts` light-aware | `build_*` |
| Ore Pen | `PenView`: light skin on the same parts (`skinLight` / `skinRow`), setters light-aware | `base_pen_*_light` |
| Tobin's Sell, Tech Shop / Upgrades, Train (panel + HUD chip), Iron Box, Foundry (window + forge moment), Cleaning | `LightSkin.apply` on their gui (wrapped `build`): dark kit colours → light, navy outlines, readable text; keeps re-skinning new rows and colour changes; the cleaning reveal effects and the Foundry's 3D rack are untouched | `sell_*_light`, `tech_ui_*_light`, `train_ui_*_light`, `ironbox_ui_*_light`, `foundry_*_light`, `clean_*_light` |

Overview of the in-game light windows: `docs/screenshots/ui_light_game/prehled_ve_hre.jpg`.
`LIGHT_UI=1 lune run tools/lune/export_scene.luau <scene>` exports every UI overlay with the switch on
(`*_light`; skinned windows are refreshed right before export, since Roblox signals don't run in Lune).

Previews with the switch on: `LIGHT_UI=1 lune run tools/lune/export_scene.luau vault_shop` / `... world yard`,
then render the `*_light` shots from `tools/preview/ui_bubble_shots.json`.
Not on main yet (wait for the steps 6-7 merge): the Robux shop, capsules, golems, wheel, codex, artifacts,
boards, settings, gear, enchants, boosts. The elevator window stays dark (owner).

## Wiring it in (after the owner's YES)
1. Owner uploads the 5 sheets (`NAHRAJ_DO_ROBLOXU/ikony_ui`) → paste the ids into `IconAssets.Sheets[*].Id`,
   then set `UIConfig.LightUI = true`.
2. **HUD**: done behind the switch (see above). Still to do: the blaster in hotbar slot 1 (ToolService),
   item pictures in the slots, the LIFT placement per the owner's answer (side tile or 4th tab).
3. **Menu**: the integrator's `SideMenuView.Entries` (Group Main/More, IconName) feed
   `HudBubble.Menu` / `HudBubble.More`; SideMenuController keeps its public functions.
4. **Windows** move onto the kit, keeping each controller's API:
   CapsuleView → CapsuleBubble, opening → OpeningBubble, GolemView → GolemsBubble,
   PenView/SellView → BackpackBubble, BuildView → BuildBubble, the Robux store → ShopBubble,
   VaultView / CrateOpeningView (blaster chat, main 6090647) → `Bubble.window` / `Bubble.card`
   (keep its pure layout functions and `tests/VaultView.spec.luau`), Codex / Settings / Boards /
   Wheel / Gear / Enchant / Foundry / TechShop / Train panels → `Bubble.window` with their colours.
5. Item pictures in the game: a `Bubble.model` helper (ViewportFrame + camera fit) for Ore Pen items.
6. All platforms: `GuiService.SelectedObject` on open, B / Backspace closes, NextSelection where the
   grid order is wrong, TV safe area, `GuiService.TouchControlsEnabled = false` while a window is open.
7. `bash tools/check.sh`, rebake, preview renders, QA notes in `docs/QA_REPORTS.md`, ping the
   integrator before merging into `claude/keen-wozniak-mx7azn`.
