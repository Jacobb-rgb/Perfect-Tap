---
name: lobby-art
description: Build or change the Terra Forge town lobby so it matches the owner's concept image docs/art/lobby_concept.webp. Use for any work in src/server/World/Lobby/*, Town.luau, Land.luau, LobbyLayout, lighting/sky of the hub.
---
# Lobby art (match the concept)

Target: docs/art/lobby_concept.webp. The owner said "exactly like this". Plan: docs/plans/LOBBY_PLAN.md (positions of
every element, 5 packages: Sky, Backdrop, Plaza, Districts, Flora). Style bible: docs/ART_DIRECTION.md. Shared kit:
src/server/World/Lobby/Style.luau (`Style.C` colors + helpers); positions only from src/shared/Config/LobbyLayout.luau.
Design v2 adds lobby stalls: Sell (miner NPC), daily wheel of fortune, gear shop, capsule (golem) stall, Tech shop,
Enchant shop, 4 leaderboards (docs/DESIGN_V2_NOTES.md); fit them into the plan.

## Loop (do it every time)
1. Build one piece. 2. `lune run tools/lune/export_scene.luau world` and render
   `SHOTS_EXTRA=tools/preview/lobby_shots.json node tools/preview/render.mjs world lobby_hero` (+ close-ups).
3. Open the render AND the concept with Read; list differences (shape, color, density, lights, readability).
4. Fix the biggest ones, repeat. 5. `bash tools/check.sh` (walkability, no holes, budgets in tests/Lobby.spec.luau).
6. Bump WorldBuilder.Version, rebake, commit, send the owner the hero render.

## Rules
- Keep gameplay hooks/tags: SellCounter, SellBin(+Intake), ShopCounter, UpgradeCounter, EmberChest (wheel), OreCodex,
  FossilDig, GuildBoard, Spin, TownSpawn.
- Don't move plots, roads, quarry, cave entrances, zones. Budgets: lobby ≤ ~5000 parts, ≤ 45 lights.
- Calm, warm, cozy mood (sunset, lanterns), readable signs with big letters, nothing noisy.
