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
