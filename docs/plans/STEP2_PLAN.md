# Step 2 plan (design v2): your own ore train

Part of docs/plans/V2_PLAN.md. Owner's words (DESIGN_V2_NOTES): trains only carry ore from the mine to your base;
you throw ore chunks into a cart at the mine's train station; **every player has their own little train**; at the
base it dumps the ore into the **Ore Pen**; train upgrades for coins, plus a one-time **~150–200 R$** upgrade sign at
the base. Later (step 3) a pen upgrade lets the train dump raw ore straight into the Cleaning Plant.

## Player view
1. Mine in the quarry → carry the dirty chunks to the **Mine Station** at the bottom of the quarry ramp → throw them
   into the station hopper (or "Load Train" while carrying). Your cargo counter fills ("Your train: 6/8").
2. The train leaves when it is full, when you press **Send Train** (prompt + button), or 25 s after the last load.
3. Your little locomotive (your plot's banner color) with an ore wagon rolls out of the station into a tunnel in the
   quarry wall, comes out of a tunnel at the south coast, runs along the **coastal railway** behind the bases and
   stops at your **Train Stop**; the wagon tips and the ore pours into your **Ore Pen**. Then it rolls back.
4. Deep zones have **Mine Lifts** (Ember Caves, Deep Hollow): throw ore in there and it goes up into your train's
   cargo too, so nobody has to carry chunks all the way out of the caves.
5. Upgrades: cargo (8 → 12 → 18 → 26 → 36 → 50) and speed (trip 30 s → 12 s) for coins at the station's
   "Train Upgrades" panel (moves into the Tech shop in step 6); the **Express** perk (Robux, sign at the base)
   doubles speed and adds +50 % cargo.

## World
| Piece | Where (world studs) | Notes |
|---|---|---|
| Mine Station | quarry floor y = -12, platform x -12..30, z -152..-146, hopper at (20, -12, -149) | east of the ramp bottom (ramp: x -8..8, z -112..-140) |
| Quarry track | z = -156 from x -72 to 72 (both directions) | ends in tunnel portals in the west and east quarry walls; KeepOut box x -74..74, z -162..-143 so rocks never grow on it |
| South portals | (±166, 0, 126), facing north | rock hill + timber portal; trains come out here |
| Coastal railway | x = ±166 (plot-local z 62 = BaseLayout.RailZ) from z 126 north to a buffer stop at z -100 | stops at z = 84, 28, -28, -84 (each plot's TrainStop); stays clear of the NEXT AREA gate/boardwalk (z -118..-112) |
| Mine Lifts | Ember Caves near the entrance (0, -12, -252); Deep Hollow at the ramp bottom (0, -40, -398) | small lift cage + hopper + "LIFT" sign |
| Express sign | each yard, next to the Train Stop | "EXPRESS TRAIN 199 R$" placeholder |
Rails are built from data (a polyline per line) by `src/server/World/Railway.luau` (sleepers every 6 studs, two rails,
<= ~450 parts in total), called from WorldBuilder (Version + 1).

## Data (save Version stays 3, new record field)
`Train = { Cargo = { Desc }, CapacityLevel = 0, SpeedLevel = 0, TripDepartAt = 0, TripArriveAt = 0, TripCargo = { Desc } }`
- Cargo = items loaded, waiting at the station. TripCargo = items on the moving train (saved, so leaving mid-trip
  never loses ore: on the next join, a trip whose arrival time has passed is delivered at once).
- Delivery goes into data.Storage up to the pen capacity; the rest stays in TripCargo, the train waits at the stop with
  a "Pen full" sign and retries every few seconds (toast once).

## Config: `src/shared/Config/TrainConfig.luau`
Capacity levels + prices, speed levels (trip seconds) + prices, AutoDepartSeconds 25, Express multipliers, track
polylines (quarry line, west/east coastal lines), stop z per plot, portal positions, visual timeline shares
(quarry leg 0–15 %, underground, coastal leg 70–95 %, unload 95–100 %), part budgets (locomotive <= 60, wagon <= 20).

## Packages
### WP-TrainCore (server + data)
Owns: TrainConfig.luau (new), src/server/Services/TrainService.luau (new), DataTemplate (Train field), Migrations
(Train sanitize), Net (TrainAction: "Send" | "Upgrade" {Kind}), StateService provider (cargo, capacity, trip times),
tests/TrainService.spec.luau. Intake zones (IntakeService.addZone) for the station hopper and the lifts: owner's
Raw/other items into Cargo (full → bounce + toast); "Load Train" prompt for carried items; trips with server time;
delivery into the pen (PenService/ItemService capacity rules); upgrades with EconomyService.spend; Perk TrainExpress.
Fire "TrainTrip" (see the shared contract below) to all players on depart (and a list to joiners).

### WP-TrainWorld (map + models)
Owns: src/server/World/Railway.luau (new), src/shared/Builders/TrainBuilder.luau (new, Kenney Train Kit style from
parts: chunky locomotive with big round lamps, cow-catcher, chimney, cab; ore wagon whose load shows the cargo's ore
colors; colors from the plot banner), WorldBuilder.luau (call Railway, Version + 1), WorldLayout.KeepOut (quarry
track box), tests/Railway.spec.luau, preview scene `trains`.

### WP-TrainClient (visuals + UI)
Owns: src/client/Controllers/TrainController.luau (new), src/client/UI/TrainView.luau (new). Animates every trip
on the client from "TrainTrip" (CFrame along the polylines, smooth acceleration, puffs of steam, wheels turning,
the wagon tipping into the pen, a soft whistle), only for trains within ~250 studs; HUD chip "Train 6/8 · Send";
station panel with cargo, Send, upgrades (all inputs, phone layout).

## Shared contract (server ↔ client)
What TrainService (server), Railway (world) and TrainController / TrainView (client) rely on. Change both sides together.

**"TrainTrip"** (Net.fireAll; a joining player gets a list of everyone else's trains that carry ore):
`{ UserId, PlotId, DepartAt, ArriveAt, Count, Color, Load, Waiting? }`. Times are server time
(`workspace:GetServerTimeNow()`); Color = the plot banner; Load = ore colors (`{}` = all dirty ore: the client shows its
own dirt colors). Count / Color / Load stay what was sent at departure. Clients refuse a trip with
ArriveAt - DepartAt > MaxTripSpan (600 s). A TrainTrip with the same DepartAt is the same train again (no rebuild).
- **Waiting** (optional, only ever `true`): the train stands at its stop because the Ore Pen is full. When the first
  unload try leaves ore on the train, everyone gets the TrainTrip **again** with the same times and `Waiting = true`
  (also in a joiner's list and when a rejoining player's waiting train is announced). Clients keep it standing there
  loaded: no tip, no way back, never sent away by the client's HoldLimit.
- **Late unload**: once the pen takes the rest, the TrainTrip is **re-sent once more** with `ArriveAt` = the unload time
  and no Waiting (DepartAt kept, or moved so the trip stays within MaxTripSpan; the same standing train), right before
  Fx "TrainUnload". Whichever of the two reaches a client first starts the tip and the way back; the train is back at
  the station ReturnSeconds after the unload.

**Fx**: "TrainUnload" (plotId, count) to everyone when a train really unloads (never while it waits); "TrainLoad"
(position) to players near a hopper that took ore.

**State snapshot** `Train = { Cargo, Capacity, Moving, DepartAt?, ArriveAt?, CapacityLevel, SpeedLevel,
NextCapacityPrice?, NextSpeedPrice?, Express, TripSeconds, AutoDepartIn?, Waiting }`. Moving > 0 = ore on board (on the
move or waiting at the stop): the station shows no train. `Waiting = true` only with Moving > 0 after ArriveAt (clients
also treat Moving > 0 two seconds after ArriveAt as waiting); the chip then says "Pen full – make room" (TrainView phase
"Waiting", no Send). After the unload ArriveAt is the unload time and the train is back at ArriveAt + ReturnSeconds.

**Prompt slots** (TrainService.PromptSlots; UIOffset = (0, Slot × 72), the machine prompts' step) on the `PromptPoint`
attachment of the Mine Station (tag "TrainStation") and every Mine Lift (tag "MineLift"):

| Slot | UIOffset | Name | Action text | Keys | Owner |
|---|---|---|---|---|---|
| 0 | (0, 0) | TrainLoadPrompt | Load Train | F / gamepad Y | server; tag "TrainPrompt", attributes Action = "Load", Slot = 0 |
| 1 | (0, 72) | TrainSendPrompt | Send Train | G / gamepad B | server; tag "TrainPrompt", attributes Action = "Send", Slot = 1 |
| 2 | (0, 144) | TrainPanelPrompt | Train (opens the panel) | T / gamepad L3 | client, local and untagged |

No prompt may stay at another slot's offset. The server never changes Enabled after creating its prompts; the client
enables Action "Load" prompts only while the player carries something (CarryCount > 0), refreshed on CollectionService's
added signal, PromptShown and CarryCount changes. A Load press with empty hands only gets a throttled hint.

**World**: hoppers are BaseParts tagged "TrainHopper" under Workspace.Map.Railway (IntakeService zones).
TrainConfig.PortalInset (the quarry tunnel mouths, in front of the quarry line's ends) and TrainConfig.BufferGap (the
buffer stops' face, past the coastal lines' ends) are used by Railway and the client alike.

## Done when
Mine → throw into the station hopper → train leaves → (visible in the quarry, then on the coast) → ore lands in the
pen; rejoining mid-trip delivers; pen full is handled; upgrades work; QA (dup via cargo/pen, trip time tampering,
intake from other players' items) passes; preview pictures of the station, the coastal line with a train and the
unload at a base.
