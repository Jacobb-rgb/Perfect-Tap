# Shopkeepers (owner 2026-10-24)

Owner, in order: "cool characters behind the counters of all shops" → his avatar → his 3D miner → (final) **"big
golems serve our shops: take a golem and just make it bigger, each shop a different cool golem, with emotes in front
of the stall, e.g. waving"**. None at the EGGS temple. Branch `feat/shopkeepers` (from main `ecf24f90`).

## Who serves where
| Shop | Golem (GolemConfig) | Size | Why |
|---|---|---|---|
| SHOP (Gear) | Dragonscale Knight `ScaleKnight` | 1.6 | armour, sword and shield: the gear shop |
| UPGRADES (Tech) | Storm Sentinel `StormSentinel` | 1.35 | storm armour and a lightning spear: tech |
| SELL | Flamewing `Flamewing` | 1.5 | small wings, goggles: fits the narrow stall |
| ENCHANT | Aether King `AetherKing` | 1.4 | halo, wings, a staff and orb, floats on clouds: magic |
| BLASTER VAULT | Dragon King `DragonKing` | 1.45 | the Mythic king for the best shop |
| DROPPERS (when it lands) | Magma Wyvern `MagmaWyvern` | 1.3 | |
| BACKPACKS (when it lands) | Sky Sprite `SkySprite` | 1.5 | |

## How it works
| Piece | File | What |
|---|---|---|
| Spots | `ShopkeeperConfig.mark(counter, feet, shop)` in the lobby builders | an **Attachment** on the counter (tag `ShopkeeperSpot`, attribute `Shop`), frame = the golem's feet, LookVector = the customers. No parts: no budget change; it streams with its counter. SHOP, UPGRADES, ENCHANT and the VAULT stand their golem on a step the counter hides (1.0-1.6 up), so its big head shows over the goods |
| Golem | `src/shared/Builders/GolemKeeper.luau` | `GolemBuilder.build(kind, feet, {Size})`: the game's own golem, bigger, tagged `NoStuds`; the rig sorts its parts: Right / Left arm (Arm, Fist, Bracer, BracerGem, Claw), RightHeld / LeftHeld (sword, shield, spear, staff + orb, lance: they follow the fist upright), Ground (aura, cloud floor, flame ring: they stay down), Body; `frames(rig, feet, pose, yaw)` = every part's CFrame |
| Emotes | `src/shared/Moves/GolemEmotes.luau` | pure poses: idle breath and sway, Wave, Hop, Spin, Dance, Bow, Cheer |
| Golems in the game | `src/client/Controllers/ShopkeeperController.luau` | builds a golem while the player is within 90 studs, removes it past 110; within 60 studs it moves (one `BulkMoveTo` for all golems each frame): turns toward the player (±35°), waves + hello bubble when the player walks up (25 s cooldown), cheers + thanks + gold burst after a buy (Notify `Reward`) or a sale (Earned `Sell`), and every 6-12 s hops, spins, dances, bows or waves by itself. One soft light, on the nearest golem only (phones: the game's light budget) |
| Numbers, lines | `src/shared/Config/ShopkeeperConfig.luau` | golems, sizes, distances, timings, hello / thanks lines |

The five blocky keepers (Outfitter, Forgemaster Ulda, Tobin, the Enchanter, the Blastsmith) are gone from the map.
Texts still say "Tobin paid ..." (SellService): a rename is the owner's call. The earlier miner version (the owner's
glb rebuilt in parts) is in the branch history (d44bf008, f99fd5bc).

## For the branches that land later
- **DROPPERS** (`art/hoppers`) and **BACKPACKS** (`art/backpacks`): add one line in their counter builder,
  `ShopkeeperConfig.mark(counter, <feet behind the counter, facing the customers>, "Droppers" | "Backpacks")`.
  Their golems and lines are already in `ShopkeeperConfig.Shops`; add the shop to `tests/Shopkeepers.spec.luau`'s list.
- Map version: 57 here so it can't clash with 53-56; renumber when merging.

## Preview
`lune run tools/lune/export_scene.luau shopkeepers [Wave|Cheer|Dance|...]` (the world, each golem on its spot, posed
at the emote's peak) or `shopkeeper_solo [emote]` (the five in a row), then
`SHOTS_EXTRA=tools/preview/shopkeeper_shots.json node tools/preview/render.mjs shopkeepers keeper_gear keeper_tech
keeper_sell keeper_enchant keeper_vault` / `shopkeeper_solo golems_row golem_close_gear golem_close_vault`.

## What to test in Studio
1. Press Play. A big golem stands behind the SHOP, UPGRADES, SELL, ENCHANT and Vault counters, each a different one,
   no studs on them; none at the EGGS temple.
2. Each breathes and sways, turns toward you when you are near; walk up: it waves (a sword, spear or staff goes up)
   and a bubble says hello; buy something / sell ore: it cheers, says thanks and throws gold sparkles; wait near one:
   every few seconds it hops, spins, dances or bows.
3. Prompts (E) at every counter still work (the golems block no clicks or prompts); nothing collides with them.
4. Phone emulator: no stutter at the plaza; the bubbles are readable.
