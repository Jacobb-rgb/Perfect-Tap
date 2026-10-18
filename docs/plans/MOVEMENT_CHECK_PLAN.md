# Movement check and beam line of sight (design note, 2026-10-18)

From the security audit (docs/SECURITY_AUDIT.md #3, #12): every range check trusts the client's character position and
the mining beam has no line-of-sight test. A teleporting bot farms rocks and chunks without walking. This note proposes a
light, false-positive-safe check. Nothing here is built yet; the integrator decides.

## Goals
- Stop teleport / speed farming bots from mining and picking up far away.
- **Never punish a real player**: lag spikes, server teleports, falling, trains, elevators, hoverboards, respawns.
- Cheap: no per-frame server loops over parts; one small table per player.

## Movement check (server)
- **Sample** each character's HumanoidRootPart position every 0.3 s (one loop over players, not parts).
- **Allowed distance** between two samples:
  `maxSpeed * dt + slack`, where `maxSpeed` = the highest legitimate horizontal speed (walk 18, hoverboards up to the
  mine chat's fastest board, train ride, express belts carry nothing but items), `slack` = 6 studs (lag, physics push).
  Vertical: falling is free (any downward move); upward moves allowed up to jump height + 4.
- **Grace windows** (the check is skipped, the sample just resets):
  - 2 s after any server move of the character: TeleportService, PlotService.sendHome, BuildService lift-out,
    AccessService push-out, elevator rides, respawn (CharacterAdded). One shared `Movement.serverMoved(player)` call
    that every PivotTo site makes.
  - while seated (trains, benches) and while the Humanoid is in FallingDown / Ragdoll.
  - the first 5 s after joining (streaming, loading).
- **On a violation** (one sample over the limit):
  1. count it; 3 violations within 10 s = "flagged" for 30 s;
  2. while flagged, the **trusted position** for range checks is the last good sample, not the live one, so mining and
     pickups far from it simply fail (no visible punishment);
  3. after 5 flags in 5 minutes, a soft pull-back to the last good sample (PivotTo) and a server log line with the
     player id. **Never kick automatically** (false positives must not cost players their session).
- **Range checks** (MiningService, CarryService pickup, Intake "owner near", AccessService) read
  `Movement.trustedPosition(player)`; when not flagged it is the live position, so honest players see no change.

## Beam line of sight (MiningService)
- Every 0.5 s per firing player: one `Workspace:Raycast` from the character's head to the target rock's nearest point,
  excluding characters, items and the rock itself. Cache the result per (player, rock) for 0.5 s.
- Blocked → the beam deals no damage this tick (the client still draws its beam; no toast).
- The quarry/cave walls are the only blockers that matter; thin decorations (lamps, fences) should be in a
  "BeamIgnore" collision group or tagged so they never block.

## Integrator review (2026-10-18): approved with these changes
1. `maxSpeed` per player, read on the server: the Humanoid's current WalkSpeed (Miner's Boots up to 26, Gear sets it
   server-side) + the active hoverboard's speed (`HoverboardService.speedOf(player)` from the mine chat) × 1.15;
   unknown boosts fall back to the maximum.
2. Grace / slack also for: the Blaster Vault crate-opening stage (check whether it moves the character), the mine
   elevator and the teleport bar (server PivotTo → `serverMoved`), standing on belts (Express Conveyors carry players:
   add belt speed to the slack, or skip while standing on a part tagged as a belt). Wheel / capsule screens and the
   tutorial beam don't move the character.
3. Jump: read the Humanoid's JumpPower / JumpHeight, not a constant.
4. LOS: MineFloors and Vault-interior decorations go on the BeamIgnore list; a rock flush against the quarry wall must
   stay mineable (tested).
5. Rollout unchanged: logging → trusted position → pull-back only after the logs. Built after the steps 6–7 landing,
   on the new main, with tests; ping before merging.

## Tests (Lune, pure)
- Movement: allowed distance per dt and speed; grace windows (server move, seated, joining); violation counting and
  flag expiry; trusted position while flagged; never a kick.
- LOS: a blocked ray zeroes the damage tick; cache expiry; ignored tags.

## Rollout
1. Ship with logging only (no trusted-position switch) for a few days and look at the flag rate of real players.
2. Turn on the trusted position; keep the pull-back off until the logs show no honest flags.

## Built (rollout step 1, 2026-10-18)
Logging only: nothing a player does is refused or moved because of the movement check yet. The beam line of sight is on.

**Files**
- `src/shared/Config/MovementConfig.luau`: every number and the switches below.
- `src/server/MovementLogic.luau`: the pure rules (no Roblox services; the Lune tests drive it).
- `src/server/Services/MovementService.luau` (ORDER: after ToolService): one loop over `Players` every 0.3 s reads
  `HumanoidRootPart.CFrame.Position`, `Humanoid.WalkSpeed` (the server sets it), JumpPower / JumpHeight (UseJumpPower,
  `Workspace.Gravity`), SeatPart / Sit and the FallingDown / Ragdoll / Physics states. API: `serverMoved(player)`,
  `isFlagged(player)`, `trustedPosition(player)`, `rangeOrigin(player, livePosition)`, `stats()`.
- `src/server/BeamSight.luau`: the beam's line of sight (cache, raycast filter, BeamIgnore). MiningService asks
  `BeamSight.canHit` before a damage tick and measures the range from `MovementService.rangeOrigin` (live while
  Enforce is off).
- Blaster Vault interior (`World/Lobby/Vault/init.luau`): its raycastable interior parts (the case steps, the counter)
  carry the `BeamIgnore` tag at build time (part count unchanged; map v26).
- Tests: `tests/Movement.spec.luau`, `tests/MiningLos.spec.luau`.

**Switches** (MovementConfig)

| Switch | Now | Meaning |
|---|---|---|
| `Enforce` | false | false: `trustedPosition` / `rangeOrigin` give the live position. true: while flagged, the last good sample. |
| `PullBack` | false | Step 3, not built: must stay false. |
| `BeamLos` | true | No beam damage through walls. |

**How it decides** (the note above, plus what the review and the tests needed)
- Allowed per sample: horizontal `maxSpeed * dt + 6`, `maxSpeed = (WalkSpeed + hoverboard) * 1.15` (the higher of the
  two samples); upward `jumpHeight + 4 + maxSpeed * dt` (the last term: stairs and ramps); falling is free. Unknown
  walk speed = 50, unknown board = 38 (Royal Phoenix).
- Belts: players walk through belts today (the "Conveyors" collision group ignores characters), so the belt term is a
  safety net: only a move over the limit casts one ray down; a part in the "Conveyors" group adds the fastest belt
  (14 studs/s) to the speed.
- Start over (sample and anchor reset): first sample, a new character, 2 s after `serverMoved`, first 5 s after
  joining. Skip (no check): seated; FallingDown / Ragdoll / Physics for at most 4 s per 30 s (the client reports its
  Humanoid state, so a faked state can't exempt anyone for long).
- 3 violations in 10 s = flagged 30 s; 5 flags in 5 min = one `warn` line with the UserId. Never a kick, never a move.
- "The last good sample" is an anchor that only moves to a sample reachable from it in the time since: a teleport
  leaves it behind until walking there would have taken that long (standing still at the far rock doesn't reset it).
- Hoverboards: the character attribute `Hoverboard` (set by the server while riding) adds
  `HoverboardService.speedOf(player)` once that service exists, else 38. On art/mine-floors the board speed is also
  the Humanoid's WalkSpeed, so it counts twice: lenient on purpose.
- Line of sight: every 0.5 s per (player, rock), from the Head (else root + 1.5) toward the rock's box: its closest
  point, then (only if that is blocked) the line to its top center (a rock up on a ledge); each line stops 1.5 studs
  before the rock, so the quarry wall right behind a rock never counts. Never blocking: characters, Items, Debris, the
  rocks folder, BeamIgnore tag (filter) or attribute (cast on behind it), CanCollide off, CanQuery off, water.

**Server moves covered** (every `character:PivotTo` calls `MovementService.serverMoved` right after; a test scans
src/server for new ones): TeleportService.luau:194 (teleport bar + elevator destination), PlotService.luau:168
(sendHome, also after every respawn), BuildService.luau:138 (lift-out of a machine footprint, any player),
AccessService.luau:35 (VIP Grotto door push-out), respawns (CharacterAdded in MovementService). The Blaster Vault crate
opening, the wheel / capsule screens and the tutorial don't move the character.

**When art/mine-floors lands** (not on main yet)
- ElevatorService `teleport()` (rides and fall rescues): `MovementService.serverMoved(player)` after
  `character:PivotTo(target)` (the scan test fails until then).
- HoverboardService: `function HoverboardService.speedOf(player: Player): number local board = HoverboardData.get(riding[player]) return if board then board.Speed else 0 end`.
- MineKit: `m:AddTag(MovementConfig.BeamIgnoreTag)` on the models of `MineKit.elevator`, `MineKit.gate` and
  `MineKit.crystals` (the SOLID decorations; walls stay untagged); bump the map version.

**Step 2 one-liners for the other owners** (turn `Enforce` on after a few days of logs). Each file also gets
`local MovementService = require(script.Parent.MovementService)` (it requires no services: no cycles). While
Enforce is off `rangeOrigin` returns the position passed in, so nothing changes before the switch.
- CarryService `hasReach`: `local distance = (record.Body.CFrame.Position - MovementService.rangeOrigin(player, root.Position)).Magnitude`
- ItemService `isTrusted`: `if (MovementService.rangeOrigin(Players:GetPlayerByUserId(record.Owner), root.Position) - position).Magnitude > GameConfig.AntiTeleportRange then`
- ItemService (LastNearOwner): `if root and (MovementService.rangeOrigin(Players:GetPlayerByUserId(record.Owner), root.Position) - position).Magnitude < 40 then`
  (`giveClientPhysics` keeps the live position: network ownership needs the real one.)
- PenService `isNear`: `local offset = MovementService.rangeOrigin(player, root.Position) - gate`
- PodiumService `isNear`: `local offset = MovementService.rangeOrigin(player, root.Position) - orePoint(plotId, slot).Position`
- TrainService `isNear`: `return root ~= nil and (MovementService.rangeOrigin(player, root.Position) - position).Magnitude <= range + RANGE_SLACK`
- MachineService (MachineAction range): `if not root or (MovementService.rangeOrigin(player, root.Position) - machine.Model:GetPivot().Position).Magnitude > GameConfig.MachineUseRange then`
- CleaningService (auto-start when the owner is close): `if root and (MovementService.rangeOrigin(machine.Owner, root.Position) - (base :: BasePart).Position).Magnitude < 22 then`
- ProcessingService, LogisticsService: no character range check, nothing to change.
- Net.luau: nothing for the movement check (audit #9, separately: `if player.Parent ~= Players or not allow(player, name, limit :: Limit) then` in `Net.on`).
- Optional, same pattern: the shop counters' `counterNear` (Sell, Shop, Vault, Gear, Enchant) and Foundry `isNear`.
