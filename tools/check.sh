#!/usr/bin/env bash
# Runs every automatic check: Roblox type analysis, Lune unit tests, place build.
# Needs rojo, lune and luau-lsp on PATH (see rokit.toml / docs/ROJO_SETUP.md).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
status=0

defs=build/globalTypes.d.luau
if [ ! -f "$defs" ]; then
  echo "Downloading Roblox type definitions..."
  curl -sSL -o "$defs" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau || true
fi

echo "== Type analysis (luau-lsp, strict mode)"
rojo sourcemap default.project.json --output build/sourcemap.json
echo '{"languageMode":"strict"}' > build/strict.luaurc
analysis=$(luau-lsp analyze --platform=roblox --sourcemap=build/sourcemap.json --definitions="$defs" \
    --base-luaurc=build/strict.luaurc src 2>&1 | grep -v "\[game/" )
if [ -n "$analysis" ]; then
  echo "$analysis"
  status=1
else
  echo "no problems found"
fi

echo "== Unit tests (lune)"
if ! lune run tools/lune/test.luau; then
  status=1
fi

echo "== Place build"
if ! bash tools/build.sh; then
  status=1
fi

if [ $status -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $status
