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

## Round 3: measured at full resolution (2026-10-28)
The reel (instagram.com/reel/De_A8Y8N38N, 1920 x 1080, 116 s) was measured frame by frame in the browser
(drawImage onto a canvas, getImageData; no downloads). Pixels are 1080p frame pixels; "u" = design units of a
720-tall screen (px / 1.5). The preview renders 1600 x 900 with 720 design units, so u compares 1:1.

| Element (time) | Reel px | u (= px / 1.5) | Notes |
|---|---|---|---|
| Top tab (0.5 s) | 248 x 98, gap 10, top y 24 | 165 x 65, gap 7, top 16 | square corners (r ~1), black outline 5 px (3.3 u), light inner line ~5 px in, dark lip 10 px (6.5 u), faint Roblox "L" studs every ~42 px (28 u), a big translucent icon clipped at the left end, the word centred |
| Tab word | cap 37 px, stroke ~4 px | font ~33 u, stroke 2.8 u | Montserrat-like heavy, white |
| Middle tab (Spawn) | 264 x 108 (10 px taller, top y 14) | 176 x 72 | the current spot sticks up |
| Left tile (0.5 s) | 116 x 116, gap 12 h / 9 v, left 14, rows 285..772 | 77 x 77, gap 8 / 6, left 10, vertically centred | outline 3.3 px (2.2 u), radius ~5.6 px (3.7 u), slate fill (64,75,86) slightly see-through, coloured inner rim brightest at the bottom (4.5 px) fading up the sides, icon 78 px (68 %) from 22 px down, word cap ~18 px (font ~16 u) |
| "OP!" sticker | ~55 px tall word | ~24 u | yellow-orange gradient, dark outline, turned ~-15 deg, over the tile's top-left corner |
| Offers mid-right | cell 200 px tall, picture ~110 px, label cap ~26 px | cell 133 u, picture 73 u, label 19 u | white sunburst behind the picture, "R$49" lime text (no box) top-right of the picture, tilted ~-8 deg; column right margin 20 px (13 u), vertically centred |
| Money | "$0" glyphs 53 px tall, line cap 35 px | font ~37 u + ~27 u | green gradient (light lime top, green bottom) with a dark edge; the line white; left 8 px (5 u), bottom 18 px (12 u) |
| Boost squares (bottom-right) | 81 x 81, gap 7, right 26, bottom ~40 | 54 x 54, gap 5 | bright coloured faces with studs, outline 3 px, radius 3 px, a white "inf" with a dark edge over the bottom edge |
| Store window (8.5 s) | x 509..1411, y 149..994 (902 x 845) | 601 x 563 | centred; outline 4 px |
| Window band | 110 px incl. an 11 px dark lip | 73 u, lip 7 u | studs: rounded squares every ~25 px (17 u); two wide light "//" stripes either side of the faded icon; icon 82 px (55 u) inside the band at the left |
| Window title | cap 32 px | font ~30 u | white, dark stroke |
| Window X | 72 px square, 22 px from the right | 48 u, inset 15 u | red, dark outline, light inner line, white X |
| Section heading "- Buy Cash -" | cap ~26 px | font ~24 u | white with a dark stroke |
| Buy Cash card | 274 x 198, gap 15, window padding 27 | 183 x 132, gap 10, padding 18 | outline 3 px, radius ~4 px; amount top-left light green, text right-aligned white, "R$49" white on a lime button (dark outline), a purple gift button left of it |
| Rebirth window (22 s) | 853 x 721 at x 531, y 179 | 569 x 481 | band ~94 px (63 u) |
| Inventory window (34 s) | 855 x 657 at x 531, y 219 | 570 x 438 | search box dark (#111) 69 px tall; cells 150 x 120, gap 16, 5 a row |
| Background while a window is open | | | the world is blurred (a camera blur) |

Motion (sampled every 1/60 s):
- Window opens (Store, 1.20-1.37 s): 0.5 -> 1.10 (peak at ~0.09 s) -> 1.0 (settled at ~0.17 s): a Back-out ease of about 0.2 s.
- Hover (Store tile, 0.60-0.70 s): grows ~5 % in ~0.1 s and stays while hovered.
- Press (1.07-1.20 s): squashes to ~0.93 for ~0.1 s, then back to the hover size in ~0.1 s.
- Confetti after a purchase (14-19 s): rainbow paper bits over the whole screen for ~2 s.

### Round 3: what the round look now does with those numbers
- Top row (PC): Shop / Lobby / Base / Vault 165 x 64 units (narrower on a tablet so the tutorial bubble stays
  clear: (screen width - 612) / 4, 110..165), the word 34 units centred, a big faded copy of the icon cut by the
  button's left end (Pop.tabMark), corners 3, studs on the faces (IconAssets ui_studs, once uploaded).
- Left tiles (PC): 77 units, gaps 7, 10 from the left, their top 140 under Roblox's bar (the reel's rows
  285..772 px); phones keep four a row at the top. Icon 72 % of the tile, corners ~4, thin slate face with
  the tile's colour in a thin bottom lip and the rim.
- The bottom centre (owner 2026-10-28, newest): [BLASTER slot | backpack button] centred like on main, in the
  round look as the reel's dark tiles with their colour in the lip and the edge (blue blaster, orange pack);
  on phones the pair keeps out of Roblox's thumbstick zone (left edge at 40 % of the screen at least, both
  looks). The Inventory tile stays in the grid with no count on it (the round-3 badge was dropped).
- Offers: 74-unit pictures every 133 units, a white sunburst behind each, "R$99" lime letters tilted -8 deg,
  no box; money 40 + 27 units, 6 from the left, 12 from the bottom.
- Store: 605 x 563 units (StoreView.Looks.Round), cards 569 wide in all (cash 183 x 132, gamepasses two a
  row 279 x 150), the X 48 units, prices as words "R$49" (Pop.priceWords), price buttons 0.24 of a card tall,
  titles in a light tint of the card's colour; the limited banner drawn 918 wide and shrunk into the list.
- Inventory (PC): at most 584 x 470 units (BackpackView.RoundMaxWidth / RoundMaxHeight), five cells a row.
- Window X on PC bands: 0.66 of the band (48 of 73), 15 in; compact bands keep 0.82 (44 pt on phones).
- Motion: AnimConfig.RoundMotion (ON since the owner's OK, 2026-10-28; Motion.roundMotion / Motion.tune /
  Motion.roundPopScale): windows 0.5 -> 1.1 -> 1 in 0.2 s, hover +5 % in 0.1 s, press 0.93 for 0.1 s and back
  in 0.1 s, no shine or breathe loops; Reduce motion stills it like UIMotion. Clip:
  docs/screenshots/reels_2026-10-27/ui3/round_motion.mp4 (preview, tools/lune/export_round_motion.luau).

- Rebirth (owner 2026-10-28: "like the rebirth in the other pictures"): the reel's window, 600 x 500 units:
  "Rebirth N" -> "Rebirth N+1", two pills with real numbers (Forge Stars now -> after this rebirth; blaster
  LV now -> the level a rebirth starts with), a dark box with one line and a bar toward the requirement
  (the level this run counts of MinBlaster), Rebirth (the same SURE? second press) OR Not now (closes).
  STAR SHOP and BLASTERS stay as small tabs (their pages get the old room back).
- Boost corner (main 920906f2): the reel's bright studded squares, the time over the bottom edge; the train
  chip a dark tile with a blue edge.

### What is still not 1:1, and why
- The TRAIN chip stays a chip with SEND under the tiles (the reel has nothing there; its SEND and the T key are
  game features); it now wears the dark tile look.
- Windows built on MenuPanel keep their own sizes (Codex, Settings, Quests...): their content is richer than
  the reel's single cards; they are centred like the reel's unless they would cover the left tiles.
- Studs on the faces and bands need the ui_studs picture uploaded (the previews draw it); until then the bands
  keep the fine checker.
- The reel's world blur behind open windows (a camera BlurEffect) is not built; ours dims.
- At 1080p the HUD scale stops at 1.25 (HudController.uiScale), so the whole UI is 83 % of the reel's size
  there; the sheets compare at the preview's 720 design units, where it matches.
