---
name: all-platforms
description: Make Terra Forge play perfectly on PC (mouse+keyboard), mobile/tablet (touch), Xbox and PlayStation (gamepad, TV). Use for every feature that has input, camera, UI, prompts or performance impact, and before marking any step done.
---
# Perfect on every platform

The owner requires the game to play perfectly on **PC, mobile, Xbox and PlayStation**. A feature is not done until it
works with only a mouse+keyboard, only touch, and only a gamepad.

## Input
- Use ContextActionService / UserInputService with all three: keys (E grab, Q throw, F prompts, B build...),
  gamepad (X grab, RB throw, Y prompts, R2 action, B back, D-pad Up build), and **on-screen touch buttons**
  (ContextActionService:BindAction(..., true) or own buttons) for every action.
- Detect the current device from UserInputService:GetLastInputType() and update hints live (PointerInput pattern).
- Show **platform-correct button glyphs**: UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonX) (Xbox vs
  PlayStation icons differ) and GetStringForKeyCode for keyboards; never hard-code "Press X".
- Blaster mining: mouse hold, touch hold on an on-screen button or tap-and-hold on the rock, gamepad R2 with aim
  assist toward the nearest rock.
- Optional rumble: HapticService on gamepads for blasting/crack (light, can be turned off).

## Console (Xbox, PlayStation) specifics
- **TV safe area:** keep UI inside the safe area (ScreenGui.ScreenInsets = DeviceSafeInsets / GuiService insets);
  text big enough for a TV (≥ 18 px at 1080p after scaling).
- **Every menu navigable with the D-pad/stick**: set GuiService.SelectedObject when a menu opens, NextSelection*
  links where the auto-order is wrong, B closes, no hover-only features (the podium "Remove" button must also
  appear when the podium is selected/targeted).
- No keyboard text entry required to play (forge name optional); no external links; hide chat UI on console if
  needed per Roblox console guidelines; Studio "Device emulator" has Xbox/PS presets for testing.
- Enable the console devices in the experience settings (docs/COMPLIANCE.md lists the publishing settings).

## Mobile
- Thumb-reachable buttons (bottom-right action cluster), ≥ 44 pt targets, compact layouts at uiScale ≤ 0.75
  (CleaningView.setCompact pattern), notch-safe UI, no tiny text.
- Performance: StreamingEnabled, low part counts, pooled particles, ≤ 45 lights in view, no per-frame server loops.

## Checklist before done
Mouse+keyboard ✔ · touch only (Studio device emulator, phone) ✔ · gamepad only ✔ · Xbox and PS glyphs ✔ ·
TV safe area ✔ · phone-sized preview render ✔ · FPS on a low-end phone emulator ✔. Add the Studio test steps to
docs/QA_REPORTS.md.
