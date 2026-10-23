# Pixel UI brief (owner 2026-10-22)

The owner sent 8 Instagram reels (phox_dev / Framewisp Roblox UI buttons) and said:
"make the UI for the shop, inventory etc. and the icons exactly like in the videos, exactly like this,
this is the right Roblox style". Reference frames: **docs/art/ui_pixel_refs/** (look at all of them first).

## What the reels look like
- **Font:** a chunky pixel font (we use Press Start 2P: `PopTheme.Pixel`), white, thick black outline, often a dark
  drop shadow. Every short word (titles, buttons, prices, labels) is pixel. Long wrapped text stays round
  (`PopTheme.Font`) so it stays readable.
- **Faces:** rounded rect (radius ~10% of a 100 square), thick black outline (3.5-4), a smooth gradient light top ->
  deep bottom, a **darker lip** along the bottom (depth), a **light gradient edge** just inside the outline, a
  **diagonal lattice** (thin light lines both ways) or small square studs over the paint.
- **Square icon buttons** (02 rebirth, 03 VIP, 04 book, 06 cart): a big outlined cartoon picture filling the square,
  a **sunburst** of light rays behind it (turning), the picture **leans** on hover.
- **Wide buttons** (01 Shop, 05 BUY, 07 INVENTORY): the picture overlaps the left end, pixel word, a **gleam** (light
  band) sweeps across now and then.
- **Shop window** (08): rainbow header with a big pixel "SHOP" and the cart picture, red square X, dark grey body,
  small pixel section word ("GAMEPASSES"), a wide orange VIP banner (crown + big "VIP" + "+500" lines + green BUY
  with a tilted "229R" price tag), then square cards in a row (MAGNET red, x2 MONEY green, x2 GEMS blue): pixel
  title at the top, the picture in the middle with tilted "119R" price tags on both sides, a short pixel line at the
  bottom ("+200 RADIUS").
- **Icons:** cartoon objects with a THICK black outline and a little blocky/stud texture on their surfaces
  (magnet, cash stack, gem, basket, crown).

## The kit (branch ui/pixel, src/client/UI/Pop.luau + src/shared/Config/PopTheme.luau)
Already done in the kit (every Pop window gets it): `Pop.text` (pixel for short words, `Pop.fit` shrinks a pixel word
to its box), `Pop.face` (lip + gradient rim), `Pop.studs` = `Pop.lattice` (frames, no upload), `Pop.gleam`,
`Pop.rays` (turns), `Pop.tile` (reel square button), `Pop.pill` (reel wide button), `Pop.fxTag(instance, kind)`
(attribute PixelFx = Spin / Gleam / Lean / Press read by Controllers/PixelFxController).
Use the kit; don't fork it. If you need a kit change, keep it small and say so in your report.

## Rules
- Visual only: never change game logic, Net calls, save data, refs other code reads, or button names other code
  finds. Keep every function signature other files call.
- No emoji. UI text English. Strict Luau (`luau-lsp` clean), never start a line with `(`.
- Phones: touch targets >= 44 pt at the 0.62 phone scale; check a phone render.
- Format only the files you touched with stylua (never `stylua src`).
- Run `bash tools/check.sh > build/check.log 2>&1; echo $?` before your final commit; it must end "ALL CHECKS PASSED".
  Never `pkill` shared commands (other chats run tests too).
- Pictures: render before/after with the preview tools (preview-pictures skill), copy keepers to
  docs/screenshots/ui_pixel/.
