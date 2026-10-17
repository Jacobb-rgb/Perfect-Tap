# Mine floors plan (owner, 2026-10-17)

Owner decisions: docs/DESIGN_V2_NOTES.md, section "Mine floors". Branch `art/mine-floors`.
Goal: the deeper the floor, the harder the rocks, the better the ores, and the cooler the crystals.

## Done (concept stage)
| File | What |
|---|---|
| src/shared/Config/MineFloors.luau | 5 floors: blaster gate 1/3/5/7/9, 6 home ores each (all 30 ores), better `CrystalOres`, palettes, lighting preset, elevator flag; rock kinds, ore counts (3/4/3), `Seconds` per kind (4/5/6 s with the floor's weakest blaster), spawn chances (Big 30 %, Crystal 10 %, Golden 2 %, Geode 1.5 %, Artifact 1 %), Giant Crystal (every 600 s), elevator price; `rockHealth(floor, kind)` |
| src/shared/Builders/RockBuilder.luau | `build(floor, kind, oreIds, base, seed)` for Small, Big, Crystal, Golden, Geode, Artifact, Giant; floor looks (quarry strata + matte crystals → ember lava cracks + glowing tips → lagoon moss, mushroom, glassy crystals → palace carved stone, gold trim, column → core floating rock, debris, glowing crystals); `applyStage(model, stage, seed)`: cracks glowing in the stage's ore color, one lump + one crystal break off |
| src/shared/Config/LightingConfig.luau | presets `Lagoon`, `Palace`, `Core` |
| tests/MineFloors.spec.luau | floors, ore coverage, HP ≈ seconds, budgets, crystals grow with depth, crack stages |
| tools/lune/lib/mine_concepts.luau, tools/preview/mine_shots.json | scene `mine_rocks`: rock rows per floor, Giant Crystals, breaking storyboard |

Render: `lune run tools/lune/export_scene.luau mine_rocks` then
`SHOTS_EXTRA=tools/preview/mine_shots.json node tools/preview/render.mjs mine_rocks`.
Pictures: docs/screenshots/mine_concepts/.

## Next (after the owner approves the rock look)
1. **Floor mood pictures**: a small diorama per floor (props, lighting) for the owner to approve.
2. **Gameplay wiring** (MiningService, BlasterData, WorldLayout): rocks spawn per floor with `MineFloors.SpawnChance`,
   roll ores from `Ores` / `CrystalOres`, HP from `rockHealth`; a drop at every stage (1 .. OreCount − 1) and the last
   ore at the shatter; floor gate check `MinBlaster`; Giant Crystal event (shared HP, reward for ≥ MinDamageShare);
   special rocks (artifact roll on Artifact rocks); OreData `Tier` follows the home floor. Retire `OreNodeBuilder.buildRock`.
3. **Breaking animation** (client): beam impact sparks, shake per hit, crack stage pop (pieces fling with physics on the
   client only, then fade), ore chunk pops out, final shatter burst (dust in the floor color, sparks, flash, sound).
4. **Re-theme floors 1–3** (Land.luau quarry/caves, zone lighting `Lagoon` for Deep Hollow) without moving the train
   session's Mine Station (quarry floor x 12..40, z −150..−144), track z = −156 and Mine Lifts
   (Ember Caves 22, −12, −258; Deep Hollow 16, −40, −402). Tell that session before changing those areas.
5. **Floors 4–5** as separate areas below the map (StreamingEnabled), each with a lift/cart feeding the player's train.
6. **Elevator**: station next to the Mine Station; bought once for `MineFloors.Elevator.Price`; menu of unlocked floors;
   save field; works with mouse, touch and gamepad.
7. **Hoverboards**: 3 coin boards (faster each), 2 Robux boards (~50 R$, faster + effects); MonetizationConfig placeholders.
8. Balance pass with the economy step (ore weights, HP, prices), QA, Studio checklist, pictures.
