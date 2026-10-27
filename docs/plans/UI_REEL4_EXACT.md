# Reel 4, round 2: the UI exactly like the reel (owner 2026-10-27)

The owner saw the round-look sheets (docs/screenshots/reels_2026-10-27/ui/) and wrote: "the UI still doesn't look
exactly like the picture; I need it completely identical; I know you can do it". So we match the reel
(docs/art/reels_2026-10-27/ui_*) element by element, LAYOUT included, not just the kit. We still draw our own icons
and pictures and never copy the pack's art. We add no new gameplay features: no codes box, trade, gifting or friend
boost.

## Order (integrator, 2026-10-27)
- (a) First all the WINDOW work on the current base: Store, Golems, Codex, Quests, Settings, Elevator, Star Forge,
  Tech / Vault / Gear, and the kit (band, title case, body, cards, cells).
- (b) Then, when feat/backpack is on main (`git branch -a --contains feat/backpack` lists claude/keen-wozniak-mx7azn),
  merge main into ui/round-look and do the HUD + BackpackView part on top. Never merge feat/backpack while it is
  unlanded (its tip can still change).
- Every new motion respects Motion.reduced() (confetti too); glints and confetti flash at most 2-3 times a second;
  sound ids are Roblox-uploaded or the 11 shipped files only.

## Contracts for (b) (feat/backpack, "Navrhy stroju" chat)
The VISUALS of HudBubble, HudView, HudController (layout only) and BackpackView are ours; BackpackState, CarryService
and the server stay theirs.
- BackpackView.build() refs and frame names: Fit -> Group -> Window (Header, Title, Close, Body); Body -> Info
  (PackName, Bar, CountLabel); List -> Row with Icon (Picture, Glow, Mystery), ItemName, Grade, Count; Empty; Footer
  (ShopLine, Hint); Dim; gui attribute Full. tests/BackpackClient.spec.luau checks these (cells may be added, the
  names stay findable).
- The HUD button "Backpack" stays in the "Carry" holder; HudView.setBackpack keeps working (~20 preview libs call it);
  anim/mine-juice's ore flight finds that button by name.
- Q / R1 still open the window. 44 pt touch targets on phones, the 8 pt text floor, TV / gamepad selection.

## HUD (ui_02, ui_03, ui_04, ui_11)
1. Left tile grid: 2 columns x 4 rows of square tiles under Roblox's top-left buttons (~76 units at 720, gaps ~6):
   dark charcoal with a subtle gradient, a near-black outline ~3, a thin inner border in the tile's accent colour,
   radius ~6, a big glossy icon in the top ~70 %, a Title Case white label with a thick dark edge at the bottom.
   Store (red, Robux store), Rebirth (magenta, Star Forge), Golems (orange), Inventory (orange-red, the backpack),
   Spin (purple, wheel), Daily (pink, quests + streak), Build (green), More (grey: Codex, Settings, Boosts, Elevator,
   Emotes, Leaderboards, Story). A tilted "OP!"-style sticker: "FREE!" on Spin when a free spin is ready (replaces the
   top-right FREE SPIN chip), "NEW!" where something is new. Phones: e.g. 4 x 2 top-left, 44 pt.
2. Top centre: separate big buttons, own colour, fine checker texture, darker bottom lip, black outline, an icon over
   the left end, a Title Case word: Shop red (the Robux store; the green Shop pill moves here), Lobby green, Base
   yellow, Vault purple.
3. Right: 3 offer icons mid-right, our product's picture, a small green "R$99" tag top-right, a Title Case name;
   tap opens the Store at that item; owned / unavailable ones hide.
4. Bottom-left: the money big green with a thick dark edge (no cash icon), a white income line under it
   ("+$1.84K/s", where the reel has "Friend Boost +0%"), the train chip above it, dark like the tiles.
5. Bottom-right: running boosts and owned passes as square icon tiles with a small text under each (time left, or
   the infinity sign for owned forever); see ui/boost-corner bd171266.
6. The backpack button by the blaster slot: a dark square tile, orange accent, its count.

## Windows (ui_01 and the other ui_*)
- Title Case everywhere ("Store", "My Golems", "Star Forge"); section headings "- Gamepass -" in Title Case, white,
  centred.
- Header band: a FLAT window colour, a fine checker / diagonal texture, a few wide diagonal stripes, a darker bottom
  lip, the reel's band height; the icon at the left a little bigger than the band, the big faded icon in the middle;
  a red square X inset at the right (dark outline, white X).
- Body: dark charcoal (~#2B2C30), a 3-unit near-black outline, corner ~6, content straight on the body with ~8
  padding, a thin scrollbar.
- Store: ONE scrolling list, no side tabs: "- Gamepass -" 2-column cards, "- Buy Cash -" 3-column lime cards, then
  the other sections in the same card style. Card: a bright two-tone gradient with sunburst rays from the picture,
  the big picture on the left half, the title top-right in heavy Title Case, the description white and right-aligned,
  the green price button bottom-right ("R$179"). No gift button.
- Inventory (BackpackView): a "Search..." box (filters by name), counter chips top right, a grid of square cells (5 a
  row on PC): dark, the rarity name at the top in its colour, the picture centred, the Title Case name at the bottom,
  "x4" bottom-right; one cell per stack. Every cell shows a picture of the ore; dirty ore shows the crust chunk
  (ItemBuilder Raw), "Dirty Ore" and an unknown rarity line, never a big "?" and never a hint of what is inside.
- Golems: the same cell grid. Codex = "Index": the cell grid and rarity filter tabs outside the window on the right
  (Common grey, Uncommon green, Rare blue, Epic purple, Legendary yellow, plus ours) if filtering is cheap.
- Quests / Streak = "Daily Rewards": 7 day cards, days 1-6 small, day 7 big and rainbow on the right; Claimed,
  Claim (green), LOCKED (red).
- Settings: dark rows (name + small grey subtitle); a green slider with a knob and a percent, or a small green ON /
  red OFF toggle.
- Elevator = "Teleport": wide cards with the area picture as background, the name top-left, a green TELEPORT; locked
  floors: a big padlock and a green UNLOCK.
- Star Forge = "Rebirth": "x1.5 -> x2.0" rows, a bar, a big green Rebirth and a red skip / close; our real content
  (you lose / keep / get, stars) in the reel's styling.
- Sell = "Sell Items": rows (icon, rarity in colour, name, green price), a green "Sell All" in the header.
- Tech / upgrades = "Upgrade": rows with price buttons. Vault / Gear = "Item Shop": rows (picture, name + rarity,
  small stats, green Equip, price).
- Priority: HUD -> Store -> Inventory -> Golems -> Codex -> Quests -> Settings -> Elevator -> Star Forge -> Sell ->
  the rest.

## Pictures
Every screen: the reel frame and ours side by side at the same size (PC + phone); iterate until layout, proportions,
colours, font and edges match (our own icons and content aside). Sheets: docs/screenshots/reels_2026-10-27/ui2/.

## Rules
Strict types, stylua only touched files (HEAD-clean check), specs follow the changes,
`bash tools/check.sh > build/check_roundlook2.log 2>&1; echo "exit $?"` = ALL CHECKS PASSED exit 0, restore
build/TerraForge.rbxl, no `git add -A`, no bare stash, commits in steps.
