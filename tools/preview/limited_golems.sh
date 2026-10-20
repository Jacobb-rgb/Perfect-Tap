#!/usr/bin/env bash
# The LIMITED EDITION golem proposals (Config/LimitedGolems) as pictures for the owner:
# the four concept scenes (tools/lune/lib/limited_golems_preview.luau), the 24 golems'
# shop icons (golem_<Id>) and the sheets in docs/screenshots/limited_golems/
# (tools/preview/limited_sheet.mjs). Run from anywhere: bash tools/preview/limited_golems.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

shots=(Dragonforge:limited_dragonforge Galaxy:limited_galaxy MechaNeon:limited_mecha FrostTitans:limited_frost)
for pair in "${shots[@]}"; do
  theme=${pair%%:*}
  shot=${pair##*:}
  lune run tools/lune/export_scene.luau "limited_$theme" | tail -1
  SHOTS_EXTRA=tools/preview/limited_golems_shots.json node tools/preview/render.mjs "limited_$theme" "$shot" | tail -1
done

icons=()
for id in CinderWhelp EmberHatchling ScaleKnight Flamewing MagmaWyvern DragonKing \
  AstroCadet CometCub OrbitKeeper CosmoWizard NovaGuardian NebulaTitan \
  BoltBot BeatBot LaserRanger RocketRex JetStriker OmegaMech \
  Frostling GlacierCub IceKnight BlizzardSage PolarTitan AuroraColossus; do
  icons+=("golem_$id")
done
lune run tools/lune/export_icon_parts.luau "${icons[@]}" | grep -c "Exported icon part" | sed 's/^/icon models: /'
node tools/preview/render_icons.mjs "${icons[@]}" | grep -c "^icon " | sed 's/^/icons rendered: /'

node tools/preview/limited_sheet.mjs
