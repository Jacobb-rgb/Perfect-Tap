export const meta = {
  name: 'design-step-d-machines',
  description: 'Design Terra Forge step d (machine chain, conveyors, build mode): 3 independent plans, judged and merged into one implementation plan',
  phases: [
    { title: 'Plan', detail: '3 game-designer plans from different angles' },
    { title: 'Judge', detail: 'score the plans and merge the best into one buildable plan' },
  ],
}

const CONTEXT = `
Project: TERRA FORGE, a Roblox mining/crafting game in Luau (Rojo) at /home/user/Perfect-Tap. Read docs/PLAN.md and docs/GAME_DESIGN.md first.
Inspirations: The Forge (stylized low-poly, forge warmth), Hydroneer (physical ore chunks you carry/throw, placeable machines, conveyors),
Fishing Chef (tactile cleaning minigame, already built in step c).
Mapping: src/shared -> ReplicatedStorage.Shared, src/server -> ServerScriptService.Server, src/client -> StarterPlayerScripts.Client.
Server services: init()/start() lifecycle, ORDER list in src/server/init.server.luau. Client controllers likewise in src/client/init.client.luau.
Remotes: src/shared/Net.luau (Events table with token-bucket rate limits; Net.on / Net.fire / Net.fireAll / Net.fireNear; false = server->client).
Already built and relevant to step d (READ these before planning):
  src/shared/Config/MachineData.luau (machines, StarterKit, slots, Bellows, footprint(), processTime()), GameConfig.luau (MachineIntakeQueue=4,
  ConveyorSpeed=7, StorageCrateCapacity=60, MaxStoredItems=300, MaxLooseItemsPerPlayer=30...), ItemData.luau (kinds Raw/Clean/Crushed/Ingot/Gear,
  grades, Recipes, value()), WorldLayout.luau (Plots, CellSize, PlotCells, plotCFrame)
  src/shared/Builders/MachineBuilder.luau (models + attachments Intake(IntakeSize attr)/Output/Prompt/OrePoint/CamPoint), ItemBuilder.luau
  src/server/Services/ItemService.luau (spawn/release/mount/stash/destroy/fromPart/ownedBy, item States Loose/Carried/Machine, LastNearOwner,
  collision groups, loose cap with overflow to data.Storage), CarryService.luau, PlotService.luau (assign, footprintCFrame, cellAt),
  MachineService.luau (register(id,{spawned,removed}), spawn, remove, point, ofPlayer, all; saved as data.PlacedMachines {Id,X,Z,R}),
  CleaningService.luau (a complete machine behaviour example: prompts, intake polling, sessions), DataService.luau + Data/DataTemplate.luau,
  src/server/Perks.luau (Perk_Workshop gives extra slots), src/client/Controllers/InteractController.luau (grab E / throw Q, gamepad X/RB, touch buttons).
Requirements for STEP D (from the brief):
  - Machine processing chain: Clay Furnace / Blast Furnace (Clean or Crushed -> Ingot), Crusher (Clean -> 2 Crushed), Auto Cleaner (Raw -> Clean, grade
    capped at MachineData MaxGrade = "Clean"), Anvil (Ingot -> Gear via ItemData.Recipes, with a short tactile hammering interaction), Storage Crate
    (store/take, count shown on a sign, capacity 60, persists in data), Sell Chute (sells what drops in, pays the item's owner), hub selling at the
    town's SellBin/SellCounter (check src/server/World/Town.luau for what exists).
  - Items enter machines physically (dropped/thrown into the intake box or delivered by conveyor), queue (MachineIntakeQueue), process on a timer
    (Bellows speed upgrade), pop out at the Output attachment; juice: glow, smoke, sounds, spinning parts.
  - Conveyors: 1x1 pieces moving loose items (AssemblyLinearVelocity on the belt or equivalent), work with network ownership and the item physics rules.
  - Build mode with a placement grid on your own plot: client ghost preview, rotate, place, pick up/move, validation on the server (bounds, overlap,
    ownership, machine slots vs conveyor slots, perks), PC + mobile + controller controls.
  - Server-authoritative, rate-limited remotes, no item duplication/loss, DataStore-safe (PlacedMachines, Storage), mobile performance
    (StreamingEnabled is on; keep part counts and per-frame work low), Roblox rules compliant, everything original.
  - Buying machines/upgrades is step e (economy/shop); for step d assume machines come from the StarterKit + a temporary way to get more is NOT needed,
    but the build mode must already handle an "inventory" of owned-but-unplaced machines (data.MachineInventory or similar) so the shop can plug in.
`

const ANGLES = [
  { key: 'player-first', angle: 'PLAYER-FIRST: optimize for how good it feels to a 10-14 year old on a phone: clarity, juice, forgiving controls, the satisfying loop of ore -> clean -> smelt -> sell in the first 3 minutes.' },
  { key: 'robustness-first', angle: 'ROBUSTNESS-FIRST: optimize for zero item duplication/loss, exploit resistance, DataStore safety, server cost and clean failure handling (player leaves mid-process, machine picked up while busy, items stuck on conveyors, plot full).' },
  { key: 'build-first', angle: 'SHIP-FIRST ARCHITECTURE: optimize for a simple, modular implementation that several agents can build in parallel with minimal file conflicts, with pure shared logic that can be unit-tested under Lune (placement validation, queues, recipes), and that step e/f can extend.' },
]

const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    modules: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          status: { type: 'string', enum: ['new', 'modify'] },
          responsibility: { type: 'string' },
          api: { type: 'string', description: 'public functions/types with signatures' },
          details: { type: 'string', description: 'key behaviour, edge cases, numbers' },
        },
        required: ['path', 'status', 'responsibility', 'details'],
      },
    },
    remotes: { type: 'array', items: { type: 'string' }, description: 'Net events to add: name, direction, payload, rate limit' },
    dataChanges: { type: 'string' },
    risks: { type: 'array', items: { type: 'string' } },
    tests: { type: 'array', items: { type: 'string' } },
    workPackages: { type: 'array', items: { type: 'string' }, description: 'parallelizable packages with file ownership' },
  },
  required: ['summary', 'modules', 'remotes', 'dataChanges', 'risks', 'tests', 'workPackages'],
}

const plans = await parallel(ANGLES.map((a) => () => agent(`${CONTEXT}\n\nYour angle: ${a.angle}\n\nRead the code listed above, then produce a concrete, buildable implementation plan for step d. Be specific: module paths, function signatures, numbers (timings, sizes, limits), the exact data shape changes and migrations, every new remote with payload and rate limit, and how each edge case is handled. Do NOT write or edit any files.`, {
  label: `plan:${a.key}`,
  phase: 'Plan',
  agentType: 'game-designer',
  schema: PLAN_SCHEMA,
})))

const valid = plans.map((p, i) => p && { key: ANGLES[i].key, plan: p }).filter(Boolean)
log(`${valid.length} plans ready`)

const merged = await agent(`${CONTEXT}\n\nThree independent plans for step d follow (JSON). Act as the lead designer/architect: read the relevant code to check each plan's claims against the actual APIs, score each plan 1-10 on (a) correctness against the existing code, (b) exploit/dup safety, (c) player feel on mobile, (d) implementability in parallel. Then write ONE merged final plan that takes the best plan as the base and grafts in the strongest ideas of the others. The final plan must be precise enough that 4-5 implementers can work in parallel without stepping on each other's files: give each work package an explicit list of files it OWNS (only that package edits them) and the shared interfaces it must honour (exact function signatures, attribute names, Net event names and payloads, data fields). Put shared contract files (Net events, configs, data template, shared pure modules) in a FIRST package that must be done before the others. Do NOT write or edit any files.\n\nPLANS:\n${JSON.stringify(valid, null, 1)}`, {
  label: 'judge+merge',
  phase: 'Judge',
  agentType: 'game-designer',
  schema: {
    type: 'object',
    properties: {
      scores: { type: 'array', items: { type: 'object', properties: { key: { type: 'string' }, score: { type: 'number' }, notes: { type: 'string' } }, required: ['key', 'score', 'notes'] } },
      finalPlan: PLAN_SCHEMA,
      contracts: { type: 'string', description: 'exact shared interfaces: Net events+payloads+rate limits, data template fields, attributes, module APIs' },
      packages: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            order: { type: 'number', description: '0 = contracts first, 1 = parallel after' },
            ownsFiles: { type: 'array', items: { type: 'string' } },
            instructions: { type: 'string' },
          },
          required: ['name', 'order', 'ownsFiles', 'instructions'],
        },
      },
    },
    required: ['scores', 'finalPlan', 'contracts', 'packages'],
  },
})
return merged
