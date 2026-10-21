# Machine looks

## Soft (style A) - in the game now, SAVED
The owner's pick of 2026-10-17 ("cute and cool"): cream soft boxes, slate plinths, glowing orange strips, round
chimneys and bowls. Code: `src/shared/Builders/KitMachines.luau`. Saved before any new style was tried:
- git tag `machines-soft-2026-10-20` (pushed): `git show machines-soft-2026-10-20:src/shared/Builders/KitMachines.luau`
  gives the file exactly as it was;
- pictures of all 25 buildable machines: `docs/screenshots/machines/all_machines_sheet.jpg`
  (scene `kit_showroom`, shots `tools/preview/kit_showroom_shots.json`).

**Decision (owner, 2026-10-21): the Soft look stays** ("the white machines, I love them, we keep that").

## Forge Works - CONCEPT, PARKED (owner 2026-10-20: "try more of a Satisfactory x Hydroneer style")
Not built further and not landed; kept on branch `art/works-machines` for reference only.
Code: `src/shared/Builders/WorksMachines.luau` (nothing in the game uses it yet). Preview: scene `works_gallery`
(`tools/lune/lib/works_gallery.luau`, shots `tools/preview/works_shots.json`): the new look in front, the Soft look
behind. Pictures: `docs/screenshots/works_concept/`.
- From Satisfactory (feel only): light steel housings with chamfered roofs, orange riveted side panels, hazard
  stripes, belt ports with a light strip, glowing firebox / slit windows, control panels, banded smoke stacks,
  ladders and roof rails, stack lamps.
- From Hydroneer (feel only): timber frames round a concrete deck, wooden plank hoppers with iron corners,
  crates, a wooden windmill tower and pole, copper pipes and tanks with brass flanges and gauges, big brass cogs,
  a water tank with a hose and a spray wand.
- So far: Cleaning Station, Clay Furnace, Crusher, Blast Furnace, Conveyor, Wind Turbine, Power Pole (6-60 parts).
- If the owner picks it: the other 18 machines, the game contracts (attachments, the crystal upgrade looks by the
  Kit role attribute, sockets), then a switch in MachineBuilder; the Soft look stays in KitMachines.
