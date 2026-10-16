---
name: preview-pictures
description: Render preview pictures of Terra Forge (world, lobby, machines, ores, UI, cleaning minigame) without Roblox Studio, check them visually and send them to the owner. Use after any visual change and whenever the owner asks for pictures.
---
# Preview pictures

The owner wants pictures of progress after every step. Renders are a three.js approximation of Roblox lighting:
always say so ("náhled z herního kódu").

## Setup (once)
`cd tools/preview && npm install && npx playwright install chromium && cd ../..`

## Render
- Export a scene: `lune run tools/lune/export_scene.luau world` (others: `gameplay`, `cleaning <OreId> <chisel|scrape|polish|reveal> [phone]`).
- Render shots from tools/preview/shots.json: `node tools/preview/render.mjs world town_overview great_forge`.
- Extra/private shots without editing shots.json: `SHOTS_EXTRA=path/to/my_shots.json node tools/preview/render.mjs world myshot`
  (shot: `{"scene":"world","position":[x,y,z],"target":[x,y,z],"fov":60,"preset":"Surface","shadowExtent":160}`; UI overlay via `"ui"`).
- Output: build/preview/shots/<shot>.jpg (never commit build/preview; copy keepers to docs/screenshots/).

## Check before sending
Open the jpg with Read. Look for: floating/clipping parts, holes, unreadable text, overexposed glows (white blobs),
too dark caves, UI covering the action (also render a phone-sized version), things that look alike.
Fix and re-render. Then send with a short Czech caption saying what the picture shows.
