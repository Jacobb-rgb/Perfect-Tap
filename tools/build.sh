#!/usr/bin/env bash
# Builds build/TerraForge.rbxl: Rojo builds the scripts/lighting, then Lune
# bakes the generated map into Workspace.Map so you can see it in Studio.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
base="build/TerraForge.base.$$.rbxl"
rojo build default.project.json -o "$base"
lune run tools/lune/bake.luau "$base" build/TerraForge.rbxl
# Rojo and Lune can't write Content properties: put back the owner's PBR models' texture packs
# (without them Studio re-uploads every one when the place runs, and a failed upload leaves the model
# grey in the published game; tools/meshy/texture_packs.mjs) and fail if one has none
node tools/meshy/texture_packs.mjs inject build/TerraForge.rbxl
node tools/meshy/texture_packs.mjs check build/TerraForge.rbxl
# nor CollisionFidelity: every MeshPart without a collision hull (the owner's models but the rocks and
# the mossy cliff, tools/lune/import_meshes.luau) gets its Box back (tools/meshy/strip_hulls.mjs)
node tools/meshy/strip_hulls.mjs boxes build/TerraForge.rbxl
