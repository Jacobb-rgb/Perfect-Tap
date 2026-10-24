# Shopkeepers (owner 2026-10-24)

Owner: "cool characters behind the counters of all shops" → "one guy for every shop, all identical" → (final)
**his 3D model** `roblox_miner_shopkeeper.glb` ("upload exactly this, not blocky, no lego studs"), **none at the
EGGS temple**. Branch `feat/shopkeepers` (from main `ecf24f90`).

## How it works
| Piece | File | What |
|---|---|---|
| The model | `docs/art/shopkeeper/roblox_miner_shopkeeper.glb` → `tools/art/shopkeeper_glb.py` → `src/shared/Builders/ShopkeeperModel.luau` | the owner's file as data: every box a Block, every cylinder a Cylinder, the lamp lens a disc, his colours; 1 unit = 1 stud, 5.53 studs tall |
| Builder | `src/shared/Builders/ShopkeeperBuilder.luau` | the pieces as SmoothPlastic parts (4 glows Neon), the model tagged `NoStuds` (no Roblox studs), on an R6-style rig (invisible HumanoidRootPart, Torso, Head, arms, legs; Motor6Ds with the R6 names and frames at his own neck, shoulders and hips; pieces welded), AnimationController + Animator |
| Spots | `ShopkeeperConfig.mark(counter, feet, shop)` in the lobby builders | an **Attachment** on the counter (tag `ShopkeeperSpot`, attribute `Shop`), frame = his feet, LookVector = the customers. No parts: no budget change; it streams with its counter |
| Keepers | `src/client/Controllers/ShopkeeperController.luau` | builds a keeper on a spot while the player is within 90 studs, removes him past 110 (phones draw 1-2 at a time, ~83 parts each); Roblox R6 idle, the head follows the player (neck joint, ±65° / ±20°), wave + hello bubble when the player walks up (25 s cooldown), cheer + thanks after a buy (Notify `Reward`) or a sale (Earned `Sell`) nearby; a soft light in front of his chest |
| Numbers, lines | `src/shared/Config/ShopkeeperConfig.luau` | scales, distances, R6 animation ids, hello / thanks lines per shop |

**Style pass** (owner 2026-10-24: "a bit nicer, with effects"; `ShopkeeperBuilder`, opts `Badge` / `Effects` / `Lights`):
metal shoulder pads, plates and tools, a leather apron, straps, boots and pack, fabric trousers and shirt, a glossy
helmet, neon orange trims and pickaxe tip, three glowing ore crystals in his pack, a shine in each eye, the shop's
name on his apron badge (SHOP, TECH, SELL, MAGIC, VAULT; `ShopkeeperConfig.badge`); a soft light cone from the helmet
lamp (Beam), sparkles rising from the crystals, a gold burst when he says thanks, a warm outline (Highlight), blinking
and a flickering lantern within 45 studs. Real lights (the lamp's SpotLight, the chest light) only on the **nearest**
keeper within 40 studs: the game's light budget for phones (`GearConfig.LampBudget` does the same for players).

**Two fixes to the file** (both in `tools/art/shopkeeper_glb.py`): its scene lost 11 mirrored pieces to duplicate
names (one eye, ear, eyebrow, apron strap, pouch and flap, backpack tube, harness strap and three SHOP letters: the
meshes are in the file, no node shows them), so the script reads every mesh; and its torso floats 0.42 studs over the
thighs, so a hip block in the trousers' colour closes the gap. Everything else is exactly the file. Change the model →
run the script again.

## Spots (map v57 on this branch)
| Shop | Counter | Spot | Scale |
|---|---|---|---|
| SHOP (Gear) | `ShopCounter` | where the Outfitter stood, 0.4 closer to the counter (the door lintel) | 1.1 |
| UPGRADES (Tech) | `UpgradeCounter` | where Forgemaster Ulda stood, 0.4 closer | 1.1 |
| SELL | `SellCounter` | where Tobin stood | 1.15 |
| ENCHANT | `EnchantCounter` | where the Enchanter stood | 1.15 |
| BLASTER VAULT | `VaultCounter` | where the Blastsmith stood (Vault `Kit.scale` now scales attachments too) | 1.25 |

The five blocky keepers (Outfitter, Forgemaster Ulda, Tobin, the Enchanter, the Blastsmith) are gone from the map.
Texts still say "Tobin paid ..." (SellService): a rename is the owner's call.

## For the branches that land later
- **DROPPERS** (`art/hoppers`) and **BACKPACKS** (`art/backpacks`): add one line in their counter builder,
  `ShopkeeperConfig.mark(counter, <feet behind the counter, facing the customers>, "Droppers" | "Backpacks")`.
  The lines are already in `ShopkeeperConfig.Shops`; `tests/Shopkeepers.spec.luau` lists the shops it checks.
- Map version: 57 here so it can't clash with 53-56; renumber when merging.

## Preview
`lune run tools/lune/export_scene.luau shopkeepers` (the world, the miner on every spot) or `shopkeeper_solo` (the
miner alone), then `SHOTS_EXTRA=tools/preview/shopkeeper_shots.json node tools/preview/render.mjs shopkeepers
keeper_gear_low keeper_tech_low keeper_sell keeper_enchant keeper_vault` / `shopkeeper_solo keeper_solo_front
keeper_solo_three_quarter keeper_solo_back`. The previews show his rest pose (no animations).

## What to test in Studio
1. Press Play. The miner stands behind the SHOP, UPGRADES, SELL, ENCHANT and Vault counters, smooth, without studs;
   none at the EGGS temple.
2. Each one breathes (R6 idle) and turns his head toward you when you are near; walk up: he waves and a bubble says
   hello; buy something / sell ore: he cheers, says thanks and throws gold sparkles. He blinks, his lantern flickers,
   the helmet lamp throws a soft cone of light onto the counter and a warm outline goes round him. (The animations are Roblox's R6 ones on his own rig:
   check that arms and head move naturally.)
3. Prompts (E) at every counter still work (the keepers block no clicks or prompts); nothing collides with him.
4. Phone emulator: no stutter at the plaza; the bubbles are readable.
