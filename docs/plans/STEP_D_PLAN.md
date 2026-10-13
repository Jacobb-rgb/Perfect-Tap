# Step d plan: machines, conveyors, build mode

Merged from three independent plans (player-first, robustness-first, build-first) by a judge agent.

## Summary

STEP D FINAL PLAN. The base is the build-first plan, which has the best parallel structure and intake geometry. Grafted in from robustness-first: machine contents are saved in the placed entry, the init-order fix, direct machine-to-machine handoff with back-pressure, the conservation fuzz test, EconomyService, and Seq on build remotes. Grafted in from player-first: outputs centred on a cell, the plot border fix, the overview build camera with tap-then-Place and belts that auto-advance, Put In prompts, wrong-item hints, sell juice, and a client-physics range.

WHAT EXISTS NOW (checked in code)
- Machines: MachineService spawns the saved data.PlacedMachines {Id,X,Z,R} plus the StarterKit (Storage Crate 1,7; Cleaning Station 4,4; Clay Furnace 8,4). It cannot place, move or pick up machines. CleaningService is the only machine behaviour; it runs its own 0.3 s GetPartBoundsInBox vise scan.
- Items: ItemService has the states Loose/Carried/Machine and a loose cap of 30. Overflow goes to data.Storage, and items are sold once Storage is past 300. Every drop gives physics to the owner's client for 3 s.
- Remotes and data: Net declares BuildPlace, BuildPickup and MachineAction, but nothing handles them. DataTemplate already has MachineInventory, PlacedMachines, Storage and Stats.IngotsSmelted/GearForged/ItemsSold. StateService already sends MachineInventory and a 'K|O|G|R' Storage summary.
- Town: Pell's SellBin (an invisible 8x5x6 'Intake' part) and SellCounter are tagged but nothing sells. Today there is no way to turn ore into coins.

CODE PROBLEMS FOUND WHILE CHECKING THE PLANS
1. Outputs are in the wrong place. 2-wide machines push output onto the seam between two cells (x=0). The Anvil Output is inside its own footprint (z=-3.6). The Auto Cleaner Output is exactly on the edge (z=-4).
2. Intake boxes don't reach where a belt presses an item against a machine. Belts must hand items over logically.
3. Plot rails, corner posts and the banner pole sit inside the 12x12 grid; the pole is in cell 11,11.
4. A conveyor is 10 parts.
5. Init-order race. MachineService hooks PlotService.onAssigned in init(), so with in-memory saves the starter machines can spawn before CleaningService registers its prompts.
6. Machine outputs handed to a far-away owner's client freeze when that part isn't streamed in.

ORDER (each step is playable; P0 and P1 run in parallel, then the five feature packages run in parallel; d2 to d6 is the merge and test order)
- d1 Contracts and core (P0 + P1). Test: the game plays as before; old saves load; the plot border looks clean; the Cleaning Station still works; in a Studio in-memory session the dev layout machines appear (they do nothing yet); `lune run tools/lune/test.luau` passes.
- d2 Storage and selling. Test: mine, clean, throw the ore into Pell's SELL bin or use 'Sell What You Carry' and see '+N' and coins. Drop items in the crate and the sign shows 3/60. Open Crate, then Take, and the item goes into your hands. A Sell Chute pays the item's owner.
- d3 Processing. Test: throw or 'Smelt Ore' clean ore into the Clay Furnace. You see glow, a hum and a 6 s bar, and an ingot pops out the front cell. Raw ore bounces out with a hint. A 5th item waits in the hopper. Leave and rejoin mid-smelt and the queue resumes. The dev-layout Crusher, Auto Cleaner and Blast Furnace work.
- d4 Build mode. Test: B, D-pad Up or the BUILD button. Move, rotate, pack up and re-place machines on PC, phone and gamepad. The ghost turns red with a reason. Belts auto-advance. Rejoin and the layout is the same.
- d5 Conveyors. Test: Auto Cleaner -> belt -> Crusher -> Furnace -> belt -> Sell Chute runs while you walk away. Corners don't snag. A belt into a furnace's front does nothing. Machines facing each other hand items over directly.
- d6 Anvil. Test: put 2 Iron ingots on the anvil, Forge, pick Tool Head, tap 4 times, and the gear lands in your hands.
- d7 Docs, QA, rebake and mobile performance pass.

NEEDS YOUR APPROVAL BEFORE CODING
BIG REFACTOR:
- (A) MachineService gets a link from each machine to its saved entry, saved In/Out contents, place/move/pickup, a tick and emit loop, and spawning moved to start().
Moderate:
- (B) ItemService additions, plus physics goes to the owner's client only within 80 studs.
- (C) Save Version 2 with an idempotent Migrations module. PlacedMachines entries gain optional In/Out.
- (D) The plot pad grows by a 1-stud border, and rails, posts and pole move out of the grid. WorldBuilder.Version 3 rebuilds the map and the place must be rebaked.
Design and balance:
- (E) All crates share one storage pool: 60 per placed crate, 300 maximum.
- (F) New intake rule: drop or throw into the hopper on top, or run a belt into any side except the output front (crates and Sell Chutes accept every side). A machine hands its output straight to the machine in its front cell.
- (G) Auto Cleaner gives 60% Rough / 40% Clean.
- (H) Every anvil tap counts; timing only changes the PERFECT/GOOD effect.
- (I) Players walk through belts.
- (J) 2-wide machines push output from their right front cell.
- (K) A Studio-only dev kit, active only with in-memory saves.
No monetization change. Flag for step e: the first sale is about 10 coins against a 200-coin pickaxe.

## Contracts (shared interfaces)

SHARED CONTRACTS FOR STEP D. Every package must honour these exactly. Only P0 edits config, Net and data files; only P1 edits core services and the ORDER lists.

1) NET (src/shared/Net.luau, Events table; rate = {Rate, Burst} per player)

Client -> server:
- BuildPlace {8,12}: (seq: int 0..2^31-1, machineId: string<=32, x: int 0..11, z: int 0..11, r: int 0..3)
- BuildMove {4,6}, NEW: (seq, model: Model under Plot_N.Machines, x, z, r)
- BuildPickup {6,10}: (seq, model: Model)
- MachineAction {8,12}: (model: Model, action: string<=24, arg: table?)
  - step d action: 'StorageTake' with arg {Key: string<=80 'K|O|G|R', Count: int 1..5}
- AnvilSubmit {2,3}, NEW: (sessionId: string<=64, recipeId: string<=32, strikes: {number})
  - #strikes == recipe.Hits; each finite and in 0..elapsed+1; strictly increasing; gaps >= 0.18; last >= Hits*0.3
- AnvilCancel {2,3}, NEW: (sessionId: string<=64)

Server -> client (Events value false):
- BuildResult {Seq: number, Op: 'Place'|'Move'|'Pickup', Ok: boolean, Reason: string?, Id: string?, X: number?, Z: number?, R: number?}
- AnvilBegin {Id: string, Anvil: Model, OreId: string, Grade: string, Count: number, Recipes: {string}, Timeout: number}
- AnvilResult {Id: string, Ok: boolean, Reason: string?, Recipe: string?, OreId: string?, Grade: string?, Value: number?, ItemId: string?}
- OpenUI: ('Storage', {Machine: Model})
- Fx kinds:
  - 'Reject'(pos: Vector3), to the item owner
  - 'Sold'(pos, total: number, count: number, rarityId: string), to the owner
  - 'SellPuff'(pos), fireNear 60, except the owner
  - 'Placed'(pos, machineId: string), fireNear 100, except the builder
  - 'PackedUp'(pos, machineId), fireNear 100, except the builder
- Notify {Text, Kind: 'Info'|'Deny'|'Reward'}
- State snapshot gains Placed: {{Id,X,Z,R}}, Build: {MachineSlots, ConveyorSlots, MachinesUsed, ConveyorsUsed}, StorageCapacity: number

Reason codes (BuildResult.Reason, from Placement.Reasons): NoPlot, TooFar, NotYours, Invalid, UnknownMachine, BadInput, OutOfBounds, Overlap, NoMachineSlots, NoConveyorSlots, NoneOwned, Busy.

2) DATA (DataTemplate.Version = 2)
- PlacedMachines: {{Id: string, X: int 0..11, Z: int 0..11, R: int 0..3, In: {Desc}?, Out: {Desc}?}}. In holds at most 4 (In[1] is being worked; anvil ingots live here). Out holds at most MachineData.MaxOutBuffer = 4.
- MachineInventory: {[machineId]: int 1..999}. A key is removed at 0.
- Storage: {Desc}, one shared pool. Player deposits are limited to min(300, 60 x placed crates). System writes are limited to 300, then paid at full value.
- Desc = {K: kind, O: oreId, G: grade?, R: recipe?}.
- Storage key = ItemData.storageKey(desc) = 'K|O|G|R' (nil becomes ''). ItemData.parseKey(key): Desc?.
- Stats.IngotsSmelted, GearForged and ItemsSold are incremented by Processing, Anvil and Sell.

3) MODEL ATTRIBUTES (server-set, clients read only)
- Existing: MachineId, Owner, GridX, GridZ, Rotation, HasOre (Cleaning).
- Busy: boolean. Cleaning session or anvil session; MachineService refuses move/pickup while it is true.
- Queue: int (#In). QueueMax: int (4). OutCount: int (#Out).
- Working: boolean. WorkStart: number (Workspace:GetServerTimeNow()). WorkTime: number. WorkOre: string?.
- Cycles: int, +1 per finished job, deposit, sale or forge.
- Status: '' | 'OutputBlocked' | 'TooManyItems'.
- Ingots: int. IngotOre: string?. Forging: boolean.
- ItemRecord runtime fields added: ReleasePos: Vector3, ReleasedAt: number.

4) PROMPTS (F / ButtonY, UIOffset = order*72, RequiresLineOfSight false)
- 'LoadPrompt': processors, crate, chute. Created only by IntakeService.addLoadPrompt. The server never changes its Enabled afterwards (the client shows it only while you carry something).
- Crate: 'OpenPrompt' (order 1).
- Anvil: 'ForgePrompt' (order 0) and 'TakePrompt' (hold 0.4, order 1).
- Pell's SellCounter part: 'SellPrompt' (hold 0.3). The client overrides its ObjectText locally.
- Model attachments (MachineBuilder): Intake (+ IntakeSize attribute), Output (at Grid.outputLocal), Prompt, Status (top + 1.5). Anvil also has AnvilPoint, CamPoint and IngotSlot1..4. Cleaning Station keeps OrePoint and CamPoint.
- Conveyor parts: Base, Belt (tag 'ConveyorBelt'), RailL (x<0), RailR (x>0), Arrow x2.

5) SHARED PURE MODULES (P0; no Roblox services; Lune-loadable)

Grid (src/shared/Machines/Grid.luau):
- footprint(id,r)->(w,d)
- key(x,z)->int
- dir(r)->(dx,dz): r0 (0,-1) toward the road, r1 (1,0), r2 (0,1), r3 (-1,0)
- right(r)->(-dz,dx)
- localCFrame(id,x,z,r)->CFrame
- cellFromLocal(p)->(x?,z?)
- outputLocal(id)->Vector3?: column floor(w/2), z = -(d*2) - 0.5, y = 1.8
- outputCell(id,x,z,r)->(x?,z?)
- sideOf(id,x,z,r,gx,gz)->('Front'|'Back'|'Left'|'Right')?

Placement (src/shared/Machines/Placement.luau):
- Reasons
- cells, inBounds, occupancy(entries, ignore?)
- limits(extraSlots, workshop)->{Machines,Conveyors}
- counts(entries)->(m,c)
- validate(entries,id,x,z,r,limits?,ignore?)->(ok,code?)
- clampOrigin(id,cellX,cellZ,r)->(x,z)
- commitPlace(data,id,x,z,r,limits)->(Entry?,code?)
- commitMove(data,entry,x,z,r)->(ok,code?)
- commitPickup(data,entry)->boolean
- sanitize(data)->{displacedId}

ConveyorLogic (src/shared/Machines/ConveyorLogic.luau):
- openSides(entries)->{[Entry]:{Left,Right}}
- faceAllowed(target, fromX, fromZ)->boolean
- feeders(entries)->{{Conveyor,Target}}
- headOn(entries)->{{Entry}}

MachineLogic (src/shared/Machines/MachineLogic.luau):
- types Desc and Reason = 'Wrong'|'Foreign'|'Mixed'|'Full'|'Busy'. 'Full' and 'Busy' mean wait; the others mean eject.
- isValidDesc, queueSize(id)
- accepts(id,desc,entry,sameOwner)->(ok,reason?)
- outputs(id,input,roll)->{Desc}
- rollGrade(chances,maxGrade,roll)
- push, complete(entry,outputs), popOut, drain
- recipeOptions(count)->{recipeId}
- forge(entry,recipeId)->(Desc?,used)
- validateStrikes(strikes,hits,elapsed)->(ok,why?)

MachineData additions:
- LoadText, WrongHint, ConveyorFaces ('All'|'NoFront'|nil), AcceptsForeign, GradeChances (AutoCleaner {Rough=0.6, Clean=0.4})
- MaxOutBuffer = 4
- machineSlots(extra, workshop) = 10 + 3*min(extra,2) + 6
- conveyorSlots(workshop) = 40 + 20

GameConfig additions: names as listed in the GameConfig module entry (MachineTick, IntakeTick, IntakeMargin, FeedReachBelt, FeedReachInto, OutputPop, OutputRetry, LooseHeadroom, MinProcessTime, RejectPop, BeltRejectPop, RejectCooldown, WrongHintCooldown, MachineUseRange=14, BuildRange=70, AntiTeleportRange=40, MaxItemSpeed, PlausibleSlack, MaxItemTravel=90, ClientPhysicsRange=80, ForeignItemReturn=8, Conveyor*, Sell*, StorageTakeMax=5, Anvil*, StudioDevKit {Layout, Inventory}).

SoundConfig additions: Gulp, MachineDone, MachineHum, Reject, CoinBurst, BuildRotate.

6) SERVER APIs (P1)

ItemService:
- descOf(rec)->Desc
- absorb(rec)->Desc: destroys, any state except Consumed
- spawnDesc(desc, ownerUserId, cf, vel?)->ItemRecord?
- storeDesc(player, desc, reason?)->'Stored'|'Sold'|'Lost'
- looseList()->{ItemRecord} (a copy)
- looseCount(userId)
- isTrusted(rec, now)->boolean
- eject(rec, velocity)
- unchanged: spawn, release, mount, stash, destroy, fromPart, ownedBy, get

PlotService:
- footprintCFrame (same signature)
- plotAt(pos)->(plotId?, localPos?)
- isNear(player, plotId, range)->boolean

MachineService:
- Behaviour = {spawned?, removed?(m, 'Unload'|'Pickup'), moved?, canAccept?(m, desc, ownerUserId, via)->(ok, reason?), insert?(m, desc, ownerUserId, via), tick?(m, now)}, where via = 'Drop'|'Belt'|'Hand'|'Machine'
- PlacedMachine += Entry, Info, Removed
- register(id, behaviour): back-fills spawned
- get, ofPlayer, all, point
- ofPlot(plotId), atCell(plotId,gx,gz)
- place(player,id,x,z,r)->(m?,code?)
- move(m,x,z,r)->(ok,code?)
- pickup(m)->(ok,code?)
- remove(m,reason)
- limits(player)->Limits, usage(player)->(m,c)
- canAccept(m,desc,owner,via), insertRecord(m,rec,via), insertDesc(m,desc,owner,via)
- pushOut(m,desc)
- emit(m,desc)->('Handed'|'Spawned'|'Blocked', rec?)
- setAttrs(m,attrs)
- onLayoutChanged(cb(player, plotId))
- onAction(action, handler(player, m, arg)): checks own plot folder, owner, within 14 studs
- spawnAll is hooked in start(), not init()

IntakeService:
- addZone(name, part, handler(rec))
- setBeltHandler(handler(belt, rec, localPos, now))
- react(m, rec, reason, via)
- addLoadPrompt(m, actionText, order)->ProximityPrompt
- hint(player, machineId, text)

Feature services:
- EconomyService (WP-StorageSell): award(player, amount, source)->balance; onEarned(cb)
- SellService: sell(rec, source)->value; sellDesc(ownerUserId, desc, pos, source)->value; onSold(cb(player, desc, value))
- StorageService: capacity(player)->number
- ProcessingService: onProcessed(cb(player, machineId, input, outputs))
- AnvilService: onForged(cb(player, gear))
- BuildService: onPlaced(cb(player, machineId))

Registration owners:
- ProcessingService registers ClayFurnace, BlastFurnace, Crusher, AutoCleaner
- StorageService registers StorageCrate
- SellService registers SellChute
- ConveyorService registers Conveyor
- AnvilService registers Anvil
- CleaningService registers CleaningStation (no canAccept)

7) CLIENT APIs (P1)
- FxController.register(kind, handler)
- PromptController.setSuppressed(reason, on)
- PlayerControls.set(enabled), claim(name)->boolean, release(name), owner()->string?
- PlacementController.isActive(), enter(), exit()
- Existing APIs used as is: HudController.refs().Menu (BUILD button added at runtime), HudController.toast, InteractController.suspend/resume, MiningController.setBusy, CleaningController.isActive, StateController.get/onChanged.

8) INVARIANTS
- No yield between removing an item from one place and adding it to another (takeTop -> insertRecord, absorb -> insert, commit* -> spawn/destroy).
- Every data change is followed by DataService.changed(player).
- Unload writes no data.
- Slot limits are never enforced on load.
- The dev kit only runs when IsStudio() and DataService.isInMemory().
- Client values are only hints; the server re-validates everything.

## Modules

### `/home/user/Perfect-Tap/src/shared/Net.luau` (modify)
Declare every step-d remote in one edit (P0 only).

API: Net.Events additions: BuildMove{4,6}, AnvilSubmit{2,3}, AnvilCancel{2,3}, BuildResult=false, AnvilBegin=false, AnvilResult=false. Changed: BuildPlace{8,12}, BuildPickup{6,10}, MachineAction{8,12}.

CleanStart stays. Payloads are listed in contracts and remotes.

### `/home/user/Perfect-Tap/src/shared/Config/GameConfig.luau` (modify)
All step-d tuning and safety numbers.

API: 

Add:
- MachineTick=0.1, IntakeTick=0.2, IntakeMargin=0.4
- FeedReachBelt=1.6, FeedReachInto=1.5
- OutputPop={Forward=6,Up=4}, OutputRetry=1, LooseHeadroom=2, MinProcessTime=0.5
- RejectPop={Out=8,Up=14}, BeltRejectPop={Side=9,Up=7}, RejectCooldown=1.5, WrongHintCooldown=10
- MachineUseRange=14, BuildRange=70, AntiTeleportRange=40, MaxItemSpeed=75, PlausibleSlack=6, MaxItemTravel=90
- ClientPhysicsRange=80 (below StreamingMinRadius 96), ForeignItemReturn=8
- ConveyorStuckSpeed=0.6, ConveyorStuckSeconds=1.5, ConveyorMaxNudges=5, ConveyorNudgeWindow=30
- SellComboWindow=0.8, SellOthersRadius=60, StorageTakeMax=5
- AnvilTimeout=60, AnvilWalkAway=20, AnvilMinStrikeGap=0.18, AnvilMinSecondsPerHit=0.3
- StudioDevKit = { Layout = { {Id='Crusher',X=4,Z=9,R=0}, {Id='AutoCleaner',X=0,Z=10,R=0}, {Id='BlastFurnace',X=7,Z=8,R=0}, {Id='Anvil',X=10,Z=1,R=0}, {Id='SellChute',X=2,Z=1,R=0} }, Inventory = {Conveyor=24, StorageCrate=1, SellChute=1, ClayFurnace=1} }. Set it to false to disable.
Unchanged: MachineIntakeQueue=4 (includes the item being worked), ConveyorSpeed=7, StorageCrateCapacity=60, MaxStoredItems=300, MaxLooseItemsPerPlayer=30.

### `/home/user/Perfect-Tap/src/shared/Config/MachineData.luau` (modify)
Per-machine behaviour metadata and slot math.

API: Machine type += LoadText: string?, WrongHint: string?, ConveyorFaces: ('All'|'NoFront')?, AcceptsForeign: boolean?, GradeChances: {[string]: number}?
MachineData.MaxOutBuffer = 4
MachineData.machineSlots(extraBought: number, workshop: boolean): number
MachineData.conveyorSlots(workshop: boolean): number

LoadText:
- Clay and Blast Furnace 'Smelt Ore'
- Crusher 'Crush Ore'
- AutoCleaner 'Auto-Clean'
- StorageCrate 'Store Items'
- SellChute 'Sell Items'
WrongHint:
- Furnaces 'Furnaces melt CLEAN or CRUSHED ore. Clean raw ore at your Cleaning Station first!'
- Crusher 'The Crusher only takes CLEAN ore.'
- AutoCleaner 'The Auto Cleaner only takes RAW ore.'
- Anvil 'The Anvil only takes INGOTS of one ore. Smelt ore in a Furnace first!'
ConveyorFaces: StorageCrate and SellChute 'All'; the 4 processors and the Anvil 'NoFront'; CleaningStation and Conveyor nil.
AcceptsForeign is true on SellChute only.
AutoCleaner.GradeChances = {Rough=0.6, Clean=0.4} (NEW BALANCE).
machineSlots = 10 + 3*min(extraBought,2) + (workshop and 6 or 0), giving 10/13/16/22. conveyorSlots = 40 + (workshop and 20 or 0).
No price, time or size changes. The StarterKit is unchanged.

### `/home/user/Perfect-Tap/src/shared/Config/ItemData.luau` (modify)
One storage-key format for the server, the client and tests.

API: ItemData.storageKey(desc: {K:string,O:string,G:string?,R:string?}): string  -- 'K|O|G|R', nil -> ''
ItemData.parseKey(key: string): Desc?

parseKey returns nil for keys over 80 characters, an unknown kind or ore, an unknown grade, or a Gear without a valid recipe. The format matches what StateService already sends.

### `/home/user/Perfect-Tap/src/shared/Config/SoundConfig.luau` (modify)
New sounds, all built-in rbxasset.

API: 

- Gulp: action_jump_land.mp3, vol 0.45, pitch 1.3-1.5
- MachineDone: clickfast.wav, 0.55, 0.75-0.85
- MachineHum: swoosh.wav, 0.15, 0.3-0.35, Looped
- Reject: button.wav, 0.4, 0.5-0.6
- CoinBurst: electronicpingshort.wav, 0.5, 1.4-1.6
- BuildRotate: clickfast.wav, 0.3, 1.3-1.4
Furnace, Crusher, AnvilClang, Place and Sell are reused.

### `/home/user/Perfect-Tap/src/shared/Machines/Grid.luau` (new)
Pure grid maths: the single source for footprints, rotation, output cells and sides. No Roblox services; runs in Lune.

API: Grid.footprint(id: string, r: number): (w: number, d: number)
Grid.key(x: number, z: number): number  -- z*PlotCells + x
Grid.dir(r: number): (dx: number, dz: number)  -- r0 (0,-1) road, r1 (1,0), r2 (0,1), r3 (-1,0)
Grid.right(r: number): (dx: number, dz: number)  -- (-dz, dx)
Grid.localCFrame(id, x, z, r): CFrame  -- plot-local footprint centre, CFrame.new(-half+(x+w/2)*4, 0, -half+(z+d/2)*4) * CFrame.Angles(0, -r*pi/2, 0)
Grid.cellFromLocal(p: Vector3): (number?, number?)
Grid.outputLocal(id): Vector3?  -- model-local Output position; nil for CleaningStation (tray), SellChute, Conveyor
Grid.outputCell(id, x, z, r): (number?, number?)  -- may be off the plot (returns raw ints)
Grid.sideOf(id, x, z, r, gx, gz): ('Front'|'Back'|'Left'|'Right')?

outputLocal for width w (Size[1]): column c = floor(w/2), x = -w*2 + (c+0.5)*4, z = -(Size[2]*4/2) - 0.5, y = 1.8.
- 2-wide machines output at x=+2, the right front cell when looking out of the machine's front.
- 1-wide and 3-wide machines output at x=0.
PlotService.footprintCFrame and the client ghost both call localCFrame.

### `/home/user/Perfect-Tap/src/shared/Machines/Placement.luau` (new)
Pure placement validation, slot limits, the inventory ledger and the layout cleaner. The client ghost and the server use the same code.

API: export type Entry = {Id: string, X: number, Z: number, R: number, In: {Desc}?, Out: {Desc}?}
export type Limits = {Machines: number, Conveyors: number}
Placement.Reasons: {[string]: string}
Placement.cells(id, x, z, r): {number}
Placement.inBounds(id, x, z, r): boolean
Placement.occupancy(entries: {Entry}, ignore: Entry?): {[number]: Entry}
Placement.limits(extraSlots: number, workshop: boolean): Limits
Placement.counts(entries: {Entry}): (machines: number, conveyors: number)
Placement.validate(entries, id, x, z, r, limits: Limits?, ignore: Entry?): (boolean, string?)
Placement.clampOrigin(id, cellX, cellZ, r): (x, z)
Placement.commitPlace(data, id, x, z, r, limits: Limits): (Entry?, string?)
Placement.commitMove(data, entry: Entry, x, z, r): (boolean, string?)
Placement.commitPickup(data, entry: Entry): boolean
Placement.sanitize(data): {string}  -- ids of displaced machines

Validation order:
1. UnknownMachine
2. BadInput (non-integer, or R outside 0..3)
3. OutOfBounds
4. Overlap
5. NoMachineSlots / NoConveyorSlots, skipped when limits is nil or ignore is set, so a move never fails on slots

Rules:
- Every machine without SlotFree counts as a machine slot, including the Cleaning Station.
- Unknown-Id entries are ignored for occupancy and counts, and kept in data.
- commitPlace: MachineInventory[id] >= 1 else 'NoneOwned'. Then validate, decrement (key removed at 0), and append a fresh {Id,X,Z,R}.
- commitMove: validate with ignore=entry, then change entry X/Z/R in place.
- commitPickup: remove by identity (table.find), then MachineInventory[id] += 1.
- Nothing yields, and a failed commit changes nothing.
- sanitize walks entries in saved order. Unknown Id: kept, skipped. Out of bounds, or overlapping an earlier entry: removed and MachineInventory += 1; its In/Out spill into Storage (beyond 300 they are paid as coins at ItemData.value).
- sanitize also trims In to MachineIntakeQueue and Out to MaxOutBuffer, with the same spill rule.
- Slot limits are never enforced on load.

Reasons text:
- OutOfBounds 'Doesn't fit on your plot'
- Overlap 'Something is already there'
- NoMachineSlots 'All machine slots are used'
- NoConveyorSlots 'All belt slots are used'
- NoneOwned 'You don't have one to place'
- Busy 'Finish using it first'
- TooFar 'Go to your forge to build'
- NoPlot 'You don't have a plot yet'
- NotYours 'That's not your machine'
- Invalid 'Something went wrong'
- UnknownMachine and BadInput 'Can't place that'

### `/home/user/Perfect-Tap/src/shared/Machines/ConveyorLogic.luau` (new)
Pure belt layout: which rails open, which belts feed which machine, which faces accept.

API: ConveyorLogic.openSides(entries): {[Entry]: {Left: boolean, Right: boolean}}
ConveyorLogic.faceAllowed(target: Entry, fromX: number, fromZ: number): boolean
ConveyorLogic.feeders(entries): {{Conveyor: Entry, Target: Entry}}
ConveyorLogic.headOn(entries): {{Entry}}

- A side rail opens when the neighbour on that side is a conveyor whose front cell is this cell, so corners and T-joins work. Right = Grid.right(r); RailR is at model local +X.
- faceAllowed uses MachineData.ConveyorFaces and Grid.sideOf: 'All' always; 'NoFront' unless the cell is the target's Front; nil never.
- A feeder is a conveyor whose front cell is covered by a non-conveyor machine with faceAllowed.
- headOn is only a ghost warning, never a validation error.

### `/home/user/Perfect-Tap/src/shared/Machines/MachineLogic.luau` (new)
Pure machine rules and the In/Out queue. Fuzz-tested for item conservation.

API: export type Desc = {K: string, O: string, G: string?, R: string?}
export type Reason = 'Wrong'|'Foreign'|'Mixed'|'Full'|'Busy'
MachineLogic.isValidDesc(desc: any): boolean
MachineLogic.queueSize(id: string): number
MachineLogic.accepts(id, desc, entry: Entry, sameOwner: boolean): (boolean, Reason?)
MachineLogic.outputs(id, input: Desc, roll: number): {Desc}
MachineLogic.rollGrade(chances: {[string]: number}, maxGrade: string, roll: number): string
MachineLogic.push(entry, desc)
MachineLogic.complete(entry, outputs: {Desc})  -- removes In[1], appends outputs to Out
MachineLogic.popOut(entry): Desc?
MachineLogic.drain(entry): {Desc}  -- In then Out, clears both (nil)
MachineLogic.recipeOptions(count: number): {string}
MachineLogic.forge(entry, recipeId: string): (Desc?, number)
MachineLogic.validateStrikes(strikes: any, hits: number, elapsed: number): (boolean, string?)

accepts:
- An invalid desc is 'Wrong'.
- SellChute: any valid desc with value > 0, from any owner.
- If not sameOwner: 'Foreign'.
- StorageCrate: OK here; capacity is checked by the service.
- Processors: kind not in Accepts is 'Wrong'; #In >= 4 is 'Full'.
- Anvil: not an Ingot is 'Wrong'; a different ore from In[1] is 'Mixed'; #In >= 4 is 'Full'.
- CleaningStation and Conveyor: 'Wrong'.
'Full' and 'Busy' mean wait. 'Wrong', 'Foreign' and 'Mixed' mean eject.

outputs:
- Furnaces: 1 Ingot, same ore, grade kept (nil becomes 'Rough').
- Crusher: 2 Crushed, same grade.
- AutoCleaner: Clean, grade from rollGrade, never above MaxGrade.

forge uses the first N ingots in In (FIFO) and gives a Gear with the lowest grade of those used (ItemData.gradeLevel).

validateStrikes needs exactly `hits` finite numbers, each 0 <= t <= elapsed+1, strictly increasing, with gaps >= AnvilMinStrikeGap and last >= hits*AnvilMinSecondsPerHit.

Empty In/Out are set to nil to keep saves small.

### `/home/user/Perfect-Tap/src/shared/Builders/MachineBuilder.luau` (modify)
Outputs on cell centres, a cheaper conveyor, and attachments for the new UIs. Stays a pure builder.

API: 

- Output attachment = Grid.outputLocal(id) for ClayFurnace, BlastFurnace, Crusher, AutoCleaner, StorageCrate and Anvil. Move each visual lip or chute wedge (and the furnace mouth glow) with it. Cleaning Station tray is unchanged.
- Every machine gets a 'Status' attachment at body top + 1.5.
- Anvil gets 'CamPoint' (lookAt from (0,8.5,-5.5) to AnvilPoint+(0,0.2,0)) and 'IngotSlot1'..'IngotSlot4' on the face.
- Conveyor goes to 6 parts: Base (invisible, CanQuery), Belt (tagged 'ConveyorBelt', CustomPhysicalProperties 0.7/1.2/0/100/100), RailL at x=-1.85, RailR at x=+1.85, and one 2-wedge neon chevron 'Arrow'. CastShadow is false on all.
- Part budget: at most 40 parts per non-conveyor machine.
- Requires ../Machines/Grid (no cycle).

### `/home/user/Perfect-Tap/src/server/World/PlotBuilder.luau` (modify)
Keep the 48x48 build grid free of decoration.

API: 

- The pad becomes (grid+2) x (grid+2).
- Rails and corner posts move to +/-(half+0.5).
- The banner pole moves to (half+1.5, half+1.5).
- The inner PlotTile becomes exactly the grid size.
- Bump WorldBuilder.Version 2 -> 3 in /home/user/Perfect-Tap/src/server/World/WorldBuilder.luau (one line), so the runtime map rebuilds until the place is rebaked.
- Town.isFree margin 28 still covers half+1.5.

### `/home/user/Perfect-Tap/src/server/Data/DataTemplate.luau` (modify)
Save version.

API: 

Version = 2. No new top-level fields. Comment that PlacedMachines entries may carry In/Out.

### `/home/user/Perfect-Tap/src/server/Data/Migrations.luau` (new)
Idempotent type clean-up on every load. Pure and Lune-testable.

API: Migrations.Latest = 2
Migrations.run(data: {[string]: any}): {Moved: number, Dropped: number}

PlacedMachines:
- Drop non-table entries and entries without a string Id.
- Finite X/Z are floored; R becomes floor(R)%4.
- Non-finite coordinates: a known Id goes to MachineInventory+1, an unknown Id is dropped with a warning.
- In/Out that are not tables become nil. Elements need a string K and O; malformed ones are dropped. Well-formed elements with an unknown kind or ore move to Storage unchanged.
MachineInventory:
- Only string keys and number values. Floor, and keep 1..999; anything else becomes nil. Unknown ids are kept (future-proof).
Storage:
- Drop non-table entries only.
Then set Version = 2. Layout repair (bounds/overlap) is NOT done here; Placement.sanitize does it in MachineService.spawnAll so the player gets a toast.

### `/home/user/Perfect-Tap/src/server/Services/DataService.luau` (modify)
Wire up Migrations.

API: 

migrate(data) calls Migrations.run(data) after the purchase-history trim and warns if Moved or Dropped > 0. Nothing else changes.

### `/home/user/Perfect-Tap/src/server/Services/ItemService.luau` (modify)
Convert between records and descriptors, a trust check, a loose list, and a physics-owner range. Existing callers are unchanged.

API: ItemService.descOf(record): Desc
ItemService.absorb(record): Desc
ItemService.spawnDesc(desc: Desc, ownerUserId: number, cf: CFrame, velocity: Vector3?): ItemRecord?
ItemService.storeDesc(player: Player, desc: Desc, reason: string?): 'Stored'|'Sold'|'Lost'
ItemService.looseList(): {ItemRecord}
ItemService.looseCount(userId: number): number
ItemService.isTrusted(record, now: number): boolean
ItemService.eject(record, velocity: Vector3)
ItemRecord += ReleasePos: Vector3, ReleasedAt: number

- absorb works on any state except Consumed. It removes CarryWeld and CarriedBy, destroys the item and returns the desc.
- storeDesc keeps the 300 cap and pays full value beyond it. stash() is rewritten on top of it with the same behaviour and texts.
- byOwner index: looseCount and ownedBy only iterate that owner's records.
- looseList returns a copy, so callers may destroy items while iterating.
- spawn and release set ReleasePos and ReleasedAt.
- giveClientPhysics: the owner's client only gets physics when their root is within ClientPhysicsRange (80); otherwise the server keeps it and ClientOwnedUntil stays nil.
- isTrusted: true if ClientOwnedUntil is nil. Otherwise the owner's root must be within AntiTeleportRange (40) of the item AND the horizontal distance from ReleasePos must be <= (now-ReleasedAt)*MaxItemSpeed + PlausibleSlack.
- maintainOne: when ClientOwnedUntil expires and the item is more than MaxItemTravel (90) from ReleasePos, warn and release it at rescueCFrame(owner), or stash it.
- eject = release(record, pivot + (0,1.5,0), velocity).

### `/home/user/Perfect-Tap/src/server/Services/MachineService.luau` (modify)
BIG REFACTOR. Placed-machine lifecycle linked to saved entries, the behaviour registry with intake hooks, the item ledger (insert/emit), the tick loop and the MachineAction dispatcher.

API: PlacedMachine += Entry: Entry, Info: MachineData.Machine, Removed: boolean
Behaviour = { spawned: ((m) -> ())?, removed: ((m, reason: 'Unload'|'Pickup') -> ())?, moved: ((m) -> ())?, canAccept: ((m, desc: Desc, ownerUserId: number, via: Via) -> (boolean, Reason?))?, insert: ((m, desc: Desc, ownerUserId: number, via: Via) -> ())?, tick: ((m, now: number) -> ())? }
Via = 'Drop'|'Belt'|'Hand'|'Machine'
register(id, behaviour)  -- back-fills spawned for machines already placed
get, ofPlayer, all, point (unchanged)
ofPlot(plotId): {PlacedMachine}
atCell(plotId, gx, gz): PlacedMachine?
place(player, id, x, z, r): (PlacedMachine?, string?)
move(m, x, z, r): (boolean, string?)
pickup(m): (boolean, string?)
remove(m, reason: 'Unload'|'Pickup')
limits(player): Limits
usage(player): (machines, conveyors)
canAccept(m, desc, ownerUserId, via): (boolean, Reason?)
insertRecord(m, record, via): (boolean, Reason?)
insertDesc(m, desc, ownerUserId, via): (boolean, Reason?)
pushOut(m, desc)
emit(m, desc): ('Handed'|'Spawned'|'Blocked', ItemRecord?)
setAttrs(m, attrs: {[string]: any})
onLayoutChanged(cb: (Player, number) -> ())
onAction(action: string, handler: (Player, PlacedMachine, any) -> ())

Startup:
- start() hooks PlotService.onAssigned(spawnAll); it is no longer done in init(). This fixes the init-order race.

spawnAll:
1. Give the StarterKit once (unchanged).
2. Studio dev kit, only if RunService:IsStudio() and DataService.isInMemory() and GameConfig.StudioDevKit, and only when the StarterKit is given: append Layout and top up Inventory.
3. Placement.sanitize(data). If anything was displaced, send one Notify '<Name> didn't fit and is waiting in your Build menu.'
4. Spawn known entries with m.Entry = the entry table.
5. Build the cell map, call DataService.changed and fire layoutChanged.

place:
- Placement.commitPlace with limits(player) (ExtraSlots + Perks Workshop), then spawn.
- If spawn fails, roll back with commitPickup.

move:
- Refused with 'Busy' if the Busy attribute is set.
- commitMove, PivotTo(PlotService.footprintCFrame), update X/Z/R and GridX/GridZ/Rotation, run the moved hooks. In/Out and running jobs are kept.

pickup:
- Refused with 'Busy' if the Busy attribute is set.
- Run removed(m,'Pickup'), then MachineLogic.drain(m.Entry) -> ItemService.storeDesc each, with one Notify 'N items from your <Name> went to Storage'.
- commitPickup, destroy the model.

Unload (plot release): removed(m,'Unload'), destroy the model, touch no data (In/Out are already in the profile).

After every layout change: rebuild that plot's cell map, call DataService.changed and fire layoutChanged (coalesced with task.defer per player). No yields between a data change and the instance change.

Item hand-in:
- canAccept calls behaviour.canAccept, otherwise returns (false,'Wrong'). For via 'Belt' and 'Machine' the caller has already checked ConveyorLogic.faceAllowed.
- insertRecord = canAccept(descOf(record), record.Owner), then absorb, then insert, all synchronous.

emit(m, desc):
- The output cell comes from Grid.outputCell.
- A non-conveyor machine there, with faceAllowed: insertDesc(target, desc, owner, 'Machine'). On success 'Handed'; on refusal Status='OutputBlocked' and 'Blocked'.
- Otherwise, if looseCount(owner) >= MaxLoose - LooseHeadroom: Status='TooManyItems' and 'Blocked'.
- Otherwise spawnDesc at the Output attachment with velocity Look*6 + Up*4: 'Spawned'.

Tick loop every MachineTick:
- pcall behaviour.tick.
- If Entry.Out is non-empty and now >= State.NextEmit, emit Out[1]. On success popOut, set OutCount and Status ''. If Blocked, NextEmit = now + OutputRetry.

setAttrs writes only changed values.

MachineAction dispatcher, in order:
1. Guard.instance(model,'Model', the player's Plot_N.Machines)
2. get
3. Owner == player
4. root within MachineUseRange of the pivot
5. Guard.string(action,24)
6. the registered handler, inside pcall

### `/home/user/Perfect-Tap/src/server/Services/PlotService.luau` (modify)
Use the shared grid maths; add point-to-plot lookup and a range helper.

API: PlotService.footprintCFrame(plotId, id, gx, gz, r) (unchanged signature; = plotCFrame * Grid.localCFrame)
PlotService.plotAt(position: Vector3): (number?, Vector3?)
PlotService.isNear(player: Player, plotId: number, range: number): boolean

plotAt does a quick reject (|dx| and |dz| <= 26 from the 8 plot centres), then PointToObjectSpace, and requires local y in -3..24. isNear uses horizontal distance from the plot centre.

### `/home/user/Perfect-Tap/src/server/Services/IntakeService.luau` (new)
The only scanner that moves loose items into machines: hoppers, belt-end feeders, static town zones, foreign-item return and Put In prompts.

API: IntakeService.addZone(name: string, part: BasePart, handler: (record) -> ())
IntakeService.setBeltHandler(handler: (belt: PlacedMachine, record, localPos: Vector3, now: number) -> ())
IntakeService.react(m: PlacedMachine, record, reason: Reason, via: Via)
IntakeService.addLoadPrompt(m: PlacedMachine, actionText: string, order: number): ProximityPrompt
IntakeService.hint(player: Player, machineId: string, text: string)

Zone index:
- Per plot, rebuilt on onLayoutChanged: cellKey -> list of zones.
- Hopper zones (machines that have canAccept) use the Intake attachment WorldCFrame and IntakeSize + IntakeMargin, registered on each footprint cell.
- Feeder zones come from ConveyorLogic.feeders: a belt-local box x +/-2, y 0..4, z from -2-FeedReachInto to -2+FeedReachBelt, registered on the belt cell AND the target cell.

Loop every IntakeTick over ItemService.looseList(). Skip a record if its State is no longer Loose.
1. Static zones (town SellBin) first. If the record is trusted, call the zone handler.
2. PlotService.plotAt, then the cell. If not isTrusted, skip.
3. Check the cell's zones, hoppers first. The first box that contains the item wins: a hopper calls insertRecord(m,rec,'Drop'); a feeder calls insertRecord(target,rec,'Belt'). If refused, call react.
4. Otherwise, if the cell is a conveyor, call the belt handler.
5. Otherwise, if the plot owner is not the item's owner, track ForeignSince. After ForeignItemReturn (8 s), ItemService.stash(rec,'Your item landed on another forge').
Cost: about 240 items x 1-3 box tests at 5 Hz, with no spatial queries.

react(m, record, reason, via):
- 'Full' or 'Busy': nothing (the item waits).
- 'Wrong', 'Mixed' or 'Foreign', at most once per RejectCooldown per item (weak-keyed table):
  - via 'Drop': eject with m Look*RejectPop.Out + Up*RejectPop.Up.
  - via 'Belt': eject with belt Right*9 + Up*7.
  - Fire Fx 'Reject'(pos) to the owner.
  - Except for 'Foreign', send hint(owner, m.Id, WrongHint).

hint throttles Notify to once per WrongHintCooldown per player per machine id.

addLoadPrompt:
- ProximityPrompt 'LoadPrompt' on the Prompt attachment: F / ButtonY, HoldDuration 0, MaxActivationDistance 10, UIOffset order*72, ObjectText = machine Name.
- Triggered: owner only, otherwise Notify 'That's not your machine.'
- Repeat CarryService.takeTop(predicate = canAccept(descOf(r), r.Owner, 'Hand')) followed by insertRecord(m, r, 'Hand') until nothing fits. No yield between takeTop and insertRecord.
- If 0 items went in, Notify '<Name> is full' or the WrongHint.
- The server never changes LoadPrompt.Enabled after creating it.

### `/home/user/Perfect-Tap/src/server/Services/CleaningService.luau` (modify)
Fit the new hooks; the minigame is untouched.

API: 

- Add moved = re-mount the vise item (stationItem) at the new OrePoint.
- removed(m, reason) ignores reason and keeps stashing the vise item (current behaviour).
- There is no canAccept, so the router leaves the station alone; its own 0.3 s vise scan stays.
- Busy is already set during a session, so moving or packing is refused.

### `/home/user/Perfect-Tap/src/server/Services/StateService.luau` (modify)
Use the single key format.

API: 

storageSummary uses ItemData.storageKey; the payload is unchanged. Placed, Build and StorageCapacity arrive through addProvider from BuildService and StorageService.

### `/home/user/Perfect-Tap/src/server/init.server.luau` (modify)
Service ORDER, edited once by P1.

API: 

DataService, WorldService, StateService, ItemService, ToolService, MiningService, CarryService, PlotService, MachineService, IntakeService, EconomyService, CleaningService, ProcessingService, StorageService, SellService, ConveyorService, AnvilService, BuildService, AccessService. Missing modules only warn.

### `/home/user/Perfect-Tap/src/client/init.client.luau` (modify)
Controller ORDER, edited once by P1.

API: 

... PromptController, CleaningController, MachineFxController, StorageController, SellController, AnvilController, PlacementController.

### `/home/user/Perfect-Tap/src/client/Controllers/FxController.luau` (modify)
Let feature controllers register their own Fx kinds, so FxController isn't edited again.

API: FxController.register(kind: string, handler: (...any) -> ())

Adds the handler to the table and warns on a duplicate kind. Existing handlers stay.

### `/home/user/Perfect-Tap/src/client/Controllers/PromptController.luau` (modify)
Context-aware prompts and suppressing prompts during close-ups.

API: PromptController.setSuppressed(reason: string, on: boolean)

- 'LoadPrompt' on your own machines is Enabled locally only while CarryCount > 0. It is re-evaluated on CarryCount change and PromptShown.
- Other players' machine prompts stay hidden (existing).
- setSuppressed sets ProximityPromptService.Enabled = (no active reasons). Used by build mode and the anvil.
- 'SellPrompt' on the SellCounter gets ObjectText 'Worth N coins' locally (sum of the Value attribute of items with CarriedBy == you).

### `/home/user/Perfect-Tap/src/client/Util/PlayerControls.luau` (new)
Shared movement lock for build mode and the anvil close-up.

API: PlayerControls.set(enabled: boolean)
PlayerControls.claim(name: string): boolean
PlayerControls.release(name: string)
PlayerControls.owner(): string?

set copies the body of CleaningController.playerControls (PlayerModule:GetControls()). CleaningController is not edited in step d. Callers also check CleaningController.isActive().

### `/home/user/Perfect-Tap/src/server/Services/BuildService.luau` (new)
Server authority for build remotes, slot state for the HUD, and placement clearing.

API: BuildService.onPlaced(cb: (Player, string) -> ())

Shared checks, in order:
1. Guard.integer seq 0..2^31-1, x/z 0..11, r 0..3; Guard.string id 32
2. data loaded, plot assigned ('NoPlot')
3. PlotService.isNear(player, plot, BuildRange) ('TooFar')
4. for Move and Pickup: Guard.instance(model,'Model', own Plot_N.Machines) and owner ('NotYours')

Handlers:
- BuildPlace -> MachineService.place. For non-conveyors, then lift characters whose root is inside the footprint to the model's top + 3, and lift loose items there to the top + 2 and wake them.
- BuildMove -> MachineService.move.
- BuildPickup -> MachineService.pickup. If it was the last crate and Storage is not empty, Notify 'Your stored items are safe. Place a crate to reach them.'
- Every request replies BuildResult. On success, fire Fx 'Placed' or 'PackedUp' near (100 studs) to everyone except the builder.

StateService provider:
- Placed = projection {Id,X,Z,R} of PlacedMachines
- Build = {MachineSlots, ConveyorSlots, MachinesUsed, ConveyorsUsed}

### `/home/user/Perfect-Tap/src/client/Controllers/PlacementController.luau` (new)
Build mode: overview camera, grid, ghost, select/move/pack up, input for PC, touch and gamepad.

API: PlacementController.isActive(): boolean
PlacementController.enter()
PlacementController.exit()

Entering:
- B, gamepad DPadUp, or a BUILD button that is added at runtime to HudController.refs().Menu (HudView is not edited).
- Only with a PlotId, within 70 studs, and not while cleaning or forging. Otherwise toast 'Go to your forge to build!'.
- On enter: PlayerControls.claim('Build') and set(false), InteractController.suspend(), MiningController.setBusy(true), PromptController.setSuppressed('Build', true), GuiService.TouchControlsEnabled=false.

Camera:
- Scriptable, 0.6 s tween to a road-side view: pitch 55 deg, distance 60, FOV 50.
- Pan clamped to the plot +/-24, zoom 40-80, no rotation.
- Exiting restores CameraType Custom.

Grid: GridOverlay.show(plotCFrame).

Ghost:
- MachineBuilder.build(id), cached per id. Transparency >= 0.45, no collide/query/touch/shadow, emitters/lights/SurfaceGuis off.
- Highlight green (80,220,120) or red (235,80,70).
- Footprint plate, plus an amber OUT plate on Grid.outputCell.
- Red reason label from Placement.Reasons.
- Yellow warnings: 'Output blocked' when the output cell is a refusing machine, and headOn belts.
- Lerps toward the snapped cell.
- Other machines get LocalTransparencyModifier 0.4 while the ghost is shown.

Validity:
- Placement.validate(snapshot.Placed + pending local entries, ..., snapshot.Build limits, ignore).
- Pending entries are dropped when BuildResult arrives. The server's answer always wins: on deny, toast + UIDeny + a 0.2 s ghost shake.

Controls:
- PC: mouse ray onto the plot plane, then cell, then clampOrigin. LMB places (drag paints belts; direction from the drag). R rotates. Click a placed machine to select it, then M moves and X or Delete packs it up. RMB or C cancels. WASD or RMB-drag pans, scroll zooms, B exits.
- Touch: a tap (<12 px, <0.3 s) moves the ghost or selects a machine. One-finger drag pans, pinch zooms. Buttons Rotate / Place / Move / Pack Up / Cancel / Done, all >= 64 px.
- Gamepad: left stick moves the cell cursor (0.25 s delay, 0.12 s repeat). A places, X rotates, Y moves or packs up the selected machine, LB/RB cycles the tray, right stick pans, LT/RT zoom, B goes back or exits.

After placing:
- Belts auto-advance one cell in their facing direction while you still have belts.
- Machines return to idle.
- Client throttle 6 requests/s. Seq increments per request.
- Fx 'Placed' and 'PackedUp' are registered for other players' builds; your own placement plays the Place sound and dust locally on Ok.

Auto-exit on death, respawn, plot loss, or moving more than 70 studs away. If the Cleaning Station is still unplaced, the BUILD button pulses.

### `/home/user/Perfect-Tap/src/client/UI/BuildView.luau` (new)
Pure UI builder for build mode.

API: BuildView.build(): Refs
BuildView.setInventory(refs, inventory: {[string]: number}, selected: string?, onPick: (id: string) -> ())
BuildView.setCounts(refs, machinesUsed, machineSlots, conveyorsUsed, conveyorSlots)
BuildView.setReason(refs, text: string?, kind: string?)
BuildView.setMode(refs, mode: 'Idle'|'Selected'|'Placing'|'Moving', isTouch: boolean)

- Bottom tray of cards in MachineData.Order: name, 'x2', category colour. Cards with a count of 0 are hidden.
- Top chip 'MACHINES 3/10 - BELTS 0/40'.
- Touch buttons at least 64 px.
- UIKit/Theme, and the Gui has the TerraForge attribute so UIScale applies. Original layout.

### `/home/user/Perfect-Tap/src/client/Effects/GridOverlay.luau` (new)
Client-only grid lines and plates for build mode.

API: GridOverlay.show(plotCFrame: CFrame)
GridOverlay.hide()
GridOverlay.plate(name: string, cf: CFrame, w: number, d: number, color: Color3?)

- 26 lines (48 x 0.05 x 0.08, transparency 0.55, no collide/query/touch/shadow) plus pooled plates, in Workspace.BuildClient.
- Created once and parented to nil when hidden, so it costs nothing outside build mode.

### `/home/user/Perfect-Tap/src/server/Services/ProcessingService.luau` (new)
ClayFurnace, BlastFurnace, Crusher and AutoCleaner behaviour.

API: ProcessingService.onProcessed(cb: (Player, machineId: string, input: Desc, outputs: {Desc}) -> ())

spawned:
- Attributes Queue=#In, QueueMax=4, OutCount=#Out, Working=false, Cycles=0, Status=''.
- IntakeService.addLoadPrompt(m, Info.LoadText, 0).

canAccept = MachineLogic.accepts(m.Id, desc, m.Entry, owner == m.Owner.UserId).
insert = push, then set Queue.

tick(m, now):
- If a job has finished (now >= State.JobEnd):
  - outputs = MachineLogic.outputs(id, In[1], rng:NextNumber()).
  - If #Out + #outputs > MaxOutBuffer: Status='OutputBlocked', wait.
  - Otherwise complete(entry, outputs), Cycles += 1.
  - Furnaces: Stats.IngotsSmelted += 1. When it first reaches 1, Notify 'Your first ingot! Sell it at Pell's Trading Post or forge it on an Anvil.'
  - Fire onProcessed.
- If idle and In is not empty:
  - JobEnd = now + max(MinProcessTime, MachineData.processTime(Info, data.Upgrades.Bellows)). Bellows is read at the start of each item.
  - Attributes Working=true, WorkStart=Workspace:GetServerTimeNow(), WorkTime, WorkOre=In[1].O.
- If idle and In is empty: Working=false.

Job progress is not saved; after a rejoin the job restarts (at most 8 s). MachineService's tick emits Out (the Crusher's 2 piles leave one tick apart). removed and moved need nothing.

### `/home/user/Perfect-Tap/src/client/Controllers/MachineFxController.luau` (new)
All machine juice from replicated attributes; no per-tick remotes.

API: 

Watches the 'Machine' tag with Added/Removed signals (streaming-safe). Every 0.5 s it picks machines within 80 studs, and only those get the RenderStepped work.

Working effects:
- Furnaces: Glow pulse, PointLight 1.2 -> 2.8, Embers 2 -> 14, ChimneyTop smoke 2 -> 6 (Blast 5 -> 12).
- Crusher: Roller1/2 and their Tooth parts spin at 6 rad/s in opposite directions.
- AutoCleaner: Drum and DrumRib spin at 3 rad/s, Vent smoke x3.
- Spinners recapture their base CFrame when GridX, GridZ or Rotation changes.
- One MachineHum loop on the nearest 4 working machines within 60 studs.

One-off effects:
- Queue goes up: Gulp + Dust at the Intake.
- Cycles goes up: MachineDone + Glint at the Output in the WorkOre colour, plus CameraShake 0.06 for your own machine within 25 studs.
- Crate Cycles: Gulp. Sell Chute Cycles: Coins flash.
- Anvil: ingot stubs on IngotSlot1..n from Ingots/IngotOre; glow while Forging.

Registers Fx 'Reject' (red Dust + Reject sound).

### `/home/user/Perfect-Tap/src/client/UI/MachineBillboard.luau` (new)
Progress billboard for YOUR machines only.

API: MachineBillboard.attach(model: Model): Refs
MachineBillboard.update(refs, progress: number, queue: number, queueMax: number, outCount: number, status: string, oreColor: Color3?)
MachineBillboard.detach(refs)

- Created lazily when Queue > 0 or Working is true, on the 'Status' attachment.
- MaxDistance 45; at most 12 at once.
- Shows a bar from (GetServerTimeNow()-WorkStart)/WorkTime, queue pips, a red FULL chip when Queue == QueueMax, and status text ('Output blocked', 'Too many loose items').

### `/home/user/Perfect-Tap/src/server/Services/EconomyService.luau` (new)
Minimal coin entry point that step e extends.

API: EconomyService.award(player: Player, amount: number, source: string): number
EconomyService.onEarned(cb: (Player, number, string) -> ())

- Floors the amount and ignores anything below 1 or above 1e7.
- Coins += amount, TotalEarned += amount, then DataService.changed.
- Returns the new balance (0 if data isn't loaded).
- ItemService.stash keeps its direct write (noted for step e).

### `/home/user/Perfect-Tap/src/server/Services/StorageService.luau` (new)
Storage Crate behaviour on the shared pool (data.Storage).

API: StorageService.capacity(player: Player): number  -- min(MaxStoredItems, StorageCrateCapacity * placedCrates)

Behaviour:
- canAccept: owner only ('Foreign'), a valid desc, and #Storage < capacity, otherwise 'Full'. 'Full' is toasted 'Your crates are full (60/60). Take items out or sell them.' at most every 5 s.
- insert: append {K,O,G,R} to data.Storage, Cycles += 1, DataService.changed.

Prompts:
- LoadPrompt 'Store Items' (order 0).
- 'OpenPrompt' 'Open Crate' (order 1, hold 0) -> OpenUI('Storage', {Machine=model}).

MachineService.onAction('StorageTake', {Key, Count}):
- Guard.table(arg,4); Key = ItemData.parseKey(string<=80); Count = int 1..StorageTakeMax.
- allowed = min(Count, freeHands + max(0, MaxLoose - LooseHeadroom - looseCount)). If 0, Notify 'Your hands are full and lots of items are lying around. Pick some up first!'
- For each item: remove the last matching entry, spawnDesc at the crate Output (offset 0.5 each), then CarryService.pickup while hands are free. If spawnDesc fails, put the entry back and warn.

CountSign:
- On DataService.onChanged and onLayoutChanged, set every crate's CountSign label to '{n}/{cap}'. Green under 80%, amber 80-99%, red when full or over capacity.
- Only write when the text changes.

removed needs nothing (the pool lives in data). StateService provider: StorageCapacity.

### `/home/user/Perfect-Tap/src/server/Services/SellService.luau` (new)
All selling: the Sell Chute, Pell's SellBin and the SellCounter. Always pays the item's owner.

API: SellService.sell(record, source: 'Bin'|'Counter'|'Chute'): number
SellService.sellDesc(ownerUserId: number, desc: Desc, position: Vector3, source: string): number
SellService.onSold(cb: (Player, Desc, number) -> ())

Selling:
- value = ItemData.value. If the owner's data isn't loaded, return 0 and leave the item.
- absorb, then EconomyService.award(owner, value, 'Sell'), Stats.ItemsSold += 1.
- Per-owner combo inside SellComboWindow: Fx 'Sold'(pos, total, count, bestRarityId) to the owner, and Fx 'SellPuff'(pos) near SellOthersRadius to everyone except the owner.
- If a batch contained Raw and Stats.ItemsSold < 40: Notify 'Tip: clean raw ore first, it sells for 2.5x more!' (at most every 60 s).

SellChute behaviour:
- canAccept = MachineLogic.accepts (any owner).
- insert = sellDesc(ownerUserId, ...), Cycles += 1.
- LoadPrompt 'Sell Items'.

SellBin: for each tagged SellBin, IntakeService.addZone('SellBin', its 'Intake' part, sell).

SellCounter:
- Server prompt 'SellPrompt', ActionText 'Sell What You Carry', ObjectText 'Pell the Trader', F/ButtonY, HoldDuration 0.3, distance 12.
- Sells everything carried (takeTop loop) and toasts 'Sold N items: +X coins'.
- With empty hands: Notify 'Bring items to sell! Pell buys raw ore, clean ore, ingots and gear.'

### `/home/user/Perfect-Tap/src/client/Controllers/StorageController.luau` (new)
Crate panel.

API: 

- Opens on OpenUI('Storage', {Machine}).
- Lists the State.Storage summary grouped by key, sorted by value: ItemData.displayName, rarity colour, count, value.
- Buttons Take (1, into your hands) and Take 5 send MachineAction(model,'StorageTake',{Key,Count}).
- Header shows StorageCount/StorageCapacity. Unknown keys are hidden. Live-updates from State.
- Closes on B, Backspace or the X button, when you are more than 14 studs from the crate, or when the model is gone.
- Gamepad selection through GuiService.SelectedObject.

### `/home/user/Perfect-Tap/src/client/Controllers/SellController.luau` (new)
Sell feedback.

API: 

Registers Fx:
- 'Sold': a '+N' billboard in the rarity colour (pool of 3) rises 3 studs over 0.9 s; a coin Burst of min(30, 6+count*3); CoinBurst + Sell sound pitched 1 + 0.05*min(count,8).
- 'SellPuff': a small gold Glint.

### `/home/user/Perfect-Tap/src/client/UI/StorageView.luau` (new)
Pure UI builder for the crate panel.

API: StorageView.build(): Refs
StorageView.setEntries(refs, list: {{Key: string, Name: string, Count: number, Value: number, Color: Color3}})
StorageView.setHeader(refs, count: number, capacity: number)

Scrolling grid: 6 columns on PC, 3 on phones. Buttons at least 56 px. At most 120 rows.

### `/home/user/Perfect-Tap/src/server/Services/ConveyorService.luau` (new)
Belt physics, rails, the walk-through collision group, and clearing jams.

API: 

- init: register the 'Conveyors' collision group, not collidable with 'Characters'.
- spawned and moved: Belt.AssemblyLinearVelocity = Belt.CFrame.LookVector * ConveyorSpeed. Belt, RailL and RailR go into CollisionGroup 'Conveyors'.
- onLayoutChanged: ConveyorLogic.openSides for that plot. Open rails get CanCollide=false and Transparency=1; closed rails are restored.
- IntakeService.setBeltHandler, with state in a weak table keyed by record. If the item is server-owned and slower than ConveyorStuckSpeed for ConveyorStuckSeconds, set its velocity to dir*7 + (0,1,0). After ConveyorMaxNudges within ConveyorNudgeWindow, push it off the side (Right*9 + Up*7). This clears head-on jams and wakes sleeping items.
- No client controller is needed: anchored-part velocity replicates.

### `/home/user/Perfect-Tap/src/server/Services/AnvilService.luau` (new)
Anvil: ingots of one ore in In, a server-checked hammering session, gear output.

API: AnvilService.onForged(cb: (Player, gear: Desc) -> ())

Behaviour:
- canAccept: Busy while a session is running, otherwise MachineLogic.accepts.
- insert: push; attributes Ingots and IngotOre.

Prompts:
- 'ForgePrompt' 'Forge' (hold 0, order 0): loads carried ingots that are accepted (takeTop loop). Needs In >= 1, otherwise Notify the WrongHint. Then a session starts.
- 'TakePrompt' 'Take Ingots' (hold 0.4, order 1): pops In ingots one by one to the Output (spawnDesc), then into your hands while they are free.

Session {Id=GUID, Player, Machine, StartedAt=os.clock()}:
- Attributes Busy=true, Forging=true.
- AnvilBegin {Id, Anvil, OreId, Grade (lowest), Count, Recipes = recipeOptions(#In), Timeout}.

AnvilSubmit(id, recipeId, strikes):
- The session must match. The session ends first, whatever happens next.
- recipeId must be in the options; validateStrikes(strikes, recipe.Hits, elapsed) must pass.
- Success: gear = MachineLogic.forge(entry, recipeId), then MachineService.emit. If 'Spawned', CarryService.pickup(player, rec) while hands are free. If 'Blocked', pushOut.
- Then Stats.GearForged += 1, Cycles += 1, AnvilResult {Ok=true, Recipe, OreId, Grade, Value, ItemId}.
- Failure: AnvilResult Ok=false with 'Something went wrong, your ingots are still on the anvil.'

AnvilCancel, AnvilTimeout (60 s), walking more than AnvilWalkAway (20) away (checked every 1 s), death and PlayerRemoving all end the session; the ingots stay.

removed (either reason) ends the session; MachineService.pickup drains In to Storage.

### `/home/user/Perfect-Tap/src/client/Controllers/AnvilController.luau` (new)
Recipe picker and hammering close-up.

API: 

On AnvilBegin:
- Validate the payload. PlayerControls.claim('Anvil'), InteractController.suspend(), PromptController.setSuppressed('Anvil', true).
- Camera to CamPoint (FOV 50, 0.5 s).
- Picker cards from Recipes: name, ingots and value preview (ItemData.value('Gear', ore, grade, id)). The option using the most ingots is highlighted.

Strike phase:
- A big STRIKE button (160 px), click or tap anywhere, Space, gamepad A or RT. Taps closer than 0.25 s apart are ignored locally.
- Every tap counts and records os.clock() - beginClock.
- A ring shrinks from 1.0 to 0.35 over 0.8 s; a tap in the 0.45-0.6 window shows 'PERFECT!' (bigger sparks), otherwise 'GOOD!'. Cosmetic only.
- Each strike plays AnvilClang with pitch +0.06 per hit, Sparks at AnvilPoint, CameraShake 0.12 (0.2 on PERFECT), and a client-only ingot flattening step by step.
- After recipe.Hits taps, send AnvilSubmit. A local gear preview spins, then the AnvilResult card appears and the controller exits after 1 s.

Back (B, Backspace or the Leave button) sends AnvilCancel. It also exits if the anvil streams out or you die.

### `/home/user/Perfect-Tap/src/client/UI/AnvilView.luau` (new)
Pure UI builder for the anvil.

API: AnvilView.build(): Refs
AnvilView.setRecipes(refs, list: {{Id: string, Name: string, Ingots: number, Value: number, Enabled: boolean}}, onPick: (id: string) -> ())
AnvilView.setRing(refs, scale: number)
AnvilView.setHits(refs, done: number, need: number)
AnvilView.popJudge(refs, text: string)
AnvilView.showResult(refs, result: {[string]: any})

STRIKE button 160 px. Original layout using UIKit and Theme.

### `/home/user/Perfect-Tap/docs/GAME_DESIGN.md` (modify)
Summary table kept in step with the configs (P0, same commit as the balance change).

API: 

Machines table:
- 'Queue: 4 items'
- Auto Cleaner '60% Rough / 40% Clean'
- Storage Crate 'crates share one store: 60 per crate, 300 max'
- Anvil 'holds 4 ingots of one ore; 3/4/5/6 hammer taps'
- Sell Chute 'pays the item's owner'
- Conveyor '7 studs/s, players walk through'
Replace 'take items from any side or the top' with: drop or throw items into the hopper on top, or run a belt into any side except the output front (crates and Sell Chutes take all sides); results go out of the front cell, straight into a machine standing there.
Add a Build controls table (PC / touch / gamepad).

### `/home/user/Perfect-Tap/docs/PLAN.md` (modify)
Step d row and QA (docs package).

API: 

- Step d row lists the new services and controllers.
- docs/STUDIO_CHECKLIST.md gets the step-d test list.
- docs/QA_REPORTS.md gets the qa-tester findings.
- Rebake build/TerraForge.rbxl via tools/build.sh, then run tools/check.sh.

## Remotes

- BuildPlace (existing, client->server, Rate 8/s, Burst 12, raised from 4/6 for belt painting): (seq: int 0..2^31-1, machineId: string<=32, x: int 0..11, z: int 0..11, r: int 0..3). The server replies with BuildResult.
- BuildMove (NEW, client->server, Rate 4/s, Burst 6): (seq, model: Model under the caller's Plot_N.Machines, x, z, r). Moves in place; refused while Busy; running jobs keep going. Replies with BuildResult.
- BuildPickup (existing, client->server, Rate 6/s, Burst 10, raised from 4/6): (seq, model: Model). The machine goes to MachineInventory and its In/Out go to Storage. Refused while Busy. Replies with BuildResult.
- BuildResult (NEW, server->client): {Seq: number, Op: 'Place'|'Move'|'Pickup', Ok: boolean, Reason: string? (a Placement.Reasons code), Id: string?, X: number?, Z: number?, R: number?}.
- MachineAction (existing, client->server, Rate 8/s, Burst 12): (model: Model, action: string<=24, arg: table?). Dispatcher checks: model in the caller's own plot folder, owner, within 14 studs. Step-d action: 'StorageTake' {Key: string<=80 'K|O|G|R', Count: int 1..5}. Unknown actions are ignored.
- AnvilSubmit (NEW, client->server, Rate 2/s, Burst 3): (sessionId: string<=64, recipeId: string<=32, strikes: {number} with exactly recipe.Hits entries). Checked with MachineLogic.validateStrikes. The session ends whatever the result.
- AnvilCancel (NEW, client->server, Rate 2/s, Burst 3): (sessionId: string<=64). The ingots stay on the anvil.
- AnvilBegin (NEW, server->client): {Id: string, Anvil: Model, OreId: string, Grade: string, Count: int 1..4, Recipes: {string}, Timeout: number}.
- AnvilResult (NEW, server->client): {Id: string, Ok: boolean, Reason: string?, Recipe: string?, OreId: string?, Grade: string?, Value: number?, ItemId: string?}.
- OpenUI (existing, server->client): ('Storage', {Machine: Model}), fired by the crate's OpenPrompt to the owner only.
- Fx (existing, server->client), new kinds:
- 'Reject'(pos: Vector3) to the item owner
- 'Sold'(pos, total: number, count: number, rarityId: string) to the owner
- 'SellPuff'(pos) via fireNear 60 to everyone except the owner
- 'Placed'(pos, machineId) and 'PackedUp'(pos, machineId) via fireNear 100 to everyone except the builder
Machine in/out juice needs no remote: it comes from replicated attributes (Queue, Cycles, Working...).
- Notify (existing): wrong-item hints (at most every 10 s per player per machine), 'didn't fit' relocation, crate full (every 5 s), storage-safe, first ingot, raw-sell tip (every 60 s), counter sale summary.
- State (existing): the snapshot gains Placed {{Id,X,Z,R}}, Build {MachineSlots, ConveyorSlots, MachinesUsed, ConveyorsUsed} and StorageCapacity.
- No remote for loading machines, opening crates, forging or Pell's counter: these are server ProximityPrompt.Triggered events.

## Data changes

DataTemplate.Version goes 1 -> 2. No new top-level fields.

1. PlacedMachines[i] = {Id, X, Z, R, In?, Out?}
- In is the input queue: In[1] is being worked, at most 4 (anvil ingots live here too).
- Out holds finished outputs waiting to leave: at most MachineData.MaxOutBuffer = 4.
- Both are lists of Storage descriptors {K, O, G?, R?}, set to nil when empty.
- Each runtime machine holds m.Entry, a reference to its table. Autosave, leave and BindToClose therefore save contents mid-job with no stash step, and a rejoin resumes them.
- Job progress is not saved; the job restarts, which costs at most 8 s.
- Older servers ignore In/Out and write them back unchanged, so a rolling update is safe.

2. MachineInventory = {[machineId]: int 1..999} (already in the template, now used)
- Only Placement.commitPlace lowers it (the key is removed at 0).
- commitPickup, sanitize displacement and the Studio dev kit raise it. The step-e shop will only add to it.
- Invariant per id: placed + inventory stays the same across place, move and pickup.

3. Storage = {{K, O, G?, R?}} (shape unchanged), now one shared pool for all crates.
- Player deposits (crate hopper, belts, Store Items) are limited to min(300, 60 x placed crates).
- System writes keep the 300 cap and pay full value beyond it, as today: ItemService.stash (loose cap, leaving), machine pickup drain, and sanitize spill.
- Removing the last crate never touches the pool.

4. Stats.IngotsSmelted, GearForged and ItemsSold start counting. Upgrades.Bellows and ExtraSlots are read (step e writes them).

5. Coins and TotalEarned change through EconomyService.award, except the existing stash-overflow payout.

Load pipeline:
- ProfileStore.reconcile, then DataService.migrate (purchase trim + Migrations.run: type clean-up, idempotent).
- On plot assignment, MachineService.spawnAll: StarterKit once, Studio in-memory dev kit, then Placement.sanitize (layout repair). Bad layout entries go to MachineInventory with one toast and are never deleted. Unknown Ids are kept untouched and not spawned. Slot limits are never enforced on load.

Leaving and shutdown:
- DataService.beforeRelease runs ItemService (stashes loose and carried items), then PlotService.release, then MachineService.remove(m,'Unload'). Unload writes no data; the Cleaning Station still stashes its vise item.
- The PlayerRemoving handler order doesn't matter, because Unload is data-free.

Size: 22 machines + 60 belts at about 40 B, plus 22 x 8 descriptors at about 30 B, plus 300 Storage entries at about 35 B, comes to under 25 KB.

Runtime-only (not saved): the Model attributes Working, WorkStart, WorkTime, WorkOre, Queue, QueueMax, OutCount, Cycles, Status, Ingots, IngotOre, Forging, Busy.

## Risks

- BIG REFACTOR. MachineService (entry link, In/Out, place/move/pickup, tick/emit) could break the Cleaning Station. Mitigation: CleaningService only gains a moved hook, and P1 is done only after a full cleaning-loop regression test (mine -> vise -> clean -> tray) plus rejoin.
- P0 and P1 run in parallel against signatures written in this plan. Mitigation: within its first hour P0 commits stub modules with the final exported signatures (bodies error 'not implemented'), so P1 can require them. P1 merges only after P0.
- Belt physics: anchored surface velocity can jitter light items or let them fall asleep. Mitigations: zero-bounce, high-friction belt; a nudge after 1.5 s of being slow; side-eject after 5 nudges in 30 s. Fallback if it still feels bad in Studio: AlignPosition riding (costs more).
- Client physics window: for up to 3 s after a drop the owner's client simulates the item. Mitigations: intakes ignore untrusted items (owner more than 40 studs away, or implausible travel), and items more than 90 studs from their release point snap back. What remains is a convenience exploit only; nobody gains coins or items against others (foreign items are refused, and Sell Chutes pay the item's owner).
- MaxLooseItemsPerPlayer=30 also counts belt items. Machine output pauses at 28 ('Too many loose items'), but player drops can still push the oldest item into Storage (with a toast). Revisit in step e: raise the cap or count belt items separately.
- Save format change (Version 2, In/Out) touches every profile. Mitigations: Migrations and sanitize are idempotent, Lune-tested, and never delete a known machine.
- WorldBuilder.Version 3 rebuilds the map at runtime until build/TerraForge.rbxl is rebaked. The docs/QA package rebakes; QA screenshots must be redone.
- The client ghost validates against a snapshot that can be up to 0.2 s old. The server decides. BuildResult carries Seq, and the client tracks pending cells so auto-advancing belts don't double-place.
- Touch gestures in build mode (tap vs drag vs pinch) are the most likely thing to feel bad on phones. Needs a real-device test; the 12 px / 0.3 s thresholds are config-free local constants that are easy to tune.
- Live players only have StarterKit machines until the step-e shop exists. The dev kit only runs when RunService:IsStudio() and DataService.isInMemory(), so testers must disable Studio API access (or set SaveInStudio=false). QA must check that it never fires in a published place.
- Mobile part budget: 8 plots x 60 belts x 6 parts = 2,880, plus machines at 40 parts or fewer. Mitigations: effects only within 80 studs, billboards only for your own machines (at most 12), the grid only in build mode, emitters idle when not working.
- About 2 prompts per machine. Mitigations: PromptController hides other players' prompts, and LoadPrompt only shows while you carry something. The server must never set LoadPrompt.Enabled.
- A hard crash (no BindToClose) still loses loose items in the world, as before. Machine contents and Storage survive up to the last autosave (120 s).
- Reward pacing: the first ingot sells for about 10 coins against a 200-coin pickaxe. Flagged for step e (tutorial reward, pricing).
- Sounds reuse built-in rbxasset files at new pitches. Real audio picks are listed in docs/ASSETS.md.

## Tests

- tests/Grid.spec.luau:
- Grid.dir(r) matches the LookVector of PlotService-style localCFrame for r 0..3.
- footprint swaps at r 1/3.
- localCFrame and cellFromLocal round-trip for all 144 cells.
- For every machine with an output and every rotation, Grid.outputCell equals the cell under the built model's Output attachment (MachineBuilder in Lune, PivotTo patch).
- tests/Placement.spec.luau:
- Bounds at every edge for each footprint (2x2 at X=11 and 3x3 at Z=10 are rejected).
- Overlap is detected; a move with ignore=self may overlap its own old cells.
- Limits 10/13/16/22 and 40/60; conveyors never use machine slots; a move never fails on slots.
- The StarterKit plus StudioDevKit.Layout validate together with no overlaps.
- commitPlace, commitMove and commitPickup keep placed+inventory constant per id; a failed commit changes nothing; no zero-count keys remain.
- sanitize: the 2nd of two overlapping entries goes to inventory, its In/Out spill to Storage, unknown Ids stay, and In of 6 is trimmed to 4 with 2 spilled.
- tests/ConveyorLogic.spec.luau:
- A straight line keeps both rails closed.
- A corner opens the receiving belt's correct side; a T-join opens both.
- A feeder into a furnace's side or back is detected; into its front it is not.
- Crates and Sell Chutes accept all faces; the Cleaning Station never gets a feeder.
- headOn pairs are listed.
- tests/MachineLogic.spec.luau:
- Accept rules per machine: Raw is refused by furnaces, a 5th item is 'Full', mixed ingots are 'Mixed', foreign items are refused except at the SellChute.
- Crusher gives 2 Crushed with the same grade; furnaces keep the grade.
- AutoCleaner over 10,000 seeded rolls gives only Rough or Clean, at 60/40 +/- 3%.
- forge gives the lowest grade and uses the first N; recipeOptions(1..4) is correct.
- validateStrikes rejects a wrong count, NaN or inf, non-increasing times, gaps under 0.18 s, a total under Hits*0.3 s, and times after elapsed+1.
- CONSERVATION FUZZ: 20,000 random push/complete/popOut/drain/forge steps with a seeded Rng. Units in equal units out by the recipe ratios plus what remains in In/Out; In <= 4 and Out <= 4 at every step.
- tests/Machines.spec.luau:
- Every MachineData id builds and has a Base PrimaryPart, Prompt and Status attachments, and an Intake with IntakeSize (except Conveyor).
- Every Output lies outside its own Intake box and 0.5 studs outside the footprint front, on a cell centre.
- Anvil has CamPoint, AnvilPoint and IngotSlot1..4.
- Conveyor has Belt, RailL (x<0) and RailR (x>0) and is at most 6 parts; other machines are at most 40 parts.
- tests/Migration.spec.luau: a v1 save with {'junk', {Id='Crusher',X=0/0,Z=1,R=5}, {Id='ClayFurnace',X=2.7,Z=3,R=-1,In={{K='Clean',O='Copper',G='Rough'},'bad'}}} and MachineInventory {Crusher=-1, Anvil=2.5} gives:
- the furnace at X=2, R=3 with In of 1
- Crusher back in inventory
- inventory {Crusher=1, Anvil=2}
- Version 2
Running it twice gives an identical result.
- tests/Config.spec.luau additions:
- machineSlots(0,false)=10, (2,false)=16, (2,true)=22; conveyorSlots(true)=60.
- storageKey and parseKey round-trip for every kind and grade; parseKey rejects junk and over-long input.
- GradeChances sum to 1 and never exceed MaxGrade.
- The Auto Cleaner's expected value is above the raw value and below a hand-cleaned Clean grade.
- processTime at Bellows 5 is >= MinProcessTime.
- Studio d1 (P0+P1):
- Join and the StarterKit appears; a full cleaning loop works; rejoin keeps the layout.
- In the command bar, write two overlapping PlacedMachines entries and rejoin: one machine is in inventory with a toast.
- The plot border has no rails inside the grid.
- Studio d2 (storage and selling):
- SellBin, SellCounter and Sell Chute pay exactly the hint value, with '+N' and coin burst juice.
- Another player's ore thrown into your chute pays them.
- The crate sign goes green, then amber, then red. Take puts items into your hands; Take 5 with full hands spills or explains.
- Packing a crate that holds 20 items leaves the pool intact and refuses deposits.
- Studio d3 (processing):
- Clean ore in the Clay Furnace (by throw and by Smelt Ore) gives an ingot in 6 s at the front cell.
- Raw ore bounces out with the hint. A 5th item waits in the hopper.
- Leave with 3 queued, rejoin, and they resume.
- Pick up the furnace mid-job: the toast and StorageCount show +3.
- Stop the server mid-job (BindToClose), rejoin, and the queue is intact.
- Walk 150 studs away and outputs keep flowing (server physics).
- Studio d4 (build mode):
- PC (B), phone emulation (button, tap then Place) and gamepad (DPadUp, stick, A/X/Y).
- Red ghost with a reason. A 3x2 rotated at the edge is clamped. Moving a smelting furnace keeps it smelting.
- Packing a Cleaning Station mid-session is refused.
- Placing on yourself lifts you on top. Belts auto-advance.
- Spamming BuildPlace and BuildMove from the command bar with NaN, 99, or another player's model: refused, no errors, rate-limited.
- Studio d5 (conveyors):
- A 5-minute soak of Auto Cleaner -> L-turn -> Crusher -> Furnace -> belt -> Sell Chute with no stuck or lost items.
- Corners open their rails. A belt into a furnace's front does nothing.
- Head-on belts clear themselves sideways. A Furnace facing a Crate stores the ingots.
- At 28 loose items the billboard shows 'Too many loose items'.
- Players walk through belts.
- Studio d6 (anvil):
- 2 Copper ingots + Tool Head + 4 taps: the gear lands in your hands.
- An Iron ingot is refused while Copper is on the anvil.
- Cancel, walking 20 studs away, death and leaving all keep the ingots.
- Packing the anvil mid-forge is refused.
- AnvilSubmit with fake strikes (0.01 s gaps) is rejected and the ingots stay.
- Item conservation in Studio: compare Storage + loose + carried + all In/Out totals before and after 100 random place/move/pickup/load cycles. They must be equal.
- Mobile performance (Device Emulator plus a real phone): a plot with 60 belts, 6 working machines and 30 moving items stays at 30+ FPS. MicroProfiler: IntakeService plus the MachineService tick stay under 0.5 ms per frame with 2 players and 30 belts.

## Work packages

### P0 Contracts (configs, Net, data, pure shared logic, models, tests) (order 0)
Owns: /home/user/Perfect-Tap/src/shared/Net.luau, /home/user/Perfect-Tap/src/shared/Config/GameConfig.luau, /home/user/Perfect-Tap/src/shared/Config/MachineData.luau, /home/user/Perfect-Tap/src/shared/Config/ItemData.luau, /home/user/Perfect-Tap/src/shared/Config/SoundConfig.luau, /home/user/Perfect-Tap/src/shared/Machines/Grid.luau, /home/user/Perfect-Tap/src/shared/Machines/Placement.luau, /home/user/Perfect-Tap/src/shared/Machines/ConveyorLogic.luau, /home/user/Perfect-Tap/src/shared/Machines/MachineLogic.luau, /home/user/Perfect-Tap/src/shared/Builders/MachineBuilder.luau, /home/user/Perfect-Tap/src/server/World/PlotBuilder.luau, /home/user/Perfect-Tap/src/server/World/WorldBuilder.luau, /home/user/Perfect-Tap/src/server/Data/DataTemplate.luau, /home/user/Perfect-Tap/src/server/Data/Migrations.luau, /home/user/Perfect-Tap/src/server/Services/DataService.luau, /home/user/Perfect-Tap/docs/GAME_DESIGN.md, /home/user/Perfect-Tap/tests/Grid.spec.luau, /home/user/Perfect-Tap/tests/Placement.spec.luau, /home/user/Perfect-Tap/tests/ConveyorLogic.spec.luau, /home/user/Perfect-Tap/tests/MachineLogic.spec.luau, /home/user/Perfect-Tap/tests/Machines.spec.luau, /home/user/Perfect-Tap/tests/Migration.spec.luau, /home/user/Perfect-Tap/tests/Config.spec.luau

First commit (within about 1 hour): every new shared module exists with its final exported signatures from the contracts. Bodies may error 'not implemented', so P1 can require them right away.

Then implement:
1. Net: add BuildMove, AnvilSubmit, AnvilCancel, BuildResult, AnvilBegin, AnvilResult. Set BuildPlace{8,12}, BuildPickup{6,10}, MachineAction{8,12}.
2. GameConfig: every new key listed in the GameConfig module entry, including StudioDevKit Layout {Crusher 4,9; AutoCleaner 0,10; BlastFurnace 7,8; Anvil 10,1; SellChute 2,1; all R=0} and Inventory {Conveyor=24, StorageCrate=1, SellChute=1, ClayFurnace=1}.
3. MachineData: LoadText, WrongHint, ConveyorFaces, AcceptsForeign, AutoCleaner GradeChances {Rough=0.6, Clean=0.4}, MaxOutBuffer=4, machineSlots and conveyorSlots.
4. ItemData: storageKey and parseKey.
5. SoundConfig: Gulp, MachineDone, MachineHum, Reject, CoinBurst, BuildRotate.
6. Grid, Placement, ConveyorLogic and MachineLogic exactly as specified. Pure; only shared Config, Vector3 and CFrame.
7. MachineBuilder:
- Output = Grid.outputLocal for Front-output machines; move the lips, chutes and furnace mouth with it.
- Status attachment on every machine. Anvil gets CamPoint and IngotSlot1..4.
- 6-part conveyor: Base, Belt tagged ConveyorBelt with CustomPhysicalProperties(0.7,1.2,0,100,100), RailL, RailR, 2 Arrow wedges.
- At most 40 parts per machine.
8. PlotBuilder: pad grid+2, rails and posts at +/-(half+0.5), pole at (half+1.5, half+1.5), PlotTile exactly the grid. WorldBuilder.Version = 3.
9. DataTemplate.Version = 2. New Migrations.run (type clean-up only, idempotent). DataService.migrate calls it.
10. GAME_DESIGN.md: machines table and intake rule (Auto Cleaner 60/40, queue 4, shared storage, anvil 4 ingots of one ore and 3-6 taps, chute pays the item's owner, belts 7 studs/s and walk-through), plus the Build controls table.
11. All specs listed in the tests, including the 20k-step conservation fuzz test and the check that StarterKit + StudioDevKit.Layout validate together.

Honour: contracts sections 1, 2, 4 and 5.
Done when `lune run tools/lune/test.luau` passes and the game still plays as before (rejoin keeps the StarterKit layout).

### P1 Core runtime (items, machine lifecycle, intake router, client hooks) (order 0)
Owns: /home/user/Perfect-Tap/src/server/Services/ItemService.luau, /home/user/Perfect-Tap/src/server/Services/MachineService.luau, /home/user/Perfect-Tap/src/server/Services/PlotService.luau, /home/user/Perfect-Tap/src/server/Services/IntakeService.luau, /home/user/Perfect-Tap/src/server/Services/CleaningService.luau, /home/user/Perfect-Tap/src/server/Services/StateService.luau, /home/user/Perfect-Tap/src/server/init.server.luau, /home/user/Perfect-Tap/src/client/init.client.luau, /home/user/Perfect-Tap/src/client/Controllers/FxController.luau, /home/user/Perfect-Tap/src/client/Controllers/PromptController.luau, /home/user/Perfect-Tap/src/client/Util/PlayerControls.luau

This is the BIG REFACTOR; it needs user approval before starting. Start in parallel with P0 against the contract text and P0's stub commit. Merge right after P0 and before any order-1 package.

ItemService:
- Add descOf, absorb, spawnDesc, storeDesc (rewrite stash on top of it with identical texts), looseList (a copy), looseCount via a byOwner index, isTrusted and eject.
- Add the ReleasePos and ReleasedAt fields.
- giveClientPhysics only within ClientPhysicsRange.
- Snap back items more than MaxItemTravel from their release point when the server takes physics back.

PlotService: footprintCFrame = plotCFrame * Grid.localCFrame; add plotAt and isNear.

MachineService: implement every function in contracts section 6, with the details in its module entry.
- spawnAll hooked in start().
- register back-fills spawned.
- StarterKit, then the Studio dev kit (IsStudio and isInMemory only), then Placement.sanitize with one toast.
- m.Entry is the saved table. place, move and pickup go through Placement.commit*.
- pickup drains In/Out to Storage via storeDesc.
- Unload touches no data.
- emit: direct handoff via ConveyorLogic.faceAllowed, back-pressure at MaxLoose-2.
- Tick loop every MachineTick (behaviour.tick + Out emission).
- The MachineAction dispatcher with its checks; layoutChanged coalesced with task.defer.

IntakeService:
- Per-plot cell index of hopper and feeder zones, rebuilt on layoutChanged.
- 0.2 s pure-maths loop over looseList: static zones, then trust check, then hopper or feeder insertRecord, then the belt handler, then foreign-item return after 8 s.
- react, hint throttle and addLoadPrompt as specified.

CleaningService: add the moved hook (re-mount the vise item); removed ignores reason.
StateService: summary via ItemData.storageKey.
init.server.luau and init.client.luau: the full ORDER lists from the plan.
FxController.register.
PromptController: LoadPrompt shown locally only while CarryCount > 0; setSuppressed via ProximityPromptService.Enabled; SellPrompt ObjectText 'Worth N coins'.
New src/client/Util/PlayerControls.luau with set, claim, release and owner (CleaningController is not edited).

Done when:
- d1 passes: join, StarterKit present, full cleaning loop, rejoin keeps the layout, an overlapping save gets repaired with a toast, dev layout machines appear in Studio in-memory sessions.
- No warnings other than 'missing service' for packages not merged yet.

### WP-Build Build mode (server authority + client placement) (order 1)
Owns: /home/user/Perfect-Tap/src/server/Services/BuildService.luau, /home/user/Perfect-Tap/src/client/Controllers/PlacementController.luau, /home/user/Perfect-Tap/src/client/UI/BuildView.luau, /home/user/Perfect-Tap/src/client/Effects/GridOverlay.luau

BuildService:
- Net.on BuildPlace, BuildMove and BuildPickup with the Guard checks in the contract order. Call MachineService.place, move and pickup, and reply with BuildResult {Seq, Op, Ok, Reason, Id, X, Z, R}.
- After a non-conveyor place, lift characters inside the footprint to the model top + 3 and loose items there to the top + 2.
- Fx 'Placed' and 'PackedUp' fireNear 100 to everyone except the builder.
- If the last crate is packed while Storage has items, Notify the 'items are safe' toast.
- StateService.addProvider: Placed (projection {Id,X,Z,R}) and Build {MachineSlots, ConveyorSlots, MachinesUsed, ConveyorsUsed}.

PlacementController, BuildView and GridOverlay as specified in their module entries:
- Scriptable overview camera, tap-then-Place on touch, auto-advancing belts, drag-painting on PC.
- Gamepad cursor on the left stick, controls R/X/Y/A/B.
- Client validity from Placement.validate on the snapshot plus pending entries; OUT plate from Grid.outputCell.
- PromptController.setSuppressed('Build'), PlayerControls.claim('Build').
- BUILD button added at runtime to HudController.refs().Menu; register Fx 'Placed' and 'PackedUp'.

Do not edit HudView, HudController, CleaningController, MachineService or Net.
Done when d4 passes on PC, phone emulation and gamepad, the command-bar spam test is clean, and the layout persists after rejoin.

### WP-Process Processing machines and machine juice (order 1)
Owns: /home/user/Perfect-Tap/src/server/Services/ProcessingService.luau, /home/user/Perfect-Tap/src/client/Controllers/MachineFxController.luau, /home/user/Perfect-Tap/src/client/UI/MachineBillboard.luau

ProcessingService registers ClayFurnace, BlastFurnace, Crusher and AutoCleaner with MachineService.register:
- spawned: attributes plus IntakeService.addLoadPrompt(m, Info.LoadText, 0).
- canAccept = MachineLogic.accepts with sameOwner. insert = push + Queue attribute.
- tick: job finish via MachineLogic.outputs/complete, respecting MaxOutBuffer (otherwise Status 'OutputBlocked'). Start the next job with the Bellows-scaled processTime (at least MinProcessTime). Set Working, WorkStart, WorkTime, WorkOre and Cycles.
- Stats.IngotsSmelted and the first-ingot Notify. onProcessed callbacks.
- MachineService emits Out; do not spawn items directly.

MachineFxController + MachineBillboard:
- Attribute-driven effects as specified (glow, smoke, spinners, hum on the nearest 4, Gulp on Queue up, MachineDone on Cycles up, anvil ingot stubs, chute coin flash, crate gulp).
- Billboards for your own machines only.
- Register Fx 'Reject'.
- Only machines within 80 studs; no per-frame work for far machines.

Done when d3 passes with the StarterKit Clay Furnace and the Studio dev-layout Crusher, Auto Cleaner and Blast Furnace, including leave/rejoin and BindToClose mid-job.

### WP-StorageSell Storage Crate, selling, economy entry point (order 1)
Owns: /home/user/Perfect-Tap/src/server/Services/EconomyService.luau, /home/user/Perfect-Tap/src/server/Services/StorageService.luau, /home/user/Perfect-Tap/src/server/Services/SellService.luau, /home/user/Perfect-Tap/src/client/Controllers/StorageController.luau, /home/user/Perfect-Tap/src/client/Controllers/SellController.luau, /home/user/Perfect-Tap/src/client/UI/StorageView.luau

EconomyService: award and onEarned as specified.

StorageService (StorageCrate behaviour):
- canAccept with the capacity min(300, 60 x crates). insert appends to data.Storage.
- LoadPrompt 'Store Items' and OpenPrompt 'Open Crate' -> OpenUI('Storage', {Machine}).
- MachineService.onAction('StorageTake') with parseKey, the hands/loose clamp, spawnDesc at the crate Output and CarryService.pickup. If spawn fails, put the entry back.
- CountSign updates only when the text changes. StateService provider: StorageCapacity.

SellService:
- sell and sellDesc pay the item's owner through EconomyService. Stats.ItemsSold. Combo Fx 'Sold' and 'SellPuff'. Raw tip.
- SellChute behaviour with AcceptsForeign and a LoadPrompt.
- IntakeService.addZone for every tagged SellBin's 'Intake' part.
- SellCounter 'SellPrompt' (hold 0.3) sells everything carried, with a summary toast.

Client:
- StorageController + StorageView crate panel (Take 1 / Take 5, closes at 14 studs, gamepad navigation).
- SellController registers Fx 'Sold' and 'SellPuff' (+N billboard pool, coin burst, pitched sounds).

Done when d2 passes, including another player's item in your chute paying them, and packing a crate keeping the pool.

### WP-Conveyor Belts (order 1)
Owns: /home/user/Perfect-Tap/src/server/Services/ConveyorService.luau

- init: register the 'Conveyors' collision group, not collidable with 'Characters' (players walk through belts).
- MachineService.register('Conveyor'):
  - spawned and moved: Belt.AssemblyLinearVelocity = Belt.CFrame.LookVector * GameConfig.ConveyorSpeed.
  - Belt, RailL and RailR get CollisionGroup 'Conveyors'.
- MachineService.onLayoutChanged: ConveyorLogic.openSides for that plot. Open rails get CanCollide=false and Transparency=1; closed rails are restored.
- IntakeService.setBeltHandler, with state in a weak table keyed by record. A server-owned item slower than ConveyorStuckSpeed for ConveyorStuckSeconds is nudged to dir*7 + (0,1,0). After ConveyorMaxNudges within ConveyorNudgeWindow it is pushed off the side (Right*9 + Up*7).
- Feeding machines is done by IntakeService (P1). Do not duplicate it.

Done when d5 passes: a 5-minute soak with no stuck or lost items, corners, head-on clearing, front-face not fed, walk-through.

### WP-Anvil Anvil forging (order 1)
Owns: /home/user/Perfect-Tap/src/server/Services/AnvilService.luau, /home/user/Perfect-Tap/src/client/Controllers/AnvilController.luau, /home/user/Perfect-Tap/src/client/UI/AnvilView.luau

AnvilService, MachineService.register('Anvil'):
- canAccept: 'Busy' while a session runs, otherwise MachineLogic.accepts (Ingot, same ore, at most 4). insert: push, attributes Ingots and IngotOre.
- ForgePrompt loads carried accepted ingots (takeTop loop), then starts a session (Busy and Forging true) and sends AnvilBegin {Id, Anvil, OreId, Grade, Count, Recipes, Timeout=60}.
- TakePrompt returns ingots to your hands.
- Net.on AnvilSubmit:
  - The session ends first.
  - Check the recipe is allowed and MachineLogic.validateStrikes passes.
  - Then MachineLogic.forge, MachineService.emit (pickup into hands if 'Spawned', pushOut if 'Blocked'), Stats.GearForged, Cycles, and AnvilResult.
- Net.on AnvilCancel. Timeout 60 s, walk-away 20 studs, death and PlayerRemoving all end the session; ingots stay.
- removed ends the session.

AnvilController + AnvilView:
- PlayerControls.claim('Anvil') and PromptController.setSuppressed('Anvil').
- CamPoint close-up, recipe picker cards with value preview.
- STRIKE button; every tap counts (client gap 0.25 s); cosmetic PERFECT/GOOD ring; clang, sparks and shake per hit; the ingot flattens.
- Submit after Hits taps, then the result card; Back sends AnvilCancel.

Done when d6 passes, including the fake-strikes rejection test.

### WP-Docs/QA Docs, rebake, QA pass (order 2)
Owns: /home/user/Perfect-Tap/docs/PLAN.md, /home/user/Perfect-Tap/docs/STUDIO_CHECKLIST.md, /home/user/Perfect-Tap/docs/QA_REPORTS.md, /home/user/Perfect-Tap/build/TerraForge.rbxl

After all merges:
1. PLAN.md: the step d row lists Grid, Placement, ConveyorLogic, MachineLogic, IntakeService, ProcessingService, StorageService, SellService, EconomyService, ConveyorService, AnvilService, BuildService and the controllers.
2. STUDIO_CHECKLIST.md: the d1-d6 Studio tests, the exploit checks, the conservation check and the mobile performance check from the plan. Include the dev kit note (disable Studio API access to get it) and a publish check that the dev kit never fires live.
3. Rebake build/TerraForge.rbxl with tools/build.sh (WorldBuilder.Version 3), run tools/check.sh, then do the qa-tester review (errors, exploits, DataStore safety, mobile performance) and record the findings in QA_REPORTS.md.
Do not edit GAME_DESIGN.md; P0 owns it.


## Plan scores

- **player-first:a-correctness** 7: Gaps it lists are real (checked in MachineBuilder/PlotBuilder). 2-wide Outputs sit on the cell seam (x=0). Anvil Output z=-3.6 is inside the footprint and Auto Cleaner z=-4 is on the edge. Rails, corner posts and the banner pole (cell 11,11) sit inside the 48x48 grid. The conveyor is 10 parts. Outputs are handed to far-away clients. Misses: (1) the init-order race (MachineService hooks onAssigned in init() before CleaningService registers); (2) belt feeding only checks items still on the belt cell, but an item pressed against a machine body often rests inside the machine's cell; (3) AnvilStrike 'N == done+1' deadlocks once a hit is dropped by the gap rule; (4) dropped items bounce out on 'Full' instead of waiting.
- **player-first:b-exploit-dup** 7: consume and insert are synchronous. isTrusted plus snap-back past 90 studs, foreign-owner rules and the StorageTake clamp are all good. Weak spot: queued and anvil items are runtime-only, so a crash loses up to 4 items per machine, and leaving depends on beforeRelease stashing them.
- **player-first:c-mobile-feel** 9: Strongest UX. Overview build camera, tap-a-cell then a big Place button, auto-advancing belts, Put In prompts, plain-language wrong-item hints, progress bar with queue pips, sell combo '+N', and the carried value shown on Pell's prompt.
- **player-first:d-parallel** 6: WP-A is huge (configs + Net + ItemService + MachineService + builders + tests). Order-1 packages depend on each other: E needs B's onBelt hook, F needs B's addLoadPrompt and D's PlayerControls. init files and HudView are spread across different owners.
- **player-first:overall** 7.3: Best player feel. Its UX, output-cell fix and plot-border fix are grafted into the final plan.
- **robustness-first:a-correctness** 8: Only plan that found the init-order race and the PlayerRemoving handler-order issue. Grid and output-cell math are consistent and outputs sit on cell centers. Downsides: it feeds any item lying within 3 studs above a machine cell (accidental feeding), refuses placement whenever a character stands in the footprint (bad in build mode), adds an extra BuildPlaceLine remote, and gives 6 starter conveyors, which goes against the brief.
- **robustness-first:b-exploit-dup** 9: Best. Machine contents are saved in the placed entry (In/Out), so they survive leaving and crashes up to the last autosave. Pure MachineLogic has a 20k-step conservation fuzz test. Also a plausibility check, foreign items refused except at the Sell Chute, and a dev grant that only works with in-memory saves.
- **robustness-first:c-mobile-feel** 6: Uses the normal character camera with a ray cursor on phones, refuses placement while you stand in the footprint, and has no prompt filtering. Anvil and billboards are fine.
- **robustness-first:d-parallel** 5: WP-E builds a temporary router that WP-F later deletes from WP-E's file. One feature package owns FxController for everyone's Fx kinds. Long dependency chain B -> D -> E -> F.
- **robustness-first:overall** 7: Best data-safety design. Grafted: In/Out persistence, init-order fix, direct machine-to-machine handoff with back-pressure, conservation fuzz test, EconomyService, Seq on build remotes.
- **build-first:a-correctness** 7: Best intake geometry: feeder boxes indexed on both the belt cell and the target cell, using pure cell-bucketed math. Reuses the existing Busy attribute. Pure Migrations module. FxController.register and a runtime BUILD button fit the current code. Misses: keeps 2-wide outputs on the cell seam (only moves Anvil and AutoCleaner z), so 1x1 belts can't catch them. Its ConveyorController duplicates belt velocity that already replicates. Items held in ServerStorage are runtime-only.
- **build-first:b-exploit-dup** 8: Pure place/move/pickup ledger (commit*) with invariant tests, idempotent migration, owner-proximity trust, foreign items returned after 8 s, and a strike-list validation that is immune to latency. Held items are lost on a crash.
- **build-first:c-mobile-feel** 7: Players walk through belts, effects are driven by attributes, and the submit-at-end anvil is latency-proof. But the build cursor relies on the character camera (weak on phones), missed anvil strikes don't count (frustrating for kids), and the Put In prompt isn't filtered.
- **build-first:d-parallel** 9: Best structure. Phase 1 is split, Phase 2 packages own disjoint files, every hotspot has a single owner, ORDER lists are edited once, and missing services only warn.
- **build-first:overall** 7.8: Chosen as the base. Fixes grafted in: cell-centred outputs (player-first), saved machine contents (robustness), the overview build camera, and taps that always count.