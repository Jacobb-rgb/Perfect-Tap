# Owner's four reels (2026-10-27): animations + the UI look

The owner (Czech) sent four Instagram reels and wrote: "here you can see how my UI in our game should look; add it,
and send me how our animations work in the game, the ones I want to add now, which you'll find in those videos".
Frames from every reel are in `docs/art/reels_2026-10-27/` (file names say what each frame shows). Nothing is copied
1:1 (the UI reel is a paid UI pack): we take the feel, layout ideas and style, built from our own Pop kit.

## Reel 1 – motionbykrit "How do games make a level up feel satisfying?" (levelup_*.jpg)
Five steps, each added on top of the last:
1. **Slow fill** – the bar races, then slows near the end ("you hold your breath"); the full bar glows bright.
2. **Flash** – a white flash with sunburst rays out of the character.
3. **Light pillar** – a pillar of light at the character, rings ripple out across the floor.
4. **Sound** – a rising "whoosh" while the bar fills, then a warm chime; a comic "WHOOSH!" word pops beside the bar.
5. **Stats** – a big tilted gold "LEVEL UP!", then the stats tick up one by one (STR 15 +3, SPD 9 +1, HP 48 +8).

The game already has most of it (LevelController, UI/LevelView, Effects/LevelBurst from a similar reel on 10-21):
orbs fill the bar, glow past 75 %, burst + flash + rays, LEVEL UP!, reward rows counting up. Missing / to improve:
the slow-down before full, the rising whoosh + warm chime sound, the "WHOOSH!" word, rings rippling across the floor
(check LevelBurst's rings read as ripples), rows ticking "tick by tick".

## Reel 2 – motionbykrit "How do games make mining feel satisfying?" (mining_*.jpg)
1. **Cracks** – every hit cuts a bigger dark crack into the rock.
2. **Chips** – little chips fly off every hit.
3. **Sound** – a dry "tok" on every hit and a crunch when it cracks.
4. **Shake** – the rock shakes on each hit.
5. **The break** – the last hit smashes it (a comic "SMASH!" word, dust, rock chunks), the crystal floats up glowing,
   then flies into your bag (a bag icon with a count that bumps).
Bonus: **ore glints** – glowing gold flecks/cracks in the rock.

The game has Effects/RockFx + RockFxLogic (stage cracks: dust, glowing shards, flash, crack sound, punch; tremble
while blasted; shatter with chunks, ring, camera shake) and WorldMotionController's ore pop (built, switched off in
AnimConfig.WorldFx). Missing: visible cracks on the rock that grow each stage, the "SMASH!" word, the ore floating up
and flying into the carry/backpack slots with a bump, gold glints. Rule: dirty ore never shows its rarity before it is
cleaned (docs/DESIGN_V2_NOTES.md), so glints/cracks are a neutral warm gold, never the ore's rarity colour.

## Reel 3 – motionbykrit "Make weather feel alive!" (weather_*.jpg)
Seven effects + a bonus, on a small floating island:
1. **Rain** – angled rain, splashes on the grass, ripples in the puddles.
2. **Thunderstorm** – heavier rain, the whole sky flashes, thunder hits a beat later.
3. **Hail** – little balls of ice that bounce and clack off everything.
4. **Snow** – drifts down slowly and piles up softly on everything.
5. **Fog** – soft layers of mist roll in and fade everything out.
6. **Wind** – trees bend from the bottom up, leaves blow across.
7. **Heatwave** – the air shimmers, the sun is cranked up.
Bonus: **rainbow** – after a quick shower the sun comes back and a rainbow fades in.
The game has no weather yet.

## Reel 4 – arestodev "Advanced UI Pack" for Roblox (ui_*.png/jpg)
A classic Roblox simulator UI:
- **Font**: a heavy round cartoon font with a thick dark outline everywhere (titles, buttons, prices, tiles). Not pixel.
- **Windows**: a coloured header band per window (Store red, Index blue, Inventory orange, Daily pink, Settings grey,
  Teleport purple, Rebirth magenta, Sell green, Upgrade green, Item Shop blue, Trade amber) with a diagonal stripe
  texture, the window's icon at the left, a big faded copy of the icon in the band's middle, a bold title and a red
  square X. A dark charcoal body with a thin dark border. Sections titled "- Gamepass -", "- Buy Cash -", "- Codes -".
- **Cards**: vivid gradient + sunburst behind a big icon, bold title top right, short description, a purple gift
  button + a green "R$179" price button at the bottom right.
- **HUD**: left a 2-column grid of square tiles (dark tile, big coloured icon, white label under it, an "OP!" sticker
  on Store); top centre three coloured tabs with an icon (Shop red, Spawn green, Plot yellow); right side offer icons
  with a small "R$49" tag; bottom right square boost icons with a counter; bottom left the money "$0" big in green
  with a small line under it.
- **Other windows**: daily rewards (7 day cards, Claimed / Claim / LOCKED, a big rainbow day 7), index with rarity
  filter tabs outside the window (Common grey, Uncommon green, Rare blue, Epic purple, Legendary yellow), inventory
  with a search box and counters, settings rows with sliders and ON toggles, teleport list with area pictures and a
  padlock + UNLOCK, rebirth "x1.5 -> x2.0" rows with a progress bar and Rebirth / OR / Skip Rebirth, stock shop with
  Restock, sell list with Sell All, trade, upgrades, a hex skill tree. Confetti bursts after a purchase.

Our Pop kit (UI/Pop, Config/PopTheme, UI/MenuPanel) already has the header stripes, red X, dark body, green price
buttons, rays and tiles; the biggest difference is the pixel font (owner's 10-22 pixel reels) and the window colours.

## Work packages (each on its own branch from anim/reels-10-27, disjoint files)
| Branch | Package |
|---|---|
| anim/weather | the weather system (new files only + the ORDER line) |
| anim/mine-juice | reel 2 mining extras + reel 1 level-up sound / slow-down / WHOOSH! |
| ui/round-look | reel 4: the round-font look + window colours + header icons + sections, as a PopTheme switch |
Merged into anim/reels-10-27 by the "Animace ve hře" chat, checked, then pictures and videos go to the owner.
