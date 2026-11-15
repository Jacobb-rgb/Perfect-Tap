# Elevator travel cinematic (owner 2026-11-15)

The owner's "ROBLOX ELEVATOR TRAVEL ANIMATION" request, built on the game's own elevator,
floors and teleport. Branch `anim/elevator-travel` (from main `a90ba516`). It lands only after
the owner's own yes.

## What the player sees (5.55-5.95 s)

| Seconds | Phase | What happens |
|---|---|---|
| 0.0-0.7 | 1 preparation | the floor window stays up (the picked card lit: ui/elevator-v2's `ElevatorWindow.pick`), **PREPARING ELEVATOR...** pill, the cage lamp turns up, a yellow warning beacon on the cage flashes twice, a small camera shake, a mechanical clunk + two beeps |
| 0.7-1.5 | 2 doors | a 0.12 s dip to black, the camera stands in a steel cabin built over the real cage (the real cage hidden), the doors slide shut over the mine being left, the digital screen over the doors shows the floor, cinema bars slide in; door slide sound, a thud |
| 1.5-~4 | 3 ride | a jolt, the shaft rushes past the windows (rock rings painted with each floor's palette, crystals, beams, lamps whose light sweeps over the doors, a glowing landing band at every floor passed), dust, glowing motes, light streaks, a rumble, two short light flickers, the seven-segment counter counts to the target (a click per floor); the server moves the character at 1.6 s |
| ~4-5.95 | 4 arrival | the brakes grind, the cabin stops with a bump, one flash, **ARRIVED!** + the mine's name and floor; the cabin now stands at the target stop; the doors open on the real floor with its own effects; the camera pulls back behind the player while the cabin fades into the real cage; controls back |

Every mine (by `MineFloors` floor Id):

| Floor | Arrival |
|---|---|
| 1 Greystone Quarry | brown dust rolls in, small rocks tumble down and bounce, warm light; far rumble |
| 2 Ember Caves | glowing embers rise, a burst of sparks, red light; crackle |
| 3 Deep Hollow | blue crystal shards grow out of the ground and glint, cool motes, blue light; tinkle |
| 4 Sunken Palace | golden glitter falls, a gold ring runs over the ground, golden light; chime |
| 5 Stormglass Rift | violet energy motes, electric sparks, three short arcs (never with Reduce motion), violet light; zap |
| 6 Heartstone Core | magenta motes rise round a glowing core that beats with a pulsing light; deep hum |

## Where everything is (Rojo builds it; nothing to set up in Explorer)

| File | Roblox | Role |
|---|---|---|
| `src/shared/Config/ElevatorTravelConfig.luau` | ReplicatedStorage.Shared.Config | the shared timeline (`plan`, `hold`), shake amounts, the six arrival themes |
| `src/shared/Builders/ElevatorCabinStage.luau` | ReplicatedStorage.Shared.Builders | the cabin + shaft set from parts (~220 parts, 6 lights, 9 pooled emitters), `pose`, `camera` (pure) |
| `src/shared/Builders/ElevatorArrivalFx.luau` | ReplicatedStorage.Shared.Builders | the arrival effects (pooled: 1 light, 3 emitters, ~22 parts), `pose` (pure), `burst`/`rates` |
| `src/client/UI/ElevatorTravelView.luau` | StarterPlayerScripts.Client.UI | the words: PREPARING ELEVATOR..., dip, cinema bars, ARRIVED! |
| `src/client/Controllers/ElevatorTravelController.luau` | StarterPlayerScripts.Client.Controllers (ORDER before ElevatorController) | drives the cinematic, takes and gives back the camera, controls, HUD, prompts |
| `src/client/Controllers/ElevatorController.luau` | (existing) | its ride half hands "Depart"/"Arrive"/"Cancel" over; closes the floor window at phase "Enter" |
| `src/server/Services/ElevatorService.luau` | (existing) | validates and moves; holds a rider for the whole cinematic; Cancel on leave/death/respawn |
| `src/server/Services/TeleportService.luau` | (existing) | refuses BASE/LOBBY/VAULT/LIFT while riding (reason `Riding`) |
| `src/shared/Net.luau` | (existing) | the `ElevatorRide` remote, documented (no new remote) |
| `src/shared/Config/SoundConfig.luau`, `LightingConfig.luau` | (existing) | new sound keys; the `ElevatorRide` lighting preset |

The owner's suggested names map to the project's: `ElevatorTravelEvent` = the existing
`Net` remote `ElevatorRide` (server -> client) + `ElevatorAction` (client -> server, rate
limited 3/s), `ElevatorTravelServer` = `ElevatorService`, `ElevatorTravelClient` =
`ElevatorTravelController`.

## Server rules (unchanged where they worked)

- `ElevatorAction { Action = "Go", Floor }`: a whole floor 1..#MineFloors.List, the elevator
  owned (main: bought once; ui/elevator-v2-server: the floor's ticket bought), blaster level >=
  the floor's `MinBlaster`, a living character, not cleaning, at a stop (16 studs), not its own
  floor, not riding. Riding to a floor never spends coins (only Buy does, once).
- `isRiding` covers the whole cinematic (`ElevatorTravelConfig.hold`, 0.35 s less than the
  client's end), so a second GO, a teleport, a rebirth or a hoverboard waits; a late move pushes
  the end back.
- `Depart { Floor, From, Name, Duration, DoorsClose = 1.6, FromAt, StopAt, Target }`; the
  character moves at 1.6 s behind the shut doors after the target area streams in; a rider who
  left, died or respawned meanwhile is never moved: `Cancel` (and the cancelled ride counts for
  nothing).

## Client: every way out gives the game back

The end, `Cancel`, a respawn, no `Arrive` within 6 s of the brake (fail-safe), a failed move,
a second `Depart`, an error inside a frame: camera `Custom` with the player's field of view,
controls (PlayerControls lock "ElevatorTravel"), prompts, grab, the blaster, the HUD's
`TerraForge*` guis (only those it put away), touch controls, the character's
`LocalTransparencyModifier`, the real cages (their lights back on), the lighting push. Each
restore step runs on its own (one failing never skips the others).

Reduce motion (`UI/Motion.reduced`): no shake, jolt, flicker or light streaks, no flash (a soft
swell), no electric arcs, fewer particles, fades instead of the camera's glide out.

## Sounds

Only ids that play today (Roblox-made uploads and shipped files, memory note roblox-sound-ids):
ElevatorStart `button.wav` 12221967 low, ElevatorWarn `electronicpingshort.wav` 12221990,
ElevatorDoorClose/Open `swoosh.wav` 12222200 low, ElevatorHum `action_falling.ogg` (looped, pitch
follows the speed), ElevatorTick `Roblox_UI_Bright_Click` 15675059323, ElevatorBrake
`unsheath.wav` 12222225 slowed, DoorThud / ElevatorDing / ElevatorArrive (existing), and one per
mine (`ElevatorArrive<Mine>`). Better sounds the owner may upload later and paste into
SoundConfig: a mechanical elevator start, sliding metal doors, a shaft wind/rumble loop, a brake
screech, an elevator ding.

## Tests

`tests/ElevatorTravel.spec.luau` (timeline 4-6 s on every pair of floors, phases in order, the
counter, flashes < 3/s, every mine's look and sound; server: one ride at a time, locked floors,
no coins for rides, Depart's stops and target, respawn/death/leave behind the doors),
`tests/ElevatorCabinStage.spec.luau` (budget, no collisions/raycasts, doors, the shaft never in
the cabin, the counter, Reduce motion, the camera, the arrival effects, the words),
`tests/ElevatorTravelController.spec.luau` (on fakes: every way out gives everything back),
`tests/Teleport.spec.luau` (no teleport while riding).

## What to test in Studio

1. Play, walk to the floor-1 elevator, E, pick an unlocked floor: preparation (pill, beacon,
   lamp, shake, sounds), the dip into the cabin, the doors close, the ride, the counter, the
   stop, ARRIVED!, the doors open on the right floor, the camera returns, you can walk.
2. Ride to every floor (a test place with everything unlocked): each mine's arrival look.
3. Tap a floor again during the ride: nothing happens; BASE/LOBBY/VAULT during the ride:
   "Wait until the elevator arrives."
4. Reset the character (Esc > Reset) in the preparation and in the ride: the camera, the HUD
   and the controls come back; you never land on the target floor.
5. Phone (device emulator) and gamepad: the words fit, nothing is selected under the cabin,
   the touch controls come back.
6. Settings > Reduce motion on: no shake, flash or flicker; the ride still plays.
7. Look at the cage after arriving: the real cage is back (no missing bars), the lamp lights.
8. MicroProfiler on a phone emulator during the ride: frame time stays low (the set moves
   with BulkMoveTo; ~220 parts, 6 lights, 9 emitters).

## Known limits / follow-ups

- The old 2D ride (`UI/ElevatorRideView.luau`) is no longer used by the game; it stays for
  `tools/lune/lib/elevator_preview.luau`'s pictures (owned by the UI chat now). Delete both
  together after ui/elevator-v2 lands.
- Merging with ui/elevator-v2: two one-liners in `ElevatorController.init` (the OpenUI guard
  uses `ElevatorTravelController.isTraveling()`, CharacterRemoving no longer calls `endRide`),
  agreed with the UI chat; its window guards TRAVEL/PURCHASE with `isTraveling()`.
- The preview video is a three.js approximation (no real particles: sprinkles; one lighting
  preset per part of the reel).
