# Daily / weekly quests + 7-day login streak

Owner approved 2026-10-21 (retention plan: Acts, 2x Money, QA pass, and this).
A window + HUD feature, not NPC quest givers (those stay parked, owner 10-20).

## What the player sees

- **QUESTS** tile in the side menu (light HUD: first tile of the MORE flyout; the MORE
  tile adds up its badge). Red badge = quests ready to claim + the streak day if it
  is not claimed yet. A toast "Quest done! ..." the moment a quest completes.
- **QUESTS window** (Pop kit, purple header):
  - LOGIN STREAK strip: 7 day cells (day 7 gold, bigger prize), today glowing, CLAIM.
  - DAILY: 3 quest cards (progress bar, "57 / 120", the reward, CLAIM / DONE),
    "New quests in 5h 12m" (00:00 UTC).
  - WEEKLY: 1 big card, "New quest in 3d 4h" (Monday 00:00 UTC).
  - ODDS button: the Crystal Capsule's golem odds (day 7 prize).
- **Streak popup** on join: once per session, after the loading screen
  (`Util/Loading.wait`), only when today's day is not claimed, never while the
  tutorial bubble shows (`TutorialController.isShown`) or another panel is open
  (it waits up to 60 s for them, else it only leaves the badge).

## Rules

### Days and weeks (UTC)
- `day = floor(now / 86400)`; dailies reset at 00:00 UTC.
- `week = floor((day + 3) / 7)` (day 0 = Thursday 1970-01-01, so the week number
  changes on Monday 00:00 UTC).

### Quests
- 3 dailies + 1 weekly, picked from `QuestConfig.Daily` / `QuestConfig.Weekly`
  by a weighted roll **without repeats**, seeded with `Rng.new("quests:<userId>:<day>")`
  (weekly: `":w<week>"`), and **saved** in `data.Quests` (so a rejoin, a server hop,
  or a level-up later that day never changes them).
- Every quest counts a counter that already exists in `data.Stats`
  (OresMined, RocksBroken, OresCleaned, FlawlessCleans, IngotsSmelted, ItemsSold,
  TrainTrips, PodiumEarned, ArtifactsFound, CapsulesOpened, WheelSpins) as a **delta**:
  `Base` = the counter when the quest was given, `progress = clamp(stat - Base, 0, Goal)`.
  No service had to change; a counter that went down (rollback) gives 0, never negative.
- Goal at blaster level L: `nice(Amount * (1 + Growth * (L - 1)))`
  (nice = rounded to 1 / 5 / 10 / 50 / 100...). Podium quests use income instead:
  `Goal = income/s * Seconds`, and are left out of the roll while income is 0.
- Pacing targets: daily ~10-20 min of normal play, weekly ~2-3 h.

| Quest (daily)           | Stat           | L1 amount | Growth/level | Notes |
|-------------------------|----------------|-----------|--------------|-------|
| Mine N ores             | OresMined      | 100       | 0.08         | ~3.3 ores per rock, a rock every ~5-8 s |
| Break N rocks           | RocksBroken    | 35        | 0.08         | |
| Clean N ores            | OresCleaned    | 8         | 0.05         | the minigame, ~40-60 s each |
| Get N Flawless cleans   | FlawlessCleans | 2         | 0            | weight 0.6 |
| Smelt N ingots          | IngotsSmelted  | 12        | 0.08         | from blaster 2 |
| Sell N items            | ItemsSold      | 30        | 0.08         | |
| Bring home N trains     | TrainTrips     | 4         | 0            | |
| Earn X on podiums       | PodiumEarned   | 900 s of income | -      | needs income > 0 |
| Open N golem capsules   | CapsulesOpened | 2         | 0            | left out where paid random items are restricted (Policy.cached) |
| Spin the daily wheel    | WheelSpins     | 1         | 0            | weight 0.5 (the free spin is daily) |

Weekly: the same kinds at ~10x (Mine 1200, Rocks 400, Clean 80, Flawless 12,
Smelt 120, Sell 350, Trains 35, Podiums 9000 s of income, Capsules 12) plus
**Find N artifacts** (ArtifactsFound, 4; ~1 % per rock). No weekly wheel quest
(it would push bought spins).

### Rewards (never Robux-only items, nothing for likes / favorites)
- Coins are paid at claim time: `max(income/s * Seconds, floor)`, where
  `floor = max(250, 3 % of the next blaster forge's coins) * Seconds / 600`
  (new players with no podium income still get something useful).
- Daily quest: 600 s of income + 10 shards.
- Weekly quest: 3600 s of income + 100 shards + Triple Lucky 15 min.
- Triple Lucky only helps capsules: where every capsule is a restricted paid random
  item (`CapsuleConfig.allRestricted`), it becomes 300 s of income in coins
  (the wheel does the same).

### 7-day login streak (`data.Streak = { Day, Last }`)
- One claim per UTC day. `Last` = the day number of the last claim, `Day` = which
  streak day (1..7) it was.
- Next day to claim: `Last == today - 1` -> `Day % 7 + 1` (day 7 starts again at 1),
  otherwise (missed a day, or first time) -> day 1. Already claimed today -> nothing.

| Day | Prize |
|-----|-------|
| 1 | 300 s of income (coins) |
| 2 | 15 shards |
| 3 | 600 s of income |
| 4 | Triple Lucky 10 min |
| 5 | 600 s of income + 30 shards |
| 6 | Hexa Lucky 10 min |
| 7 | **Crystal Capsule** (no Common golems, a chance at Mythic) + 50 shards |

- Day 7's capsule is random: its exact odds (`CapsuleConfig.odds("Crystal")`) are in
  the window and the popup (ODDS). It opens through `CapsuleService.grantFree`
  (the normal opening plays). Full golem inventory -> the claim is refused
  ("InventoryFull: make room"), the day stays claimable, nothing is paid instead.
  Restricted players (every capsule a restricted paid random item) get its coin
  value (`WheelConfig.capsuleFallbackCoins`).
- The old Ember Chest streak (`data.Daily`) stays retired; the daily wheel stays.

## Server (QuestService)
- `QuestAction` (Net, Rate 2, Burst 4):
  - `("Claim", { Kind = "Daily", Index = 1..3 })` / `("Claim", { Kind = "Weekly" })`
  - `("Streak")` claims today's streak day.
  Every request read gets `ActionResult { Action = "Quest", Op, Ok, Reason?, Index? }`
  and on success `QuestReward { Kind, Index?, Day?, Coins?, Shards?, Boost?, Seconds?, Capsule?, Full? }`.
  Reasons: `NotDone`, `Claimed`, `Stale` (the quest list changed: a new day), `BadQuest`, `NoData`,
  `Tomorrow` (streak claimed today), `InventoryFull` (day 7 waits for room).
- Policy (may yield) is asked first, then check + write + grant with no yield
  (double taps can't double claim: Claimed / Last are written before granting).
- Quests are (re)rolled on join, on every claim, and by a 30 s loop that only
  compares day numbers per player (no per-part work).
- StateService provider `snapshot.Quests` (the view: titles, progress, goals, rewards
  priced now, reset times, the streak cells).

## Client
- `UI/QuestView.luau` (pure builder + layout, Lune previews build it):
  window, day cells, quest cards, ODDS panel, the streak popup.
- `Controllers/QuestController.luau`: open / close / toggle / isOpen,
  `onUnseenChanged` (badge), the join popup, toasts, gamepad (SelectionGroup, B closes),
  phone layouts (568x320, 844x390: >= 44 pt buttons through the fit scale).
- Side menu entry `Quests` (Group More, Order 0, IconName Quests) + `MenuPanels.Names`.

## Data (integrator owns DataTemplate / Migrations)
```lua
Quests = { Day = 0, Daily = {}, Week = 0, Weekly = {} },
-- Daily / Weekly: { { Id, Base, Goal, Claimed } }
Streak = { Day = 0, Last = 0 },
```
No migration needed: `QuestLogic.sanitize` repairs anything broken on read
(missing / junk entries are rerolled for the current day).

## Tests
`tests/Quests.spec.luau`: day / week math, seeded stable rolls (no repeats,
level scaling, podium needs income, capsule quests skipped when restricted),
deltas, claims (once, not before done, stale), streak (claim once a day, grows,
resets after a missed day, wraps after 7), rewards (coins floor, boosts,
capsule fallback), Net limits, view layouts (PC + both phones, 44 pt), no emoji.
