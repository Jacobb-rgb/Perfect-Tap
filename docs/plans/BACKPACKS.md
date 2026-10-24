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

## The stall

`LobbyLayout` piece `BackpackStall`: the lawn north of the SHOP, between it and the wheel's
stairs (center (-40, 0, -44), 10 x 11 x 8, facing the plaza): the only spot near the plaza free
at radius 7. 27 map parts (Districts 2,253 -> 2,280). The three display packs are NOT map parts:
the shelf and the plinth plates carry the attribute `BackpackId` (no tag: Plaza Life keeps its
miners off tagged parts) and the clients, finding them through the counter's model, build them
within 70 studs. Measured against main ecf24f90: map 33,178 -> 33,064, lobby area
14,045 -> 13,994 (LobbyParts 14,500), phones' stream round the spawn 24,539 -> 24,425 and the
plaza 24,791 -> 24,677 (StreamParts 25,000). The stall adds 27; the rest re-rolls: the wilds
draw their spots from the free lawn, so they all move (Mountains 326 -> 273, Pieces 409 -> 354,
the five secrets unchanged), the meadow -24 (fences, lawn) and Plaza Life -9 (a lantern and a
prop on that lawn). No lights. The plaza ore cart at (-35, -35) stands in front of the stall.
Map version 56 (`WorldBuilder.Version`, numbered after the pending hoppers 53, podiums 54 and
no-Foundry 55: renumber when merging main if the order changes).

## What to test in Studio

1. Walk to the BACKPACKS stall: the three display packs appear on the shelf and the plinths
   (sparkles, fire on the Emberforge, stars on the Starforge); walk 100 studs away: they go.
2. Press E at the counter: the shop opens (two rows of five cards, the 3D packs turn the right
   way); walk away: it closes. B / Backspace / X close it too. Phones: the cards scroll.
3. Buy the Trail Pack with 250+ coins: the card turns EQUIPPED, the pack appears on your back
   (top level with the shoulders, the straps over the shoulders), the header says 15 ore.
4. EQUIP an older pack: it swaps on your back; other players see it within 120 studs.
5. An R6 avatar and a big Rthro avatar: the pack sits on the back and scales with the torso.
6. Settings > Reduce motion: the pack's particles stop.
