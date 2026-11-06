# Egg opening V2 (owner 2026-10-30, "ULTIMATE EGG OPENING V2")

Branch `anim/egg-v2`, on top of `anim/egg-redo` 0a735457 (the clicker-video opening, still waiting for the
owner's OK). V2 keeps that flow, its rules and its server untouched and adds the owner's phases and a
rarity cinematic. Client only: the server (CapsuleService) still rolls, charges and grants every golem once;
the opening only shows the confirmed result.

## The flow (UI/HatchFx timeline, UI/HatchStage poses, Open 3 of Commons)

| Phase | Seconds | What |
|---|---|---|
| Entrance | 0 - 0.68 | the eggs rise into place from below, 0.3 -> 1 of their size (Back), 0.09 s apart, a half turn settling; a glowing platform grows under each |
| Float | 0.68 - 1.23 | slow bob, slow turn, a few motes rising |
| Charge | 1.23 - 2.68 | white rings + puff, two energy rings orbit each egg (opposite ways, faster and faster), motes stream in, the glow behind the egg grows, a 2 Hz size pulse, a growing shake, the cracks in three steps in the colour of the golem inside |
| Burst | 2.68 - 2.84 | silhouette, ONE flash (RevealKit gap; stronger for the rarer), shell pieces, rings fly apart, platforms flare |
| Reveal | 2.84 - 4.19 | golems 0.3 -> 1 (Back), bob, aura, name + "1 in N", up to 5: a rarity pill over each head with the bonus ("+10% Income") |
| Fly | 4.19 - 4.64 | they spin and fly to the player; the HUD comes back |

Every number is in `HatchFx.Times` (Normal / Fast = Auto / Calm = Reduce motion) and `HatchFx.Tiers`.
Totals: Open 3 Commons 4.64 s, Epic 4.84 s, Legendary 6.19 s, Mythic 6.79 s, Auto about 2.1 s.

## The rarity cinematic (`HatchFx.Tiers`, by the batch's best rarity)

| Best | Show |
|---|---|
| Common | soft white glow and sunburst, 8 confetti, flash 0.55 |
| Uncommon | green tint, 1 energy pulse ring, 12 confetti |
| Rare | blue, 2 energy pulse rings, 18 confetti |
| Epic | strong purple aura, flash 0.8, the blurred world tinted (ColorCorrection on the camera) |
| Legendary | golden rays, suspense 0.8 s, slow-motion pop 0.55 s, gold confetti, LEGENDARY! + the golem's bonus, chime |
| Mythic | rainbow rays and energy, suspense 1 s, slow pop 0.65 s, rainbow stage light, rainbow confetti, MYTHIC! (the server already tells the others: CapsuleService.announce) |

## Rules kept
- Skip (tap / Space / Enter / A) goes to the burst, then on only after MinShow: every golem is seen, named.
- Auto plays the fast timings; x50 packs play as openings of 10 ("2 / 5").
- Reduce motion: no rise, float, orbit, motes, pulses, shake, flash or spin; fades only.
- Phones: the full show (owner 2026-10-30: "don't hold back for phones, it must be clean and smooth").
- Smooth: every rock of the eggs is a slow sway (HatchFx.sway, 2.8 - 4.4 a second) whose strength only
  ramps (crack steps ease in, the silhouette stills it eased): no buzz, no jump between two frames.
- Everything is pooled (CapsuleView.buildOpening) and hidden by HatchStage.clear; the world tint is
  removed with the blur (CapsuleController.endChain) and after a failing opening.
- Review round 1 (integrator 2026-10-30): the banner's word is fitted ONCE a run (HatchStage.bannerFit,
  from the pills' rest and bob range; only the word shrinks, the sub line stays at TagMin or more); the
  pills step aside for AUTO like the names (else the rarity alone, else none); the show (Tier, banner,
  pulses, tint) follows the best golem the player KEEPS, an auto-deleted one is never celebrated; the
  Mythic banner's rainbow turns evenly (Paint.Rotation, one sequence); every sway eases out over the
  silhouette (sampled every ms: at most 0.5 degrees and 0.4 % a ms).

## Files
- src/client/UI/HatchFx.luau: Times (entrance, float), Tiers, timeline, eggPose (Drop, Yaw, Charge),
  platformAt, orbitAt, moteAt, auraAt, pulseU, bannerAt, lightAt, flashPeakOf, bonusText.
- src/client/UI/HatchStage.luau: dress, posePlatforms, poseOrbits, poseMotes, poseAuras, poseBadges,
  poseRarity, pulses in poseRings, tier confetti, events "Charge" and "Banner".
- src/client/UI/CapsuleView.luau: pooled Platforms, Orbits, Motes, Auras, Badges, Banner; setBadge,
  fadeBadge, setBanner; Inset; banner sizing in layoutOpening.
- src/client/Controllers/CapsuleController.luau: sounds on Charge / Banner, setMood (ColorCorrection).
- tests/EggOpening.spec.luau: V2 timings, poses, layers, every rarity's show, clear.
- tools/lune/export_egg_panel.luau: `redo v2` stills, `redo v2video`.

## What to check in Studio
Open 1 / 3 / 10 on each egg; a Legendary and a Mythic (Studio test place, give coins); Auto; skip at each
phase; Reduce motion on; a phone in the device emulator (812 x 375) and an iPad; reset the character
mid-opening (the HUD and the world tint come back); the frame rate on a phone during Open 10.
