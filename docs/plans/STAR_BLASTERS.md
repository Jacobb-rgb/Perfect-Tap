# Star blasters (proposal, 2026-10-20)

The owner's idea, replacing "buy the next blaster level for Robux": five new weapons above LV 10 that open only after
rebirths. They can be bought for Robux, and they are **kept through every later rebirth**, because losing something
you paid for isn't fair.

Pictures:
- `build/preview/shots/star_lineup.jpg`: all five
- `build/preview/shots/star_close_a.jpg`, `star_close_b.jpg`: close-ups

They come from `tools/lune/lib/star_blasters_preview.luau` (scene `star_blasters`).

## The five

Each one uses a Kenney Blaster Kit shape the levels don't use, in its own sky skin with sparks or flames.

| Weapon | Kenney shape | Opens at rebirth | Power (option A) | Robux (placeholder) | Forge Stars (option 2) |
|---|---|---|---|---|---|
| Comet Launcher | blaster-h (launcher) | 1 | x1.2 | 149 R$ | 20 |
| Nebula Twin | blaster-l (twin barrels) | 2 | x1.35 | 249 R$ | 30 |
| Pulsar Rifle | blaster-f (long rifle) | 3 | x1.5 | 399 R$ | 45 |
| Supernova Gatling | blaster-o (four barrels) | 5 | x1.65 | 599 R$ | 65 |
| Singularity Rail | blaster-q (twin rails) | 8 | x1.8 | 899 R$ | 90 |

The data is in `src/shared/Config/StarBlasterData.luau`. The shapes are KenneyBlaster models 11-15, traced by
`tools/kenney/blaster_lite.py`; level guns 1-10 are unchanged.

## The owner's choices

**Power**
- **A (recommended):** the star blaster hits Mult × the damage of the blaster level you forged. It is the best gun at
  every level, and after a rebirth it doesn't skip the run: the floors still open with your forged level, and the
  stars still count only Foundry levels.
- **B:** a fixed power above LV 10 at any level. A rebirth run becomes trivial with it, so it is pay-to-win.

**Earning without Robux**
- **1:** Robux only.
- **2 (recommended):** Robux OR Forge Stars in the Star Shop (prices above). Free players get them too, just later.
- **3:** free at a higher rebirth count (for example Comet at rebirth 3). Robux opens it as early as its own rebirth
  count.

**Prices**
- The prices above are placeholders: one-time game passes, owned forever.

## How it works in the game (agreed with the integrator, to build after the picks)

- **Game passes:** one-time passes with Grant "RebirthWeapon" and a WeaponId (MonetizationService.registerPass:
  granted on every join and on a purchase; a refund takes it back).
- **Ownership:** data.RebirthWeapons { [id] = true }. RebirthConfig.reset never touches it.
- **Unlocking:** a weapon can be sold and equipped once Rebirths >= Unlock. A pass bought on the game page before
  that waits, and its card says "opens at rebirth N".
- **Equipping:** data.StarBlaster = the equipped id, or "" for your forged blaster. VaultService / ToolService hand
  it out. Its beam takes the weapon's glow. With power A, the damage is BlasterData.damage(your level) × Mult.
- **Stars:** star weapons never change what a rebirth pays (RebirthConfig.reachedOf counts Foundry-forged levels).
- **Coins:** none ever (the no-Robux-to-coins rule).
