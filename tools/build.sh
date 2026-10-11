#!/usr/bin/env bash
# Builds build/TerraForge.rbxl: Rojo builds the scripts/lighting, then Lune
# bakes the generated map into Workspace.Map so you can see it in Studio.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
base="build/TerraForge.base.$$.rbxl"
rojo build default.project.json -o "$base"
lune run tools/lune/bake.luau "$base" build/TerraForge.rbxl
