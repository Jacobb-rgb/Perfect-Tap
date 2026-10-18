# Mine floors plan (owner, 2026-10-17)

Owner decisions: docs/DESIGN_V2_NOTES.md, section "Mine floors". Branch `art/mine-floors`.
Goal: the deeper the floor, the harder the rocks, the better the ores, and the cooler the crystals.

## Done (concept stage)
| File | What |
|---|---|
| src/shared/Config/MineFloors.luau | 5 floors: blaster gate 1/3/5/7/9, 7 home ores each, floor 1 has 8 (all 36 ores of the owner's roster), better `CrystalOres`, palettes, lighting preset, elevator flag; rock kinds, ore counts (3/4/3), `Seconds` per kind (4/5/6 s with the floor's weakest blaster), spawn chances (Big 30 %, Crystal 10 %, Golden 2 %, Geode 1.5 %, Artifact 1 %), Giant Crystal (every 600 s), elevator price; `rockHealth(floor, kind)` |
| src/shared/Builders/RockBuilder.luau | v3 (owner: "more shard shapes", The Forge basalt rocks as reference): a tall central stone shard and a ring of shards leaning outward, each with extra facets and a slanted or ridged top (palace: upright pillars with gold trims), a glowing core in the gaps (lava, ice, gold, heart glow) and dense clusters of slim two-tone faceted crystals (glowing tips, twinkles, pointed hero crystals made of exact triangles). `build(floor, kind, oreIds, base, seed)` for Small, Big, Crystal, Golden, Geode, Artifact, Giant; floor looks (quarry matte copper/quartz → ember lava seams + fire tips → lagoon moss, mushroom, glassy crystals → palace carved stone, gold trim, column → core floating rock, debris, pure glow); `applyStage(model, stage, seed)`: cracks glowing in the stage's ore color on the outer chunks, one chunk + one crystal break off. Budgets 66–92 parts (Giant 170) |
| src/shared/Config/LightingConfig.luau | presets `Lagoon`, `Palace`, `Core` |
| src/client/UI/RockLabel.luau | name + HP over a rock (owner: "like The Forge"): name in `MineFloors.labelColor`, "20 HP" (or red "Lv 5" when locked), red HP bar; 45-stud range, hidden behind walls. Names from `MineFloors.rockName` (Greystone / Basalt / Hollow Stone / Palace Stone / Void Rock, "… Boulder", "Quartz Shard" …, Golden Rock, Geode, Ancient Rock, Giant …). Wire it in MiningController with the gameplay step (max ~12 labels, nearest rocks) |
| Floor 1 (owner: "only the first floor is not as good") | blue-grey slate shards that stand out on the sand, pale layers, shiny copper veins and nuggets, grass tufts, big copper/quartz crystal crowns with glowing tips |
| tests/MineFloors.spec.luau | floors, ore coverage, HP ≈ seconds, budgets, crystals grow with depth, crack stages |
| tools/lune/lib/mine_concepts.luau, tools/preview/mine_shots.json | scene `mine_rocks`: rock rows per floor, Giant Crystals, breaking storyboard; scene `mine_showcase`: the stepped neon ore shelf like the owner's reference |

| src/server/World/Mine/MineKit.luau | shared floor pieces + the Floor<N> contract: elevator stop, blaster gate, ore lift (Railway.buildLift), rock walls, stalactites, crystal clusters (RockBuilder.decorCluster), rock spawns |
| src/server/World/Mine/Floor1Quarry … Floor5Core | the 5 floor areas (concept, owner asked "start the floors" after approving the rocks): 1 sunset open-pit quarry with slate terraces, voxel trees, scaffolds, shed, rails and the glowing Ember Caves tunnel; 2 basalt-column cave with glowing veins, lava river + arch bridge, lava fall, pools; 3 crystal lagoon with glowing water, two waterfalls, giant crystals out of the water, boardwalk and mushroom groves; 4 sunken throne hall with checkered floor, marble columns, banners, broken throne and Ember King statue; 5 floating violet islands with glowing bridges and the giant cracked Heartstone. Each 18–31 rock spawns (back = Deep), GiantSpawn, Entrance, elevator, gate, ore lift; 2.1–2.8K parts, ≤ 23 lights. Scene `mine_floor <N>` places rocks on the spawns; pictures in docs/screenshots/mine_floors/ |

Render: `lune run tools/lune/export_scene.luau mine_rocks` (or `mine_showcase`) then
`SHOTS_EXTRA=tools/preview/mine_shots.json node tools/preview/render.mjs mine_rocks` (or `mine_showcase`).
Performance note: rocks are now 55–75 parts; when wiring them in, consider building the crystal clusters on the
client only (decoration) and keeping the server rock to the chunks.
Pictures: docs/screenshots/mine_concepts/.

## Next (after the owner approves the rock look)
1. ~~Floor mood pictures~~ done as full floor areas (above); owner feedback next. Known: Railway.buildLift faces
   along world X by the sign of x and hangs its cable to y + 30 (fine at origin x = 0; add a facing/height option
   when the floors move to their real places).
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
   Ore lifts (train session, 2026-10-17): add each lift to TrainConfig.Lifts (Id, Position, Size); the model needs tag
   "MineLift" + attribute LiftId, a BasePart "Intake" tagged "TrainHopper" (attribute LiftId) and an Attachment
   "PromptPoint" (Railway.buildLift makes all of these; tests/Railway.spec.luau checks every entry), and a
   WorldLayout.KeepOut box around each lift. Send the positions to the train session first.
6. **Elevator**: station next to the Mine Station; bought once for `MineFloors.Elevator.Price`; menu of unlocked floors;
   save field; works with mouse, touch and gamepad.
7. **Hoverboards**: 3 coin boards (faster each), 2 Robux boards (~50 R$, faster + effects); MonetizationConfig placeholders.
8. Balance pass with the economy step (ore weights, HP, prices), QA, Studio checklist, pictures.
