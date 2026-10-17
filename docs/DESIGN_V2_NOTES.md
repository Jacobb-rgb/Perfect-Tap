# Design v2 – owner's new direction (2026-10-16)

The owner changed core parts of the game. **This overrides docs/GAME_DESIGN.md where they conflict.**
Open questions are at the bottom; once answered, fold everything into GAME_DESIGN.md and a new plan.

## New references (Kenney, all CC0 like the Factory Kit; rebuild their look from Roblox parts)
| Kit | Link | Used for |
|---|---|---|
| Train Kit | https://kenney.nl/assets/train-kit | trains that carry ore from the mine to the player's base |
| Blaster Kit | https://kenney.nl/assets/blaster-kit | **blasters replace pickaxes** (laser mining) |
| Mini Dungeon | https://kenney.nl/assets/mini-dungeon | style reference for decorations in general |
| Mini Characters | https://kenney.nl/assets/mini-characters | style reference for the **golem pets** (chunky little figures; ours are metal/ore golems, e.g. silver ones, some with helmets) |
| Factory Kit | https://kenney.nl/assets/factory-kit | machines, pipes, fuel tanks, hoppers, conveyors (docs/KENNEY_FACTORY_KIT.md) |

## What the owner said (translated from Czech)
1. **Trains** are used purely to transport ore from the mine to your base. At the base the ore is dumped into an
   **ore pen** ("like a sandbox without sand", a fenced pen for ore).
2. From the pen you choose, by value, which ore you want to put on display. Every base always has **two small
   podiums** for ore. An ore on a podium **earns money per second** based on its value (example: a diamond worth
   $1,300 per second). "So people enjoy it."
3. Hovering the mouse over a podium shows a button next to it, in English, e.g. **"Remove"**, so you can swap the ore.
4. **Blasters instead of pickaxes:** laser blasters mine **rock chunks**. Rocks contain ores of different values:
   about **30 ore types**, e.g. **two ores in one rock**, and every ore has its own **spawn rate** because each one has
   a different rarity.
5. **Start:** you get one rusty, basic blaster. You get ore, put it on the podium, earn money.
6. With money you buy machines: furnaces, conveyors, smelters, crushers, cleaners. Then you throw everything into a
   **foundry** ("slévárna"), which creates a **stronger blaster**. How strong depends on the value of the ore
   (details to be agreed later).
7. The Mini Dungeon kit is only there to show how the various decorations should look.
8. UI text stays in English (e.g. "Remove").

## What this changes in the current build (for planning)
- Mining: MiningService/ToolData pickaxes → blasters (laser beam, hold to blast?), ore nodes → rocks with a loot table
  of ores (OreData grows from 10 to ~30 ores with rarity + spawn weight + value per second).
- Transport: new train system (mine station → track → base station/ore pen), replacing long carry trips.
- Base: plots get an ore pen + 2 podiums with passive income (EconomyService ticks income; StateService shows it).
- Economy: money mainly from podiums (selling may change or disappear – see questions).
- Crafting: machine chain ends in a **Foundry** that outputs blasters (new item kind / tool tiers).
- Machines, build mode, conveyors (step d) stay useful for the processing chain feeding the foundry.
- The Cleaning Station minigame's role must be decided (see questions).

## Open questions (asked 2026-10-16; answers go here)
See the chat/answers section below.

### Answers (owner, 2026-10-16)
1. **Blasting:** hold the button, a laser beam fires, the rock cracks gradually; a stronger blaster breaks it faster. ✔
2. **Drops:** physical ore chunks drop (as now); you pick them up and throw them into a cart at the mine's train
   station; your train takes them to your base's ore pen. ✔
3. **30 ores:** Claude invents original names and values (mix of real minerals like coal, copper, gold, diamond and
   original fantasy ores), each with rarity, spawn weight and value per second. ✔
4. **Trains:** every player has their **own** little train. ✔
5. **Train upgrades:** yes, for in-game money; **also** a sign at the base offering an upgrade for about
   **150–200 Robux** (one-time purchase).
6. **Podium:** one ore piece per podium; better-cleaned ore earns more. ✔
7. **Podiums:** 2 for free. Podiums 3 and 4: **100 Robux**, or included in a bigger **game pass (~560 Robux)** that
   has more benefits.
8. **Offline earnings:** owner undecided, asked for proposals (see "Proposals for 8" below).
9. **Pen:** ore you don't display stays in the pen. Later, **automation (only with an upgrade):** on a billboard you
   mark ore types to always keep in the pen; unmarked types are sent onto a conveyor (to machines).
10. **Game pillars:** the game is mainly about **mining, earning money, automation and finding artifacts**, with a
    **story**. Cleaning ore is "just work" that raises the ore's value, so the ore earns more on a podium, or clean
    ore / ingots make a better blaster in the foundry. (The cleaning minigame stays, as a value-raising job.)
11. **Blasters:** 10 levels; an 11th shown as "Coming soon".
12. **Money comes only from podiums.** Ore you don't need is sold to the **miner NPC** in the middle of the town,
    at a **"Sell" stall** next to the shop.
13. **Lobby (the concept image) stays**, with:
    - a **Sell** stall (the miner NPC);
    - a **wheel of fortune**: one free spin **every day**, the timer keeps counting even while AFK;
    - a **shop for upgrades bought with in-game money**: e.g. **miner's boots** (walk speed), **helmet with a head
      lamp** (see more in the dark), and other gear upgrades;
    - a **capsule stall**: like pet eggs, but capsules containing **pets that are colorful golems** (owner said
      "iron golems like Minecraft" → we must design ORIGINAL ore/stone golems, not Minecraft's Iron Golem);
    - the **8 plots** ("pens"/bases) for 8 players per server.

### Notes for implementation (Claude)
- **Original IP:** golem pets must be our own design (ore golems, crystal golems, lava golems...), no Minecraft look
  or names.
- **Capsules = random items.** If capsules can be bought with Robux, or with coins that can be bought with Robux,
  Roblox treats them as **paid random items**: show the exact odds before buying, check
  `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` and hide/disable them where restricted,
  and answer the Maturity questionnaire accordingly (docs/COMPLIANCE.md must be updated). The free daily wheel must
  show its odds too.
- **Robux items:** train upgrade (~150–200 R$, one-time → game pass or one-time dev product saved in the profile),
  podiums 3–4 (100 R$), big pass (~560 R$, includes podiums 3–4 + other perks). Keep MonetizationConfig placeholders.
- **New systems to plan:** blasters (tool + laser VFX + rock HP), rocks with ore loot tables (30 ores), per-player
  trains + mine station carts + base ore pen, podiums with income per second (+ "Remove" button on hover/tap,
  also for touch and gamepad), offline earnings (decision 8), foundry → blaster tiers 1–10, pen sorting billboard
  (upgrade), gear shop (boots, helmet lamp...), daily wheel, capsule pets (golems that follow you and maybe give a
  bonus), artifacts + story, Sell stall NPC.
- Existing work that still fits: world/lobby, physical chunks and carrying, cleaning minigame (now a value booster),
  machines/build mode/conveyors (processing chain into the foundry), DataService/ProfileStore, Net/Guard.
- Must change: pickaxes → blasters; ore nodes → rocks with multiple ores; OreData 10 → ~30; selling/economy flow
  (income from podiums), Pell's trading post → miner NPC Sell stall; tutorial (mine → cart → train → pen → podium).

### Proposals for 8 (offline earnings), waiting for the owner's choice
- **A (recommended):** podiums keep earning while you're offline at **50%** speed for up to **3 hours**; the big game
  pass raises it to 100% / 8 hours. A "While you were away: +$12,400" popup on return.
- **B:** offline earnings at full speed but only up to **1 hour**; an in-game-money upgrade ("Night Shift") extends
  it step by step (2 h, 4 h, 8 h).
- **C:** no offline earnings, but a **"welcome back" chest** whose size grows with time away (max after 12 h).

### Follow-up answers (owner, 2026-10-16)
- **Capsules (golem pets):** buyable with **both** in-game money and Robux.
- **Shop side menu (UI on the side of the screen, as in other games):** Robux/coin boosts such as **"Triple Lucky"**
  for capsules/eggs and **"Hexa Lucky"** for mining (better odds of rare ores), plus **open x3** and **open x10**
  capsule options (also for in-game money).
- **Story and artifacts:** Claude invents them, e.g. "a kingdom once stood here...", and artifacts you find while
  mining; built so new chapters/artifacts can come in later **updates**.
- Offline earnings (question 8): **decided, see below.**

### Compliance note for boosts
Paid boosts that change the odds of random results (Triple/Hexa Lucky on capsules or mining) must show the **new odds
in numbers before purchase**, and everything random that can be paid for follows the paid-random-items rules
(PolicyService check, odds shown). See docs/COMPLIANCE.md.

### Story draft (proposed by Claude, extends the existing lore; owner may change it)
- Long ago Terra was the **Kingdom of Kaldrum**, ruled by the **Ember Kings** from a city built around the
  **Heartstone**, the living ember at the world's core (existing lore). Kaldrum's smiths built three wonders:
  **Sunlance blasters** (laser tools that cut rock like butter), the **Royal Railway** that carried ore across the
  kingdom, and **golems**, living stone helpers powered by Heartstone sparks.
- One night the Heartstone **cracked** ("the Shattering"). Kaldrum sank into the rock; its shards became the glowing
  ores, its railway was buried and its golems fell asleep as **dormant golem cores**.
- Today the **Forgekeepers' Guild** has rekindled the Great Forge in **Emberfall** (existing hub). You arrive as an
  apprentice with a rusty old blaster. You dig out ore, restore the railway to your base (your own train), earn money
  by showing your best ores on podiums, rebuild better blasters in the foundry, and wake golems from capsules (each
  capsule holds a dormant golem core, which explains the pets).
- **Artifacts:** rare relics inside rocks (crowns, royal seals, rail lanterns, golem blueprints, star maps, Heartstone
  fragments...), grouped into **collections**. Completing a collection unlocks a **story chapter** (journal pages read
  at the Guild board) and a reward (title, podium skin, small bonus). Each update can add a new region + a new
  collection + the next chapter (e.g. "The Sunken Palace", "The Golemworks", "The Royal Depot").

### Decision 8: offline earnings (owner, 2026-10-16)
Option **A**, adjusted: podiums keep earning while the player is offline at **50% speed for up to 5 hours**. A
purchasable **extension** raises it to **12 hours** for that player: included in the big game pass (~560 R$) and
also sold separately for **99 Robux**. Show a
"While you were away: +$X" popup on return.

### Quality pillars (owner, 2026-10-16)
The owner wants the game to beat the "12 bosses of gamedev" (meme: QA, Burnout, Marketing, Scope, VFX, UI, Sound,
Bugs, Design, Music, Code, Art). What matters for us: **Art, UI, VFX, Sound, Music, Design, Code, and no Bugs (QA)**.
- **Music must be calm and good, nothing hype**: cozy, relaxing background music (lo-fi/acoustic/ambient feel),
  different calm tracks per area (town, mine, caves, base), soft crossfades, a music volume setting.
  Roblox only allows audio the owner uploads or audio from Roblox's licensed Creator Store music library, so
  the tracks are chosen by asset ID (placeholders in SoundConfig until the owner picks or uploads them).
- Every feature gets polish: readable UI on phones, juicy but not noisy VFX, satisfying sounds, careful QA.
- The owner also linked an Instagram reel (https://www.instagram.com/reel/DddJLuVBjnZ/), the source of the meme
  screenshots; Claude could not open it (Instagram needs a login).

### Round 3 answers (owner, 2026-10-16)
1. **Offline extension:** part of the big game pass, and separately for 99 Robux. ✔
2. **Big numbers:** yes, abbreviations up to K, M, B, T (trillion), Qa, **Qi (quintillion)** and beyond. Prices must
   **grow fast** (exponential cost curves) because podium income grows fast; players must not get everything at once.
3. **Full automation of everything except mining** (owner's new idea, important):
   - **Dirty ore hides its rarity.** Raw ore is dirty: you don't know what it is until it is cleaned (cleaning = the
     reveal; fits the Cleaning Station reveal and the existing "???" idea).
   - With a high enough **pen upgrade**, the **train dumps raw ore straight into the cleaner** instead of the pen.
   - The **cleaner (cleaning plant)** is upgradeable: more upgrades = cleans **better** (higher grade cap) and
     **faster**. Every machine has upgrades (speed etc.).
   - From the cleaner the ore drops into an **iron box** where you now see what it is and choose what to **keep**
     (pen → podium) and what to **send on**.
   - In the pen you take out what you don't want and press **"Send"**: items move slowly onto the **conveyors**, then
     ride to the cleaner / further machines. The route depends on how the player builds the factory.
   - Smelted ore → **ingots** → the **foundry** makes **blasters**.
   - New: an **Enchant shop** that sells **perks and upgrades for blasters**.
4. **Rocks:** 1–3 ores per rock, rarer deeper, small artifact chance. ✔ **Every one of the 30 ores needs its own
   unique, beautiful look** (shape, color, glow, particles), and **blaster looks follow the ore they're forged from**.
5. **Golems:** as proposed: they follow you, each gives a bonus (e.g. +10% podium money or faster mining), 3 equipped
   at once, rarities from Common to Mythic. ✔
6. **Rebirth:** yes, optional (later update), permanent bonus (proposed +25% money per rebirth).
7. **Trading:** yes, add trading between players (needs a safe two-step confirm screen and anti-scam checks).
8. **Leaderboards:** yes, **3 boards** in the lobby with different focuses (proposal: Money per second, Total earned,
   Artifacts / rarest ore found).
9. **Gear shop:** boots (walk speed), helmet with head lamp (see more), **backpack** (carry more ore), **gloves**
   (faster pickup), **magnet** (ore flies to you). ✔
10. **Wheel of fortune:** Claude designs the rewards (proposal: coins, luck boosts, golem capsules, small chance of a
    rare ore); odds shown on the wheel.
11. **Artifacts:** collection book in the UI **and** a small **museum on your base** to display them. ✔
12. **Music:** chosen from Roblox's free licensed library (Studio Toolbox → Audio), calm tracks; Claude writes what to
    search for and where to paste the IDs.

### Round 4 answers (owner, 2026-10-16)
- **Golem pets look:** based on Kenney **Mini Characters** (https://kenney.nl/assets/mini-characters), turned into
  golems: silver, gold, ore-colored and more, some with helmets and other gear. Original designs, built from parts.
1. **Enchant shop:** many perks for in-game money; rarer ones for a lot of money or for shards; the **2 rarest** for
   an enormous amount of money **or 20 Robux**.
2. **Cleaning:** you clean by hand (the minigame) only **until you buy the automatic cleaner**. After that you don't
   have to clean by hand anymore (no "Flawless only by hand" rule; the cleaner's quality comes from its upgrades).
   The automatic cleaner, all conveyors and the other automation machines are bought for in-game money in a
   **Tech shop**.
3. **Trading:** golems and ores only (no blasters, no money). ✔
4. **Leaderboards: 4 boards:** Money per second, Total earned, Artifacts found, and **Most hours played**.

### Platforms (owner, 2026-10-16)
The game must play **perfectly on PC, mobile, Xbox and PlayStation** (mouse+keyboard, touch, gamepad, TV).
See the project skill .claude/skills/all-platforms/SKILL.md.

### Mine floors (owner, 2026-10-17)
The deeper you go, the harder the rocks and the better the ores. Plan: docs/plans/MINE_FLOORS_PLAN.md,
data: src/shared/Config/MineFloors.luau, rocks: src/shared/Builders/RockBuilder.luau.
1. **5 floors now**, more floors in updates (floor 6 comes with blaster 11 "Coming soon"). Proposal **A** chosen:
   1 Greystone Quarry (blaster 1+) · 2 Ember Caves (3+) · 3 Deep Hollow, re-themed as a crystal lagoon (5+) ·
   4 Sunken Palace of Kaldrum (7+) · 5 Heartstone Core (9+). Each floor has 6 home ores; all 30 ores exist from launch.
2. **Route C:** floors 1–3 stay connected on foot; floors 4–5 only by an **elevator that is bought once with coins**.
3. **Hoverboards:** 3 styles for coins (each faster) + 2 styles for ~50 Robux each that are **also faster** and have
   special effects (owner: "more benefits").
4. **Rocks:** more HP on every floor; the weakest blaster allowed on a floor breaks a rock in **about 5 s**.
   Kinds: **small = 3 ores, big = 4 ores, crystal ("shard") = 3 ores of better rarity, 10 % of rocks, a bit more HP**
   (crystal and shard are the same thing). A **breaking animation** (cracks, chunks, shatter). Blaster **lock**
   ("Needs Lv N") on rocks and floor gates: yes.
5. **No crystal crust** mechanic; instead the crystals must look **better and cooler on every deeper floor**.
6. Yes to: better ore deeper inside each floor (veins), **special rocks** (golden rock, geode, artifact rock) and the
   server-wide **Giant Crystal**.
