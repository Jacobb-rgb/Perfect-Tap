# TERRA FORGE – Store page (Roblox game details page)

This file is everything you need for the game's page on Roblox, ready to copy and paste.
Roblox rules were checked on **2026-10-12**. The sources are at the bottom.

- `TODO` = you must fill this in by hand.
- Text inside the grey code boxes is ready to paste. Everything else is notes for you.
- Roblox now says "game" where older docs said "experience". Both mean the same thing here.

---

## 0. Before you paste

### Only claim what is in the build

Roblox shows fewer people a game whose page doesn't match the gameplay. So before you publish,
tick each line below once it really works in the live build. If something isn't in yet, cut it
from the description.

| Claim on the page | Build step (see `PLAN.md`) | Works in the live build? |
|---|---|---|
| Mine nodes, physical chunks, carry and throw | b | [ ] TODO |
| Cleaning Station: chisel, scrape, polish, grades up to Flawless | c | [ ] TODO |
| 10 ores, Quarry, Ember Caves, Deep Hollow, VIP Glimmer Grotto | a, b | [ ] TODO |
| Crush, smelt, anvil (dagger, helm…), selling | d, e | [ ] TODO |
| Furnaces, crushers, anvils, conveyors on your own plot (9 machines, Cleaning Station included) | d | [ ] TODO |
| Daily Ember Chest, Ore Codex, badges (today only the "New ore discovered" tracking exists, no Codex screen yet) | e, f | [ ] TODO |
| Passes are optional, every ore can be mined without them | f | [ ] TODO |
| "PC, phone, tablet and console": the **Console** device box is ticked and the game was tested on a controller. If not, remove "console" / "i konzoli" from both descriptions | f | [ ] TODO |

### Dashboard checklist

- [ ] **Maturity & Compliance Questionnaire** (Creator Dashboard → Configure → Questionnaire). Answer honestly.
      There is no combat and no blood. The dagger, greatsword and helm are only crafted goods you sell; nobody can
      equip or swing them. The forge name is a short typed name that goes through Roblox's text filter, not freehand
      drawing or writing, so it isn't "free-form user creation". There are no paid random items.
      You can't make the game Public (or Limited) until the questionnaire is done, and Roblox restricts games
      without it. Full answers: `COMPLIANCE.md` section 1. TODO: fill it in and note the label you get here: `TODO`.
- [ ] **Audience**: to reach players under 16 (Roblox Kids and Select accounts), your account must be verified
      (government ID if you are 18+, face age estimation if you are under 18) with 2-step verification on, and you need
      either Roblox Plus/Premium for 2 months in a row or the refundable publishing fee (1,000 Robux per game).
      The game also has to pass Roblox's evaluation (250 unique plays by highly engaged, age-checked players within
      60 days, plus a safety review). Until then, only age-checked players aged 16+ can play it.
      TODO: decide which route you take.
- [ ] **Description length**: the limit is **1,000 characters** (Roblox's "Game descriptions" guide). Both descriptions
      below fit (English 908, Czech 954 characters, counted with the emoji), so keep the "What's new" line short.
      TODO: check the counter in the dashboard when you paste.
- [ ] **Czech**: Czech (`cs` / `cs-cz`) is in Roblox's language list. First add it under Creator Dashboard →
      Localization → **Languages** → Add Language, then paste the Czech text in **Translate** → Czech →
      **Information** tab. Czech is **not** on Roblox's automatic-translation list, so without your text Czech
      players see the English one. TODO: check with an account set to Czech that the Czech page really shows
      (I could not confirm that Czech is a language players can pick in the Roblox app).
- [ ] **Social links** (Engagement → Social Links): up to 3 links, and each type only once. You can choose from Facebook, X/Twitter,
      YouTube, Twitch, Discord, Guilded or a Roblox Community. You must be age-checked as 16+ to add them,
      and only age-checked 16+ players can see them. Don't put URLs in the description or inside the game.
      TODO: your links.
- [ ] **Group / Community**: TODO: community name. The design gives 500 coins for joining once. That's fine in-game,
      but don't make it the headline anywhere. Roblox shows fewer people pages that lead with rewards.
- [ ] **No "like" or "favorite" reward**: it isn't in the design, and Roblox has no rule that allows it.
      The Community Standards ban misleading content or metadata used to drive engagement, and DevForum answers warn
      that paying players for a thumbs-up can get a game moderated. Code can't check likes anyway. Leave it out, and
      never mention likes, favorites or rewards in the description or thumbnails.

---

## 1. Title

**Exact title string (use this):**

```text
TERRA FORGE
```

Roblox has no separate subtitle field yet. You can use a subtitle in two ways: (a) on social posts and the trailer's
end card, or (b) added to the name. If you add it to the name, choose before launch and then keep it.
Roblox says renaming often makes a game harder to find.

**Subtitle variant A** (the feeling of the game, 32 characters as a full name):

```text
TERRA FORGE: Mine, Clean & Forge
```

**Subtitle variant B** (search keywords, 37 characters as a full name):

```text
TERRA FORGE: Mining & Crafting Tycoon
```

Czech name (optional, Localization → Czech → Information → Name). Only use it if you also chose variant A
for the English name; with plain TERRA FORGE, leave the Czech name empty so it stays the same:

```text
TERRA FORGE: Těž, čisti a kuj
```

My pick: launch as plain **TERRA FORGE** and use variant A on social posts and on the trailer's end card
(not on thumbnails: our thumbnail rule below allows only the logo). The name stays short, easy to remember and the
same in every language. Roblox's roadmap lists "name checks" for late 2026, which will protect game names from
copycats and add a separate **promotional text** field for update info. A stable name will help then, and when that
field ships, move the "What's new" line there.

---

## 2. English description

**Hook (the first line, 124 characters).** Roblox's description guide says the first ~160 characters show in search
snippets and on mobile before "read more", so it names the game, the genre and the unique feature:

```text
TERRA FORGE is a mining and crafting tycoon: mine glowing ore, clean it by hand and forge it into gear in your own workshop!
```

**Full description (paste as is, 908 characters):**

```text
TERRA FORGE is a mining and crafting tycoon: mine glowing ore, clean it by hand and forge it into gear in your own workshop!

The Heartstone, the heart of Terra, has shattered into glowing ore. Join the Forgekeepers' Guild in Emberfall and help reforge it.

⛏️ HOW IT WORKS
• Crack ore nodes with your pickaxe. Real chunks drop: carry them or throw them
• Clean each chunk by hand: chisel, scrape, polish. Can you get Flawless?
• Crush and smelt ore into ingots, forge daggers, helms and more, then sell
• Set up furnaces, crushers, anvils and conveyors on your own plot
• Find 10 ores in the Quarry, Ember Caves and Deep Hollow, up to the mythic Heartstone Shard
• Daily Ember Chest, Ore Codex and badges
• No combat. Every ore can be mined without a game pass

🎮 Play on PC, phone, tablet and console

🆕 WHAT'S NEW (v1.0, TODO date)
• Launch! 3 mining zones plus the VIP Glimmer Grotto, 10 ores, 9 machines
```

The "What's new" block: replace it with every update and keep it to 1–2 lines, so the whole text stays under the limit.
Only list things that are in the build you just published.

No controls in the description: Roblox's description guide asks creators not to list controls there and to teach
them in the game instead (they also eat the character limit). Use the table below for the tutorial and the
on-screen hints.

### Controls reference (taken from the code, for the in-game tutorial)

| Action | PC | Mobile | Console |
|---|---|---|---|
| Mine | Left click, aim with the mouse | Tap | R2 |
| Grab / drop a chunk | E | "Grab" button | X |
| Throw (hold to charge, release) | Q | "Throw" button | R1 |
| Use the Cleaning Station | F | Tap the prompt | Y |
| Cleaning: chisel / scrape / polish | Hold left mouse button and drag | Drag with your finger | Left stick moves the tool, hold A (or R2) |
| Polish without circling (accessibility) | "Hold to rub" toggle | same | same |
| Leave cleaning / collect the result | Leave button or Backspace / E or Enter | Leave / Collect buttons | B / A |
| Other machines, build mode | TODO (step d) | TODO | TODO |

Sources in code: `src/client/Controllers/InteractController.luau`, `CleaningController.luau`,
`src/client/Cleaning/PointerInput.luau`, `src/server/Services/CleaningService.luau`.

---

## 3. Czech description (Popis v češtině)

Written for Czech players, not translated word by word. Place, item and grade names stay in English
because that's how players see them in the game. The game itself is in English for now, so the Czech text says so
(remove that sentence once the game is translated).

**Úvodní věta (1 řádek):**

```text
TERRA FORGE je tycoon o těžbě a kovářství: těž zářící rudu, ručně ji vyčisti a ve své dílně z ní ukovej výbavu!
```

**Celý popis (vložit beze změn, 954 znaků):**

```text
TERRA FORGE je tycoon o těžbě a kovářství: těž zářící rudu, ručně ji vyčisti a ve své dílně z ní ukovej výbavu!

Srdce světa Terra se roztříštilo na zářící rudu. Přidej se k Cechu strážců výhně v Emberfallu a pomoz ho znovu vykovat.

⛏️ JAK SE HRAJE
• Rozbíjej ložiska krumpáčem a sbírej skutečné kusy rudy. Nos je v náručí nebo je házej
• Každý kus ručně vyčisti: otesej dlátem, oškrábej a vylešti. Zvládneš Flawless?
• Rudu podrť a roztav na ingoty, ukovej z nich dýky, přilby a další zboží a prodávej
• Postav si na svém pozemku pece, drtiče, kovadliny a dopravníky
• Najdi 10 druhů rudy v Greystone Quarry, Ember Caves a Deep Hollow, až po mýtický Heartstone Shard
• Denní Ember Chest, Ore Codex a odznaky
• Žádné souboje. Každou rudu vytěžíš i bez game passu

🎮 Hraj na PC, mobilu, tabletu i konzoli. Hra je zatím v angličtině.

🆕 CO JE NOVÉHO (v1.0, TODO datum)
• Hra je venku! 3 těžební oblasti a k tomu VIP Glimmer Grotto, 10 druhů rudy, 9 strojů
```

---

## 4. Genre, subgenre and keywords

### Genre (checked against Roblox's current list)

Roblox's genres right now: Action, Adventure, Education, Entertainment, Obby & platformer, Party & casual,
Puzzle, RPG, Roleplay & avatar sim, Shooter, Shopping, **Simulation**, Social, Sports & racing, Strategy,
Survival, Utility & other.
The Simulation subgenres are Idle, Incremental Simulator, Physics Sim, Sandbox, **Tycoon** and Vehicle Sim.

**Pick: Simulation → Tycoon.** Roblox describes Tycoon as "simulating the management of a business or base".
That is TERRA FORGE's loop: gather and process ore, sell it, upgrade, and grow your own plot of machines.

- Second choice: **Simulation → Sandbox**, but only if building the plot becomes the main thing players do.
- Not *Incremental Simulator*: Roblox describes it as "simple repetitive actions to increase a counter".
  Cleaning ore by hand is a skill, not a counter.
- Not *Physics Sim*: throwing chunks is a nice touch, not the core of the game.
- You can only change the genre **once every 3 months**, so set it once you're sure. Roblox may correct a genre
  it thinks is wrong. If that happens, you get an email and can appeal through roblox.com/support with your Universe ID (TODO: Universe ID).

### Tags: what exists right now

- **Creators can't add free-form tags to a game.** The settings only have genre and an optional subgenre.
- Roblox's roadmap lists **"Dynamic filters" (genre and tag filters for players)** for **late 2026**.
  It has been delayed several times, so check the dashboard again after it ships. TODO: re-check around 2027-01.
- Search now understands plain-language searches ("mining games") in all supported languages.
  So the keywords that matter are the ones in the **name and description**. Use them naturally and don't repeat them.
  Roblox shows fewer people games that stuff keywords or name other games. Roblox's description guide also says
  tags and hashtags in the description don't help ranking and only use up characters, so don't add any.

### Keywords

Already in the descriptions: mine/mining, ore, pickaxe, crafting, tycoon, clean, polish, smelt, crush, anvil, forge, conveyors, plot, workshop.

**Search ads** (Ads Manager → new campaign with the **Visits** objective → ad set placement **Search Experience**;
up to **10 keywords per ad set**, and an ad only shows when the search exactly matches a keyword).
Choose from the suggestions Roblox shows while you type; if a word isn't suggested, drop it. TODO: build the ad sets.

| Ad set | Keywords (English) |
|---|---|
| Core | mining, mine, ore, pickaxe, forge, blacksmith, crafting, smelting, mining tycoon, mining game |
| Feel | satisfying, cleaning, polishing, crystals, factory, conveyor, furnace, anvil, workshop, cozy |

| Sada | Klíčová slova (čeština) |
|---|---|
| Základ | těžba, ruda, krumpáč, kovárna, kovář, tavení, výroba, dílna, tycoon, simulátor |

**Never use:** names of other games (for example "mining simulator" or "the forge", which are titles of existing
Roblox games), "free robux", "admin", "pets", "obby", "fight", "PvP", or anything that isn't in the game.

---

## 5. Icon and thumbnails

### Roblox rules and best practices (checked 2026-10-12)

**Icon**
- Square, **512×512** px. One icon per language. You can upload a Czech icon in Localization → Translate → Czech → Information,
  but if the icon has no text, one icon works everywhere.
- It shrinks to about **150×150** in some places, so check that it still reads at that size.
- It should be unique and show what the game is about. No vague symbols or graphics.
- Every icon is moderated before other people can see it.

**Thumbnails (images)**
- **16:9**, ideally **1920×1080**. Other ratios get stretched. Formats: .jpg .gif .png .tga .bmp.
- Up to **10 images or videos** on the game's details page.
- Home page: keep **2–5 thumbnails active**. Roblox then shows each player the one that works best for them.
  Each image must be **under 3 MB**. Keep several active and test new ones with each big update.
- Don't put anything important in the **bottom** of the image, because the player count can cover it.
- Images must match the real game. Roblox shows fewer people a game whose pictures promise something else.
  Everything uploaded is moderated under the Community Standards and Terms of Use.
- You can add alt text to each thumbnail for accessibility. Ready-made alt text is below.

**Videos**
- They must be **authentic gameplay**. Camera moves, light color correction, your logo and real in-game UI are fine.
  Gameplay, UI or graphics that aren't in the game are not allowed. No real-life footage.
- **No voice-over, narration or songs with lyrics.** Music must come from the Roblox audio catalog.
- Use text **sparingly** and only to describe gameplay. No ads or claims ("50% off", "FREE!").
- Graphics must look like the real game. Roblox rejects videos that make the game look better than players will see it.
- Quota: **3 video uploads per month**. Rejected videos count toward it.
- A video shows first on the details page. Xbox, PlayStation and VR don't show videos.
- Private games can't have a video preview (Roblox staff reply on the announcement thread), so upload it after launch.

**Our house rules (stricter than Roblox's):** no text in the icon. In thumbnails, at most a small TERRA FORGE logo
at the top. No arrows, red circles, fake buttons, prices, "UPDATE!" stickers or shocked faces.
Every picture must show something that really happens in the game.

**Pass icons** (on the Store tab): max 512×512. Keep the important part inside the circle, because Roblox crops pass icons round.

### How to make the images honestly

1. Set up the moment in Studio, start a solo playtest and press **Shift+P** to get the free camera.
   Capture at 1920×1080.
2. **Thumbnails: use the real capture.** The AI prompts below are mainly for planning the shot. If you run AI over a
   capture at all, use it as the **reference image** at low strength (about 0.25–0.4) and only for cleanup, so shapes,
   colors and the low-poly style stay true to the game. Never use it to make the graphics look better than the game.
   The **icon** may be a drawn or rendered illustration, but it must still show things that exist in the game.
3. Never let AI invent UI. If a shot needs UI, such as the FLAWLESS card, paste in the real UI from your capture.
4. Compare the result with the real game. If a player would say "it doesn't look like that", don't use it.

Shared style line (already inside every prompt below):
*low-poly 3D, chunky blocky shapes, flat-shaded faces, warm forge glow, soft bloom, saturated colors*.

### Icon concepts (3)

**Icon negative prompt (use for all three):**

```text
text, letters, words, numbers, logo, watermark, signature, UI, buttons, frame, border, photorealistic,
realistic textures, high-poly detail, smooth subdivision, film grain, noise, blurry, low resolution,
several subjects, cluttered background, blood, injury, fighting, monsters, guns, currency symbols,
coins raining, dollar signs, gift boxes, arrows, red circles, shocked face, brand logos, real people
```

**Icon A – "Flawless Ore" (recommended)**
A single cracked ore chunk with a shining gold core, held in the Cleaning Station's metal vise (as in
`cleaning_reveal.jpg`). It shows the clean-it-yourself idea in one glance.

```text
Square game icon, 1:1, 512x512, low-poly 3D render. One chunky ore rock split open in the center, its core
glowing bright gold with soft bloom and light rays, clean chisel cuts glowing along its edges, clamped in a dark
metal vise on a wooden workbench. A few golden sparkles float upward. Warm forge-orange to deep brown radial background, strong rim light,
flat-shaded faces, chunky blocky shapes, saturated warm colors, bold silhouette that still reads at 150x150,
subject fills about 70% of the frame, centered.
```

**Icon B – "First Strike"**
A pickaxe hitting a dark node as a glowing chunk pops out. It says "mining" right away.

```text
Square game icon, 1:1, 512x512, low-poly 3D render. A chunky stone-and-wood pickaxe striking a dark grey rock node;
the rock cracks with glowing white seams and one chunky ore piece with the same glowing white seams pops out toward
the viewer with small rock fragments and dust. Warm orange glow from below, dark cave background with soft orange haze,
flat-shaded faces, chunky blocky shapes, saturated colors, bold silhouette, centered, readable at small size.
```

**Icon C – "Apprentice Forgekeeper"**
A friendly blocky miner holding up a mythic shard. A character face, but no clickbait expression.

```text
Square game icon, 1:1, 512x512, low-poly 3D render. A cheerful blocky toy-like character with a simple cube head,
a proud grin and a plain red shirt, shown from the chest up, holding a glowing pink-red crystal shard up with both
hands; the shard lights the face warmly. Behind: a softly blurred forge building with a red roof and two chimneys,
glowing doorway, floating sparks. Flat-shaded faces, chunky shapes, bright saturated colors, centered.
```

### Thumbnail concepts (5)

Suggested order on the details page: 1, 2, 3, 4, 5. Activate 1, 2, 3 and 5 for the Home page at launch,
and add 4 once the machines are in.

**Thumbnail negative prompt (use for all five):**

```text
text, letters, captions, logo, watermark, fake UI, HUD, buttons, health bars, damage numbers, currency icons,
coins raining, price tags, arrows, red circles, emoji stickers, before/after split, photorealistic, realistic
textures, high-poly, smooth subdivision, film grain, blur, blood, gore, injury, combat, enemies, monsters, guns,
explosions, horror, real people, real-world places, brand logos, characters from other games, extra limbs,
distorted hands, cluttered composition, important details in the bottom 15 percent
```

**1 – "Flawless!" (the Cleaning Station reveal)**
Moment: the last polish stroke and the reveal. Real reference: `docs/screenshots/cleaning_reveal.jpg` (Solarite).
Use a Legendary or Mythic ore: the light rays only appear for those. Paste the real FLAWLESS result card into the
empty middle area, with the word FLAWLESS well above the bottom 15% (the player count can cover the bottom).

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, warm forge glow,
soft bloom, saturated colors. Close view over a wooden workbench with a dark metal vise holding a large faceted ore
chunk that has just been cleaned and polished: its golden core blazes with light rays and bloom, clean glowing cut
lines around its edges. Tools hang on the back wall: a chisel, a brush, a hammer. Warm amber workshop light, softly
blurred background. Keep the center below the ore calm and empty for an in-game result card.
```

Alt text: "A polished golden Solarite ore glows on the Cleaning Station after a Flawless clean."

**2 – "First Strike" (mining in Greystone Quarry)**
Moment: a node breaking in its last crack stage while a chunk pops out. A node drops one chunk per crack stage, so
the chunks from earlier stages already lie on the ground. Real reference: `docs/screenshots/mining.jpg`.

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, soft bloom,
saturated colors. Third-person view in an open-pit quarry with layered tan and brown blocky cliffs under a warm
pink-orange sky. A blocky avatar in a red shirt swings a chunky pickaxe into a dark grey ore node with glowing white
cracks; one chunky ore piece with glowing seams pops off toward the camera with small dust puffs and rock fragments,
two more chunks already lie on the sandy ground. Long soft shadows, golden hour.
```

Alt text: "A player swings a pickaxe and an ore chunk pops out of a rock in the quarry."

**3 – "Arms Full" (carrying and throwing)**
Moment: walking home with a stack of 5 chunks (the Ore Frame upgrade) and throwing one toward the plot.
Capture it in Emberfall with the Great Forge behind (see `town_overview.jpg`, `great_forge.jpg`).

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, warm glow, soft
bloom, saturated colors. Third-person view from behind and to the side: a blocky avatar walks a dirt path through a
low-poly village at golden hour, carrying a tall stack of four glowing ore chunks in its arms (orange, silver, gold
and blue glowing seams), a fifth chunk flying in a throw arc toward a fenced workshop plot. In the background
a forge building with a red roof and two chimneys glows orange, sparks rise, lamp posts glow, autumn orange and
green blocky trees.
```

Alt text: "A player carries a stack of glowing ore chunks through the town of Emberfall."

**4 – "My Workshop" (the machine line on your plot)**
Moment: conveyor → crusher → furnace → anvil, with ingots coming out and a helm being hammered.
TODO: capture only after step d is done, and make the machines look exactly like the real models.

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, warm forge glow,
soft bloom, saturated colors. High three-quarter view of a fenced square workshop plot on grass. A short conveyor
belt carries glowing ore chunks into a stone crusher, then into a clay furnace glowing orange that pushes shiny
ingots toward an anvil, where a blocky avatar hammers a helmet with sparks flying. A wooden storage crate and a
cleaning workbench stand at the side. Warm late-afternoon light, tidy layout, clear machine silhouettes.
```

Alt text: "A conveyor carries ore through a crusher and a furnace to an anvil on a player's plot."

**5 – "Deep Hollow" (the rarest ore)**
Moment: finding a glowing Heartstone node in the deepest cave. Real reference: `docs/screenshots/deep_hollow.jpg`.
Turn the exposure up a little in the capture. The real cave is very dark.

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, soft bloom,
saturated colors. Wide shot inside a huge dark cavern lit only by glowing crystals: tall pastel crystal pillars in
cyan, pink, mint and lavender, and rock ore nodes topped with glowing green, white and gold crystals. In the center
one rare ore node glows a deep pink-red with soft bloom; a small blocky avatar holding a chunky
pickaxe stands in front of it, lit pink. Deep blue-black shadows, light volumetric haze, strong sense of depth.
```

Alt text: "A player finds a rare glowing pink-red ore node in a dark crystal cave."

---

## 6. Trailer / video preview (about 27 s)

Rules recap: real gameplay only, 1920×1080, music from the Roblox audio catalog (instrumental), in-game sounds,
**no voice and no lyrics**, very little text that only describes gameplay, logo at the end. 3 uploads per month.
Roblox's announcement allows videos up to **60 s** and up to 1920×1080; the docs page gives no number, and some
older forum posts mention about 30 s. This plan is 27 s, so it fits either way. Upload it only after the game is
public (private games can't have a video preview). TODO: confirm the limit in the upload dialog.

| Time | Shot (capture with Shift+P free camera) | On-screen text | Sound |
|---|---|---|---|
| 0:00–0:03 | Slow push over Emberfall at sunset toward the glowing Great Forge | – | Music starts soft |
| 0:03–0:07 | Quarry: pickaxe hits, the node cracks in 3 stages, chunks pop out | "Mine it" | Rock hits on the beat |
| 0:07–0:10 | Player grabs chunks, the stack grows in their arms, a charged throw lands next to the Cleaning Station | – | Thud |
| 0:10–0:17 | Cleaning: chisel along the glowing line ("Great cut!"), dirt patches pop off ("Spotless!"), polish circles ("Gleaming!"), FLAWLESS card | "Clean it by hand" | Scrape and polish sounds, reveal chime |
| 0:17–0:21 | Furnace glow, an ingot comes out, anvil hammering, the helm appears; quick shot of the conveyor line (TODO after step d) | "Forge it" | Clangs |
| 0:21–0:24 | Fast cuts: Ember Caves lava glow, Deep Hollow crystals, a glowing Heartstone node | – | Music peaks |
| 0:24–0:27 | Logo end card over the Great Forge | TERRA FORGE | Music ends |

Don't add "Play now", "Free", "Best game", prices or anything that isn't in the build.

---

## 7. Social and update log templates

### Roblox update announcement
(Creator Dashboard → Engagement → Events & Updates → old updates form. **Max 60 characters, once every 3 days.**
It goes to players who turned on notifications. Be specific: "bug fixes" tells players nothing.)

```text
TERRA FORGE is open! Mine, clean and forge your first ore
```
(57 characters)

```text
TERRA FORGE je tady! Těž rudu, čisti ji a kuj výbavu
```
(52 characters)

More examples. The Blast Furnace is one of the 9 launch machines, so use these only if it is held back from v1.0
and ships later:
`New: the Blast Furnace smelts ore in just 2.5 seconds` (53) /
`Novinka: Blast Furnace taví rudu za pouhé 2,5 sekundy` (53).

### Roblox event (Events & Updates → Create Event)

```text
Category: TODO (pick the closest one in the dashboard)
Title: TODO (example: Flawless Week)
Subtitle: TODO (example: Clean ore by hand, earn the First Flawless badge)
Description: TODO. Explain what the event is, how it fits the game, and what players can earn.
  Only promise rewards that really exist, such as badges from the design.
Start / end: TODO
Thumbnail: a fresh one, not the same as the game thumbnails (Roblox says this helps)
Privacy: Private until ready, then Public
```

### Changelog (community wall, Discord, X)

```text
TERRA FORGE – Update vX.Y (TODO date)

NEW
• TODO (one line per feature, and only things that are live)

CHANGED
• TODO (balance, e.g. "Silver base value 20 → 22")

FIXED
• TODO (say what was broken, e.g. "Chunks no longer fall through the Grotto floor")

KNOWN ISSUES
• TODO or "None we know of"

Thanks for playing and for every bug report! – TODO studio/community name
```

Czech version:

```text
TERRA FORGE – aktualizace vX.Y (TODO datum)

NOVINKY
• TODO

ZMĚNY
• TODO

OPRAVY
• TODO

ZNÁMÉ PROBLÉMY
• TODO nebo „Zatím o žádných nevíme“

Díky, že hrajete a hlásíte chyby! – TODO název studia/komunity
```

### Short social post (X / YouTube community / Discord)

```text
Your ore is dirty. Fix that. ⛏️
Chisel, scrape and polish every chunk by hand in TERRA FORGE, then smelt it and forge it into gear.
Now on Roblox. Link: TODO (use a Roblox share link so you can track visits)
```

```text
Tvoje ruda je špinavá. Tak s tím něco udělej. ⛏️
V TERRA FORGE každý kus ručně otešeš dlátem, oškrábeš a vyleštíš, pak ho roztavíš a ukuješ z něj výbavu.
Nově na Robloxu. Odkaz: TODO (použij Roblox share link, ať vidíš, kolik návštěv přinese)
```

Reminders: post links only on social media and in the game page's Social Links, never inside the game.
Don't name other games in posts. Use footage from the real build.

---

## Sources

Checked on 2026-10-12 (and re-checked in review the same day). The create.roblox.com pages could not be opened
directly from this environment, so they were read from Roblox's official public docs source
(github.com/Roblox/creator-docs, `main` branch, commit `af5f853` of 2026-10-10). The DevForum and Community Standards
pages could not be opened either; they were checked through search-result excerpts and are marked *(excerpt)*.

**Roblox Creator Hub docs**
- Thumbnails (sizes, max 10, video rules, 3/month quota, personalization 2–5, <3 MB, bottom area): https://create.roblox.com/docs/production/publishing/thumbnails
- Icons (512×512, 150×150 preview, one per language, moderation): https://create.roblox.com/docs/production/publishing/experience-icons
- Genres and subgenres (full list, 3-month change limit, appeals): https://create.roblox.com/docs/production/publishing/experience-genres
- Publish games and places (name/description best practices, audience, publishing requirements, fees): https://create.roblox.com/docs/production/publishing/publish-games-and-places
- Discovery (best practices, issues that limit exposure, semantic search): https://create.roblox.com/docs/discovery
- Game descriptions (1,000-character limit, ~160-character hook, don't list controls, no tags/hashtags; Roblox marks this guide as experimental): https://create.roblox.com/docs/production/publishing/descriptions
- Events and updates (60-character updates, once every 3 days, event setup): https://create.roblox.com/docs/production/promotion/experience-events
- Social media links (16+ rules, 3 links, allowed sites, no links in-game): https://create.roblox.com/docs/production/promotion/social-media-links
- Search ads (Visits campaign, Search Experience placement, 10 keywords per ad set, exact match): https://create.roblox.com/docs/production/promotion/search-ads
- Share links (trackable links for social posts): https://create.roblox.com/docs/production/promotion/share-links
- Promotion overview (share links, communities): https://create.roblox.com/docs/production/promotion
- Content maturity and compliance (questionnaire, labels, free-form creation, paid random items): https://create.roblox.com/docs/production/promotion/content-maturity
- Roblox Kids and Select (verified account, 2FA, fee or subscription, evaluation: 250 plays in 60 days): https://create.roblox.com/docs/production/publishing/kids-and-select
- Localization overview (source and supported languages): https://create.roblox.com/docs/production/localization
- Automatic translation (supported-language list, which does not include Czech): https://create.roblox.com/docs/production/localization/automatic-translations
- Add translations (Information tab: name, description, icon, thumbnails): https://create.roblox.com/docs/production/localization/add-translations
- Language codes (Czech `cs` / `cs-cz`): https://create.roblox.com/docs/production/localization/language-codes
- Passes (pass icon max 512×512, circular crop): https://create.roblox.com/docs/production/monetization/passes
- Docs source mirror: https://github.com/Roblox/creator-docs

**Roblox DevForum and roadmap**
- Creator Roadmap 2026: Fall Update (dynamic genre/tag filters delayed to late 2026; name checks and a promotional text field, late 2026) *(excerpt)*: https://devforum.roblox.com/t/creator-roadmap-2026-fall-update/4880208
- Creator Roadmap: https://create.roblox.com/roadmap
- Video Previews for your game's page (Roblox announcement: up to 60 s and 1920×1080, 3 free uploads a month; staff reply: private games can't have a preview) *(excerpt)*: https://devforum.roblox.com/t/video-previews-for-your-games-page/4068103
- Like rewards, no clear official rule *(excerpt)*: https://devforum.roblox.com/t/do-tos-allow-x-likes-for-next-reward/1029127 and https://devforum.roblox.com/t/asking-people-to-like-your-game-against-tos/3753529

**Roblox policy (en.help.roblox.com / about.roblox.com)**
- Community Standards (Integrity section: no misleading content or metadata to drive engagement) *(excerpt)*: https://en.help.roblox.com/hc/articles/203313410 and https://about.roblox.com/community-standards
- Terms of Use: https://en.help.roblox.com/hc/articles/115004647846
