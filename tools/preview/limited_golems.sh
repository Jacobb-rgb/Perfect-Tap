#!/usr/bin/env bash
# The LIMITED EDITION pictures (Config/LimitedGolems, Config/LimitedUpcoming):
# the banner concept (tools/lune/lib/limited_golems_preview.luau with the
# set's backdrop in tools/lune/lib/limited_backdrops/<Set>.luau), the shard
# showcase, the set's golem and shard icons and the sheets in
# docs/screenshots/limited_golems/ (tools/preview/limited_sheet.mjs).
# Run from anywhere: bash tools/preview/limited_golems.sh [SetId ...]   (default: Dragonforge)
set -euo pipefail
cd "$(dirname "$0")/../.."

sets=("$@")
if [ ${#sets[@]} -eq 0 ]; then sets=(Dragonforge); fi
for set_id in "${sets[@]}"; do
  shot="limited_$(echo "$set_id" | tr '[:upper:]' '[:lower:]')"
  lune run tools/lune/export_scene.luau "limited_$set_id" | tail -1
  SHOTS_EXTRA=tools/preview/limited_golems_shots.json node tools/preview/render.mjs "limited_$set_id" "$shot" | tail -1
  lune run tools/lune/export_scene.luau "limitedshard_$set_id" | tail -1
  SHOTS_EXTRA=tools/preview/limited_golems_shots.json node tools/preview/render.mjs "limitedshard_$set_id" "${shot}_shard" | tail -1
  # the set's icons: its 6 golems and its capsule / shard (from the info file)
  icons=$(python3 -c "import json,sys; d=json.load(open('build/preview/limited_${set_id}_info.json')); c=d['CapsuleId']; print(' '.join(['golem_'+g['Id'] for g in d['Golems']]+[c if c.startswith('shard_') else 'capsule_'+c]))")
  lune run tools/lune/export_icon_parts.luau $icons | grep -c "Exported icon part" | sed 's/^/icon models: /'
  node tools/preview/render_icons.mjs $icons robux | grep -c "^icon " | sed 's/^/icons rendered: /'
done

node tools/preview/limited_sheet.mjs "${sets[@]}"
