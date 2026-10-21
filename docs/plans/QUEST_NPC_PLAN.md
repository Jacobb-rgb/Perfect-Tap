# Quest NPC plan (systems design, 2026-10-21, review round 1 applied)

Branch `feat/quest-npcs` from main f3a5327 (map v44). This is a plan only: nothing in the game reads it yet. The art
prototype (`NpcBuilder`, the preview pictures) is in this worktree.

## Pro majitele:

Po mapě bude stát **8 postav, které dávají úkoly**. Každá má svou barvu, svítící kolečko pod nohama a nad hlavou
žlutý vykřičník, když pro tebe má úkol. Mluvíš s nimi klávesou **E** (na ovladači Y, na mobilu klepnutím).

| Postava | Kde stojí | Od kdy |
|---|---|---|
| Archivist Quill, fialový učenec s létající knihou | lobby, náměstí u Cechovní tabule | po tutoriálu |
| Misty Gleam, čistička drahokamů se stříkačkou | lobby, náměstí, vidíš ji hned od spawnu | po tutoriálu |
| Pip Farwander, průzkumník v oranžové bundě s lucernou a krumpáčem | lom, mezi rampou a Mine Station | po tutoriálu |
| Brakka Emberhand, kovář s obřím kladivem na rameni | Ember Caves, u cesty od vchodu | blaster 3 |
| Sela Shardwell, hornice s růžovými krystaly | Deep Hollow, kousek od vchodu | blaster 5 |
| Captain Aurel, palácový strážce s trojzubcem | Sunken Palace, na terase u výtahu | blaster 7 |
| Volta Sparkwright, bouřková inženýrka s velkým klíčem | Stormglass Rift, dole pod plošinou výtahu | blaster 8 |
| Ashka, šamanka v kostěné masce | Heartstone Core, mezi výtahem a Mine Liftem | blaster 9 |

**Příklady úkolů a odměn:**
- Pip: „Přines mi 6 železa." Odměna: 1 Leaf Ore a 1 Honeycomb.
- Brakka: „Rozbij 20 kamenů v Ember Caves." Odměna: 3 Amber.
- Misty: „Vyčisti 5 rud na Pristine." Odměna: nový artefakt do sbírky.
- Sela: „Přines 1 Flawless Diamond." Odměna: artefakt Locomotive Crest.
- Volta: „Přines 3 Leaf Gem na Pristine." Odměna: 2 Volcanic Core.
- Ashka, úplně poslední úkol: „Přines 1 Flawless Heartstone." Odměna: 3 Heartstone.

**Odměny jsou jen artefakty a lepší rudy.** Artefakt je vždycky takový, který ještě nemáš. Rudy přijdou špinavé do
Ore Penu. Žádné mince, shardy, kapsle, boosty ani kosmetika. Žádné denní úkoly. Celkem 33 úkolů, každý jen jednou,
10 z nich dává artefakt.

**Na co se tě ptám (stačí napsat číslo a písmeno):**
1. Líbí se ti postavy na obrázcích? A = ano, B = chci něco změnit (napiš co).
2. Kolik artefaktů z úkolů? A = 10 z 24, B = méně (6), C = víc (14). Pozor: artefakt z úkolu může dokončit celou
   sbírku a ta pak dá titul, skin podia a bonus.
3. Kolik úkolů najednou? A = nejvýš 3, B = nejvýš 5.
4. Po rebirthu: A = hotové úkoly zůstanou hotové, B = začnou znovu, ale jen s rudou.

Obrázky jsou náhled z herního kódu, ne přímo z Robloxu, takže světlo a barvy vypadají ve hře trochu jinak.

---

**The owner's request**, after his Studio playtest, in Czech: put NPCs around the map, dressed "mega cool", who give
quests, for example for artifacts or better ore.

**His answers:**
- **Rewards:** artifacts and rare ores. Artifacts go into the collection through `ArtifactService`. Rare ore arrives
  **dirty** in the Ore Pen.
- **Quest types:**
  - (a) "bring me ore", for example 3 clean Emberite or one Flawless Gold;
  - (b) "mine / clean X", for example mine 20 rocks in Ember Caves or clean 5 ores to Pristine.
- **Not wanted:**
  - coin or shard rewards;
  - capsules or boosts;
  - cosmetics;
  - "find something in the mine" quests;
  - daily quests;
  - emoji anywhere.
- **Judged by:** pictures, in the bright "Pop" look.

What was read for this plan:
- **Server services:** ArtifactService (+ ArtifactConfig, StoryConfig), PenService, ItemService.storeDesc / keepRelic,
  CarryService, SellService (the hands + pen hand-over pattern), MiningService (signals, `shatter`, Stats),
  CleaningService (`onCleaned`, the relic path), WheelService (dirty ore into the pen).
- **Save code:** DataTemplate, Migrations, DataService, ProfileStore.reconcile, docs/SAVE_AUDIT.md,
  docs/PUBLISHING.md step 12.
- **State and tutorial:** StateService, TutorialService / TutorialConfig.
- **Configs:** MonetizationConfig / MonetizationService, BlasterData, MineFloors, WorldLayout, OreData, ItemData,
  EconomyConfig, RebirthConfig.reset, TrainConfig, MovementConfig, PopTheme.
- **Net and prompts:** Net, PromptConfig.
- **Client UI:** Pop / PopTheme, HudController, MenuPanels, PromptController, MiningController and InteractController
  (their ray filters).
- **Budgets:** LobbyLayout budgets with tests/LobbyBudget and tests/PhoneBudget.
- **Balance:** docs/BALANCE_SIM.md and a fresh `tools/lune/balance_sim.luau` run on f3a5327 (build/balance/sim.json).
- **Art prototype:** `src/shared/Builders/NpcBuilder.luau`, `tools/lune/lib/npc_preview.luau`,
  `tools/preview/npc_shots.json`, `tests/NpcBuilder.spec.luau`.

The plan uses the art prototype's 8 outfit ids and names, so the systems and the art stay one roster. Section 8 lists
what review round 1 changed.

---

## 0. Summary

1. **8 quest givers:**
   - 2 on the lobby plaza;
   - 1 in the Greystone Quarry, between the ramp and the Mine Station;
   - 1 on each mine floor 2–6.

   Each one opens at a blaster level and has **one chain of 4–5 quests**: 33 quests in all. A chain is done once and
   never repeats. There are no daily quests.
2. **Three goal kinds**, all counted on the server:

   | Kind | Example | What the player does | Counted from |
   |---|---|---|---|
   | Bring | 3 Emberite, Clean or better | Hands the ore over from their hands or their Ore Pen | a check at hand-in |
   | Mine | Break 20 rocks in the Ember Caves | Breaks rocks in that zone | `MiningService.onRockBroken` (a new 3-line hook) |
   | Clean | Clean 5 ores to Pristine at a Cleaning Station | Plays the cleaning minigame | `CleaningService.onCleaned` |
3. **Rewards:**
   - **Ores:** fixed dirty ores, delivered into the Ore Pen. Every reward ore is one the quest's floor drops itself,
     preferably its crystal or rarest ores. Mythic ores only from gate 9.
   - **Artifacts:** 10 quests give **one missing artifact** each, never a duplicate and never the Mythic.
   - **Fixed, not random:** every reward is decided in advance, so there are no odds to show.
   - **Never given:** coins, shards, boosts, capsules or cosmetics.
   - **Size:** capped by coins (R3, the best processed value) and by podium income (R6, against the typical player's
     income). The balance sim run with the quest rewards is required before landing.
4. **Save:** one new record, `Quests = { [npcId] = { Step, Progress, Active, Done } }`. Migrations repairs it.
   `Version` stays **3** (section 3.3 gives the reason, and the rule for after release).
5. **Code:**
   - **Server:** `QuestService`, plus a shared `QuestConfig` with the data and the pure rules.
   - **Client:** `QuestController`, plus three UI builders: the dialog, the HUD tracker and the markers.
   - **Art:** `NpcBuilder` (anchor + dress), `NpcSpots` (moved from the preview).
   - **Changes to other chats' files** (6.2): one-line hooks in Net, DataTemplate, the two init scripts and MenuPanels;
     `migrateQuests` in Migrations (~45 lines); the `onRockBroken` signal in MiningService (~3 lines).
   - **Left untouched:** CleaningService, ArtifactService, PenService, MiningController, InteractController and the
     world builders.
6. **Budget:**

   | | Parts | Lobby | Whole map |
   |---|---|---|---|
   | Today | | 13,589 / 13,700 | 31,843 / 32,000 |
   | Server adds | 8 invisible anchor parts (2 of them in the lobby) | 13,591 / 13,700 | 31,851 / 32,000 |

   The dressed models (51–60 parts each with their pad, cap 70) are built **on the client, only within 120 studs and
   only on the player's own floor**. That works the way the museum relics already work.

---

## 1. NPC roster

### 1.1 Who, where, when

The ids are `NpcBuilder.Outfits` ids. They are also the keys of `data.Quests` and must never be renamed. The names,
titles, looks and the Pop paint come from `NpcBuilder.Outfits` (one source). `QuestConfig` adds the story and the
quests.

| # | Id | Name, title | Stands at (feet x, z; facing) | Opens | Collection | Pop paint |
|---|---|---|---|---|---|---|
| 1 | `Scholar` | Archivist Quill, Relic Scholar | Lobby plaza, west, by the Guild Board: (−20, −14), faces the spawn | tutorial done or skipped | Crown of Kaldrum | Purple |
| 2 | `GemPolisher` | Misty Gleam, Gem Polisher | Lobby plaza, east, in the spawn view: (16, 11), faces the spawn | tutorial done or skipped | Heartstone Lore | Pink |
| 3 | `Explorer` | Pip Farwander, Deep Explorer | Greystone Quarry, between the ramp foot and the Mine Station: (23, −128), faces the ramp | tutorial done or skipped | Royal Railway | Orange |
| 4 | `LavaSmith` | Brakka Emberhand, Lava Smith | Ember Caves, on the path from the entrance: (2, −278), faces the entrance | blaster 3 | Golemworks | Red |
| 5 | `CrystalMiner` | Sela Shardwell, Crystal Miner | Deep Hollow, past the ramp foot: (−14, −414), faces the ramp | blaster 5 | Royal Railway | Teal |
| 6 | `PalaceGuard` | Captain Aurel, Palace Guard | Sunken Palace terrace, 18 studs from the elevator stop: (−6, −756), faces the elevator | blaster 7 (+ the elevator) | Crown of Kaldrum | Yellow |
| 7 | `StormEngineer` | Volta Sparkwright, Storm Engineer | Stormglass Rift floor, below the landing deck: (−26, −768), faces the stairs | blaster 8 | Golemworks | Blue |
| 8 | `CoreShaman` | Ashka, Core Shaman | Heartstone Core landing, between the elevator and the Mine Lift: (0, −760), faces the elevator | blaster 9 | Heartstone Lore | Green |

**One set of spots.** The table is `Preview.Spots` in `tools/lune/lib/npc_preview.luau` (X, Z, the ground search
height, the Face point). WP-Q2 moves that table **verbatim** into `src/shared/Config/NpcSpots.luau`, and the preview
reads it from there. No other copy exists. The server finds the ground with one ray at start.

**How the spots were checked** (a scratch Lune run over the built map v44; tests/QuestNpcs.spec keeps it, section
6.3 item 7):
- ground under the spot, flat within 0.45 studs under the Root box's corners;
- the spot is in the NPC's own `WorldLayout` zone (`Emberfall` for the lobby);
- the Root box plus a 2-stud margin is outside every `WorldLayout.KeepOut` box (the ramps, the cave entrance, the
  station track and platform, the Mine Lifts);
- open space: no visible map part within 4 studs between 0.8 and 6 studs over the feet (not inside a hut, not
  against a wall);
- the `PromptPoint` is at least **14 studs** from every Main prompt with Distance 10 (the station hopper, the Mine
  Lifts, the elevator call panels, the stall counters) and **16 studs** from the Distance 12 ones (the Guild Board,
  the Fossil Dig, the capsule stall, the codex). With `OnePerButton` the closer prompt wins, so this keeps Talk from
  stealing E presses meant for Put In or a counter (the minimum is 12; 2 studs of margin);
- at least 7 studs from every rock spawn (`NodeSpawn`).

Measured: the nearest prompts are 14.9–34 studs away, the nearest rock spawns 8.2–53 studs.

**What changed from the first draft:** its Explorer spot stood on the Mine Station platform, inside the track's
KeepOut box and 3.5 studs from the hopper; its CrystalMiner spot was inside the hollow ramp's KeepOut box; the
prototype's Explorer spot turned out to be inside a quarry hut.

**The lobby spots** are inside the plaza ring (r ≈ 24). Plaza Life's decorative miners keep to the lawns at r ≥ 41,
so they never meet. Both lobby NPCs are in the spawn view (`npc_world_spawn` picture).

**Not used:** Tobin (the Sell stall) stays a seller only. The VIP Glimmer Grotto gets no NPC and no goal, because it
is paid content.

### 1.2 Personalities and lore

Every NPC is tied to the Forgekeepers' story (GAME_DESIGN.md "Lore", StoryConfig chapters):

- **Archivist Quill** (old, kind, fussy about dust, talks like a lecturer). He writes every page of the Guild Journal
  you read at the Guild Board (StoryConfig). His quests fill in the Ember Kings' history (Crown of Kaldrum).
- **Misty Gleam** (bubbly perfectionist, sprays everything, "Sparkle check!"). She is the Guild's expert on the
  Cleaning Station. She gives only cleaning quests. She once polished a star map out of a muddy stone (Heartstone
  Lore).
- **Pip Farwander** (restless explorer, "Onward!"). His brass compass glows near the old Royal Railway. He hunts for
  the Night Train that "the Guild still searches for" (Railway chapter 4).
- **Brakka Emberhand** (loud, laughs, loves heat). He is the great-grandson of Master Orvald of the Golemworks
  (Golemworks chapter) and wants to cast golem casings again.
- **Sela Shardwell** (calm, hums to crystals: "they grow toward kind voices"). She found rails under the Deep
  Hollow's crystal lagoon, which is where the Night Train stopped. This closes Pip's mystery.
- **Captain Aurel** (proud, formal, honorable). His family has kept the royal guard's watch in the sunken palace for
  a hundred years, for a king who never came back (Crown of Kaldrum).
- **Volta Sparkwright** (talks fast, excited inventor). She tames the Rift's lightning to wake the First Golem
  (Golemworks Legendary).
- **Ashka** (slow, cryptic, kind). She listens to the Heartstone for the Guild and keeps the Forgekeepers' Oath:
  "keep the fire, share the ore, wake what sleeps" (Heartstone Lore).

### 1.3 Looks (WP-Art, prototyped and reviewed)

`NpcBuilder` builds them as **Kenney Mini Characters** proportions from parts:
- no meshes and no lights; Neon for the glow;
- each NPC in its own Pop paint (`Outfits[i].Paint`, a `PopTheme.Paints` key, unique), with the accent
  (`= Paint.Top`) for the nameplate title and the same paint for the pad, the marker and the dialog band;
- a **quest pad** under the feet (2 parts, client side): a flat disc in the paint's Bottom on a glowing rim in its
  Top. It is what makes them read from far away in the dark caves;
- a contrast accent per zone, checked in the world pictures: Brakka a bright cream apron and brighter ember trims in
  the red caves; Sela warm gold plates and magenta crystals in the cyan lagoon; Pip an orange jacket on the brown
  quarry floor; Quill a bright purple and gold robe on the dark plaza;
- faces with eye shines; Misty, Volta and Brakka grin, Pip and Sela smile, Aurel keeps a formal line, Quill hides his
  under the beard and Ashka wears a mask;
- props that read from the front: Pip's lantern held out and a pickaxe on his shoulder, Brakka's hammer on his
  shoulder with a big glowing head, Sela's crystal cluster, Volta's open-jaw wrench over her shoulder.

The outfits are described in its header.

**Anchor and dress (the live game):**
- `NpcBuilder.anchor(id, feet) -> Model`: **1 part**, the `Root` box, with the three attachments `NameplatePoint`,
  `QuestMarkerPoint` and `PromptPoint` and the attributes `Npc`, `DisplayName`, `Title`, `Area`, `Paint`, `Height`
  and `RootHeight`. The server builds this. The points come from the per-outfit **`Height` constant**, so the anchor
  needs no outfit parts; tests/NpcBuilder.spec checks the constant equals the dressed top.
- `Root` is invisible and **never collides, is never queried and never touched** (`CanCollide`, `CanQuery`,
  `CanTouch` off), and it is tagged `MovementConfig.BeamIgnoreTag`. Players walk through NPCs (common in Roblox).
  The mouse aim ray in MiningController `cast`, InteractController's grab ray and ore thrown at the hopper all pass
  it, so a rock behind an NPC stays clickable. No other chat's ray filter changes.
- `NpcBuilder.dress(model)`: adds the outfit parts and the pad into an anchor model (undresses first, so it can be
  redone). `NpcBuilder.undress(model)` removes every part but Root. The client calls them.
- `build()` stays as `anchor` + `dress` for previews, specs and the dialog portrait.
- **Rules for the dressed model:** at most `MaxParts = 70` (today 51–60 with the pad), at most 20 Neon parts, no
  PointLights and no particles. Phones must be able to show 2–3 NPCs at once. Budgets: section 6.4.

**Animation contract** (`NpcBuilder` header; the client in 5.1):
- a part with the attribute `Group` belongs to a rigid group that moves as one (`workspace:BulkMoveTo` over the
  group's parts, never part by part);
- `Group = "Head"`: the head and everything worn on it (face, hair, beard, hat, helmet, hood, goggles, mask). It
  turns about the vertical axis through `(0, NeckY, 0)` of the feet;
- every other group floats (its parts also carry `Float = true`): Quill's book (covers, pages, rune, relic), each
  relic shard, each bubble, Ashka's heartstone with its core and orbit stones, each rune stone with its glyph;
- no part changes Size at run time: an idle "breath" is a small bob of the whole model.

---

## 2. Quest design

### 2.1 Goal kinds (exact rules)

| Kind | Fields | Counts when | Signal |
|---|---|---|---|
| **Bring** | `Ore`, `Grade` (the lowest grade accepted), `Count` | At hand-in, the player has `Count` cleaned ores (item kind `Clean`) of `Ore` with grade ≥ `Grade`, in their **hands and/or Ore Pen** | none: checked at hand-in (`CarryService.list`, `data.Storage`) |
| **Mine** | `Zone` (a WorldLayout zone id), `Count` | A rock whose own zone is `Zone` breaks for the player | `MiningService.onRockBroken(player, zoneId)` (new, required, 6.2) |
| **Clean** | `Grade`, `Count`, optional `Rarity` (lowest) or `Ore` | The player finishes the cleaning minigame on an **ore** (not a dusty relic) with grade ≥ `Grade` and the filter matching | `CleaningService.onCleaned`; ore when `OreData.ById[oreId] ~= nil` |

**Grades.** Grade order is Rough < Clean < Pristine < Flawless (`ItemData.gradeLevel`).

**Bring goals:**
- `Grade = "Rough"` means "any cleaned ore". Dirty, crushed and ingot items never count.
- **Podiums don't count.** Players keep their best clean ore on podiums, so the dialog says "from your hands or your
  Ore Pen" next to every Bring goal.
- **Which items are taken** (no Flawless wasted on a Pristine-or-better goal):
  1. the lowest grade that qualifies first;
  2. then hands before pen;
  3. then the newest pen entry first.

**Mine goals:**
- They count only while the quest is accepted. There is no back-pay.
- Several accepted quests with the same zone count the same rocks (this helps the player).

**Clean goals:**
- Only hand cleaning counts, which is the signature minigame. Machines never fire `onCleaned`.
- Goal texts say "at a Cleaning Station".
- `CleaningGuard` already caps a scripted Flawless at Pristine.

**Flawless goals** (score 0.92 or more, hand cleaning only) are hard for casual players. They are only ever the
**last step of a chain** (6 quests: SC4, GP4, CM4, PG4, SE4, CS5), so they never block a later quest. The card shows
the requirement before Accept: "Flawless: hand-cleaned at a Cleaning Station, score 92 % or more".

**Kinds left out, and why:**
- **"Mine N of ore X":** dirty ore is a secret until it is cleaned. Counting it at the rock would reveal it.
- **"Find X":** the owner said no.

**Goal text** is generated from the goal, at most 48 characters:
- "Bring 3 Emberite (Clean or better)"
- "Break 20 rocks in the Ember Caves"
- "Clean 5 Rare+ ores to Pristine"

### 2.2 The chains

- **Gate** = the blaster level needed to **accept** that quest. A quest already accepted can still be handed in
  after a rebirth.
- **Floor** = the highest floor whose MinBlaster ≤ the gate.
- **Ore rewards:** dirty ore, delivered into the Ore Pen.
- **Artifact rewards** follow the pick rule in 2.4 (`Prefer` first). The `Else` column is what the quest gives
  instead when every artifact it could give is already owned; its line is `DoneElse` (2.6).

**1. Archivist Quill, `Scholar`** (lobby). Opens: tutorial done or skipped.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | SC1 | Ink from Coal | Bring 5 Coal (any grade) | 1 | 1 Frostbite | |
| 2 | SC2 | The Quarry Remembers | Break 25 rocks in the Greystone Quarry | 1 | Artifact: Crown of Kaldrum, Common (Prefer `CrownCoin`) | 1 Frostbite |
| 3 | SC3 | Silver Seals | Bring 2 Silver (Clean or better) | 3 | 1 Bronze + 1 Amber | |
| 4 | SC4 | Gilding the Chronicle | Bring 1 Flawless Gold | 5 | Artifact: Crown, Rare (Prefer `EmberScepter`) + 1 Obsidian | 2 Obsidian |

**2. Misty Gleam, `GemPolisher`** (lobby). Opens: tutorial done or skipped. Cleaning quests only.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | GP1 | First Shine | Clean 5 ores to Clean or better | 1 | 1 Frostbite | |
| 2 | GP2 | Pristine Practice | Clean 5 ores to Pristine | 2 | Artifact: Heartstone Lore, Uncommon (Prefer `StarMapFragment`) | 1 Leaf Ore + 1 Honeycomb |
| 3 | GP3 | Gentle Hands | Clean 3 Uncommon+ ores to Pristine | 3 | 1 Silver | |
| 4 | GP4 | The Jeweler's Test | Clean 3 Rare+ ores to Flawless | 5 | 1 Amethyst + 1 Crystal Rose | |

**3. Pip Farwander, `Explorer`** (quarry). Opens: tutorial done or skipped.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | EX1 | Fuel for the Lantern | Bring 6 Iron (any grade) | 1 | 1 Leaf Ore + 1 Honeycomb | |
| 2 | EX2 | Clear the Old Line | Break 30 rocks in the Ember Caves | 3 | Artifact: Royal Railway, Uncommon (Prefer `RailLantern`) | 1 Silver |
| 3 | EX3 | Signal Lamps | Bring 4 Amber (Clean or better) | 4 | 1 Silver + 1 Cobalt | |
| 4 | EX4 | Green Signals | Bring 2 Jade (Pristine or better) | 5 | 2 Amethyst + 1 Obsidian | |

**4. Brakka Emberhand, `LavaSmith`** (Ember Caves). Opens: blaster 3.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | LS1 | Stoke the Forge | Break 20 rocks in the Ember Caves | 3 | 3 Amber | |
| 2 | LS2 | Ember Steel | Bring 3 Emberite (Clean or better) | 3 | 1 Silver | |
| 3 | LS3 | A Golem's Casing | Bring 4 Cobalt (Clean or better) | 4 | Artifact: Golemworks, Rare (Prefer `GolemBlueprint`) | 1 Silver |
| 4 | LS4 | Eyes of Sapphire | Bring 3 Sapphire (Pristine or better) | 5 | 2 Diamond + 1 Obsidian | |

**5. Sela Shardwell, `CrystalMiner`** (Deep Hollow). Opens: blaster 5.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | CM1 | Let Them Breathe | Break 35 rocks in the Deep Hollow | 5 | 1 Obsidian + 1 Amethyst | |
| 2 | CM2 | Dragon's Clutch | Bring 3 Dragon Egg (Pristine or better) | 6 | 2 Obsidian | |
| 3 | CM3 | Lagoon Lights | Bring 2 Amethyst (Pristine or better) | 6 | 3 Diamond | |
| 4 | CM4 | The Night Train's Crest | Bring 1 Flawless Diamond | 6 | Artifact: Royal Railway, Epic (Prefer `LocomotiveCrest`) | 1 Crystal Rose + 1 Diamond |

**6. Captain Aurel, `PalaceGuard`** (Sunken Palace). Opens: blaster 7.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | PG1 | Clear the Throne Hall | Break 40 rocks in the Sunken Palace | 7 | 2 Royal Aurum | |
| 2 | PG2 | A Gleaming Hall | Clean 5 Epic+ ores to Pristine | 7 | 2 Sunstone | |
| 3 | PG3 | The Kings' Tribute | Bring 3 Royal Aurum (Pristine or better) | 7 | Artifact: Crown, Epic (Prefer `EmberCrown`) | 2 Sunstone |
| 4 | PG4 | For the Lost King | Bring 1 Flawless Galaxy Stone | 8 | 2 Moonstone + 1 Storm Gem | |

**7. Volta Sparkwright, `StormEngineer`** (Stormglass Rift). Opens: blaster 8.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | SE1 | Ground the Coils | Break 40 rocks in the Stormglass Rift | 8 | 1 Leaf Gem + 1 Moonstone | |
| 2 | SE2 | Charged Crystals | Clean 4 Legendary+ ores to Pristine | 8 | 2 Leaf Gem | |
| 3 | SE3 | Leaf Gem Capacitors | Bring 3 Leaf Gem (Pristine or better) | 8 | 2 Volcanic Core | |
| 4 | SE4 | Wake the First Golem | Bring 1 Flawless Volcanic Core | 9 | Artifact: Golemworks, Legendary (Prefer `FirstGolemEye`) | 2 Celestial Core |

**8. Ashka, `CoreShaman`** (Heartstone Core). Opens: blaster 9.

| Step | Id | Title | Goal | Gate | Reward | Else |
|---|---|---|---|---|---|---|
| 1 | CS1 | Listen to the Core | Break 40 rocks in the Heartstone Core | 9 | 2 Dragon Scale | |
| 2 | CS2 | Sparks of the Oath | Clean 5 Mythic ores to Pristine | 9 | Artifact: Heartstone Lore, Rare (Prefer `ForgekeeperOath`) | 2 Aetherium |
| 3 | CS3 | Phoenix Ash | Bring 3 Phoenix Feather (Pristine or better) | 9 | 2 Celestial Core | |
| 4 | CS4 | Focus the Sunlance | Bring 2 Celestial Core (Pristine or better) | 9 | Artifact: Heartstone Lore, Legendary (Prefer `SunlanceLens`) | 2 Dragon Scale |
| 5 | CS5 | A Heart That Still Beats | Bring 1 Flawless Heartstone | 10 | 3 Heartstone | |

**Totals:** 33 quests (19 Bring, 7 Mine, 7 Clean), 10 artifact rewards and 6 Flawless goals, each the last step of
its chain.

| Rarity | Artifacts | Quests |
|---|---|---|
| Common | 1 | SC2 |
| Uncommon | 2 | GP2, EX2 |
| Rare | 3 | LS3, CS2, SC4 |
| Epic | 2 | CM4, PG3 |
| Legendary | 2 | SE4, CS4 |

**Rewards that feel like better ore** (review): a floor's crystal ores or its rarest home ores, never the floor's most
common one. SE1 gave Storm Gem (the Rift's most common home ore) and CM1 gave Sapphire (a mid home ore); both changed.
Rewards also feed the next step where they can: CM3's Diamonds for CM4's Flawless Diamond, SE2's Leaf Gems for SE3,
SE3's Volcanic Cores for SE4, CS3's Celestial Cores for CS4.

**Every goal can be done:**
- Each Bring ore drops on a floor the gate opens (SC3: Silver in the Ember Caves; PG4: Galaxy Stone in the Sunken
  Palace…).
- Each Mine zone's MinBlaster ≤ the gate.
- Each Clean rarity filter covers what the gate floor drops. The Sunken Palace, the Rift and the Core drop only
  Epic+, Legendary+ and Mythic ores.

The spec checks all three (section 6.3).

### 2.3 Reward rules (big but safe)

Checked with the real config (OreData, ItemData, BlasterData, MineFloors, EconomyConfig) and a fresh balance sim run
(f3a5327, Typical player, 120 players, medians). Every row passes.

| Rule | What | Why |
|---|---|---|
| R1 Floor | Every reward ore is in the `Ores` or `CrystalOres` of the quest's floor | A reward is "the floor's best ores, guaranteed and sooner", never a skip past a floor |
| R2 Count | At most 3 ores per quest. At most 1 artifact per quest, 2 per chain and 10 in all. Never the Mythic artifact. Mythic **ores** only from gate 9 | The Heartstone Fragment stays the long chase. Shard restore stays useful |
| R3 Coins | The **best processed value** of a quest's ores, each at Flawless, ≤ **25 %** of the Foundry price of the next floor's MinBlaster level (no next floor: level 10's price) | Keeps early rewards under one blaster step |
| R4 Kind | Rewards are only dirty ore (into the pen) and new artifacts. **Never** coins, shards, boosts, capsules or cosmetics. A duplicate artifact is never given, so `DuplicateShards` never pays | The owner's list |
| R5 Fixed | Rewards never depend on random rolls, Robux, VIP or luck boosts | No odds to show (COMPLIANCE). Nobody pays for a better reward |
| R6 Podium | From gate 3: the **Pristine podium income** of a quest's ores (`ItemData.income({K="Clean", O=ore, G="Pristine"})`, summed) ≤ **25 %** of the Typical player's median income in the quest's floor window (table below) | One quest must never double the income it is given at |

**R3, the best processed value.** A clean ore sells for `ItemData.value("Clean", ore, "Flawless")`, but smelting pays
more: an ingot is ×1.25 and gear ×1.25 × the recipe bonus per ingot (Greatsword 1.9). So R3 measures, per ore,
`max over recipes of ItemData.value("Gear", ore, "Flawless", recipe) / recipe.Ingots` (= the Flawless clean value ×
2.375). The first draft measured the clean value only; its GP1 (2 Emberite) was 5,040 as ingots and 9,576 as gear,
over the 4,250 cap. The rule now binds the gate 1–2 quests:

| Quest | Reward | Best processed | Share of the cap |
|---|---|---|---|
| EX1, GP2 Else | 1 Leaf Ore + 1 Honeycomb | 3,591 | 84 % (cap 4,250 = 25 % of blaster 3's 17,000) |
| SC1, GP1, SC2 Else | 1 Frostbite | 3,420 | 80 % |
| LS1 | 3 Amber | 41,040 | 7.8 % (cap 525,000) |
| CS5 | 3 Heartstone | 410M | 0.6 % |

**R6, podium income.** The reference is the Typical player's **median income over the floor window** the quest is
played in (from reaching the floor's MinBlaster to reaching the next floor's), from `build/balance/sim.json`:

| Gates | Window (Typical) | Median income | R6 cap (25 %) | Closest quest |
|---|---|---|---|---|
| 1–2 | tutorial (~10 min) → blaster 3 (13 min) | 35/s | not applied: R3 binds | |
| 3–4 | blaster 3 (13 min) → blaster 5 (47 min) | 1,710/s | 428/s | LS1 408/s (95 %) |
| 5–6 | blaster 5 → blaster 7 (1h59) | 49.7K/s | 12.4K/s | EX4 12.2K/s (99 %) |
| 7 | blaster 7 → blaster 8 (3h16) | 722K/s | 180K/s | PG2 95K/s (53 %) |
| 8 | blaster 8 → blaster 9 (5h00) | 4.97M/s | 1.24M/s | SE3 442K/s (36 %) |
| 9 | blaster 9 → blaster 10 (8h00) | 26.8M/s | 6.69M/s | CS3 / SE4 Else 1.87M/s (28 %) |
| 10 | 8h → 10h | 37.2M/s | 9.30M/s | CS5 4.08M/s (44 %) |

`QuestConfig.TypicalIncome` holds this table (with the sim run's date and commit). WP-Q4 refreshes it with every
balance sim run, and the spec checks R6 against it.

**SE3** (the review's main economy point): the first draft gave 1 Aetherium + 1 Phoenix Feather, both Mythic: 816K/s
on podiums at Pristine and 1.15M/s at Flawless. The review compared that with 0.79M/s, the Typical income at 3h00,
16 minutes before blaster 8. Within 5 minutes of blaster 8 the Rift lifts the Typical income to about 4.5M/s, so
SE3 was about 16 % of its window. It is changed anyway, as asked: Mythic ores only from gate 9 (R2), and SE3 gives 2
Volcanic Core (442K/s). The first draft also said "4 podiums": `EconomyConfig.Podiums.Free = 2`, and podiums 3–4
need the Robux perk.

**Required before landing (WP-Q4):** `tools/lune/balance_sim.luau` models the quest rewards and the Typical player
still reaches blaster 10 at 8h ± 15 min. The model needs:
- the quest ores, arriving dirty in the pen when the typical player finishes each quest (gate reached + the quest's
  play time, 3–10 minutes; Flawless goals at the cleaning skill's Flawless rate);
- the artifacts, which can complete collections and switch on their bonuses: Crown of Kaldrum +5 % income, Heartstone
  Lore +10 % income, Royal Railway +10 % sell, Golemworks +10 % golem bond. Quests give 3 of the 6 Crown artifacts
  (SC2, SC4, PG3), 3 of the 6 Heartstone Lore ones (GP2, CS2, CS4, never the Mythic), 2 of 6 Railway and 2 of 6
  Golemworks ones;
- a refreshed R6 table from the same run.

### 2.4 Which artifact (fixed, shown before accepting)

A quest's artifact spec is `{ Collection, Rarity, Prefer? }`. `QuestConfig.artifactFor(artifacts, spec)` picks, in
this order:
1. `Prefer` (an `ArtifactConfig` id of that collection and rarity) when the player has **not** found it yet. It is the
   artifact the story is about (the Ember Crown for Aurel, the Oath for Ashka).
2. Else the first artifact in `ArtifactConfig.List` order with the spec's `Collection` and `Rarity` that the player
   has not found.
3. Else the first missing artifact of that `Rarity` in any collection. That is never the Mythic, because no spec
   names Mythic.
4. Else nothing: the quest gives its `Else` ores instead, with its `DoneElse` line.

**Lines never name the artifact.** A Done line uses the token `{Artifact}`, which the dialog fills with the picked
artifact's name (a leading "The " dropped, so "the {Artifact}" reads right for "The Ember Crown"). Steps 2–3 can pick
another artifact than the story's, so a literal name could be wrong. The first draft named six of them literally, and
CS2's "These words are yours now" (the Oath) never matched even on a fresh save, because `List` order picks the
Ember Rune first. `DoneElse` has no token.

**How it is granted:**
- The quest card shows the exact pick live, from the State's `Artifacts`.
- The server picks again at hand-in, in the same step that grants it.
- The grant is `ArtifactService.cleanRelic(player, id, npcPromptPosition)`, the public "record a find" call:
  - the relic pops out of the NPC and flies to the player (the existing `ArtifactFound` moment);
  - a completed collection plays its full moment (its title, podium skin and bonus switch on);
  - the museum updates.
- It counts once in `Stats.ArtifactsFound` (the ARTIFACTS board). That is accepted: at most 10 per player, once.

### 2.5 Repeatable? No

- **One-time chains.** A chain is done once per save. After it, the NPC says its "all done" line and shows no marker.
- **Rebirth:** `RebirthConfig.reset` never touches `data.Quests`, so finished chains stay finished.
  - An accepted quest stays accepted, with its progress.
  - It can be handed in once the goal is met, whatever the new blaster level is. The gate only stops **accepting**.
  - Note: the pen is emptied on rebirth, so ore for a Bring goal is gathered again.
- **Updates** may **append** quests to a chain. They never reorder or remove any (the spec pins the id order). A
  finished chain that grew reopens on load (section 3.2).

### 2.6 Lines (English UI, at most 120 characters each, no emoji)

Each NPC also has a `Hello` line (step 1, nothing accepted), a `Locked` line ("Come back with a Level {N} blaster…")
and an `AllDone` line. Quest lines are listed as Offer / Done; artifact quests also have DoneElse. `{Artifact}` is the
token from 2.4. Ore names in a Done line are the quest's own reward ores (the spec checks it).

**Archivist Quill**
- Hello: "Ah, a new Forgekeeper! Archivist Quill. Every page of the Guild Journal is in my handwriting."
- SC1: "Coal makes the finest ink, and I am nearly out. Bring me 5 Coal, any grade, but cleaned." / "Black as
  midnight! Take this Frostbite. Wash it gently."
- SC2: "The Quarry remembers the Ember Kings. Break 25 rocks there and see what turns up." / "A relic of the Ember
  Kings! The {Artifact} belongs in your collection." / Else: "Your royal shelf is already full! Then take this
  Frostbite instead."
- SC3: "Royal seals were pressed in silver. Bring me 2 Silver, Clean or better." / "Splendid. Bronze and Amber, for
  your trouble. Mind the dust."
- SC4: "The last chapter needs gilding: one Flawless Gold, not a speck on it." / "The {Artifact}, from page one of
  the oldest chronicle. And Obsidian for the cover." / Else: "The chronicle is complete. Two Obsidian, the finest
  ink stones I own."
- AllDone: "The Journal grows thanks to you. Read it at the Guild Board."

**Misty Gleam**
- Hello: "Hi hi! Misty Gleam, Gem Polisher. Dirt is just shine that hasn't happened yet!"
- GP1: "Sparkle check! Clean 5 ores at a Cleaning Station, Clean grade or better." / "Squeaky! Here's a Frostbite.
  Don't you dare leave it dusty."
- GP2: "Now Pristine! Clean 5 ores to Pristine. Slow, steady sweeps." / "I polished this out of a muddy stone: the
  {Artifact}! You keep it." / Else: "You found them all already? Then take Leaf Ore and Honeycomb, fresh from the
  quarry."
- GP3: "Gentle hands now: clean 3 Uncommon or better ores to Pristine." / "Gorgeous! A Silver, freshly dug. Make it
  shine."
- GP4: "Jeweler's test: clean 3 Rare or better ores to Flawless. Not one crack!" / "FLAWLESS! I might cry. Amethyst
  and a Crystal Rose, you've earned them."
- AllDone: "Nothing left to teach you. Go make the world sparkle!"

**Pip Farwander**
- Hello: "Pip Farwander, explorer! My compass glows near the old Royal Railway. It's glowing right now."
- EX1: "My lantern runs on iron filings. Bring me 6 Iron, any grade." / "Onward! Leaf Ore and Honeycomb from my last
  dig. Still dirty, sorry."
- EX2: "The old line runs through the Ember Caves. Break 30 rocks there to clear it." / "Look! The {Artifact}, right
  under the rubble. The Royal Railway lives!" / Else: "Just rubble this time. Here, a Silver for your trouble."
- EX3: "The signal lamps burn amber. Bring me 4 Amber, Clean or better." / "The tunnels are lit! Silver and Cobalt
  for your pack."
- EX4: "The deep signals were green jade. Bring me 2 Pristine Jade." / "Every signal is green again! Amethyst and
  Obsidian from the deep line. Onward!"
- AllDone: "Sela says the rails end in the Deep Hollow lagoon. Onward!"

**Brakka Emberhand**
- Hello: "HA! Fresh legs in my caves! Brakka Emberhand, great-grandson of Master Orvald of the Golemworks."
- LS1: "My forge has gone cold! Break 20 rocks in the Ember Caves and let the heat back in." / "Feel that warmth? HA!
  Amber for you. Golems love the stuff."
- LS2: "A golem casing needs Ember steel. Bring me 3 Emberite, Clean or better." / "Good steel! This Silver is too
  pretty for armour. Take it."
- LS3: "Cobalt makes the joints. Bring me 4 Cobalt, Clean or better." / "Great-grandpa's own work, dug out of my
  scrap pile: the {Artifact}. It's yours." / Else: "Nothing in the scrap pile you don't have! Take this Silver, HA!"
- LS4: "Every golem needs eyes. Bring me 3 Pristine Sapphire." / "Now we're cooking! Diamonds and Obsidian from the
  deep shelf."
- AllDone: "The forge is roaring again. Orvald would laugh till the roof shook!"

**Sela Shardwell**
- Hello: "Shh. Listen. The crystals hum. I'm Sela. They grow toward kind voices."
- CM1: "The shore is crowded. Break 35 rocks in the Deep Hollow so the crystals can breathe." / "Better. Obsidian
  and Amethyst, grown in the quiet."
- CM2: "Dragon eggs sleep in the warm shallows. Bring me 3, Pristine, and gently." / "They're warm. Thank you. Two
  Obsidian came up with the eggs. Take them."
- CM3: "The lagoon's lights are amethyst. Bring me 2 Pristine Amethyst." / "The lights are back on. Diamonds, for
  your pen."
- CM4: "Something lies under the crystals: rails. Bring one Flawless Diamond to light my lamp." / "The {Artifact}.
  The Night Train stopped here. Thank you." / Else: "Only rails today. Take a Crystal Rose and a Diamond for the
  light."
- AllDone: "Tell Pip his train is found. The crystals will keep it safe."

**Captain Aurel**
- Hello: "Halt! ...Pardon me. Captain Aurel of the Palace Guard. My family has kept this watch for a hundred years."
- PG1: "The throne hall is buried. Break 40 rocks in the Sunken Palace." / "The hall breathes again. Royal Aurum, as
  the old law allows."
- PG2: "A royal hall must gleam. Clean 5 Epic or better ores to Pristine." / "Gleaming. Sunstone, from the guard's
  own vault."
- PG3: "The kings' tribute was Royal Aurum. Bring me 3, Pristine or better." / "The {Artifact}. I guarded it for a
  king. Guard it for Kaldrum." / Else: "The crown room is empty. Take Sunstone from the vault instead."
- PG4: "One last tribute: a Flawless Galaxy Stone, for the king who never came back." / "My watch is over. Moonstone
  and a Storm Gem, for the road ahead."
- AllDone: "Long live Kaldrum. And long live its miners."

**Volta Sparkwright**
- Hello: "Oh! A visitor! Volta Sparkwright, storm engineer. Mind the coils, they bite."
- SE1: "The coils are overloaded! Break 40 rocks in the Stormglass Rift to ground them." / "Zap! Grounded! A Leaf Gem
  and a Moonstone, still crackling."
- SE2: "I need charged crystals. Clean 4 Legendary or better ores to Pristine." / "Perfect charge! Leaf Gems, handle
  with gloves."
- SE3: "Leaf Gems make the best capacitors. Bring me 3, Pristine." / "Capacitors full! Two Volcanic Cores, still
  humming."
- SE4: "The First Golem's eye needs a spark: one Flawless Volcanic Core." / "It blinked! The {Artifact}. Keep it
  somewhere VERY safe." / Else: "No eye left to wake! Then take two Celestial Cores. Don't lick them."
- AllDone: "Next project: a golem that makes tea. Don't tell Brakka."

**Ashka**
- Hello: "You came all the way down. Good. I am Ashka. I listen to the Heartstone for the Guild."
- CS1: "Break 40 rocks in the Heartstone Core. Each one tells the heart you are here." / "It heard you. Dragon
  Scales, shed by the deep."
- CS2: "The Oath is kept in sparks. Clean 5 Mythic ores to Pristine." / "Keep the fire, share the ore, wake what
  sleeps. The {Artifact} is yours now." / Else: "You carry every word already. Take Aetherium, the heart's breath."
- CS3: "Phoenix ash rekindles any fire. Bring me 3 Phoenix Feathers, Pristine." / "The fire is kind tonight.
  Celestial Cores, for you."
- CS4: "The Sunlance once lit Kaldrum. Two Pristine Celestial Cores will focus its lens." / "The {Artifact}. Light
  bends inside it. So does hope." / Else: "The lens is already yours. Take these Dragon Scales instead."
- CS5: "The hardest gift: one Flawless Heartstone. The heart must see itself whole." / "It beats faster. Take these
  Heartstones. One day it will be whole."
- AllDone: "The heart is listening. So am I. Come back when it speaks again."

### 2.7 Pacing (typical player, docs/BALANCE_SIM.md 2026-10-20 table)

| Window | NPCs that open | Quests in reach |
|---|---|---|
| ~10 min (tutorial done) | Quill, Misty, Pip | SC1, SC2, GP1, EX1 (and GP2 at blaster 2) |
| ~15–30 min (blaster 3–4) | Brakka | SC3, GP3, EX2, EX3, LS1–LS3 |
| ~50 min (blaster 5) | Sela | SC4, GP4, EX4, LS4, CM1 |
| 1h20–2h (blaster 6) | | CM2–CM4 (fills the gap before the elevator) |
| ~2h (blaster 7 + elevator) | Aurel | PG1–PG3 |
| ~3h15 (blaster 8) | Volta | PG4, SE1–SE3 |
| ~5h (blaster 9) | Ashka | SE4, CS1–CS4 |
| ~8h (blaster 10) | | CS5, the finale |

Each quest is 3–10 minutes of normal play. The chains add about 2.5–4 hours of guided goals, spread over the 8-hour
run. The Flawless steps (6) may wait longer for casual players; nothing after them waits on them.

---

## 3. Data

### 3.1 Save fields (DataTemplate, integrator)

```lua
-- quest givers (QuestConfig, QuestService): per NPC id (NpcBuilder outfit id)
-- { Step, Progress, Active, Done }. An NPC with no entry is on step 1 and not
-- accepted; an entry appears with the first Accept. Step = the quest the player
-- is on (1 .. #chain; #chain + 1 = the chain is finished). Progress = the Mine /
-- Clean count of the current step (0 for Bring and while not accepted).
-- Active = accepted (only then do rocks and cleans count). Done = every quest
-- this build knew is finished (a newer build with a longer chain reopens it).
Quests = {},
```

**How old saves get it:** the template entry is an empty table, so `ProfileStore.reconcile` adds `Quests = {}` to old
saves and never reconciles inside it. It is a map, like `KeepList`.

**Size:** 8 entries of about 70 bytes of JSON each. The junk guard (64 entries kept) caps it near 4.5 KB. The worst
case in tests/SaveSize.spec is 134 KB of 256 KB today.

### 3.2 Migrations repair (integrator; a `migrateQuests(data, report)` after `migrateStep8`)

- **The record itself:** `data.Quests` that isn't a table becomes `{}` (`Dropped += 1` when it wasn't nil).
- **Keys:**
  - Keys must be short ids (`idLike`). An NPC id this build doesn't know is **kept** (a newer build's NPC).
  - At most `MAX_QUEST_NPCS_KEPT = 64` entries are kept, the first in sorted key order. The rest are dropped.
- **Entries:** an entry that isn't a table is dropped. In an entry:

  | Field | Valid value | Junk becomes |
  |---|---|---|
  | `Step` | whole 1..`MAX_QUEST_STEP_KEPT` (99) | 1 |
  | `Progress` | whole 0..1e6 | 0 |
  | `Active` | boolean | false |
  | `Done` | boolean | false |
- **Fields a newer build adds** stay when they are well-formed scalars. That is the same rule as golem entries: a key
  of at most 32 characters, a boolean, a finite number or a string of at most 64 characters, and at most 8 of them.
- **Not done here:** nothing needs QuestConfig. A Step past this build's chain is kept as it is (section 4.1, the
  "Newer" state).
- **Behaviour:** idempotent. In tests/Migration.spec, a future save with unknown NPC ids, steps and fields comes out
  unchanged, and junk is repaired.

**Done on load by QuestService:**
- If `Done == true` and `Step <= #chain` (an update appended quests), it sets `Done = false`.
- If `Done == false` and `Step == #chain + 1`, it sets `Done = true`.

### 3.3 Version and the newer-save gate

**Decision: `Version` stays 3. `DataTemplate.Version` and `Migrations.Latest` stay unchanged.**

1. **The game is not public yet.** Every pass and product id is 0, and the owner hasn't uploaded. Every record added
   before release shipped under Version 3, with a "same Version 3" note in the Migrations header:
   - hoverboards;
   - star blasters;
   - `Wheel.Spins`;
   - `PurchaseLog`;
   - `PaidCoins`.

   Quests follows that.
2. **It is safe even without a bump:**
   - An older server without QuestService keeps `data.Quests` untouched. `reconcile` keeps unknown top-level keys,
     and its Migrations never read the record.
   - A newer build's NPC ids, steps and fields are kept by the repair in 3.2.
   - Nothing a save names here can be "repaired away" by an older build.
3. **If the game is public when this lands**, follow PUBLISHING.md step 12 (new save field → bump):
   - set `DataTemplate.Version = 4` and `Migrations.Latest = 4` together, with a no-op step from 3 to 4;
   - tests/SaveSafety.spec checks that the two are equal.

   The integrator checks the release state at landing time and notes the choice in the Migrations header.

### 3.4 State section (client view)

QuestService registers a provider with `StateService.addProvider`:

```lua
snapshot.Quests = {
  Npcs = { [npcId] = { Step, Progress, Active, Done, Have? } }, -- every QuestConfig NPC (defaults filled)
  ActiveCount = n,   -- accepted quests (unknown NPC ids too, so the cap holds across builds)
}
```

- **`Have`** is only on accepted Bring quests: matching items in the hands plus the pen (a count only; podiums never
  count).
- **Pushes when carried items change:** the provider recomputes on every push. When the player's `CarryCount`
  attribute changes, QuestService calls `StateService.push(player)`. The data didn't change, so it doesn't call
  `DataService.changed`.
- **What the client reads alongside:** `BlasterLevel`, `Tutorial` and `Artifacts`, which are already in the snapshot.
  From them it works out every status with the same pure `QuestConfig.status`, and the reward artifact with
  `QuestConfig.artifactFor`.

---

## 4. Server: QuestService

**New files:**
- `src/server/Services/QuestService.luau`;
- `src/shared/Config/QuestConfig.luau` (data plus pure rules, shared with the client and the specs);
- `src/shared/Config/NpcSpots.luau` (the 8 spots, owned by the art package, moved from `Preview.Spots`).

### 4.1 QuestConfig (pure, shared)

**Types:**
- `Npc { Id, Hello, Locked, AllDone, Unlock = { Tutorial = true, Blaster = n }, Chain = { Quest } }`.
  Name, Title, Area, Floor and **Paint** are read from `NpcBuilder.ById` (one source; no `Paint` here).
- `Quest { Id, Title, Gate, Goal, Reward = { Ores?, Artifact? = { Collection, Rarity, Prefer? }, Else? }, Offer,
  Done, DoneElse? }`. `DoneElse` is required exactly when `Reward.Artifact` is set.
- `Goal` is one of:
  - `{ Kind = "Bring", Ore, Grade, Count }`;
  - `{ Kind = "Mine", Zone, Count }`;
  - `{ Kind = "Clean", Grade, Count, Rarity?, Ore? }`.

**Constants:**

| Constant | Value |
|---|---|
| `MaxActive` | 3 |
| `TalkRange` | 10 (the prompt's distance) |
| `HandInSlack` | 6 |
| `ShowDistance` | 120 |
| `HideDistance` | 140 |
| `AnimateDistance` | 60 |
| `LockedIds` | the ordered quest ids, so the order of a chain can't change silently |
| `TypicalIncome` | the R6 table of 2.3, with the sim run's date and commit |

**Statuses** (`status(npcId, view) -> (Status, Quest?)`):

| Status | When |
|---|---|
| `Hidden` | tutorial not done |
| `Locked` | gate above the blaster |
| `Available` | can be accepted |
| `Full` | available, but `MaxActive` quests are already accepted |
| `Active` | accepted, not finished |
| `Ready` | accepted and finished. For Bring: `Have ≥ Count` |
| `Done` | chain finished |
| `Newer` | Step past this build's chain and not Done. Shown, never changed |

**Pure functions** (for the server, the client, the specs and Migrations-free repair):
- `entryOf`, `repairEntry`, `current`, `status`, `activeCount`;
- `goalText`, `requirementText(goal)` (the Flawless / hand-cleaning note on the card), `rewardText`;
- `doneText(quest, artifactId?)`: the Done line with `{Artifact}` filled, or `DoneElse` when no artifact was picked;
- `countsItem(goal, desc)`;
- `planHandIn(goal, hands, pen) -> { Hands = {i}, Pen = {i} }?`, with the order from 2.1;
- `countsRock(goal, zoneId)`: `Zone` equality. The Grotto can never match, because no goal names it;
- `countsClean(goal, oreId, grade)`: false when `OreData.ById[oreId]` is nil (a dusty relic: CleaningService passes
  the artifact id as the ore id);
- `artifactFor(artifacts, spec)` (with `Prefer`, 2.4);
- `rewardOf(quest, artifacts) -> { Ores, Artifact? }`;
- `penRoomNeeded(reward, penTaken)`.

**`Reasons`:**

| Code | Text |
|---|---|
| `BadNpc` | "That person isn't here" |
| `NoData` | "Your save is still loading" |
| `TooFar` | "Walk up to them first" |
| `Tutorial` | "Finish the tutorial first" |
| `Locked` | "You need a stronger blaster for this one" |
| `Full` | "You already have 3 quests. Finish or drop one first" |
| `Active` | "You already have this quest" |
| `NotActive` | "Accept the quest first" |
| `NotReady` | "Not finished yet" |
| `Missing` | "You don't have the ore yet (hands or Ore Pen)" |
| `PenFull` | "Make room in your Ore Pen for the reward" |
| `PenOver` | "Your Ore Pen is too full: take some ore out first" |
| `Done` | "Nothing more to do here" |
| `Newer` | "Come back after the next update" |

### 4.2 Life cycle and API

```text
init()   Net.on("QuestAction", onAction)
         DataService.onLoaded(onLoaded)                 -- repair, Done fix-up, push
         MiningService.onRockBroken(onRock)             -- rocks: (player, zoneId), the rock's own zone
         CleaningService.onCleaned(onCleaned)           -- cleans: ore when OreData.ById[oreId] ~= nil
         StateService.addProvider(provide)              -- snapshot.Quests
         Players.PlayerAdded: watch CarryCount -> StateService.push (only with an accepted Bring)
start()  build the anchors: Workspace.QuestNpcs / Npc_<id> = NpcBuilder.anchor(id, feet)
         (feet = NpcSpots ground ray, facing the spot's Face point), ModelStreamingMode Atomic, tag "QuestNpc"
         (Root already non-colliding, non-queried and tagged BeamIgnore by NpcBuilder);
         the "Talk" prompt on PromptPoint (PromptConfig.make { Name = "Prompt",
         ActionText = "Talk", ObjectText = name, Distance = TalkRange }), tag "QuestPrompt";
         Triggered: data loaded -> Net.fire("OpenUI", player, "Quest", { Npc = id })
API      QuestService.accept(player, npcId) -> (ok, reason?)
         QuestService.handIn(player, npcId) -> (ok, reason?, reward?)
         QuestService.drop(player, npcId)   -> (ok, reason?)
         QuestService.onQuest(cb(player, { Npc, Step, Quest, How = "Accept" | "Complete" | "Drop" }))
                                            -- analytics / badges later
         QuestService._test = { action, loaded, rock, cleaned, anchors, reset }
```

The anchors are built at server start, like the yard museums. They are **not** in the baked map: no
`WorldBuilder.Version` bump, no `build/TerraForge.rbxl` change and no edits to the floor builders.

### 4.3 Tracking

**Rocks (Mine goals): a required hook.** MiningService gets `MiningService.onRockBroken(cb)`, fired in `shatter` for
the player whose damage broke the rock, with `rock.Zone.Id` (the zone already exists there). About 3 lines in the
mine chat's file (6.2). The listener adds 1 to every accepted Mine quest with `Zone == zoneId`, capped at `Count`,
calls `DataService.changed(player)` and, on reaching `Count`, sends a Notify: "Quest done: return to {Name}"
(`Kind = "Success"`).

Why not the first draft's `Stats.RocksBroken` delta plus the root position at flush time: it miscounts rocks shot
across a zone border and drops counts when the character is dead at the flush.

**Cleans (Clean goals).** The listener is on `CleaningService.onCleaned(player, oreId, grade, score)`:
- an **ore** clean when `OreData.ById[oreId] ~= nil`. CleaningService passes the artifact id as the ore id for a
  dusty relic, and `tests/QuestConfig.spec` checks that ore ids and artifact ids never overlap;
- it counts for every accepted Clean goal that `countsClean` matches.

No baselines, no `OresCleaned` stamp, and CleaningService is not edited.

### 4.4 Hand-in (one step, no yield in between)

1. **Guards:**
   - `Guard.string(action, 8)` is one of Accept, HandIn or Drop;
   - `Guard.table(arg, 4)`;
   - `npc = Guard.string(arg.Npc, 32)` and it exists in `QuestConfig.ById`;
   - the data is loaded;
   - for Accept and HandIn, the character root is within `TalkRange + HandInSlack` of the NPC's PromptPoint
     (`TooFar`). Drop works anywhere.
2. **Status check:**
   - HandIn needs `Ready`, **or** `Available` for a Bring quest whose plan already exists.
   - The button then reads HAND IN and accepts and completes in one press, without using an active slot.
   - Anything else returns the matching reason.
3. **Plan the items** (Bring): `planHandIn(goal, hands, data.Storage)`:
   - hands = `CarryService.list(player)` filtered to records owned by the player in state `"Carried"`, read with
     `ItemService.descOf`;
   - no plan → `Missing`.
4. **Plan the reward:** `rewardOf(quest, data.Artifacts)`.
5. **Room check before anything is taken:**
   - `PenService.isOver(data)` → `PenOver`;
   - `n = oreCount - #plan.Pen`; if `n > 0` and `PenService.refusal(data, n)` → `PenFull`.

   This is unlike the wheel, which pays coins. Coins are not a quest reward.
6. **Take the items:**
   - pen entries first, removed by identity from the highest index down, as SellService does;
   - then the hand items, each through `CarryService.takeTop(player, function(r) return r == wanted end)` and then
     `ItemService.absorb`.
7. **Grant:**
   - each ore through `PenService.store(player, { K = "Raw", O = ore })`. As a last resort, if a store fails anyway:
     `ItemService.storeDesc(player, desc, "Quest reward")`, a rescue that never loses the item;
   - the artifact through `ArtifactService.cleanRelic(player, id, promptPosition)`. If it returns nil, which cannot
     happen after the pick, the `Else` ores are granted.
8. **Advance:**
   - `Step += 1`, `Progress = 0`, `Active = false`;
   - when `Step > #chain`, set `Done = true`.
9. **Answer:**
   - `DataService.changed(player)`;
   - reply `ActionResult { Action = "Quest", Op = "HandIn", Ok = true, Id = npc, Level = Step, Reward = { Ores, Artifact? } }`;
   - fire the `onQuest` listeners.

**Accept:** sets `Active = true` and `Progress = 0`.
- It needs `Available`: tutorial done, gate met, `Step <= #chain`, not already accepted.
- It also needs `activeCount < MaxActive`.

**Drop:** sets `Active = false` and `Progress = 0`.

Every operation replies with `ActionResult { Action = "Quest", Op, Ok, Reason?, Id, Level }`. The existing
ActionResult listeners filter by `Action`, so they ignore it.

### 4.5 Remotes and rate limits (Net.luau, integrator)

```lua
QuestAction = { Rate = 2, Burst = 4 }, -- ("Accept" | "HandIn" | "Drop", { Npc }) the quest givers
--   (QuestService): Accept / HandIn within QuestConfig.TalkRange (+ HandInSlack) of that NPC,
--   Drop anywhere; answered by ActionResult { Action = "Quest", Op, Ok, Reason?: a
--   QuestConfig.Reasons code, Id = npc id, Level = the NPC's step after it, Reward? (HandIn) }
```

- **Server to client:** reuses `OpenUI` (kind "Quest", `{ Npc }`), `ActionResult`, `Notify`, `ArtifactFound` and
  `State`. There is no new server-to-client remote.
- **Comments only:** the `ActionResult` comment gets "Quest" added to its Action list.

### 4.6 Exploit cases

| # | Attempt | Why it fails |
|---|---|---|
| 1 | Spam Accept / HandIn / Drop | Net token bucket (2/s, burst 4). Handlers are pcall'd. Every refusal is cheap |
| 2 | Hand in from far away, or at another NPC | Distance from **that** NPC's PromptPoint, measured on the server |
| 3 | A forged or unknown NPC id, or junk args | `Guard` checks and the `QuestConfig.ById` lookup → `BadNpc` |
| 4 | Double HandIn in one frame | No yield from check to advance. The second call sees the new Step and is not Ready |
| 5 | Another player's items, thrown or loose items | Only records owned by the player in state `"Carried"`, plus the player's own `data.Storage` |
| 6 | Dirty, crushed, ingot, relic or junk entries passed off as ore | `countsItem` needs kind `Clean`, the ore id and the grade. Junk pen entries are skipped |
| 7 | Duplicating items around the hand-in | Plan, take and grant happen in one synchronous step. Pen entries are removed by identity and hand records are absorbed (Consumed) |
| 8 | A full pen eats the reward | Refused **before** anything is taken (`PenFull` / `PenOver`). The store-fail fallback is the rescue path |
| 9 | Progress claimed by the client | No remote carries progress. Only `onRockBroken` and `onCleaned` count, and only while the quest is accepted |
| 10 | Relic cleans counted as ore cleans | `OreData.ById[oreId]` is nil for an artifact id; ore ids and artifact ids never overlap (spec) |
| 11 | A scripted Flawless | `CleaningGuard` already caps synthetic runs at Pristine, both for Clean goals and for the items brought |
| 12 | Breaking rocks outside the zone | The rock's own `Zone` is counted, not the player's position, so a rock shot across a zone border counts for its own zone |
| 13 | VIP Grotto rocks | No goal names `Grotto`, so nothing counts there |
| 14 | Farming rewards with rebirth or rejoin | Chains are one-time and `Quests` survives rebirth. Rewards are tied to Step, which only moves forward |
| 15 | A junk or hand-edited save | Migrations repair (3.2), plus `repairEntry` on every read |
| 16 | An older server after an update | The keep-unknown repair (3.2) and the version note (3.3) |
| 17 | Bypassing the slot cap | `activeCount` counts every Active entry, unknown NPCs too |
| 18 | Hiding behind an NPC, or an NPC blocking a rock or the hopper | Root never collides or is queried: rays and thrown ore pass it |

**Performance:**
- No server loops at all.
- Per broken rock: at most 3 Mine goals.
- Per clean: at most 3 Clean goals.
- The provider counts `Have` by storage key, only for accepted Bring quests: at most 300 pen entries and 24 hand
  items.
- The anchors are static.
- Per-player tables are weak-keyed and cleared on leave.

### 4.7 Nothing here is sold (MonetizationService and MonetizationConfig were read)

- **No products or passes:** no product, pass or `ProcessReceipt` grant touches quests, and none is added.
- **No paid shortcuts:** there is no "skip" and no paid reroll.
- **Paid perks that touch quests only indirectly:**
  - Triple and Hexa Lucky make rarer drops more likely;
  - Robux blaster levels open gates sooner;
  - the Podiums perk (podiums 3–4) lets a player show more reward ores.

  All are general progression, not quest content. VIP (the Grotto) is excluded from every goal.
- **Compliance:** rewards are fixed (no odds) and nothing is social. docs/COMPLIANCE.md needs no change.

---

## 5. Client and UI

**New files:**
- `src/client/Controllers/QuestController.luau`;
- `src/client/UI/QuestView.luau` (dialog);
- `src/client/UI/QuestTrackerView.luau` (HUD);
- `src/client/UI/QuestMarker.luau` (billboards).

All builders are pure, so the Lune previews and specs run them.

### 5.1 NPCs in the world

- **Building on demand:**
  - QuestController watches `CollectionService` tag "QuestNpc" (the anchors stream in and out with
    StreamingEnabled).
  - A 5 Hz loop checks at most 8 anchors.
  - It calls `NpcBuilder.dress(anchor)` within `ShowDistance` (120) **and only when the player is on that NPC's
    floor**: `WorldLayout.zoneAt(root position)` is the NPC's zone, or both are surface zones (the lobby's
    `Emberfall`, the `Quarry`, the `Outcrops`). It calls `NpcBuilder.undress` past `HideDistance` (140) or on
    another floor, like `MuseumBuilder.ShowDistance`. Distance alone is not enough: the Sunken Palace (y ≈ −220),
    the Rift (≈ −300) and the Core (≈ −400) are only 80–100 studs apart vertically, so 3D distance would dress the
    wrong floor's NPC.
- **Idle animation**, within `AnimateDistance` (60), at 15 Hz, for at most 3 NPCs, following the `NpcBuilder`
  animation contract (1.3):
  - each floating group bobs as one, with `workspace:BulkMoveTo` over the group's parts;
  - the whole model bobs a little (the "breath"); no part changes Size;
  - the `Head` group turns toward the local player within 14 studs (at most ±35°), about `(0, NeckY, 0)`.

  No server work.
- **Nameplate:** a BillboardGui on `NameplatePoint` (`MaxDistance` 60, `AlwaysOnTop = false`). The name is in Pop
  white text with a black edge on a `PopTheme.Body` plate; the title is in the NPC's accent colour.
- **Marker:** `QuestMarker` on `QuestMarkerPoint` (`MaxDistance` 120, `AlwaysOnTop = false`, bobbing, Pop paint,
  black border, LuckiestGuy), shown only on the player's floor (the same zone rule). No marker shows through a
  ceiling. No emoji: "!" and "?" are plain ASCII.

  | Status | Marker |
  |---|---|
  | `Available` or `Full` | a gold "!" disc |
  | `Ready` | a green "?" disc, a little bigger, pulsing |
  | `Locked` | a slate pill "LV 5" |
  | `Active` (not ready) | a small grey "..." |
  | `Done` or `Hidden` | nothing |

### 5.2 Talk prompt

- **On the server:** made by the server on the anchor's `PromptPoint` with `PromptConfig.make`:
  - role Main, so E on keyboard, Y on gamepad and tap on touch;
  - in the stock Roblox look;
  - ActionText "Talk", ObjectText = the name.

  tests/PromptKeys.spec already checks that every prompt is made by `PromptConfig.make`. The spots keep it 14 studs
  or more from other Main prompts (1.1).
- **What the dialog does to other prompts:**
  - While it is open, `PromptController.setSuppressed("Quest", true)`.
  - The dialog **does not** bind E, so the E press that opened it can never accept a quest. That is also the
    PromptKeys rule.

### 5.3 The dialog (QuestView, Pop look)

**PC / TV**, about 760 × 440 design units, centred, with the window band in the NPC's paint:

```text
+------------------------------------------------------------------+
| ////  PIP FARWANDER   Deep Explorer                         [X]  |  <- Pop.window band
+------------------------------------------------------------------+
|  +------------+   "My lantern runs on iron filings. Bring me     |
|  |  portrait  |    6 Iron, any grade."                           |
|  |  (3D NPC,  |   +--------------------------------------------+ |
|  |  rays)     |   | FUEL FOR THE LANTERN          QUEST 1 OF 4 | |
|  +------------+   | [ore] Bring 6 Iron (any grade)             | |
|   o o o o         | From your hands or your Ore Pen            | |
|  (chain dots)     | Have 4 / 6  (hands 1, pen 3)  [=====----]  | |
|                   | REWARD  [ore] 1 Dirty Leaf Ore -> Ore Pen  | |
|                   |         [ore] 1 Dirty Honeycomb            | |
|                   +--------------------------------------------+ |
|     [ DROP ]              [ TRACK ]              [ ACCEPT ]      |
+------------------------------------------------------------------+
```

**Building blocks:**
- **Portrait:** `Pop.model` showing a dressed clone of the NPC (head and shoulders camera) over `Pop.rays`.
- **Speech:** Pop text with a quick typewriter. Tap or click shows it all. Done lines through
  `QuestConfig.doneText` (the `{Artifact}` token filled).
- **Quest card:**
  - `Pop.card` (Slate);
  - the goal icon: the ore model, a rock icon for Mine or a spray icon for Clean;
  - the requirement line, **before Accept**: "From your hands or your Ore Pen" for Bring (podiums don't count);
    "Hand-cleaned at a Cleaning Station" for Clean; and for a Flawless goal "Flawless: score 92 % or more, by hand";
  - a progress bar and the numbers;
  - reward chips: ore pictures with "x2 Dirty Frostbite → Ore Pen" (arrows are allowed text), and the artifact
    picture and name with "New for your collection" (and "Completes the collection!" when it is the last missing
    one).
- **Buttons:** `Pop.button`. The primary one is Green (ACCEPT) or Yellow (HAND IN).

**What the buttons do in each status:**

| Status | Text | Buttons |
|---|---|---|
| Hidden | Hello + "Finish your training first: the tutorial shows the way." | CLOSE |
| Locked | Locked line, LV chip | CLOSE |
| Available | Offer (Hello on step 1) | ACCEPT. HAND IN instead when a Bring goal is already met |
| Full | Offer + the `Full` reason | ACCEPT greyed with the reason |
| Active | Offer, progress | TRACK, DROP (asks "SURE?" once) |
| Ready | "Done!" hint | **HAND IN** (Yellow, pulsing), TRACK |
| Done | AllDone line, "CHAIN COMPLETE" tag | CLOSE |
| Newer | the `Newer` reason | CLOSE |

**Hand-in moment:**
- After a successful HandIn (`ActionResult`), the card flips to "QUEST COMPLETE!" (Pop title, Gold), with the NPC's
  Done line (or DoneElse) and the reward chips from `Reward`.
- `ArtifactFound` then plays ArtifactController's existing relic flight, from the NPC to the player.

**Phones** (uiScale ≤ 0.75): a compact sheet:
- the portrait shrinks to a round head in the band;
- the card is full width;
- buttons are at least 72 design units tall (44 pt or more at 0.62).

**Gamepad and TV:**
- on open, `GuiService.SelectedObject` is the primary button;
- `NextSelection` links run across DROP ↔ TRACK ↔ primary ↔ X;
- B or Backspace or Esc closes;
- everything stays inside the TV safe area (`ScreenInsets`).

**Panel rules:**
- `MenuPanels`: the dialog is a panel (closeOthers / isOpen / close). It goes in `MenuPanels.Names`.
- The ScreenGui "TerraForgeQuests" carries the `TerraForge` attribute and a `UIScale` named "Scale", so
  HudController scales it with every other gui. No HudController edit.

### 5.4 HUD tracker (QuestTrackerView)

**Where:** the right edge, in the vertical middle band.
- PC and gamepad: `y` 30–60 %.
- Touch: under the top-right FREE SPIN chip and above the jump and throw cluster.

It never covers:
- the teleport bar;
- the left tiles;
- the hotbar;
- the money;
- the touch buttons.

The spec checks the rectangles (6.3).

**What it shows:**

```text
 QUESTS 2/3                 [-]
 +---------------------------+
 | PIP FARWANDER             |
 | Break rocks: Ember Caves  |
 | [=========-----]   21/30  |
 +---------------------------+
 | MISTY GLEAM        READY! |   <- Green paint, gentle pulse
 | Return to the lobby plaza |
 +---------------------------+
```

- **Rows:** one Pop row per accepted quest, at most 3. Each has the NPC name in its accent colour, the short goal and
  a bar or "Have 4 / 6". A Ready row says where the NPC is: their area name, plus "Elevator: Sunken Palace" for
  floors 4–6.
- **Collapse:** the header collapses the tracker. That choice is kept only for the session.
- **Hidden** when there is no accepted quest, while a panel is open (`MenuPanels.otherOpen`), during cleaning or
  build mode, and while the tutorial is running.
- **Tap or click a row:** toggles the **guide line**, the same as TRACK in the dialog. It is a client Beam from the
  character to the NPC's PromptPoint, only when that anchor is streamed in and on the player's floor. Otherwise the
  row shows the area hint.
- **Gamepad:** the tracker is display-only. TRACK is in the dialog.

### 5.5 All platforms checklist (the all-platforms skill)

| Platform | What must work |
|---|---|
| Mouse + keyboard | E talks, click the buttons, Esc closes. Clicking a rock behind an NPC mines it |
| Touch | Tap the prompt. Buttons are 44 pt or more. The tracker rows are 44 pt tall, and nothing sits under the thumbstick or the jump button |
| Gamepad | Y talks, the D-pad moves between buttons, A presses, B closes. Xbox and PS glyphs come from the stock prompt |
| TV | Inside the safe area. Text is 18 px or more at 1080p |
| Light UI on / off | The dialog and the tracker use Pop in both. Nothing depends on the light HUD's layout except the rectangles the spec checks |

---

## 6. Work packages (for a later parallel build)

### 6.1 Packages and file ownership

| WP | Owner | New files | Notes |
|---|---|---|---|
| **Q0 Contracts** (first, small) | quest chat, with the integrator's OK | `src/shared/Config/QuestConfig.luau` (data from section 2, rules from 4.1); `tests/QuestConfig.spec.luau`; `tests/QuestLogic.spec.luau` | Also lands the one-line hooks in 6.2. Q1–Q3 start once it is in |
| **Q1 Server** | quest chat (systems) | `src/server/Services/QuestService.luau`; `tests/QuestService.spec.luau` | Only **reads** other services (section 4), plus the MiningService hook (6.2) |
| **Q2 NPC art + spots** | art designer (this worktree's NpcBuilder) | `src/shared/Builders/NpcBuilder.luau` (anchor / dress / undress, done); `src/shared/Config/NpcSpots.luau` (moved verbatim from `Preview.Spots`); `tests/QuestNpcs.spec.luau`; `tools/lune/lib/npc_preview.luau` (reads NpcSpots), `tools/preview/npc_shots.json` | Q1 calls `NpcBuilder.anchor` and reads `NpcSpots`. Pictures for the owner |
| **Q3 Client UI** | UI builder | `src/client/Controllers/QuestController.luau`; `src/client/UI/QuestView.luau`, `QuestTrackerView.luau`, `QuestMarker.luau`; `tests/QuestView.spec.luau`; UI preview scenes (`uiexport`: `quest_dialog_pc`, `quest_dialog_phone`, `quest_tracker`) | `NpcBuilder.dress` / `undress` are ready to use |
| **Q4 Balance** (required) | machines chat (balance sim) | none | The balance sim run of 2.3 and the refreshed `TypicalIncome` table, before Q5 |
| **Q5 Landing** | integrator | none | Merge, `tools/check.sh` (full log), the adversarial review of 4.6, docs, owner pictures |

`tools/lune/export_scene.luau` already has `npc_lineup`, `npc_world` and `npc_spawn` from the art package. The UI
scenes go through `uiexport`. Never `stylua src`: format only the files you touched.

**Hygiene:** `build/TerraForge.rbxl` shows as modified in this worktree, but nothing here changes the map (the anchors
are built at server start). No package commits it unless `tools/check.sh` rebuilds it for a real map change; another
agent shares this worktree, so restore it from main before committing (`git checkout main -- build/TerraForge.rbxl`).

### 6.2 Small hooks in existing files (whose chat owns them)

Chat names are from HANDOFF.md section 4.

| File | Hook | Size | Owner |
|---|---|---|---|
| `src/shared/Net.luau` | `QuestAction` entry (+ "Quest" in the `ActionResult` comment) | 1 entry | integrator ("TERRA FORGE Roblox hra vývoj") |
| `src/server/Data/DataTemplate.luau` | `Quests = {},` with its comment (3.1) | 1 line | integrator |
| `src/server/Data/Migrations.luau` | `migrateQuests` + one call after `migrateStep8` + a header paragraph | ~45 lines | integrator (save-safety review: "Design zbraní a blasterů") |
| `tests/Migration.spec.luau`, `tests/SaveSize.spec.luau` | future-save Quests kept unchanged, junk repaired; Quests at its cap | 2 tests | integrator |
| `src/server/init.server.luau` | `"QuestService",` at the end of ORDER (after TutorialService) | 1 line | integrator |
| `src/client/init.client.luau` | `"QuestController",` after `"TutorialController"` | 1 line | integrator |
| `src/client/Util/MenuPanels.luau` | `"QuestController",` in `Names` | 1 line | UI chat ("Nový UI design" / the Pop shop chat) |
| `src/server/Services/MiningService.luau` | **required:** `MiningService.onRockBroken(cb)`, fired in `shatter` with `(player, rock.Zone.Id)` | ~3 lines | mine chat ("Úrovně a vzhled min"), who shares the file with the blaster chat |
| `tools/lune/balance_sim.luau` | **required:** model the quest rewards and the collection bonuses (2.3) | | machines chat (balance sim) |
| *optional* `src/server/Services/AnalyticsService.luau`, `BadgeConfig` | quest funnel through `QuestService.onQuest`; "First quest" and "Chain complete" badges (id 0 until the owner uploads) | | integrator |
| `docs/HANDOFF.md`, `docs/STUDIO_CHECKLIST.md`, `docs/QA_REPORTS.md` | status, Studio steps (6.6) | | integrator at landing |

**Not touched:**
- ArtifactService, PenService, StateService, ItemService, CarryService, TutorialService, CleaningService;
- HudController, PromptController, MiningController, InteractController (Root is non-colliding and non-queried, so
  their ray filters need no `QuestNpcs` entry);
- LobbyLayout and the lobby budget specs;
- WorldBuilder (no map version bump);
- the floor builders.

### 6.3 Specs to write

1. **tests/QuestConfig.spec.luau (Q0).** Data integrity:
   - every NPC id is an `NpcBuilder` outfit, unique, short; no `Paint` in QuestConfig;
   - chains have 3–5 quests; ids are unique and match `LockedIds` in order;
   - gates never go down; the first gate equals the unlock level.
2. **Goals are valid and can be done.** Real ids, grades and zones:
   - no `Grotto`, `Emberfall` or `Outcrops` zone;
   - each Mine zone's floor gate ≤ the quest gate;
   - each Bring ore drops on a floor the gate opens;
   - each Clean rarity is covered by the gate floor;
   - a Flawless goal is only ever the last step of its chain.
   - Counts are in range: Bring 1–10, Mine 10–60, Clean 1–10.
3. **Reward rules R1–R6 (2.3)** on the real config:
   - floor tables;
   - at most 3 ores per quest; Mythic ores only from gate 9;
   - artifacts: at most 1 per quest, 2 per chain and 10 in all, never Mythic, each spec's pool not empty, `Prefer`
     (when set) is an `ArtifactConfig` id of the spec's collection and rarity, and every artifact quest has `Else`
     ores that also pass R1/R3/R6;
   - R3 with the best processed value (Clean, Ingot and Gear per ingot, at Flawless) against 25 % of the next
     floor's Foundry price;
   - R6 with `ItemData.income` at Pristine against `QuestConfig.TypicalIncome`, from gate 3;
   - no coins, shards or other kinds anywhere in the data.
4. **Texts:**
   - Offer, Done, DoneElse, Hello, Locked and AllDone are at most 120 characters (with `{Artifact}` filled by the
     longest possible name);
   - titles at most 28; `goalText` at most 48;
   - **no Offer, Done or DoneElse line names an artifact literally** (any `ArtifactConfig` name); a Done line with an
     artifact reward holds `{Artifact}` exactly once; DoneElse never does;
   - an ore named in a Done line (its `OreData` name, plural allowed) is one of that line's reward ores;
   - no emoji (tests/NoEmoji.spec scans every src file anyway).
5. **Ids:** no `OreData` id is also an `ArtifactConfig` id (the clean listener tells them apart).
6. **tests/QuestLogic.spec.luau (Q0):**
   - **Statuses:** every status in `status`, including Newer and Done reopening for a grown chain; `MaxActive`.
   - **Items:** `countsItem` grade order; `planHandIn` takes the lowest grade first, hands before pen, the newest pen
     entry first, and skips Raw, Relic, junk and other owners' items.
   - **Rewards:** `artifactFor` takes `Prefer` first, then `List` order, falls back across collections, then to
     `Else`, and never picks a duplicate; `doneText` fills the token or uses DoneElse; `penRoomNeeded`.
   - **Counting and repair:** `countsRock` / `countsClean` filters (a relic id never counts); `repairEntry` clamps.
7. **tests/QuestService.spec.luau (Q1).** Fakes as in Tutorial.spec and PenService.spec, with the real
   DataTemplate.
   - **Accept:** works, and is refused for Tutorial, Locked, Full, Active, TooFar and BadNpc.
   - **Mine counting:** a rock of the goal's zone, of another zone, and of the Grotto, which never counts; capped at
     `Count`; the Ready Notify once.
   - **Clean counting:** grade and rarity filters, and a relic clean that doesn't count.
   - **Bring hand-in:**
     - takes exactly the planned items from the hands and the pen, each once;
     - stores the reward in the pen;
     - calls `cleanRelic` with the NPC position;
     - gives `Else` ores when the collection is complete.
   - **Refusals:** PenFull and PenOver leave everything untouched.
   - **Advancing:** a double HandIn grants once; Step and Done move forward; Drop; the ActionResult payloads;
     `DataService.changed` is called.
   - **Saves:** unknown NPC entries are left alone; `RebirthConfig.reset` keeps `Quests`.
8. **tests/QuestNpcs.spec.luau (Q2):** the spot rules of 1.1 on the built map:
   - **Spots:** ground under the spot (the `Preview.groundAt` ray), flat within 0.45 under the Root box; the NPC's own
     zone; the Root box plus 2 studs outside every `WorldLayout.KeepOut` box; open space (no visible map part within 4
     studs, 0.8–6 studs over the feet); the `PromptPoint` at least 14 studs from Main prompts with Distance 10 (the
     station hopper, the Mine Lifts, the elevator call panels, the stall counters) and 16 from the Distance 12 ones
     (the Guild Board, the Fossil Dig, the capsule stall, the codex); at least 7 studs from every rock spawn.
   - **Anchors:** 1 part each, Atomic, Root tagged BeamIgnore, `CanCollide` / `CanQuery` / `CanTouch` off.
   - **Budgets**, recomputed the way LobbyBudget and PhoneBudget do, plus the anchors and the client models:
     - map + nodes + museums + anchors ≤ MapParts − 200;
     - lobby + museums + lobby anchors ≤ LobbyParts;
     - phone + the dressed NPCs within `ShowDistance` of the spawn and the plaza centre ≤ PhoneParts.
9. **tests/NpcBuilder.spec.luau (Q2, done, 12 tests):** unique Pop paints with the accent = the paint's Top; the
   `Height` constant = the dressed top; the anchor is 1 part with the points and attributes; dress / redress /
   undress; the pad; nothing collides, is queried or touched; the groups (every Float part in a float group, float
   groups compact, the head group holds every part worn on the head and no body part); eye shines and the smiles;
   part and Neon caps; R15-like names.
10. **tests/QuestView.spec.luau (Q3):**
    - layouts at PC 1280×720, phone 844×390 (uiScale 0.62) and TV 1920×1080 with safe insets;
    - buttons at 44 pt or more;
    - the dialog fits on screen;
    - the requirement line shows before Accept for Bring, Clean and Flawless goals;
    - the tracker rectangle avoids the teleport bar, the left tiles, the hotbar, the FREE SPIN chip and the touch
      cluster;
    - the status → buttons table from 5.3;
    - gamepad `NextSelection` links;
    - no E binding.
11. **Additions (integrator):** Migration.spec and SaveSize.spec (6.2). Nothing else changes: Net.spec,
    PromptKeys.spec, NoEmoji.spec and strict luau-lsp cover the new files without edits.

### 6.4 Budget estimate (measured on this worktree, main f3a5327, map v44)

| What | Today | + Quests | Budget |
|---|---|---|---|
| Map + ore nodes + yard museums | 31,843 | + 8 anchors = 31,851 | 32,000 (MapParts 32,200 − 200) |
| Lobby area + museums | 13,589 | + 2 anchors = 13,591 | 13,700 |
| Phone view (lobby + always-streamed + museums) | 16,379 | + Quill 51 + Misty 54 (anchors included) = 16,484; at the quarry rim, with Pip as well, 16,540 | 18,000 |
| Each mine floor's own model | F1 1,095 · F2 1,157 · F3 1,112 · F4 2,325 · F5 1,838 · F6 2,326 | unchanged: anchors are not in the floor models, and dressed NPCs are client-side, only on the player's floor | 1,250 near / 2,500 |
| Lights | | 0 (Neon only) | the Rift's 11-PointLight phone cap untouched |
| Per NPC on the client | | 51–60 parts with the pad (cap 70), at most 20 Neon, 2 BillboardGuis, 1 prompt, built only within 120 studs on the player's floor | |

### 6.5 Done when

1. `bash tools/check.sh` exits 0, the **full, unfiltered** log is saved, strict luau-lsp says "no problems found",
   and every new spec passes.
2. The WP-Q4 balance sim run with the quest rewards keeps the Typical player's blaster 10 at 8h ± 15 min, and its
   `TypicalIncome` table is in QuestConfig.
3. Pictures are sent to the owner (preview renders are three.js approximations; say so):
   - the 8-NPC lineup, the close-ups and the back view (done, art package);
   - each NPC in place (done: `npc_world_*` for all 8 spots, and `npc_world_spawn` with both lobby NPCs and their
     markers);
   - the dialog on PC and on a phone (Available, Ready, Quest Complete);
   - the HUD tracker on PC and on a phone;
   - a marker.
4. The adversarial review of 4.6 finds nothing open. `docs/QA_REPORTS.md` gets the "what to test in Studio" list
   (6.6).
5. The owner says yes to the roster and the looks. Then the integrator lands it (HANDOFF landing protocol).

### 6.6 What to test in Studio

- **Talking:** talk to each NPC with E, a gamepad (Y) and touch (emulator). The dialog opens, other prompts hide and
  B / Esc closes. At the Mine Station, E still loads the hopper.
- **Walking and aiming:** walk through an NPC; click a rock behind Brakka or Sela and mine it; throw ore past Pip.
- **Accepting:** accept SC2 and break 25 Quarry rocks. The tracker counts up and turns READY, and a toast appears.
  Rocks broken in town don't count. Shoot a rock across a zone border: it counts for its own zone.
- **Cleaning:** accept GP1 and clean 5 ores by hand. A dusty relic clean must not count.
- **Bring from the pen:** for EX1, bring 6 Iron with some carried and some in the pen. Exactly 6 are taken, the lowest
  grade first. Ore on podiums is not counted.
- **Rewards:**
  - the dirty ore lands in the pen;
  - fill the pen to the cap and try again: refused with nothing taken;
  - an artifact reward flies out of the NPC into the collection, the museum updates, and the Done line names the
    artifact actually given.
- **Floors:** on the Sunken Palace terrace, Volta and Ashka (below) are not dressed and their markers don't show
  through the floor.
- **Saving:** rejoin and check the progress is kept. Rebirth and check the finished chains stay finished.
- **Cap:** three quests accepted, a fourth is refused with the `Full` text.
- **Phones:** FPS on a low-end phone emulator on the plaza with both lobby NPCs dressed. On console, navigate the
  dialog by D-pad.

---

## 7. Open questions for the owner (with the defaults this plan uses)

1. **The 8 NPCs and their looks** (pictures first): are they OK? Default: the reviewed prototype.
2. **10 artifacts** of 24 come from quests, always ones you don't have yet, and never the Heartstone Fragment. A quest
   artifact can **complete a collection**, which unlocks its title, podium skin and bonus (quests give 3 of the 6
   Crown artifacts and 3 of the 6 Heartstone Lore ones). Is that fine, or should there be more or fewer?
3. **At most 3 quests** accepted at the same time. Default: 3.
4. **After a rebirth**, finished chains stay finished. Default: yes. The alternative is restarting chains with ore
   rewards only.
5. **Tobin** stays a seller only. Default: yes. He could also give quests later, with a second prompt on G.

---

## 8. Review round 1 (critic, 2026-10-21): what changed

| # | Point | Where | Done |
|---|---|---|---|
| 1 | Done lines named exact artifacts; the fallback could give another one | 2.2, 2.4, 2.6, 4.1, 6.3 | `Prefer` per artifact spec, the `{Artifact}` token, `DoneElse` lines, a spec against literal names |
| 2 | SE3 (two Mythics) too big; "4 podiums" wrong | 2.2, 2.3 | SE3 = 2 Volcanic Core; Mythic ores from gate 9; R6 podium rule with a measured income table; Podiums.Free = 2; the sim run with collection bonuses is required (WP-Q4) |
| 3 | R3 ignored ingots and gear | 2.3 | R3 = the best processed value per ore; gate 1–2 rewards cut to fit (GP1 = 1 Frostbite) |
| 4 | Spots didn't match the prototype; two stood in KeepOut boxes; prompt distance 8 too small | 1.1, preview, 6.3 | One set of spots (`Preview.Spots`, later NpcSpots), all 8 re-checked on the built map (KeepOut + 2, open space, prompts 14 / 16, rocks 7) |
| 5 | Accent colours came in near-duplicate pairs, disagreed with the paints | NpcBuilder, 1.3, 4.1 | `Paint` (PopTheme key) per outfit, the accent derived from it, unique (spec); Quill purple and gold, Volta electric blue with yellow, Ashka mint with one pink heartstone |
| 6 | Brakka, Sela, Pip and Quill blended into their areas | NpcBuilder, pictures | The quest pad; Brakka's cream apron and brighter trims; Sela's gold plates and magenta crystals; Pip's orange jacket; Quill's bright purple robe |
| 7 | The anchor couldn't place its points | NpcBuilder, 1.3 | `Height` constant per outfit (spec), `anchor` / `dress` / `undress`, attributes, Root tagged BeamIgnore |
| 8 | Float parts would tear apart; no head group; scaling | NpcBuilder, 1.3, 5.1 | `Group` attribute (float groups and `Head`), BulkMoveTo, a bob instead of a scale |
| 9 | The colliding, queried Root blocked aim, grab and thrown ore | NpcBuilder, 1.3 | Root never collides, is never queried or touched |
| 10 | Stacked floors: wrong NPC dressed, markers through ceilings | 5.1 | Dress and markers only on the player's floor (zone check), `AlwaysOnTop = false` |
| 11 | Rock counting by position at flush time; relic cleans by the stamp | 2.1, 4.2, 4.3, 6.2 | The required `onRockBroken(player, zoneId)` hook; `OreData.ById` for ore vs relic; a spec that the ids never overlap |
| 12 | "Shards" line, SE3 line, podiums in Bring | 2.6, 2.1, 5.3 | "Take these Heartstones"; the new SE3 line; "hands or Ore Pen" on the card and in the reasons |
| 13 | Bored faces, plain props | NpcBuilder | Eye shines, grins and smiles; Pip's lantern and pickaxe; Brakka's shoulder hammer; Sela's crystal cluster; Volta's wrench over the shoulder |
| 14 | Pictures showed 4 of 8 spots | preview, shots | All 8 spots and a spawn view; Pop nameplates (Body, Well, black edge); the stale `npc_close_smith_miner.jpg` deleted |
| 15 | SE1 and CM1 rewards were common ores | 2.2 | SE1 = Leaf Gem + Moonstone; CM1 = Obsidian + Amethyst |
| 16 | Flawless steps blocked later steps | 2.1, 2.2, 5.3 | GP3 and CS4 are Pristine now; the 6 Flawless goals are all last steps; the requirement shows before Accept |
| 17 | Doc references and the owner question | 0, 1.1, 1.3, 7 | Section citations fixed; the hook sizes stated; question 2 mentions collection completion |
| 18 | `build/TerraForge.rbxl` modified in the worktree | 6.1 | Hygiene rule: no package commits it without a real map change |
