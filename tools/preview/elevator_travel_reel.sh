#!/usr/bin/env bash
# Renders the elevator travel cinematic exported by
#   lune run tools/lune/export_elevator_travel.luau reel [from] [to] [fps]
# The preview draws one lighting preset a reel, so the ride comes as three reels (the stop,
# the cabin, the arrival), joined here into build/preview/elevtravel.mp4 with its storyboard
# build/preview/elevtravel_board.jpg. A three.js approximation of Roblox: the game's own code
# poses everything.
#   bash tools/preview/elevator_travel_reel.sh [fps=20]
set -euo pipefail
cd "$(dirname "$0")/../.."
fps=${1:-20}
out=build/preview
for seg in a b c; do
  node tools/preview/render_reel.mjs "elevtravel_${seg}" "$fps" 4000000 -
done
rm -rf "$out/elevtravel_frames"
mkdir -p "$out/elevtravel_frames"
i=0
for seg in a b c; do
  for f in "$out/elevtravel_${seg}_frames"/frame_*.jpg; do
    cp "$f" "$(printf '%s/elevtravel_frames/frame_%04d.jpg' "$out" "$i")"
    i=$((i + 1))
  done
done
swift tools/preview/encode_mp4.swift "$out/elevtravel_frames" "$out/elevtravel.mp4" "$fps" 4000000
node tools/preview/render_reel.mjs elevtravel "$fps" 4000000 board
echo "video -> $out/elevtravel.mp4 ($i frames)"
