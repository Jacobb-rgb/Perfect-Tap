# Hatch v2: the egg opening, Pet Simulator 99 quality (owner 2026-10-29)

> Superseded the same night (owner 2026-10-29, ~23:00): the egg opening follows the owner's
> clicker-sim video instead (docs/plans/CLICKER_VIDEO_2026-10-29.md, package A1: UI/HatchFx,
> UI/HatchStage). This plan was never shown in game; only RevealFx (its shared reveal, used by the
> secret ores) stays from it.

Owner: "a much, much better look and animation for opening eggs; take
inspiration from Pet Simulator". The starting point is the 2026-10-28 "wow
hatch" (HatchFx: wobble, cracks, leaking light, the break, the solid golem
on rays). We copy the FEEL and the quality bar, never their images, sounds or
UI art: our eggs, our golems, our fonts (Montserrat / Fredoka, Roblox's), our
sounds (the shipped files and Roblox-uploaded ids).

## What PS99 does (studied from hatch videos, frame by frame)

Sources: YouTube hatch videos, sampled at 0.2-0.5 s per frame (a "Huge hatch
animation" short, a "Rainbow Huge Elephant" hatch, a long mass-hatch
session). What we saw, step by step:

1. **The eggs come to the camera** (about 0.2 s). The bought eggs appear right
   in front of the camera, over the world (no window), in a neat grid: one
   egg big in the middle; several eggs in rows that fill the screen's width.
   The world stays visible, a little blurred and darkened behind.
2. **They wobble together** (about 1 s normally, about 0.3 s with fast
   hatch). Side to side, faster towards the end; all eggs in step.
3. **The break** (about 0.2 s). The eggs go white (a soft flash over the
   eggs, not the whole screen) and pop.
4. **The pets stand where the eggs were** (held about 0.6-1 s), each with its
   name under it in a white, rounded, heavy font with a dark outline; the
   rare ones have a coloured name / glow. Then they fly off towards the
   player.
5. **The big moment (a Huge)**: the other eggs vanish; the special one turns
   into a swirling cloud of light with sparkles and streaks (about 3 s of
   suspense, the camera nudging); a full-screen white-to-colour flash; the
   pet appears HUGE in the middle of the screen, for a Rainbow its colour
   cycling; about 0.8 s later its name and a small badge appear under it;
   held about 1.5 s. Then the normal pets of the batch show.
6. **Fast and auto**: with fast hatch a whole batch takes about 1.6-2 s
   (eggs in 0.2 s, wobble 0.3, flash 0.2, pets 1 s, fly away 0.3). Auto keeps
   hatching batch after batch; every pet still shows with its name.

What makes it feel good: everything is BIG and centred, the timing is short
and rhythmic (no waiting), one strong flash per batch, the rare moment is
long and different (suspense, then a reveal), names always under the pets,
and the eggs and pets are where your eyes already are.

## Our plan (Terra Forge)

The overlay stays (it shows the odds' note, OPEN AGAIN and the buttons), but
the stage is new:

| Phase | Normal | Fast (Auto) | Reduce motion |
|---|---|---|---|
| Fly in: eggs fly up from the bottom into their places, a spin and a bounce | 0.35 s | 0.2 s | eggs fade in 0.2 s |
| Wobble: harder and faster, cracks glow, light leaks (by rarity) | 0.9-2.0 s | 0.45-0.9 s | still 0.4 s |
| Suspense (Legendary / Mythic in the batch): that egg rises, glows in its colour, the rays gather, a slow nudge | 1.1 s | 0.6 s | none |
| Break: one flash (rate-capped), shell pieces, a ring; eggs of a batch pop in a fast ripple (0.06 s apart) | 0.25 s | 0.2 s | fade 0.3 s |
| Golem(s) pop out where the egg was (solid, bouncy), name + rarity + chance | held 1.7 s (one) | held 0.8 s | fade in |
| Jackpot moment (Legendary / Mythic): the golem centre-stage, big, gold / rainbow rays, headline "LEGENDARY!" / "MYTHIC!", screen shake, its own sound | until tap (Auto: 2 s) | 1.2 s | still, no shake |

- **One egg**: big in the middle; the golem pops big on rarity rays
  (RevealFx), its name, the rarity pill and its chance under it.
- **Open 3 / Open 10**: a wide stage; the eggs in a row of 3 or two rows of 5
  fill it; they wobble together and pop in a ripple; each golem stands where
  its egg was, its name and chance under it, the rarest on rays. A Legendary /
  Mythic then gets its jackpot moment, and the grid comes back.
- **Fast / skip**: Auto uses the fast timings. A tap / Space / A jumps to the
  next step (a result always shows at least 0.3 s with its name). Skip all
  (B / Backspace) jumps to the end: every golem of the batch on the stage,
  named. Nothing is ever skipped without being shown (paid random items).
- **Rarity tiers** (RevealFx.tierOf): Common / Uncommon = Normal (12 rays),
  Rare / Epic = Rare (16 rays, sparkles), Legendary / Mythic = Jackpot (two
  ray layers, gold / rainbow, headline, confetti, shake, own sound), "Secret"
  (secret ores) = black and rainbow.
- **Rules kept**: golems SOLID (nothing see-through over them: rays, glow and
  flash sit under the golem's viewport); EggPanel.BigE; the odds stay with
  names; flashes at most 2.5 a second (one shared clock: RevealFx.FlashGap);
  Motion.reduced() gets the short, still version; skip / continue 44 pt;
  A continues on a gamepad; text 18 px and more at 1080p; phones: calm eggs
  for more than 3, particles capped and pooled, the stage's models freed on
  close.

## RevealFx (shared with the secret ores' jackpot reveal)

`src/client/Effects/RevealFx.luau`: the rays, the soft glow, the flash (the
shared cap), the sparkle burst, the banner (name, rarity pill, chance, NEW!)
and the jackpot / secret tiers. `RevealFx.show(kind, itemId, rarity, opts)`
draws into any parent (a frame or a ScreenGui) and returns a handle
(`close`, `setCenter`, `pose`). Its API and look are documented at the top of
the file. The egg hatch (CapsuleController, HatchFx) and the secret ores
(Effects/SecretReveal, the "Návrhy strojů" chat) both call it.

## After the eggs: blaster cases at the Vault

Proposal only (one picture, no code): the same RevealFx rays, banner and
jackpot tier for CrateOpeningView's result, the crate background unchanged
(the owner kept the old one on 2026-10-28).
