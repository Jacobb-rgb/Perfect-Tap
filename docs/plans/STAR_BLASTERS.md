# Star blasters (built 2026-10-20, the owner's picks)

This was the owner's idea: five new weapons above LV 10 that open only after rebirths. Each one is bought **once**,
with Robux (a game pass) or with Forge Stars, and is **kept through every later rebirth**, because losing something
you paid for isn't fair.

Pictures:
- `build/preview/shots/star_lineup.jpg`: all five (scene `star_blasters`, `tools/lune/lib/star_blasters_preview.luau`)
- `build/preview/shots/star_held.jpg`, `star_held_front.jpg`: LV 10 and the five held (scene `star_blasters_held`)
- `build/preview/shots/rebirth_blasters_pc_light.jpg`, `rebirth_blasters_phone_light.jpg`: the Star Forge's
  BLASTERS tab (scene `rebirth`, `LIGHT_UI=1`). The card pictures are the icons `star_<id>`
  (`lune run tools/lune/export_icon_parts.luau star_Comet ...`, then `node tools/preview/render_icons.mjs star_Comet ...`).

## The owner's picks

- **Power A:** a star blaster hits Mult × the damage of the blaster level you forged (x1.2 to x1.8). The floors, the
  range and the rebirth stars still follow the forged level, so a rebirth run is never skipped.
- **Earning 2:** Robux **or** Forge Stars.
- **Prices** (Robux halved from the first draft):

| Weapon | Kenney shape | Opens at rebirth | Power | Robux | Forge Stars |
|---|---|---|---|---|---|
| Comet Launcher | blaster-h (launcher) | 1 | x1.2 | 75 R$ | 20 |
| Nebula Twin | blaster-l (twin barrels) | 2 | x1.35 | 125 R$ | 30 |
| Pulsar Rifle | blaster-f (long rifle) | 3 | x1.5 | 199 R$ | 45 |
| Supernova Gatling | blaster-o (four barrels) | 5 | x1.65 | 299 R$ | 65 |
| Singularity Rail | blaster-q (twin rails) | 8 | x1.8 | 449 R$ | 90 |

## How it works

- **Data:** `src/shared/Config/StarBlasterData.luau` holds the list and the rules: unlocked, owns, equipped, mult,
  quote, buy and cardState. The shapes are KenneyBlaster models 11-15, traced by `tools/kenney/blaster_lite.py`.
- **Save:**
  - `RebirthWeapons = { [id] = true }` lists the weapons you own.
  - `RebirthWeaponPasses = { [id] = true }` lists the ones a pass gave.
  - `StarBlaster` is the equipped id ("" = the forged blaster).
  - RebirthConfig.reset never touches these fields. Migrations keeps a newer build's short ids.
- **Game passes:** MonetizationConfig `StarComet` … `StarSingularity` are built from StarBlasterData, so their
  prices always match. They have Grant "RebirthWeapon" and a WeaponId. RebirthService registers the handler:
  - Grant: the weapon is owned and marked as given by the pass. It is equipped when it is open and nothing else is
    in hand. A pass bought before its rebirth waits, and the card says "Yours! It opens at rebirth N".
  - Buying with stars waits until Roblox has answered the weapon's live pass check ("Checking"). If a weapon was
    bought with stars too, its stars come back once and from then on the pass holds the weapon.
  - Revoke (a refund) takes back only a weapon the pass gave.
- **Stars:** RebirthAction `{ Action = "Weapon", Id }` buys with stars once Rebirths ≥ Unlock and equips the weapon.
  `{ Action = "Equip", Id }` switches weapons ("" = the forged blaster).
- **In the hand:** ToolService builds `BlasterBuilder.buildStar`. It uses the star's shape and glow, the forged
  level's Range and Level, and the attribute `Star`; the beam effects use the top tier.
- **Jewellery (owner 2026-10-20: "paid weapons must be mega cool", then "more rounded, cleaner, perfect"):**
  KenneyBlaster Tier 4 (BlasterBuilder.starSkin) is clean, round jewellery on the approved Kenney shapes, built
  from Part cylinders and balls:
  - On top: three smooth crystals, round columns with round tips (the tall one in the middle, two leaning forward
    and back), in a round gold cup. StarFit.Crystal keeps the tips under the head.
  - On the main panel: one clean row of round gems (StarBlasterData.Gem: a sapphire, an aquamarine, a topaz, a ruby
    and a pink rhodolite) in round gold bezels, 3, 2 or 1 depending on the panel.
  - At the muzzle: a round glowing disc. A single slim barrel (StarFit.Ring) also gets a round gold ring set with
    four round gems.
  - Nothing busy: no stars, cracks, side crystals or spikes. The glowing rim stays.
  - The held tool carries a StarGlow PointLight in the star's color (range 8, no shadows).
  - Parts per held tool: Comet 57, Nebula 44, Pulsar 78, Supernova 51, Singularity 47 (MaxParts 90).
- **Held size:** KenneyBlaster.scale gives a star LV 10's length unless that makes it bigger than the biggest level
  bodies (`KenneyBlaster.StarFit`: 2.3 tall, 1.25 wide, 1.9 behind the hand). The stubby shapes (Nebula, Supernova)
  come out shorter. A KenneyBlaster.spec test keeps every level and star inside that budget. The picture is
  `build/preview/shots/star_held.jpg` (scene `star_blasters_held`: LV 10 and the five in a dummy's hand).
- **Damage:** MiningService multiplies by `StarBlasterData.mult`. The beam takes the star's Glow.
- **Window:** the Star Forge gets a 3rd tab, BLASTERS. Each card shows a live 3D gun (ViewportFrame) and
  ⭐ price + R$ price, EQUIP / EQUIPPED, or 🔒 REBIRTH n. The R$ button shows only once the weapon is open, and it
  prompts only for a live pass id while the receipts gate is open.
- **Coins:** the weapons never give coins (the no-Robux-to-coins rule).
- **Tests:** `tests/StarBlasters.spec.luau`, plus the keep list in `tests/Rebirth.spec.luau` and the pass list in
  `tests/Step8Receipts.spec.luau`.

The owner still needs to create the 5 game passes on the Creator Dashboard, paste their ids into
MonetizationConfig and keep them Off Sale until step 8 opens the receipts gate (docs/COMPLIANCE.md 2.6a).
