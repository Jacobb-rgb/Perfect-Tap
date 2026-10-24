# Backpacks: the look, the shop, the stall (art/backpacks)

Owner 2026-10-24 (chat "Styl a obchod batohu"): ten backpacks worst to best after his
reference picture (a royal blue rune pack with gold trim), a BACKPACKS stall in the lobby,
coins only. Three rounds of looks: v1 too basic, v2 more details and effects, v3 clean
rounded panels with rims like the picture ("clean"), then small accessories on packs 1-7.
The owner approved the packs ("batohy jsou hotové") and asked for the stall and the shop.

## Split with the backpack inventory ("Návrhy strojů", integrator 2026-10-24)

| Here (art/backpacks) | "Návrhy strojů" (the inventory piece) |
|---|---|
| `Config/BackpackData` (ids saved: never rename), `BackpackData.capacity(id)` | save fields `data.Backpacks = { Equipped, Owned }`, `data.BackpackItems` |
| `Builders/BackpackBuilder`, `Builders/BackpackFx` | the migration (old Gear "Ore Backpack" level -> a tier) |
| the worn model (`BackpackWearController`, player attribute `Backpack`) | `BackpackService`: the prompt on `BackpackCounter`, `OpenUI "Backpacks" { Counter }` |
| the shop window (`BackpackShopView`, `BackpackShopController`) | `Net BackpackAction ("Buy"/"Equip", { Id })` -> `BackpackResult { Id, Ok, Reason? }` |
| the stall (`Lobby/Districts/Backpacks`, LobbyLayout piece `BackpackStall`) | `State.Backpacks { Equipped, Owned, Count, Capacity }`, player attribute `Backpack` |

Order rule: any tier you can afford; a buy auto-equips when the new pack is bigger. Until the
inventory lands the client is inert: no `BackpackAction` in `Net.Events` = the shop buttons say
"opens soon", no worn packs (no attribute), the stall shows its display packs.

## The packs

| # | Id | Rarity | Ore | Price (proposal) | Parts | Effects |
|---|---|---|---|---|---|---|
| 1 | RookiePack | Common | 5 | free | 72 | - |
| 2 | TrailPack | Common | 15 | 250 | 131 | - |
| 3 | LeatherRucksack | Uncommon | 30 | 5K | 142 | a glint |
| 4 | MinersPack | Uncommon | 60 | 120K | 139 | lantern light, glints |
| 5 | IronboundPack | Rare | 100 | 2.5M | 143 | blue glints, light |
| 6 | ExplorersPack | Rare | 175 | 60M | 135 | teal sparkles, light |
| 7 | AmethystPack | Epic | 275 | 900M | 170 | violet sparkles, light |
| 8 | RuneboundPack | Epic | 400 | 12B | 159 | rising runes, light |
| 9 | EmberforgePack | Legendary | 600 | 120B | 155 | fire + smoke, embers, light |
| 10 | StarforgePack | Mythic | 1000 | 600B | 164 | stars, wing sparkles, light |

Prices are a proposal on the 6-floor curve; the inventory's balance sim confirms them.
`BackpackBuilder.MaxParts` = 200 (tests). Phones: other players' packs only within 120 studs,
particles within 50 at half rate, none with Reduce motion; only your own pack's light shines.

## The shop (in place of the ROCK SCANNER)

Owner 2026-10-24, after the first stall (a 27-part kiosk north of the SHOP): "in place of the
scanner, in front of the Vault", and four things more: more details and decorations, bigger like
a shop, a shopkeeper at the counter, more lights and effects; the ROCK SCANNER goes (the Ore
Codex opens from the side menu's CODEX button; `CodexController` still adds its prompt to any
model tagged `OreCodex`, there is none now).

`LobbyLayout` piece `BackpackStall`: center (46, 0, 74), 16 x 16 x 12, facing west (-X) to the
end of the `ToScanner` path, between the DROPPERS house, the vault's east statue, the red trees
and the ore outcrop at (50, 58). `Districts/Backpacks` builds the shell (79 parts, one light):
the porch with two plinths, the gold-framed gateway with teal neon, the BACKPACKS board, corner
pillars with lantern cubes, parapet and crenels, the roof podium, the side racks, the back-left
shelf, the counter (tag `BackpackCounter`, Attachments `BackpackPromptPoint` and `KeeperFeet`)
and the shopkeeper's step. The clients build the rest (not map parts):

- the ten packs on the plates with the attribute `BackpackId` (every pack once: the porch
  Runebound and Emberforge, the racks Rookie/Trail/Leather and Miner's/Iron-Bound/Explorer's,
  the shelf Amethyst, the roof the giant Starforge: `DisplayScale` 2.2, `DisplaySpin` 0.5 rad/s,
  its light on a PC). Each plate's `DisplayRange`: roof 45, porch 38, inside 30 studs. The
  inside plates carry `DisplayLite`: phones show those packs without their small details
  (`BackpackBuilder.lite`, ~40% of the parts) until the camera or the player is in the shop.
- `Builders/BackpackShopDecor` (~100 parts, within 30 studs): rune banners, sign lamps, side
  wall crests, hanging lanterns (lights on a PC), the rune crest behind the shopkeeper, rug,
  crates, bedroll shelf, barrel, rope, rack brackets, maps, coins, ledger, bell, planters and
  the gold dust in the gateway (off with Reduce motion).
- the shopkeeper: feat/shopkeepers (`ShopkeeperConfig.Shops.Backpacks` = SkySprite, Size 1.5)
  lands first; when this branch lands: in `Backpacks.build` after the counter
  `ShopkeeperConfig.mark(counter, counter.KeeperFeet.WorldCFrame, "Backpacks")` (require
  Shared.Config.ShopkeeperConfig), and in tests/Shopkeepers.spec.luau "Backpacks" in SHOPS and
  `Backpacks = "BackpackCounter"` in COUNTERS (the feet stand on the step, facing the gateway).

Budgets (main 958ddb46 -> this branch, the budget tests' own counting): map 33,450 -> 33,459,
lobby area + museums 14,699 -> 14,681 (LobbyParts 14,730), phones' stream round the spawn
24,811 -> 24,820, the plaza 25,063 -> 25,072, the DROPPERS door 25,206 -> 25,215 (StreamParts
25,240). The shop's client packs and decor are out of range at all three spots
(tests/Backpacks.spec.luau). At the shop's own gateway a phone holds 20,832 + 2,658 + 352
streamed + its packs 853 (inside ones lite) + decor 90 + the DROPPERS showroom 526 = 25,311
(tests/Backpacks.spec.luau): StreamParts 25,240 -> 25,345 (integrator 2026-10-24, owner:
quality over limits).
Map version 58 (`WorldBuilder.Version`, numbered past the pending podiums, no-Foundry and
shopkeepers: renumber at landing).

## What to test in Studio

1. Walk to the BACKPACKS shop at the end of the path east of the Vault's steps: the giant
   Starforge pack turns on the roof (from ~45 studs), the porch packs appear (~38), then the
   racks, the banners, lanterns and crest (~30); walk away: they go. Reduce motion: it stops.
2. Press E at the counter: the shop opens (two rows of five cards, the 3D packs turn the right
   way); walk away: it closes. B / Backspace / X close it too. Phones: the cards scroll.
3. Buy the Trail Pack with 250+ coins: the card turns EQUIPPED, the pack appears on your back
   (top level with the shoulders, the straps over the shoulders), the header says 15 ore.
4. EQUIP an older pack: it swaps on your back; other players see it within 120 studs.
5. An R6 avatar and a big Rthro avatar: the pack sits on the back and scales with the torso.
6. Settings > Reduce motion: the pack's particles stop.
