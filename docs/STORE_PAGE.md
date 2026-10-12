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
| Smelt, crush, anvil (dagger, helm…), selling | d, e | [ ] TODO |
| Furnaces, crushers, anvils, conveyors on your own plot (9 machines) | d | [ ] TODO |
| Daily Ember Chest, Ore Codex, badges | e, f | [ ] TODO |
| "F / Y to use" works on **every** machine, not only the Cleaning Station | d | [ ] TODO |
| Passes are optional, every ore can be mined without them | f | [ ] TODO |

### Dashboard checklist

- [ ] **Maturity & Compliance Questionnaire** (Creator Dashboard → Configure → Questionnaire). Answer honestly.
      There is no combat and no blood. Daggers and helms are only crafted goods you sell. Forge names go through
      Roblox text filtering, so they don't count as "free-form user creation". There are no paid random items.
      If you skip the questionnaire, Roblox limits who can play the game. TODO: fill it in and note the label you get here: `TODO`.
- [ ] **Audience**: to reach players under 16 (Roblox Kids and Select accounts), you need an age-checked account, 2FA,
      and either Roblox Plus/Premium for 2 months or the refundable publishing fee. The game also has to pass Roblox's
      evaluation (250 unique plays from highly engaged players in 60 days). Until then, only 16+ players can play it.
      TODO: decide which route you take.
- [ ] **Description length**: both descriptions below are about 970 characters (counted). Older DevForum posts say
      the limit is 1,000, but no current Roblox page gives a number. TODO: check the counter in the dashboard when you paste.
- [ ] **Czech**: Czech (`cs` / `cs-cz`) is a supported Roblox language. Paste the Czech text in
      Creator Dashboard → Localization → **Translate** → Czech → **Information** tab. Players who turn on
      automatic translations get a machine translation unless you add your own.
- [ ] **Social links** (Engagement → Social Links): up to 3 links, and each type only once. You can choose from Facebook, X/Twitter,
      YouTube, Twitch, Discord, Guilded or a Roblox Community. You must be age-checked as 16+ to add them,
      and only age-checked 16+ players can see them. Don't put URLs in the description or inside the game.
      TODO: your links.
- [ ] **Group / Community**: TODO: community name. The design gives 500 coins for joining once. That's fine in-game,
      but don't make it the headline anywhere. Roblox shows fewer people pages that lead with rewards.
- [ ] **No "like" reward**: it isn't in the design, and Roblox has no clear rule that allows it.
      The Community Standards ban misleading tricks to drive engagement. Leave it out.

---

## 1. Title

**Exact title string (use this):**

```text
TERRA FORGE
```

Roblox has no separate subtitle field. You can use a subtitle in two ways: (a) as the first line of the
description and on social posts, or (b) added to the name. If you add it to the name, choose before launch and then keep it.
Roblox says renaming often makes a game harder to find.

**Subtitle variant A** (the feeling of the game, 32 characters as a full name):

```text
TERRA FORGE: Mine, Clean & Forge
```

**Subtitle variant B** (search keywords, 37 characters as a full name):

```text
TERRA FORGE: Mining & Crafting Tycoon
```

Czech name (optional, Localization → Czech → Information → Name):

```text
TERRA FORGE: Těž, čisti a kuj
```

My pick: launch as plain **TERRA FORGE** and use variant A as the description hook and on thumbnails or social posts.
The name stays short, easy to remember and the same in every language. Roblox's roadmap lists "name checks" that
protect game names from copycats for late 2026, so a stable name will also help then.

---

## 2. English description

**Short hook (1 line, 79 characters):**

```text
Mine glowing ore, clean it by hand and forge it into gear in your own workshop!
```

**Full description (paste as is, about 970 characters):**

```text
Mine glowing ore, clean it by hand and forge it into gear in your own workshop!

Terra's Heartstone has cracked into glowing ore. Join the Forgekeepers of Emberfall and help relight the Great Forge.

⛏️ HOW IT WORKS
• Crack ore nodes with your pickaxe. Real chunks drop: carry them or throw them
• Clean each chunk by hand: chisel, scrape, polish. Can you get Flawless?
• Smelt, crush and hammer ingots into daggers, helms and more, then sell
• Set up furnaces, crushers, anvils and conveyors on your own plot
• Find 10 ores in the Quarry, Ember Caves and Deep Hollow, up to the mythic Heartstone
• Daily Ember Chest, Ore Codex and badges
• No combat. Every ore is free to mine

🎮 CONTROLS
PC: Click to mine, E grab/drop, hold Q to throw, F to use
Mobile: Tap to mine, Grab/Throw buttons, drag to clean
Console: R2 mine, X grab, hold R1 to throw, Y to use

🆕 WHAT'S NEW (v1.0, TODO date)
• Launch! Emberfall, 4 mining zones, 10 ores, 9 machines and the Cleaning Station
```

The "What's new" block: replace it with every update and keep it to 1–2 lines, so the whole text stays under the limit.
Only list things that are in the build you just published.

### Controls reference (taken from the code)

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

Written for Czech players, not translated word by word. Place names and grade names stay in English
because that's how players see them in the game.

**Krátký háček (1 řádek):**

```text
Těž zářící rudu, vyčisti ji vlastníma rukama a ve své dílně z ní ukovej výbavu!
```

**Celý popis (vložit beze změn, cca 970 znaků):**

```text
Těž zářící rudu, vyčisti ji vlastníma rukama a ve své dílně z ní ukovej výbavu!

Srdce světa Terra puklo a jeho úlomky se staly zářící rudou. Pomoz Strážcům výhně z Emberfallu znovu rozdmýchat Velkou výheň.

⛏️ JAK SE HRAJE
• Rozbíjej ložiska krumpáčem, kusy rudy pak nos v náručí nebo je hoď
• Každý kus vyčisti ručně: dláto, škrabka, leštění. Dáš to na Flawless?
• Tav, drť a na kovadlině kovej dýky, přilby a další zboží na prodej
• Postav si na pozemku pece, drtiče, kovadliny a dopravníky
• 10 druhů rudy v Quarry, Ember Caves a Deep Hollow, až po mýtický Heartstone
• Denní Ember Chest, Ore Codex a odznaky
• Žádné souboje. Každou rudu vytěžíš zdarma

🎮 OVLÁDÁNÍ
PC: klik = kopat, E = zvednout/položit, drž Q = hodit, F = použít
Mobil: ťukni = kopat, tlačítka Grab/Throw, čisti tahem prstu
Konzole: R2 = kopat, X = zvednout, drž R1 = hodit, Y = použít

🆕 CO JE NOVÉHO (v1.0, TODO datum)
• Start hry! Emberfall, 4 těžební oblasti, 10 rud, 9 strojů a čisticí stanice
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
  Roblox shows fewer people games that stuff keywords or name other games.

### Keywords

Already in the descriptions: mine/mining, ore, pickaxe, clean, polish, smelt, crush, anvil, forge, conveyors, plot, workshop.

**Search ads** (Ads Manager → Search ad; up to **10 keywords per ad set**, and they only match the exact search).
Choose from the suggestions Roblox shows while you type. TODO: build the ad sets.

| Ad set | Keywords (English) |
|---|---|
| Core | mining, mine, ore, pickaxe, forge, blacksmith, crafting, smelting, mining tycoon, mining simulator |
| Feel | satisfying, cleaning, polishing, crystals, factory, conveyor, furnace, anvil, workshop, cozy |

| Sada | Klíčová slova (čeština) |
|---|---|
| Základ | těžba, ruda, krumpáč, kovárna, kovář, tavení, výroba, dílna, tycoon, simulátor |

**Never use:** names of other games, "free robux", "admin", "pets", "obby", "fight", "PvP", or anything
that isn't in the game.

---

## 5. Icon and thumbnails

### Roblox rules and best practices (checked 2026-10-12)

**Icon**
- Square, **512×512** px. One icon per language. You can upload a Czech icon in Localization → Information,
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
- Quota: **3 video uploads per month**. Rejected videos count toward it.
- A video shows first on the details page. Xbox, PlayStation and VR don't show videos.

**Our house rules (stricter than Roblox's):** no text in the icon. In thumbnails, at most a small TERRA FORGE logo
at the top. No arrows, red circles, fake buttons, prices, "UPDATE!" stickers or shocked faces.
Every picture must show something that really happens in the game.

**Pass icons** (on the Store tab): max 512×512. Keep the important part inside the circle, because Roblox crops pass icons round.

### How to make the images honestly

1. Set up the moment in Studio, start a solo playtest and press **Shift+P** to get the free camera.
   Capture at 1920×1080.
2. Use the AI prompts below either **to plan the shot**, or with your real capture as the **reference image** at low
   strength (about 0.25–0.4), so shapes, colors and the low-poly style stay true to the game.
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
A single cracked ore chunk with a shining gold core, sitting on an anvil. It shows the clean-it-yourself idea in one glance.

```text
Square game icon, 1:1, 512x512, low-poly 3D render. One chunky ore rock split open in the center, its core
glowing bright gold with soft bloom and light rays, clean chisel cuts glowing along its edges, resting on a dark
iron anvil. A few orange sparks float upward. Warm forge-orange to deep brown radial background, strong rim light,
flat-shaded faces, chunky blocky shapes, saturated warm colors, bold silhouette that still reads at 150x150,
subject fills about 70% of the frame, centered.
```

**Icon B – "First Strike"**
A pickaxe hitting a dark node as glowing chunks burst out. It says "mining" right away.

```text
Square game icon, 1:1, 512x512, low-poly 3D render. A chunky stone-and-wood pickaxe striking a dark grey rock node;
the rock cracks with glowing white seams and three chunky ore pieces (ember orange, silver, icy blue) burst toward
the viewer with small rock fragments. Warm orange glow from below, dark cave background with soft orange haze,
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
Moment: the last polish stroke and the reveal. Real reference: `docs/screenshots/cleaning_reveal.jpg`.
Paste the real FLAWLESS result card into the empty lower-middle area.

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, warm forge glow,
soft bloom, saturated colors. Close view over a wooden workbench with a dark metal vise holding a large faceted ore
chunk that has just been cleaned and polished: its golden core blazes with light rays and bloom, clean glowing cut
lines around its edges. Tools hang on the back wall: a chisel, a brush, a hammer. Warm amber workshop light, softly
blurred background. Keep the lower-middle third calm and empty for an in-game result card.
```

Alt text: "A polished gold ore glows on the Cleaning Station after a Flawless clean."

**2 – "First Strike" (mining in Greystone Quarry)**
Moment: a node breaking in its last crack stage while chunks pop out. Real reference: `docs/screenshots/mining.jpg`.

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, soft bloom,
saturated colors. Third-person view in an open-pit quarry with layered tan and brown blocky cliffs under a warm
pink-orange sky. A blocky avatar in a red shirt swings a chunky pickaxe into a dark grey ore node with glowing white
cracks; the node bursts into three chunky ore pieces with glowing seams flying toward the camera, small dust puffs
and rock fragments. Long soft shadows, golden hour.
```

Alt text: "A player swings a pickaxe and ore chunks burst out of a rock in the quarry."

**3 – "Arms Full" (carrying and throwing)**
Moment: walking home with a stack of 5 chunks (the Ore Frame upgrade) and throwing one toward the plot.
Capture it in Emberfall with the Great Forge behind (see `town_overview.jpg`, `great_forge.jpg`).

```text
16:9 widescreen game screenshot, 1920x1080, low-poly 3D, chunky blocky shapes, flat-shaded faces, warm glow, soft
bloom, saturated colors. Third-person view from behind and to the side: a blocky avatar walks a dirt path through a
low-poly village at golden hour, carrying a tall stack of five glowing ore chunks in its arms (orange, silver, gold,
blue and green glowing seams), one more chunk flying in a throw arc toward a fenced workshop plot. In the background
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
one rare ore node pulses with a deep pink-red glow and soft light rays; a small blocky avatar holding a chunky
pickaxe stands in front of it, lit pink. Deep blue-black shadows, light volumetric haze, strong sense of depth.
```

Alt text: "A player finds a rare glowing pink-red ore node in a dark crystal cave."

---

## 6. Trailer / video preview (about 27 s)

Rules recap: real gameplay only, 1920×1080, music from the Roblox audio catalog (instrumental), in-game sounds,
**no voice and no lyrics**, very little text that only describes gameplay, logo at the end. 3 uploads per month.
TODO: check the maximum video length in the upload dialog. A DevForum summary says 60 s, but the Roblox docs don't give a number.

| Time | Shot (capture with Shift+P free camera) | On-screen text | Sound |
|---|---|---|---|
| 0:00–0:03 | Slow push over Emberfall at sunset toward the glowing Great Forge | – | Music starts soft |
| 0:03–0:07 | Quarry: pickaxe hits, the node cracks in 3 stages, chunks pop out | "Mine it" | Rock hits on the beat |
| 0:07–0:10 | Player grabs chunks, the stack grows in their arms, a charged throw lands next to the Cleaning Station | – | Thud |
| 0:10–0:17 | Cleaning: chisel along the glowing line ("GREAT CUT!"), dirt patches pop off, polish circles ("SHINY!"), FLAWLESS card | "Clean it by hand" | Scrape and polish sounds, reveal chime |
| 0:17–0:21 | Furnace glow, an ingot comes out, anvil hammering, the helm appears; quick shot of the conveyor line (TODO after step d) | "Forge it" | Clangs |
| 0:21–0:24 | Fast cuts: Ember Caves lava glow, Deep Hollow crystals, Heartstone node pulse | – | Music peaks |
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
TERRA FORGE je tady! Těž, čisti a kuj svou první rudu
```
(53 characters)

More examples, to use only when the feature ships:
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

NOVÉ
• TODO

ZMĚNY
• TODO

OPRAVY
• TODO

ZNÁMÉ PROBLÉMY
• TODO nebo „Žádné o nich nevíme“

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
V TERRA FORGE každý kus ručně odsekáš, oškrábeš a vyleštíš, pak ho roztavíš a ukuješ z něj výbavu.
Teď na Robloxu. Odkaz: TODO (použij Roblox share link, ať vidíš návštěvy)
```

Reminders: post links only on social media and in the game page's Social Links, never inside the game.
Don't name other games in posts. Use footage from the real build.

---

## Sources

Checked on 2026-10-12. The create.roblox.com pages could not be opened directly from this environment, so they were
read from Roblox's official public docs source (github.com/Roblox/creator-docs, `main` branch). The DevForum and
Community Standards pages were checked through search-result excerpts; those are marked *(excerpt)*.

**Roblox Creator Hub docs**
- Thumbnails (sizes, max 10, video rules, 3/month quota, personalization 2–5, <3 MB, bottom area): https://create.roblox.com/docs/production/publishing/thumbnails
- Icons (512×512, 150×150 preview, one per language, moderation): https://create.roblox.com/docs/production/publishing/experience-icons
- Genres and subgenres (full list, 3-month change limit, appeals): https://create.roblox.com/docs/production/publishing/experience-genres
- Publish games and places (name/description best practices, audience, publishing requirements, fees): https://create.roblox.com/docs/production/publishing/publish-games-and-places
- Discovery (best practices, issues that limit exposure, semantic search): https://create.roblox.com/docs/discovery
- Events and updates (60-character updates, once every 3 days, event setup): https://create.roblox.com/docs/production/promotion/experience-events
- Social media links (16+ rules, 3 links, allowed sites, no links in-game): https://create.roblox.com/docs/production/promotion/social-media-links
- Search ads (10 keywords per ad set, exact match): https://create.roblox.com/docs/production/promotion/search-ads
- Promotion overview (share links, communities): https://create.roblox.com/docs/production/promotion
- Content maturity and compliance (questionnaire, labels, free-form creation, paid random items): https://create.roblox.com/docs/production/promotion/content-maturity
- Roblox Kids and Select (evaluation, 250 plays in 60 days): https://create.roblox.com/docs/production/publishing/kids-and-select
- Localization overview (automatic translations): https://create.roblox.com/docs/production/localization
- Add translations (Information tab: name, description, icon, thumbnails): https://create.roblox.com/docs/production/localization/add-translations
- Language codes (Czech `cs` / `cs-cz`): https://create.roblox.com/docs/production/localization/language-codes
- Passes (pass icon max 512×512, circular crop): https://create.roblox.com/docs/production/monetization/passes
- Docs source mirror: https://github.com/Roblox/creator-docs

**Roblox DevForum and roadmap**
- Creator Roadmap 2026: Fall Update (dynamic genre/tag filters and name checks, late 2026) *(excerpt)*: https://devforum.roblox.com/t/creator-roadmap-2026-fall-update/4880208
- Creator Roadmap: https://create.roblox.com/roadmap
- Video Previews for your game's page (uploaded gameplay videos replace YouTube previews; 60 s is a community summary) *(excerpt)*: https://devforum.roblox.com/t/video-previews-for-your-games-page/4068103
- Like rewards, no clear official rule *(excerpt)*: https://devforum.roblox.com/t/do-tos-allow-x-likes-for-next-reward/1029127 and https://devforum.roblox.com/t/asking-people-to-like-your-game-against-tos/3753529
- Description length (older posts say 1,000 characters) *(excerpt)*: https://devforum.roblox.com/t/max-description-characters/1399618

**Roblox policy (en.help.roblox.com / about.roblox.com)**
- Community Standards (Integrity section: no misleading content or metadata to drive engagement) *(excerpt)*: https://en.help.roblox.com/hc/articles/203313410 and https://about.roblox.com/community-standards
- Terms of Use: https://en.help.roblox.com/hc/articles/115004647846
