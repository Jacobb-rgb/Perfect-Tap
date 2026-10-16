---
name: kenney-style-builder
description: Build Terra Forge machines, trains, blasters, golem pets and decorations in the style of the Kenney kits (Factory, Train, Blaster, Mini Dungeon, Mini Characters) out of Roblox parts. Use when creating or restyling any model built in code (MachineBuilder, train, blaster, pet, decor builders).
---
# Kenney-style builds from parts

The owner wants the look of Kenney's kits (all CC0): Factory Kit (machines, pipes, fuel tanks, hoppers, conveyors),
Train Kit (per-player ore trains), Blaster Kit (laser blasters instead of pickaxes), Mini Dungeon (decor style),
Mini Characters (golem pets: silver/gold/ore golems, some with helmets). Links and mapping: docs/KENNEY_FACTORY_KIT.md,
docs/DESIGN_V2_NOTES.md. Reference renders: docs/art/kenney_*.jpg (render more with tools/preview/kenney_sheet/).

## Never import the meshes
Roblox can't load mesh files from code; they would need uploading under the owner's account. Rebuild the shapes from
blocks, wedges, corner wedges, cylinders and balls with src/shared/Builders/Geo.luau, in the Terra Forge palette
(iron, copper, brass, molten glow; docs/ART_DIRECTION.md section 9), not Kenney's blue/purple.

## Shape rules taken from the kits
- Chunky, slightly oversized proportions; bevels = thin wedges/corner wedges on the main edges.
- A darker **base band** and an orange/hazard **trim strip** at the bottom of housings.
- Pipes: cylinders with **octagon-looking flanges** (2 short cylinders slightly wider) and 2–4 bolt balls.
- Hoppers: funnel from 4 wedges on top = the intake. Fuel tanks: round cylinders with bands and a gauge.
- Conveyors: rollers (cylinders) between side rails, arrow decals from 2 wedges, hazard stripes.
- Trains: chunky locomotive with big round lights, cow-catcher, ore wagons whose load shows the ore colors.
- Blasters: toy-like chunky body, glowing core, barrel rings; tiers add coils/fins; colors follow the ore (ore-design).
- Golems (Mini Characters proportions): big head, short body, stubby limbs, ore-colored, helmets/visors as variants.

## Keep the contracts
Machines must keep every attachment/tag/attribute MachineBuilder creates today (Intake+IntakeSize, Output, Prompt,
Status, OrePoint/CamPoint, AnvilPoint/IngotSlot1..4, conveyor Base/Belt(tag ConveyorBelt)/RailL/RailR/Arrow) and their
MachineData footprints. Run `bash tools/check.sh` after every change.

## Budgets (mobile)
Machine 40–70 parts, conveyor ≤ 6, locomotive ≤ 60, wagon ≤ 20, held blaster ≤ 25, pet ≤ 20, decor prop ≤ 15.
CastShadow off on small parts, Neon only for glows, CanCollide only where players bump.

## Finish with pictures
Render each new model (preview-pictures skill), compare with the Kenney reference sheet, fix, send to the owner.
