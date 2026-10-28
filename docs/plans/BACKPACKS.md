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

`LobbyLayout` piece `BackpackStall`: center (46, 0, 73), 18 x 16 x 12 (owner: "a bit wider"), facing west (-X) to the
end of the `ToScanner` path, between the DROPPERS house, the vault's east statue, the red trees
and the ore outcrop at (50, 58). `Districts/Backpacks` builds the shell (79 parts, one light):
the porch with two plinths, the gold-framed gateway with teal neon, the BACKPACKS board, corner
pillars with lantern cubes, parapet and crenels, the roof podium, the side racks, the back-left
shelf, the counter (tag `BackpackCounter`, Attachments `BackpackPromptPoint` and `KeeperFeet`)
and the shopkeeper's step. The clients build the rest (not map parts):

- the ten packs on the plates with the attribute `BackpackId` (every pack once: the porch
  Runebound and Emberforge, the racks Rookie/Trail/Leather and Miner's/Iron-Bound/Explorer's,
  the shelf Amethyst, the roof the giant Starforge: `DisplayScale` 2.8 on a two-tier podium,
  standing still (owner 2026-10-25; the controller can still turn a plate with `DisplaySpin`),
  its light on a PC). Each plate's `DisplayRange`: roof 40, porch 32, golem and inside 30 studs
  (dropped beyond the range + 6). The inside plates and the golem's carry `DisplayLite`:
  phones show those packs without their small details (`BackpackBuilder.lite`, ~40% of the
  parts), inside the shop too.
- `Builders/BackpackShopDecor` (~100 parts, within 30 studs): rune banners, sign lamps, side
  wall crests, hanging lanterns (lights on a PC), the rune crest behind the shopkeeper, rug,
  crates, bedroll shelf, barrel, rope, rack brackets, maps, coins, ledger, bell, planters and
  the gold dust in the gateway (off with Reduce motion).
- the shopkeeper (`ShopkeeperConfig.Shops.Backpacks` = SkySprite, Size 1.5): `Backpacks.build`
  marks its spot after the counter (`ShopkeeperConfig.mark`, the feet on the step facing the
  gateway; tests/Shopkeepers.spec.luau lists "Backpacks"). It cheers for a bought pack:
  BackpackService answers BackpackResult { Id, Ok, Reason?, Op } and `ShopkeeperConfig.buyShops`
  takes an Ok of Op "Buy" (an equip is no buy).
- the worn and shown packs and the decor live in `Workspace.ClientBackpacks`, which
  `StudStyleConfig.SkipNames` keeps smooth (no studs: the owner's 10-24 rule).

Trees (owner 2026-10-25: "more trees round it"): three hero voxel trees on Flora pieces
`BackpackTreeNW` (35, 56) green (scale 1.0), `BackpackTreeNE` (61, 61) orange and `BackpackTreeW` (26, 65)
green, each with a flower ring (Flora/Trees.backpackTrees, ~60 parts; the meadow now keeps 12
studs off the railway tunnel mouths: a re-rolled lawn tuft touched the south-east portal).

Golems (owner 2026-10-25): a golem stands by the porch with the Runebound pack on its back (piece
`BackpackGolem` (36, 0, 66.5), lean Districts Kit.golem, size 2.3, the pack on an invisible plate
`GolemPack`: DisplayRange 30, DisplayLite), and Plaza Life's 9 miner spots are mining golems
(`Life.miner` builds a golem with a hard hat: pickaxe on the shoulder, swinging at an ore rock,
or holding up a glowing chunk; same part count as the old miners).

Budgets at landing (main b1fab138, the budget tests' own counting): MapParts 34,330 and
LobbyParts 14,730 hold as they are; Flora lobby parts 3,229 (LobbyParts 3,205 -> 3,260). The
phones' worst spot by the shop is its gateway: 20,784 streamed + 2,661 always-streamed + 352
museum + its packs 914 (phones show the 7 inside packs and the golem's lite, inside the shop
too; PCs in full) + decor 90 + the DROPPERS showroom 512 + the shopkeeper golems in range 215 =
25,528 (the counter 25,517): StreamParts 25,240 -> 25,560 (the measured worst + ~30). The
shop's plates are dropped again beyond their range + 6 (BackpackShopDecor.Hysteresis; ranges
roof 40, porch 32, golem and inside 30, decor 30), so the spawn, the plaza and the DROPPERS
door hold none of its client parts even after a visit (tests/Backpacks.spec.luau).

Map version 64 (`WorldBuilder.Version`, on main e4dd151a v63).

## What to test in Studio

1. Walk to the BACKPACKS shop at the end of the path east of the Vault's steps: the giant
   Starforge pack stands on the roof (from ~40 studs), the porch packs appear (~32), then the
   racks, the golem's pack, the banners, lanterns and crest (~30); walk away: they go. No studs
   on any pack. Phones: the inside packs look a little simpler (no small details).
2. Press E at the counter: the shop opens (two rows of five cards, the 3D packs turn the right
   way); walk away: it closes. B / Backspace / X close it too. Phones: the cards scroll.
3. Buy the Trail Pack with 250+ coins: the card turns EQUIPPED, the pack appears on your back
   (top level with the shoulders, the straps over the shoulders), the header says 15 ore (more
   with Deep Pockets / Strong Back, and the cards show the same bonus), the shopkeeper cheers.
   A gamepad: the first card is selected when the window opens.
4. EQUIP an older pack: it swaps on your back; other players see it within 120 studs.
5. An R6 avatar and a big Rthro avatar: the pack sits on the back and scales with the torso.
6. Settings > Reduce motion: the pack's particles stop.
