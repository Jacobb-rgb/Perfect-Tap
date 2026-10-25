# Shopkeepers (owner 2026-10-24)

Owner, in order: "cool characters behind the counters of all shops" → his avatar → his 3D miner → (final) **"big
golems serve our shops: take a golem and just make it bigger, each shop a different cool golem, with emotes in front
of the stall, e.g. waving"**. None at the EGGS temple. Branch `feat/shopkeepers` (from main `ecf24f90`).

## Who serves where
| Shop | Golem (GolemConfig) | Size | Why |
|---|---|---|---|
| SHOP (Gear) | Dragonscale Knight `ScaleKnight` | 1.6 | armour, sword and shield: the gear shop |
| UPGRADES (Tech) | Storm Sentinel `StormSentinel` | 1.35 | storm armour and a lightning spear: tech |
| SELL | Flamewing `Flamewing` | 1.9 | small wings, goggles: fits the narrow stall (owner: bigger) |
| ENCHANT | Aether King `AetherKing` | 1.4 | halo, wings, a staff and orb, floats on clouds: magic. Stands **beside** the rune table (viewer's left, turned to the table's front): behind it the hut's door lintel and the floating crystals hid it (owner: "not very visible") |
| BLASTER VAULT | Dragon King `DragonKing` | 1.45 | the Mythic king for the best shop |
| DROPPERS | Ember Hatchling `EmberHatchling` | 1.5 | a fire hatchling in its shell: narrow enough for the spot by the counter's left end (behind the counter the DARK MATTER DROPPER's podium leaves no room); it replaces the blocky Dropper Master of the showroom |
| BACKPACKS (when it lands) | Sky Sprite `SkySprite` | 1.5 | the backpack chat's shop (art/backpacks) has a `KeeperFeet` attachment on its counter: one `ShopkeeperConfig.mark(counter, counter.KeeperFeet.WorldCFrame, "Backpacks")` line when it lands |

## How it works
| Piece | File | What |
|---|---|---|
| Spots | `ShopkeeperConfig.mark(counter, feet, shop)` in the lobby builders | an **Attachment** on the counter (tag `ShopkeeperSpot`, attribute `Shop`), frame = the golem's feet, LookVector = the customers. No parts: no budget change; it streams with its counter. SHOP, UPGRADES and the VAULT stand their golem on a step the counter hides (1.0-1.25 up), so its big head shows over the goods; ENCHANT's stands beside its table |
| Golem | `src/shared/Builders/GolemKeeper.luau` | `GolemBuilder.build(kind, feet, {Size})`: the game's own golem, bigger, tagged `NoStuds`; the rig sorts its parts: Right / Left arm (Arm, Fist, Bracer, BracerGem, Claw), RightHeld / LeftHeld (sword, shield, spear, staff + orb, lance: they follow the fist upright), Ground (aura, cloud floor, flame ring: they stay down), Body; `frames(rig, feet, pose, yaw)` = every part's CFrame |
| Emotes | `src/shared/Moves/GolemEmotes.luau` | pure poses: idle breath and sway, Wave, Hop, Spin, Dance, Bow, Cheer |
| Golems in the game | `src/client/Controllers/ShopkeeperController.luau` | builds a golem while the player is within 90 studs (one build per 0.4 s check, nearest first), removes it past 110; within 60 studs it moves (one `BulkMoveTo` for all golems each frame), past 60 (or with no character) it goes back to its rest pose once and stands still: turns toward the player (±35°), waves + hello bubble when the player walks up (25 s cooldown), and every 6-12 s hops, spins, dances, bows or waves by itself. Thanks (cheer + line + gold burst, at most once per 0.5 s): a sale whose Earned `Sell` popup is within 24 studs of the Sell golem's feet (its counter or SellBin; a plot's Sell Box is far away), or a bought item at a shop (`ShopkeeperConfig.buyShops`: ShopResult for UPGRADES / DROPPERS, ActionResult Gear / Enchant `Buy`, VaultResult) with the player within 24 studs of that shop's golem; no other Reward counts. A hello or thanks during a Hop / Spin / Dance waits for it to end; one that cuts into a Wave / Bow / Cheer blends in over 0.2 s. Reduce Motion (`UI/Motion.reduced`): only Bow / Wave by itself, a Cheer without its jump, no bubble pop, a smaller burst (the idle stays). One soft light, on the nearest golem only (phones: the game's light budget); a keeper keeps no light of its own (`GolemKeeper.build` drops the Mythic gear lights, its embers at most 3 a second) |
| Numbers, lines | `src/shared/Config/ShopkeeperConfig.luau` | golems, sizes, distances, timings, hello / thanks lines |

The five blocky keepers (Outfitter, Forgemaster Ulda, Tobin, the Enchanter, the Blastsmith) are gone from the map.
Texts still say "Tobin paid ..." (SellService): a rename is the owner's call. The earlier miner version (the owner's
glb rebuilt in parts) is in the branch history (d44bf008, f99fd5bc).

## For the branches that land later
- **BACKPACKS** (`art/backpacks`): add `ShopkeeperConfig.mark(counter, counter.KeeperFeet.WorldCFrame, "Backpacks")`
  in `Backpacks.build` after the counter; its golem and lines are already in `ShopkeeperConfig.Shops`; add
  `"Backpacks"` / `BackpackCounter` to `tests/Shopkeepers.spec.luau`'s SHOPS and COUNTERS.
- **BACKPACKS** also: its shop's purchase answer goes into `ShopkeeperConfig.buyShops`, so its golem thanks for a buy.
- Map version: 55 here (`WorldBuilder.Version`); the integrator renumbers when merging.

## Spots and the map
Checked by `tests/Shopkeepers.spec.luau` against the built map (no golem part inside a map part outside
its own shop at rest): the SELL golem stands 1.9 studs toward the SHOP's lane from Tobin's old place,
`Fronts.luau` `at(-1.0, 0, -0.4)`, so its right wing keeps out of the plaza's entrance lantern, also when it
turns toward a player; the ENCHANT golem 1.4 studs further out from the hut's window wall (`Enchant.luau`
`at(3.9, FLOOR, -3.9)`), so its head, helm, wings and cape keep out of the facade, the door frame and the corner
pillar. What still touches (all inside its own stall or hut; the Flamewing is 9 studs wide and 3.8 deep at the
bottom, the stall 6.6 wide with 1.6 studs between the cart and the SellBin, so no spot at Size 1.9 is fully
clear): the Flamewing's lower wings, tail and scarf ends in the SellBin's front wall behind it, and its left
wing tip over the edge of the lane; the Aether King's cloud floor and cape in the crystal cluster beside it, its
left arm grazing the rune table's top, its staff orb and crest tips against the right lantern pillar's cap.
Moving the plaza lantern / SellBin or the hut's crystal cluster (or a smaller size) would clear them: the
owner's call.

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
4. Phone emulator: no stutter at the plaza (arriving at the spawn the golems appear one by one); the bubbles are
   readable.
5. One sale at the SELL counter or into the SellBin: one cheer and one line. With a Sell Box on your plot, stand at
   the SHOP or UPGRADES counter: no golem cheers for the Sell Box's sales, a wheel prize or a boost.
6. SETTINGS → Reduce Motion: the golems only bow and wave by themselves, a cheer stays on the floor, the bubbles show
   without a pop, a smaller sparkle burst.
7. Walk up while a golem spins or dances: it finishes the move, then waves (no snap back to the front). Walk away past
   60 studs mid-emote: it stands at rest, not frozen mid-move.
8. Inside the Vault and the ENCHANT hut: the golem near you has one soft light, no other light of its own.
