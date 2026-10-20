#!/usr/bin/env bash
# The LIMITED EDITION pictures (Config/LimitedGolems): the banner concept
# (tools/lune/lib/limited_golems_preview.luau), the set's golem and capsule
# icons (golem_<Id>, capsule_<Id>) and the sheets in
# docs/screenshots/limited_golems/ (tools/preview/limited_sheet.mjs).
# Run from anywhere: bash tools/preview/limited_golems.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

shots=(Dragonforge:limited_dragonforge)
for pair in "${shots[@]}"; do
  set_id=${pair%%:*}
  shot=${pair##*:}
  lune run tools/lune/export_scene.luau "limited_$set_id" | tail -1
  SHOTS_EXTRA=tools/preview/limited_golems_shots.json node tools/preview/render.mjs "limited_$set_id" "$shot" | tail -1
done

icons=(capsule_Dragonforge)
for id in CinderWhelp EmberHatchling ScaleKnight Flamewing MagmaWyvern DragonKing; do
  icons+=("golem_$id")
done
lune run tools/lune/export_icon_parts.luau "${icons[@]}" | grep -c "Exported icon part" | sed 's/^/icon models: /'
node tools/preview/render_icons.mjs "${icons[@]}" robux | grep -c "^icon " | sed 's/^/icons rendered: /'

node tools/preview/limited_sheet.mjs
