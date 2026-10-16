# Kenney Factory Kit – what it is and how Terra Forge uses it

- **Page:** https://kenney.nl/assets/factory-kit (download button there; the owner downloaded version 3.0)
- **All Kenney assets / bundle:** https://kenney.nl/assets · donate (optional): https://kenney.nl/donate
- **License:** Creative Commons Zero (CC0 1.0) – http://creativecommons.org/publicdomain/zero/1.0/
  Free for personal, educational **and commercial** use, no permission needed. Crediting "Kenney" / www.kenney.nl is
  optional (we credit it in docs/art/README.md and can add it to the game's credits/description).
- **What's inside (v3.0, 140+ models):** `Models/GLB format`, `Models/FBX format`, `Models/OBJ format` (+ `colormap.png`
  texture), `Previews/*.png`. Models: machines (machine, machine-fortified, machine-window, machine-connection-pipe/-hole,
  machine-bed), hoppers (round/square, high/low), large pipes (straight, long, bend, curve, junction, cross, valve, bump,
  glass versions), conveyors (straight, sides, stripes, bars/rollers, corners, junctions, slopes, long parts), cogs,
  pistons (used as fuel tanks), scanners (arches), robot arms, cranes (+magnet), catwalks and stairs, structures
  (posts, walls, doorways, yellow frames), boxes, screens, levers, warning lights, doors, floors.
- **Reference renders in this repo:** docs/art/kenney_machines.jpg, docs/art/kenney_pipes_conveyors.jpg,
  docs/art/kenney_structures_props.jpg (rendered from the GLB files with tools/preview/kenney_sheet/).
  The original zip is kept outside git (handoff folder `assets/kenney_factory-kit_3.0.zip`).

## How we use it
**As the style reference for every machine and industrial prop**, rebuilt from Roblox parts (blocks, wedges,
cylinders) in Terra Forge's forge palette (iron, copper, brass, glowing molten accents), not the kit's blue/purple.
Reason: Roblox cannot load mesh files from code or Rojo. Every mesh would first have to be uploaded through Roblox
Studio under the owner's account, so a part-based rebuild works immediately, stays light on phones and is fully ours.

Style rules taken from the kit (details: docs/ART_DIRECTION.md, section "Machines"):
chunky bevelled housings with a darker base band, octagonal pipe flanges with bolts, funnel hoppers on top as the
intake, roller conveyors with side rails and orange hazard stripes, big gears on the sides, glass pipe sections that
show glowing molten metal, valves with hand wheels, round fuel tanks, stacked warning lights.

| Terra Forge machine | Kenney models to imitate |
|---|---|
| Cleaning Station | machine-bed (work bench), lever-double, screen-panel-small |
| Clay Furnace | machine-fortified + hopper-round on top + pipe-large chimney, orange base trim |
| Blast Furnace | machine-connection-pipe, pipe-large-bend / -valve, pipe-glass-large (molten metal), piston-round as fuel tank |
| Crusher | hopper-high-square on top, machine-window, cog-a/cog-c on the sides, piston-square |
| Auto Cleaner | scanner-high arch over conveyor-bars-stripe-high, robot-arm-a brushes |
| Anvil | (no direct match) chunky anvil on a machine-bed-style base, lever-double |
| Storage Crate | box-large inside a structure-yellow-high frame |
| Sell Chute | hopper-high-round over pipe-large-bend into the ground, screen-small coin sign |
| Conveyor (1x1) | conveyor-stripe-sides / conveyor-bars-stripe (rollers), conveyor-corner |
| Decor (plots, lobby, Forge works) | crane, crane-magnet, catwalk-straight/stairs, pipe-large network, piston-round tanks, warning-traffic, screens |

Constraints when rebuilding: keep every attachment, tag and attribute that src/shared/Builders/MachineBuilder.luau
currently creates (Intake + IntakeSize, Output, Prompt, Status, OrePoint/CamPoint on the Cleaning Station,
AnvilPoint/CamPoint/IngotSlot1..4 on the Anvil, conveyor parts Base/Belt (tag ConveyorBelt)/RailL/RailR/Arrow),
keep footprints (MachineData Size), and stay within a part budget (about 40-70 parts per machine, 6 per conveyor).

## Optional later: real meshes
If the owner wants the exact Kenney shapes: in Roblox Studio use **3D Importer** (Home → Import 3D) to import the
chosen .glb/.fbx files (they upload under the owner's account), put the results in a folder such as
ReplicatedStorage/Assets/FactoryKit, save them to the repo as an .rbxm, and let the builders use a mesh when it exists
and fall back to the part version otherwise. Not needed for launch.
