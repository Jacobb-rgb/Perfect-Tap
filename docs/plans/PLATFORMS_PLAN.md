# Platforms, Belt Lift and Slide (owner's YES, 2026-10-20)

A second building level on the plot: 2×2 platforms on legs, 5 studs up (the Belt Lift's rise), in the machines' style A.
Belts and machines stand on the decks; a Belt Lift carries items up from the ground, a Slide brings them down. The
preview the owner approved: branch `art/platforms-preview` (`tools/lune/lib/platforms_preview.luau`,
`docs/screenshots/platforms_preview/*`).

## What already works without changes
- Belts are physical: an anchored `Belt` part with `AssemblyLinearVelocity = LookVector * speed`. A belt on a deck
  carries items at its height; a tilted Belt part carries them up (Lift) or down (Slide).
- Machine intakes, belt ends, sinks and emits are position based (IntakeService zones, MachineService output points),
  so a machine on a deck takes and gives items at its own height.

## Data and rules (shared `Placement`, server `MachineService` / `BuildService`, client build mode)
- `Entry.L` (level): nil or 0 = ground, 1 = deck. Saved; `Placement.sanitize` / Migrations drop junk levels.
- New machine **Platform** (MachineData, Category "Logistics", 2×2, `Behaviour = "Platform"`, NoIntake, a price in
  the early game). Its footprint at L0 is its legs: other ground machines may not overlap it, **flat belts may**
  (Conveyor, Express Conveyor: the space under the deck). Its 4 cells are **deck cells** at L1.
- A machine or belt at L1 needs every footprint cell on a deck cell (one or more platforms side by side) and no
  overlap with another L1 entry. Occupancy is keyed by (cell, level).
- **Belt Lift** (1×3, L0): its 3 cells are ground cells outside every deck; the cell in front of its high end is a
  deck cell (the items arrive on the deck belt there). **Slide** (1×3, L0): the cell behind its high end is a deck
  cell. Both are belts for the slot count (`IsConveyor`) and get a tilted Belt part (KitMachines.slope).
- Picking up a platform is refused while anything stands on its deck (`DeckInUse`); moving a platform moves nothing
  on it (refused while the deck is used).
- `MachineService.atCell(plotId, gx, gz, level?)`: neighbours of the Robot Arm, Splitter, Sorter and the emit
  front cell use the machine's own level; the Lift's front is L1, the Slide's back is L1.
- Power: poles keep working by distance (a deck machine is powered from a ground pole in range).
- Slots: a platform counts as a machine slot (not a belt).

## Client (build mode, all platforms)
- The ghost goes onto the deck when the hovered cell is a deck cell and the machine may stand there; a toggle
  (keyboard `V`, gamepad `DPadUp`, a touch button "Deck / Ground") puts a flat belt under the deck instead.
- The ghost shows its level (raised by `Platform.Level`), red where the rule fails, with the Placement reason.
- Grid overlay: deck cells drawn at deck height while a deck-capable machine is held.

## Visuals and budgets
- Platform: the preview model (17 parts: deck plate, glow edge, 4 legs, cross braces, a ladder), style A, small
  parts without shadows. Belt Lift / Slide: KitMachines.slope.
- A full plot of platforms (12×12 cells = 36 platforms) stays inside the plot budget test.

## Tests
- Placement: deck cells, L1 overlap, belts under a deck, other machines refused under a deck, Lift / Slide edge
  rules, platform pickup / move refused while the deck is used, sanitize of levels.
- MachineService: atCell by level, a deck Robot Arm / Splitter only sees its level, emit onto a deck belt.
- Physics-free item flow check: a Lift's Belt part velocity points up its slope, a Slide's down.
- Saves: an old save without `L` loads unchanged; a deck entry whose platform is gone is moved off (inventory).

## Phases (each its own piece, check.sh + ping)
1. Data + rules + server (Placement, MachineData Platform / BeltLift / Slide, MachineService levels, BuildService,
   sanitize, tests).
2. Client build mode (ghost level, toggle, overlay, touch / gamepad) + pictures.
3. Polish: Tech shop cards, tutorial hint, budgets, pictures for the owner.

## Built (phases 1 and 2, 2026-10-20)
- Data: MachineData `Platform` (2x2, Logistics, Behaviour "Platform", NoIntake, 2,500, a machine slot), `BeltLift` /
  `Slide` (1x3, IsConveyor + SlotFree like the Express Conveyor, 150, `Slope = "Up" / "Down"`), `DeckHeight = 5`,
  `MaxLevel = 1`; Tech shop icons for the three (their cards come from Buildable as before).
- Rules (`Placement`): `Entry.L`, `Placement.key(x, z, level)`, `occupancy` by cell and level (a belt under a deck
  keeps its ground cell), `decks`, `validate(..., level)` with `NoDeck` / `UnderDeck` / `DeckEdge` / `DeckInUse`,
  `deckInUse` / `canPickup` (a Lift / Slide reaching a deck uses it too), commits with a level (L saved only on a
  deck), `sanitize` in two passes (the ground first, then Lift / Slide edges and deck entries). Lifts and Slides are
  no chute belts (only flat belts on chute cells). `ConveyorLogic` works by level (`frontOf`: a Lift delivers onto
  the deck): feeders, side rails (a Lift opens the deck belt's side) and head-on.
- Server: `MachineService` indexes cells by level (`atCell(plot, x, z, level?)`, `deckAt`, `atHeight` for items),
  spawns deck entries `DeckHeight` up (attribute `GridL`), emits / side outputs / the Robot Arm work on the
  machine's own level, a used platform isn't packed up. `BuildService`: `BuildPlace` / `BuildMove` take an optional
  level (nil / 0 ground, 1 deck, anything else `BadInput`); replies and the State snapshot carry `L`; only what is
  up at deck level is lifted for a deck machine, a platform lifts players but never the items on the belts under it.
  `ConveyorService`: the slopes are belts (tilted Belt part, velocity along its LookVector), jam nudges go along the
  slope, the queue check looks around the item's cell and at its height. `IntakeService`: the belt under an item is
  the one at its height; a Lift's feeder box sits at its top end, up at the deck. `PlotService.footprintCFrame` and
  `Grid.localCFrame` take a level. Migrations: `L` is a whole number >= 1 or nil (saves without L are unchanged).
- Models: `KitMachines.platform()` (the preview's look in 17 parts: slim legs in the footprint's corners, so a belt
  under the deck keeps its whole surface, low feet, cream slab, metal top "Deck" at exactly DeckHeight, glow strips,
  two braces under the slab; no rails), `KitMachines.slope(up, length, rise, fit)` for the game (29 parts inside its
  1x3 cells: the control box hangs under the high end's brace; a grippy tagged Belt; the pivot where a flat belt's is,
  so both ends meet the belts' surfaces).
- Client (`PlacementController`, `BuildView`): the ghost goes onto the deck when the cell under the cursor is a deck
  cell and the machine may stand there, and the cursor reads the deck's height there; the Deck / Ground toggle (V,
  gamepad D-pad Up while building, the touch button "DECK" / "GROUND" while the plot has decks) puts a flat belt
  under the deck and makes picking prefer what is under it; a belt line keeps the level it starts on; deck cells get
  plates at deck height while a machine is held; a Lift / Slide shows the deck cell its top end must reach; a
  refused spot is red with the Placement reason; packing up a used platform is refused before the server is asked.
- Tests: tests/Platforms.spec.luau (rules, sanitize, saves without L, Migrations, ConveyorLogic by level, models, 36
  platforms on a full plot, runtime index / spawn / emit / slope velocity / jam nudge / the Lift's feeder), plus deck
  cases in Placement, BuildService and Logistics (a deck Robot Arm and Splitter see only their level).
- Pictures: docs/screenshots/platforms/ingame_*.jpg (scenes `platforms_game` / `platforms_build`,
  tools/lune/lib/platforms_scene.luau, shots tools/preview/platforms_shots.json; the layout goes through
  Placement.validate).
- Left for phase 3: Tech shop card polish (order / section of the three), a tutorial hint, a ladder or steps (players
  can jump the 5 studs), power cables drawn up to deck machines (they are powered by distance already), a Studio check
  of items riding up the Lift (friction 1.2 on a 26.6 degree slope) and across its 1-stud end gaps.
