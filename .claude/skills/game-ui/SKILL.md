---
name: game-ui
description: Build or change any Terra Forge UI (HUD, shops, side menu, podium Remove button, capsule opening, wheel, leaderboards, codex, popups). Use for anything under src/client/UI or any ScreenGui/BillboardGui/SurfaceGui.
---
# Game UI

Style: src/shared/Config/UITheme.luau (FredokaOne body, LuckiestGuy titles, Accent orange, dark warm panels) and
src/client/UI/UIKit.luau (panel, button with lip, label, chip). UI is designed for 720 px height and scaled by
HudController.uiScale (floor 0.62 on phones). UI text is **English**.

## Rules
- Works on **PC, phone, tablet, Xbox and PlayStation** (see the all-platforms skill): every button reachable by
  mouse, touch and gamepad (GuiService selection), touch targets ≥ 44 pt at the phone scale, nothing important in
  the screen corners covered by notches/top bar, readable from a sofa on a TV.
- **Side menu** (left edge, like popular simulators): Shop, Boosts (Triple Lucky, Hexa Lucky), Capsules, Codex,
  Settings. Robux items clearly marked with the Robux icon and price; odds shown for anything random.
- **Big numbers:** one shared formatter: 1,234 → 1.23K → 4.5M → 2B → 3T → Qa → Qi → Sx → Sp → Oc → No → Dc.
  Money per second shown as "+$1.3K/s". Never show raw floats.
- **Podiums:** hovering (mouse) or tapping/selecting (touch/gamepad) shows a "Remove" button next to the podium.
- Juice but calm: short pop/scale tweens, soft sounds, no flashing walls of text. Toasts max 3 at once.
- Every screen has a close button (and B / Backspace closes it). No dead buttons.
- Test layouts with phone-sized renders (preview-pictures skill) and add Lune tests for formatters/pure layout math.
