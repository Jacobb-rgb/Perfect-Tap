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

Pictures: `docs/screenshots/ui_bubble/` (overview: `prehled_styl_a.jpg`). Re-render:
`lune run tools/lune/export_ui_bubble.luau` then
`SHOTS_EXTRA=tools/preview/ui_bubble_shots.json node tools/preview/render.mjs world <shot>`
(`factory` scene for `ui_bubble_build_*`). Icons: `tools/preview/render_icons.mjs`
(+ `tools/lune/export_icon_parts.luau` for game models), sheets: `export_icon_sheets.luau` + `icon_sheets.mjs`.

All builders are pure and take plain data, so the controllers fill them from configs; specs in
`tests/*Bubble.spec.luau` check the content and the >= 44 pt touch sizes at uiScale 0.62.

## Wiring it in (after the owner's YES)
1. Owner uploads the 3 sheets → paste the ids into `IconAssets.Sheets[*].Id`.
2. **HUD**: HudController builds `HudBubble` instead of `HudView` (coins, income, toasts, zone name,
   floaters, the carry slots → hotbar). TeleportController drives `HudBubble` tabs (cooldown cover,
   gamepad hint stay). The LIFT button: follow the owner's answer (side tile or 4th tab).
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
