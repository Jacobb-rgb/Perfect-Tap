# Shopkeepers (owner 2026-10-24)

Owner: "cool characters behind the counters of all shops" → then "just one guy for every shop, made from **my skin**,
all of them identical". Branch `feat/shopkeepers` (from main `ecf24f90`).

## How it works
| Piece | File | What |
|---|---|---|
| Spots | `ShopkeeperConfig.mark(counter, feet, shop)` in the lobby builders | an **Attachment** on the counter (tag `ShopkeeperSpot`, attribute `Shop`), frame = his feet, LookVector = the customers. No parts: no budget change; it streams with its counter |
| Template | `src/server/Services/ShopkeeperService.luau` | `Players:CreateHumanoidModelFromUserId(owner)` once at start (pcall, 4 tries, 8 s doubling) → `ReplicatedStorage.ShopkeeperTemplate`: scripts stripped, root anchored, the rest loose for the joints, no collision / touch / queries / shadows, name and health bar hidden, state machine off |
| Keepers | `src/client/Controllers/ShopkeeperController.luau` | clones the template onto every spot that streams in (client-only: nothing more streams to phones), scale per shop, feet on the spot; Roblox idle, the head follows the player (neck joint, ±65° / ±20°), wave + hello bubble when the player walks up (25 s cooldown), cheer + thanks after a buy (Notify `Reward`) or a sale (Earned `Sell`) nearby; a soft light in front of his chest (the shops are dark, the owner's skin is black) |
| Numbers, lines | `src/shared/Config/ShopkeeperConfig.luau` | `UserId`, scales, distances, Roblox animation ids (R15 + R6), hello / thanks lines per shop |

**Whose avatar:** `ShopkeeperConfig.UserId` when set, else the game's creator when a **user** owns the game
(`game.CreatorType == User`), else in Studio the first player who joins (the one pressing Play). If the game is
published under a **group**, `UserId` must be filled in (the owner's Roblox UserId). The keepers follow his current
avatar: a new skin shows on the next server start.

## Spots (map v57 on this branch)
| Shop | Counter | Spot | Scale |
|---|---|---|---|
| SHOP (Gear) | `ShopCounter` | where the Outfitter stood, 0.4 closer to the counter (the door lintel) | 1.1 |
| UPGRADES (Tech) | `UpgradeCounter` | where Forgemaster Ulda stood, 0.4 closer | 1.1 |
| SELL | `SellCounter` | where Tobin stood | 1.15 |
| ENCHANT | `EnchantCounter` | where the Enchanter stood | 1.15 |
| BLASTER VAULT | `VaultCounter` | where the Blastsmith stood (Vault `Kit.scale` now scales attachments too) | 1.25 |
| EGGS | the ROYAL podium | on the dais in the gap between the ROYAL and the Stone egg, behind the front eggs | 1.15 |

The five blocky keepers (Outfitter, Forgemaster Ulda, Tobin, the Enchanter, the Blastsmith) are gone from the map.
Texts still say "Tobin paid ..." (SellService): a rename is the owner's call.

## For the branches that land later
- **DROPPERS** (`art/hoppers`) and **BACKPACKS** (`art/backpacks`): add one line in their counter builder,
  `ShopkeeperConfig.mark(counter, <feet behind the counter, facing the customers>, "Droppers" | "Backpacks")`.
  The lines are already in `ShopkeeperConfig.Shops`; `tests/Shopkeepers.spec.luau` lists the shops it checks.
- Map version: 57 here so it can't clash with 53-56; renumber when merging.

## Preview
`lune run tools/lune/export_scene.luau shopkeepers` (stand-ins dressed dark like the owner's skin, scaled like the
keepers) then `SHOTS_EXTRA=tools/preview/shopkeeper_shots.json node tools/preview/render.mjs shopkeepers keeper_gear
keeper_tech keeper_sell keeper_enchant keeper_vault keeper_eggs`. Lune can't load Roblox avatars: the real look is a
Studio check.

## What to test in Studio
1. Press Play (the place unpublished: your own avatar is used). Within a few seconds your avatar stands behind the
   SHOP, UPGRADES, SELL, ENCHANT and Vault counters and between the eggs.
2. Each one breathes (idle) and turns his head toward you when you are near; walk up: he waves and a bubble says
   hello; buy something / sell ore: he cheers and says thanks.
3. Prompts (E) at every counter still work (the keepers block no clicks or prompts); nothing collides with him.
4. Phone emulator: no stutter at the plaza; the bubbles are readable.
5. Output: no `[ShopkeeperService]` warning. If the avatar fails to load, the shops still work without keepers.
