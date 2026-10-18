# review/hory-noc: the mountains chat's night work (2026-10-18)

One branch with everything from the night, on top of main 49c2bac (tutorial). It is fast-forwardable from main.
Map v30, 20,672 / 23,000 parts. `bash tools/check.sh`: ALL CHECKS PASSED (792 tests, PhoneBudget included).
It goes in only after the integrator's ok **and** the owner's "ano" in the mountains chat.

## What is in it (each part still has its own branch)

| # | Branch | What the owner sees | Depends on |
|---|---|---|---|
| A | `art/concept-pass` (89cc973) | lanterns on the fences, bushes and rocks on the lawns, autumn jungle crowns, no spire shadows | main |
| B | `art/lobby-life` (9c701b0) | koi in the ponds, butterflies over the flower beds | A |
| C | `art/plaza-life` (73b7e41) | 9 miners round the plaza, lanterns and props at the stall fronts, the stream with a humped bridge and a waterfall into the sea | A |
| D | `feature/music-badges` (d763c1a) | music per area (silent until the owner picks tracks), 11 badges (skipped until created), analytics | main |
| E | `docs/perf-audit` (2101ccf) | the far ships lie still (phones: 621 fewer parts moved per frame); docs/PERF_AUDIT.md | main |
| F | `fix/meadow-outcrops` (fbf7d94) | no pond or flower bed over an ore rock (a bug from map v20) | main |
| G | review-only commit cc5e7e1 | phone trims: fewer grass tufts, lighter flower beds, 2-part fence lanterns, 4-part plaza lanterns | A, C |
| H | review-only commit 949c5fa | the meadow ponds come back (3: south-west and south-east corners, east behind the forge); with A-F together the meadow had placed none | F (and C) |
| I | review-only commit d713af0 | quiet lobby sounds: water at the waterfalls and the stream, plops and crickets at the ponds, hammer and fire at the forge, wind high up (docs/handoff/ZVUKY_LOBBY.md) | main |

## If the owner says yes to only some

Drop in this order (the later ones depend on nothing that comes after them):
1. **D, E, F** are independent: each can go in or out on its own (merge its branch onto main).
2. **G** needs A and C: drop it whenever A or C is dropped. **H** fixes what F and C together did to the
   meadow's ponds: keep it whenever F is in (cherry-pick 949c5fa). **I** (cherry-pick d713af0) works on any of
   them; its spots skip what is missing (no stream = no brook spot).
3. **B** and **C** need A: without A, cherry-pick their own commits (B: 9c701b0; C: 2788610) onto main and
   rebake; Meadow conflicts are small (B adds koi/butterflies, C adds `Meadow.track`).
4. **A** alone: merge `art/concept-pass` onto main.

Every merge: take `WorldBuilder.Version` = max + 1 and keep every note; rebake (`bash tools/build.sh`).

## Meeting art/mine-floors (mine ambience, 97548a1)

The mine floors reuse this branch's ambience (I). Whichever of the two lands on main second:
1. AmbienceConfig.luau: `local MineAmbience = require(Shared.Config.MineAmbience)`, and right after
   `AmbienceConfig.Kinds = {...}`: `for kind, layers in MineAmbience.Kinds do AmbienceConfig.Kinds[kind] = layers end`
   (MineAmbience never requires AmbienceConfig).
2. tests/Ambience.spec.luau: scope "exactly 5 kinds", "spots in the lobby area" and "<= 20 spots" to the lobby kinds
   (Waterfall, Brook, Pond, Forge, Plaza); tests/MineAmbience.spec.luau covers the floors.
3. `WorldBuilder.Version` above both (mine-floors 28, this branch 30), every note kept.
SoundConfig: their keys sit after DoorThud, ours after CaseRise; no names collide.

## Not done (on purpose)

- Persistent horizon -> `StreamingMesh` LOD for the isles and the fleet (integrator plan item a, up to ~3k fewer
  streamed parts): the imposter meshes are coarse and the preview cannot show them; try it after a device test
  (docs/PERF_AUDIT.md item 9). The planets stay Persistent (Sky/Planets note).
- The space skybox, the music ids, the badge ids and two ambience ids (plaza murmur, frog) wait for the owner
  (NAHRAJ_DO_ROBLOXU/*).
