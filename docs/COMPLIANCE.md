# Terra Forge – Roblox compliance guide

This page lists what Terra Forge needs to pass Roblox moderation, get the right
maturity label, and reach as many players as possible, including younger ones.

- **Checked against Roblox's docs on:** 12 October 2026. Roblox changes these
  rules often (Roblox Kids/Select arrived in 2026, and new Terms of Use take
  effect on 1 November 2026). Re-check the sources at the bottom before launch.
- **TODO** marks anything you have to fill in or do by hand.
- "Dashboard" means the Creator Dashboard / Creator Hub
  (create.roblox.com/dashboard/creations). "Studio settings" means
  **File → Experience Settings** in Studio. Older notes, such as
  `STUDIO_CHECKLIST.md` and a warning in `DataService.luau`, still call it
  "Game Settings".

**In short:** Terra Forge has no violence, blood, scares, romance, alcohol,
gambling or trading, so it should get the lowest label, **Minimal**.
**Paid random items are planned (design v2, steps 6-8):** Royal golem
capsules, the Robux Triple/Hexa Lucky packs and the Starbreaker enchant's
pass (an odds booster). They are built as "Coming soon" placeholders (id 0
in `MonetizationConfig.luau`); the questionnaire answer changes the day the
first one goes live (see 1.1 #12). That makes it eligible for **every age group**, including
Roblox Kids (5–8) and Roblox Select (9–15). The game stays 16+ until it
passes Roblox's Kids & Select evaluation (see 2.9). The main risks are the
public **forge name sign** (it must be filtered and limited to one change per
minute), the **group/like reward** (only the group part is safe),
**purchase handling** (receipts must be processed safely) and **store page
images** (they must show the real game).

---

## 1. Maturity & Compliance Questionnaire

**Where:** Dashboard → your game → **Configure → Questionnaire**.

**How to answer:** answer for the most intense thing a player can run into
anywhere in the game. Only count content *you* made; avatar items that
players bring in don't count. If an update changes any answer, you **must**
resubmit the questionnaire. Until it is submitted, Roblox limits who can play
the game, and you cannot make the game public without it.

### 1.1 Answers for Terra Forge

These are the question categories in Roblox's current questionnaire (October
2026). Your Dashboard may word or order them differently. **TODO:** if it
shows a category that isn't listed here, answer it the same way: describe
only what is really in the game.

| # | Category | Answer | Why |
|---|---|---|---|
| 1 | **Violence** | **None** | Roblox defines violence as force used *against players or NPCs*. In Terra Forge you only hit rocks (ore nodes) and ingots on an anvil. No one can hurt anyone: the pickaxe only damages nodes (`MiningService`), and thrown ore chunks pass through characters because they are in a separate collision group (`ItemService`). Lava in Ember Caves is decoration and does no damage. There are no enemies. |
| 2 | **Blood** | **None** | There is no blood anywhere. Hit effects are dust, sparks and ore shards. |
| 3 | **Fear** | **None** | Ember Caves and Deep Hollow are dark, but they are lit by glowing ore. There are no creepy NPCs, jump scares, screams, heavy breathing or ominous music, which are Roblox's examples of mild fear. |
| 4 | **Crude humor** | **None** | No burping or toilet jokes. |
| 5 | **Unplayable gambling** (depictions) | **None** | No casino, cards, dice or slot imagery. Selling at Pell's Trading Post pays a fixed, shown price. |
| 6 | **Strong language** | **None** | No swearing in game text. Keep **Allow Strong Language** off (section 3). |
| 7 | **Romantic themes** (also private spaces and adult settings such as clubs or bars) | **None** | No romance or dating, and the game doesn't take place in bedrooms, bathrooms, clubs or bars. |
| 8 | **Alcohol** | **None** | No bars, taverns or drinks. The barrels and crates in Emberfall are plain props. Never label them "ale", "mead" and so on. |
| 9 | **Social hangout** | **No** | The main activity is mining and crafting, not chatting. Keep "hangout", "chill" or "vibe" wording out of the title and description: Roblox classifies a game as a hangout if its title or description refers to one. |
| 10 | **Free-form user creation** | **No** | This means freehand drawing, painting, writing on surfaces, or pixel canvases. Placing machines on your plot is building with 3D assets, which Roblox excludes. The forge name is a short typed name, not freehand writing, and it goes through Roblox's text filter before anyone sees it (see 2.1). Roblox also excludes anything that goes through Roblox moderation before it is shown. |
| 11 | **Sensitive issues** (political, social, religious) | **No** | The lore is original fantasy (the Heartstone, the Forgekeepers' Guild). |
| 12 | **Paid random items** | **No today; Yes as soon as one is live** | Today every Robux product id is a placeholder (0), so nothing random can be bought. **Answer Yes and resubmit the day the first of these goes live:** Royal golem capsules and the limited edition capsules (random golem, Robux), the Triple Lucky / Hexa Lucky Robux packs (they raise the odds of capsules / ore) and the Starbreaker enchant pass (raises ore luck and the artifact chance). Roblox's definition (paid random items page): random rewards bought with Robux, or with currency or items that can be bought with Robux. **Coins can be bought with Robux** since the owner turned coin packs on (2026-10-20, `MonetizationConfig.CoinPacksEnabled = true`), so coin capsules, coin luck boosts and coin enchants **are paid random items too** (`coinsBuyable()`: hidden and refused where restricted, exact odds shown before every buy in the capsule and boost windows). Server Luck (`ServerLuck15`, x2 ore luck for the whole server) is a paid odds booster as well. **Spin & Win spins are sold** (owner 2026-10-20: `WheelSpins1/5/10`), so the wheel is a paid random item too (see 2.6 "Spin & Win"). Free random rewards don't count: the free daily spin, ore drops, artifacts, cleaning grades and capsules won on the wheel. |
| 13 | **Paid item trading** | **No** | Players cannot trade. Every item belongs to one player: only the owner can pick it up (`ItemService`), and selling is designed to always pay the owner. |
| 14 | **Media: players share media** (images, video, text, audio, models) with built-in game tools | **No** | There is no in-game screenshot sharing, feed or gallery. |
| 15 | **Media: endless feeds / autoplay** | **No** | None. |
| 16 | **Media: viewing content captured in other games** | **No** | None. |
| 17 | **AI: players interact with generative AI** | **No** | There are no AI chatbots or AI NPCs. Using AI tools to *build* the game doesn't count. |
| 18 | **AI: type of interaction** | (skipped) | This question only appears if you answered "Yes" to the one above. |

Crafted gear such as the **Dagger** and **Greatsword**, plus the **Helm** and
**Tool Head**, are only objects you forge and sell. They can't be equipped or
swung at anyone, so they don't count as violence. **If you ever let players
equip and swing them, or add enemies, knockback or player damage, re-answer
Violence and resubmit.**

### 1.2 Expected result

- **Maturity label: Minimal**, with no content descriptors. Minimal is the
  lowest label. Roblox describes it as "may contain occasional mild violence
  and/or light unrealistic blood", and Terra Forge has neither.
- **Who it can reach:** Minimal and Mild games can be shown to Roblox Kids
  (ages 5–8) and Roblox Select (9–15). Moderate games reach Select and
  standard Roblox (16+). Restricted games are 18+ only.
- **Not automatic:** to reach Kids and Select, you (the creator) and the game
  must also pass Roblox's Kids & Select requirements (see 2.9). Until then,
  only age-checked players aged 16+ can play.
- **When paid random items go live** (1.1 #12 becomes Yes): resubmit, then
  read the questionnaire preview again. **TODO:** check on the Dashboard how
  a "Yes" for paid random items shows on the game page and whether it
  changes Kids & Select eligibility; if it does, the owner decides whether
  Royal capsules and the Robux luck packs are worth it.

### 1.3 Things that would change the label (avoid, or resubmit)

- Enemies, combat, or damage between players → Violence.
- Scary cave sounds, creatures or jump scares in Deep Hollow → Fear.
- Loot crates or spin wheels paid with Robux (or with coins once coins can
  be bought with Robux) → Paid random items. The Royal capsule is one, and
  so are the Spin & Win spins sold since 2026-10-20 (see 1.1 #12): show
  the odds, use PolicyService (2.2).
- "Luck" items bought with Robux or coins that raise the chance of rare
  results → Roblox requires the NEW odds to be shown in numbers before
  purchase. Ours: Triple Lucky (capsule odds: `CapsuleConfig.odds(id, true)`
  next to the normal odds), Hexa Lucky and the Lucky / Prospector /
  Starbreaker enchants (`BoostConfig.preview`: per zone the chance of each
  rare rarity now and after, plus the artifact chance per rock). The cards
  must show those numbers before every coin, shard or Robux buy.
- Trading or gifting items between players → Paid item trading.
- A drawing board, paintable signs or a free-text bulletin board → Free-form
  user creation, which limits the game to players aged 16+.
- A "hang out at the forge" theme in the title or description → Social hangout.

---

## 2. Community Standards and Terms checklist for this game

### 2.1 Text filtering: the forge name sign

Roblox already filters chat. **Any other text that players type and others
can see is your job to filter.** Roblox's docs say games without text
filtering can be removed. In Terra Forge that text is the **forge name**,
which will be shown on the sign at the player's plot (`SetForgeName` remote,
`DataTemplate.ForgeName`). The naming feature isn't built yet: today the sign
(`PlotSign`) shows "<DisplayName>'s Forge" while the plot is owned and
"Free Plot" when it isn't (`PlotService`).

**How it must work (server only):**

1. The client sends the name once, when the player presses **OK**. Don't
   filter on every keystroke.
2. **Accept a new name at most once per minute per player.** Roblox's chat
   guidelines require a rate limit of at least 1 minute for any editable text
   that other players can see, and they name signs as an example. The
   current limit for `SetForgeName` in `Net.luau` (`Rate = 0.5, Burst = 2`)
   allows a change every 2 seconds, which is too fast. **TODO (code):** add
   a 60-second cooldown in the server handler (count it from the last
   accepted name) and tell the player kindly how long to wait. You can also
   lower the `Net.luau` limit to `Rate = 1/60, Burst = 1` as a backstop.
3. Clean it up on the server: trim spaces, remove line breaks and control
   characters, and limit the length. **TODO:** pick a length, for example 3–24
   characters. Turn off `RichText` on the sign's TextLabel so tags show as
   plain text.
4. Filter it with Roblox's text filter. The owner must be in this server,
   because `FilterStringAsync` throws if the user isn't:
   ```lua
   local ok, result = pcall(function()
       return TextService:FilterStringAsync(raw, player.UserId, Enum.TextFilterContext.PublicChat)
   end)
   ```
5. Get the version that is safe for everyone. The sign is seen by every
   player on the server, so use the **broadcast** version, not the per-user
   one:
   ```lua
   local ok2, shown = pcall(function()
       return result:GetNonChatStringForBroadcastAsync()
   end)
   ```
6. Only put `shown` on the sign. Never show `raw` to anyone, including on the
   owner's own screen.

**If filtering fails** (an error is thrown, or `ok`/`ok2` is false):

- **Show nothing from the player's text.** Roblox: "If it fails, do not
  display the text to any user." Keep the sign on the default text that
  `PlotService` already shows, "<DisplayName>'s Forge". Display names are
  already moderated by Roblox, so this is safe.
- Tell the player kindly: "We couldn't check that name right now. Please try
  again in a moment."
- Don't loop retries. `FilterStringAsync` already retries internally. Let the
  player try again later, or try once more on their next join.
- If the filtered text came back with `#` characters (the filter blocked
  part of it), it is still safe to show. It is friendlier to say "That name
  can't be used, please pick another" and keep the old name or the default
  sign text.

**Saving:** the save stores the raw name (`ForgeName`). That is fine, as long
as you **filter it again every time you show it**, for example when the owner
joins and their plot sign is built. Filter rules change over time, and
Roblox's docs list stored text (their example: pet names in data stores) as
text you must filter when you show it. When the owner leaves, the sign must
go back to "Free Plot" (`PlotService` already does this when it releases
the plot); you can't filter for a user who isn't in the server.

**Prompt text:** in the naming box, write: *"Name your forge! Please don't use
your real name or any personal info."*

**Other text:** text the game writes itself (ore names, the lore, the
`Notify` messages) is under your control and doesn't need filtering. If you
ever build names from **random** word parts (for example a "random forge
name" button), filter those too, because random combinations can form bad
words.

### 2.2 PolicyService: per-player rules

Call `PolicyService:GetPolicyInfoForPlayerAsync(player)` once on the server
when the player joins, wrapped in `pcall`. If the call fails, assume the
**strictest** values: paid random items restricted, trading not allowed, no
ads.

| Key | What it means | Does it matter for Terra Forge? |
|---|---|---|
| `ArePaidRandomItemsRestricted` | `true` = this player may not use paid random items (with Robux or with currency bought with Robux) | **Yes (steps 6-8).** Hidden and refused for these players: Royal capsules, the Robux Triple/Hexa Lucky packs and the Starbreaker pass (`MonetizationConfig` `PaidRandom`, `promptStatus` → "Restricted"; `EnchantConfig.quote` → "Restricted"). With coin packs on (owner 2026-10-20), coin capsules and coin boosts too (`CapsuleConfig.isPaidRandom`, `BoostConfig.isPaidRandom`), and Server Luck. The Spin & Win spins for Robux: the BUY SPINS panel hides, a "Buy" answers "Restricted", and spins bought earlier stay saved but can't be spun there (`WheelService`); their free daily spin still works. Players who can't buy any capsule get coins instead of Triple Lucky on the wheel. Odds are shown to everyone. |
| `IsPaidItemTradingAllowed` | `false` = this player may not trade paid items | **Not today**: there is no trading. Golem trading is planned (design notes, round 4): golems from Robux purchases are saved with `Paid = true` so that trading can block them for these players. |
| `AllowedExternalLinkReferences` | Legacy field. Roblox's reference says it **always returns an empty list** now. | Treat it as "no external links are ever allowed in the game" (see 2.3). |
| `IsSubjectToChinaPolicies` | `true` = the game should apply China-related compliance changes | Nothing in Terra Forge is known to need changing. **TODO:** log how often it is `true` (analytics). If it ever is, read the DevForum post linked from the PolicyService page. |
| `AreAdsAllowed` | `true` = immersive ads may be shown | Only needed if you add ads later. Ads have their own rules (Roblox's Advertising Standards and the immersive / rewarded video ads docs); the only allowed way to reward players for an ad is Roblox's Rewarded Video Ads feature. |
| `IsContentSharingAllowed`, `IsEndlessContentLoadAllowed`, `IsEndlessContentAutoplayAllowed` | Media-sharing features | Not used. |
| `IsEligibleToPurchaseSubscription`, `IsEligibleToPurchaseCommerceProduct` | Subscriptions and commerce products | Not used. Terra Forge sells only passes and developer products. |

**Done (code):** `src/server/Policy.luau` wraps PolicyService: it asks once
per player (in `pcall`, retried with backoff when the call fails), caches the
answer and gives the strictest answer until it knows. Capsules, boosts,
enchants, the wheel and later trading all ask it.

### 2.3 No off-platform links

- **In the game:** no URLs, Discord invite codes, YouTube or X handles, or
  contact emails in any text, sign, decal or loading screen. Roblox's social
  links doc says creators cannot share social media links within a game. You
  may say *"Find us on the game page"* and leave it at that.
- **On the game page:** add social links in the Dashboard instead
  (**Engagement → Social Links**, up to 3; Discord, YouTube, X, Twitch,
  Facebook, Guilded or a Roblox community). You must age-verify as 16+ to add
  them, and only players verified as 16+ can see them. Never offer rewards
  for joining Discord or following accounts outside Roblox.

### 2.4 Never ask for personal info

- Never ask for a real name, age, birthday, school, location, phone number,
  email or social handles. That covers prompts, NPC dialogue and surveys.
- The forge name box says *"Please don't use your real name or any personal
  info"* (see 2.1). Roblox's filter also blocks things like phone numbers.
- Show players by their Roblox **DisplayName** (already moderated by Roblox),
  for example on plot ownership signs or leaderboards (`LeaderboardService`
  looks them up with `UserService:GetUserInfosByUserIdsAsync`).

### 2.5 Chat

- Use Roblox's default `TextChatService`. Roblox filters it and applies age
  rules for you. Since January 2026, chat requires an age check worldwide.
  Players are placed in age groups (under 9, 9–12, 13–15, 16–17, 18–20, 21+)
  and by default can chat only with nearby groups. Chat is off by default for
  Roblox Kids (5–8) and for Select accounts that haven't done an age check.
- **The game must be fully playable without chat.** Many young players won't
  have it. Prompts, notifications and the cleaning minigame already use
  on-screen UI, which is good. Keep the tutorial (not built yet) on-screen too.
- Don't build a custom chat, whispers or a message board. Roblox requires all
  in-game chat to go through `TextChatService`, and any other player text
  needs filtering and a 1-minute rate limit (see 2.1), and possibly a
  questionnaire change.
- **On console**, Roblox's console guidelines say to hide the chat window
  (`ChatWindowConfiguration.Enabled = false`, for example when
  `GuiService:IsTenFootInterface()` is true).
- System messages from the game (`DisplaySystemMessage`, `Notify`) are text
  you write, so they need no filter.
- **Voice chat:** turn it off (section 3). It is **on by default** for new
  games, so you have to switch it off yourself. Terra Forge doesn't need it.

### 2.6 Fair monetization

What Terra Forge sells (design v2; the source of truth is
`src/shared/Config/MonetizationConfig.luau`, every id still a placeholder 0
= "Coming soon"):

| Product | Type | Key in code | What it does | Paid random? |
|---|---|---|---|---|
| Forgemaster's Pass (~560 R$) | Game pass | `BigPass` | Podiums 3-4, 12 h offline earnings, 2× carrying (`StrongBack`), the Glimmer Grotto (`ForgeVip`), extra machine slots (`Workshop`) | No |
| Two More Podiums (100 R$) | Game pass | `Podiums` | Podiums 3 and 4 | No |
| Night Shift (99 R$) | Game pass | `OfflineExtension` | Offline earnings up to 12 h instead of 5 | No |
| Express Train (199 R$) | Game pass | `TrainExpress` | Faster, bigger ore train | No |
| Heartfire Enchant (20 R$) | Game pass | `EnchantHeartfire` | Mythic enchant: damage | No |
| Starbreaker Enchant (20 R$) | Game pass | `EnchantStarbreaker` | Mythic enchant: +75 % ore luck, +50 % artifact chance | **Yes** (odds booster) |
| Royal Capsule x1 / x3 / x5 / x10 | Developer products | `RoyalCapsule1/3/5/10` | Random golems (x5: the Store) | **Yes** |
| Dragonforge Capsule x1 / x3 / x10 / x50 (99 / 249 / 799 / 3499 R$) | Developer products | `DragonforgeCapsule1/3/10/50` | LIMITED EDITION: random golems of the Dragonforge set, sold only in the Store's banner until the edition's real end date (see "Limited editions" below) | **Yes** |
| Triple Lucky 15 min / 1 h | Developer products | `TripleLucky15/60` | Capsule odds: the rarest golems x3 | **Yes** (odds booster) |
| Hexa Lucky 15 min / 1 h | Developer products | `HexaLucky15/60` | Ore luck x2.5 (Rare x2.5 … Mythic x9.9 weight) | **Yes** (odds booster) |
| Coin packs (19 / 49 / 99 / 249 / 499 R$) | Developer products | `CoinsSmall/Medium/Large/Huge/Mega` | Coins: minutes of the player's podium income (on: `CoinPacksEnabled = true`; bought coins survive a rebirth, `PaidCoins`) | No, but they make coin capsules and coin boosts paid random items |
| Next Blaster (49 / 99 / 199 / 399 R$) | Developer products | `BlasterNextA/B/C/D` | The next blaster level, by price band (each bought level starts every later rebirth's blaster 1 level higher, up to LV 9; never pays Forge Stars) | No |
| Server Luck 15 min (49 R$) | Developer product | `ServerLuck15` | x2 ore luck for everyone on the server while it runs | **Yes** (odds booster) |
| Spin & Win spins x1 / x5 / x10 (25 / 99 / 179 R$) | Developer products | `WheelSpins1/5/10` | Spins of the Spin & Win wheel, held in `data.Wheel.Spins` (never expire; the free daily spin is used first) | **Yes** |

**TODO:** set prices, write descriptions and upload icons. Pass and
developer product icons must be at most 512×512 (.png/.jpg/.bmp) and keep
important details inside the circle.

Listed passes and products can also be bought **outside the game**, on the
game page's Store tab, so a player may join already owning one. The join
check for passes and `ProcessReceipt` for products (below) cover this once
step 8 is in; until then every game pass stays **Off Sale** (see 2.6a).

**Rules to follow** (from Roblox's monetization guidelines, plus our own
choices marked *(ours)*):

- **No misleading or pushy prompts.** Roblox: users must never be misled,
  confused or pressured into purchases they did not intend. Roblox also says
  to avoid "pushy or urgent messages" with minors.
  - Only open a purchase prompt after the player taps a shop or buy button.
    Never open one on join, after a bad cleaning grade, or on a timer *(ours)*.
  - No fake countdown timers, no timers that restart, and no "70% OFF" unless
    it is a real, temporary discount. A price that is always "on sale" is not
    a real discount, and a sale that only lasts a very short time to rush
    players is not fair (Roblox).
  - The close (X) button must be easy to see on every shop screen, including
    on mobile *(ours)*.
  - Don't say "you'll lose your streak!" or similar in a scary way. Daily
    reward reminders stay friendly and calm *(ours)*.
- **Limited editions** (the owner's decision, 2026-10-20: "a limited mega
  cool edition of golems"; `Config/LimitedGolems`). A themed set of 6
  golems is sold as a Robux capsule (Dragonforge first: `DragonforgeCapsule1/3/10/50`)
  only in the Store's FEATURED banner, for one window. Editions change
  monthly and the owner sets each launch with us. The rules:
  - **A real end date, no fake timers.** `LimitedGolems.Current.EndsAt` is a
    fixed date (Dragonforge: 2026-11-30 23:59:59 UTC). The banner counts down
    to it and the sale really stops there: after it the server refuses to
    prompt the capsule ("This limited edition has ended") and the banner is
    gone (`LimitedGolems.current(now)` is nil). The timer never restarts and
    the same edition is not brought back with a new "last chance" date.
  - **Odds before buying.** The banner shows every golem's exact chance
    (34 / 28 / 20 / 12 / 5 / 1 %, and the Triple Lucky odds while it runs),
    like every capsule; each product's description says so.
  - **No fake discounts.** The x3 / x10 / x50 packs are priced per pack
    (99 / 249 / 799 / 3499 R$) and never shown as "% OFF" against a price
    that was never asked.
  - **PolicyService like every paid random item** (`PaidRandom = true`,
    `CapsuleConfig.isPaidRandom`): hidden and refused where
    `ArePaidRandomItemsRestricted` is true.
  - **Never lost.** A receipt is always granted, also one that arrives after
    the end (a purchase finished in the last second, a Roblox retry), so the
    capsule, its products and the golems stay in the configs forever; golems
    woken are ordinary golems for good (paid, locked, and a x50 that doesn't
    fit waits as the pending credit, never coins).
- **Benefits exactly as described.** Each pass's description must match what
  the code does (2× carry, the Grotto, +6/+20 slots). If you change a pass,
  update the description, and never take away something buyers already have.
  **TODO:** before launch, check each description against the code that
  applies the perk: `Bonuses.carryCapacity` (Strong Back), `AccessService`
  and `MiningService` (Forge VIP), and the slot limits once machines are
  built (Workshop Expansion). The VIP tag and the slot limits aren't built
  yet, so don't promise them until they work.
- **Luck boosts and odds boosters:** every card shows the new odds in
  numbers before the buy (see 1.3); the Hexa Lucky and Starbreaker texts
  say what changes ("Rare x2.5 … Mythic x9.9", "+75 % ore luck").
- **Forge VIP and ore odds** *(to be safe)*. Roblox says paid items that
  improve the odds of random outcomes must explain the new odds in numbers
  before purchase (their example is a "magic fishing rod"). The Grotto has
  its own ore mix (`WorldLayout.luau` node weights), so the Forgemaster's
  Pass description ends with those numbers ("Glimmer Grotto ore: 19.0%
  Silver, 16.9% Gold, 14.8% Emberite, 14.8% Amber, ... 1.6% Crystal Rose."
  on the 36-ore map), built from the weights by
  `MonetizationConfig.grottoOddsText()`, so it never goes stale; copy the
  same line into the pass description on the Creator Dashboard whenever the
  weights change (the in-game text follows by itself, the Dashboard text
  does not). The free daily wheel's ore prize never uses the Grotto
  (`WheelConfig.oreOdds` leaves VIP zones out for everyone), so the pass
  changes no free random prize.
- **Not pay-to-win only.** Every ore is minable by everyone: Silver, Gold and
  Emberite also spawn outside the Grotto. Coin pouches only skip time. Keep
  it that way.
- **Process receipts safely** (developer products):
  - Set exactly **one** `MarketplaceService.ProcessReceipt` callback, in
    `MonetizationService`.
  - Check whether `receiptInfo.PurchaseId` is already in the player's
    `Purchases` table. If it is, return `PurchaseGranted` again and don't
    grant twice.
  - Grant the coins, record the `PurchaseId` and **save**. Only after the save
    succeeds, return `Enum.ProductPurchaseDecision.PurchaseGranted`.
  - If the player isn't in this server, their data isn't loaded, or the save
    fails, return `NotProcessedYet`. Roblox retries the next time they join.
  - Roblox can run the same receipt on two servers at once (for example
    right after a server hop). Only grant on the server that holds the
    player's session lock (`DataService` / `ProfileStore`); everywhere else
    return `NotProcessedYet`.
  - Never grant from `PromptProductPurchaseFinished`. Roblox warns that it
    firing doesn't mean the purchase succeeded.
  - Roblox doesn't keep per-player purchase history for you. The `Purchases`
    table is your record (capped: the newest 100 ids, and never one younger
    than 30 days, `DataService.trimPurchases`); `PurchaseLog` says which
    product each id was and is trimmed with it.
- **Game passes:**
  - On join, check `MarketplaceService:UserOwnsGamePassAsync` inside `pcall`.
    If the check errors, retry a bit later instead of treating the player as
    "not owned" forever (here: 4 tries per round, then up to 5 more rounds a
    minute apart while the player stays).
  - On `PromptGamePassPurchaseFinished`, if it succeeded and the pass id
    matches, set the perk (`Perks.set`). A "not owned" answer never takes
    back a pass bought in the same session: the answer can be from before the
    purchase (a check in flight, Roblox's cache). A refund shows on a later join.
- **What step 8 wires (status).** `MonetizationService` holds the one
  `ProcessReceipt` and the pass checks, and every entry in
  `MonetizationConfig` names its handler in `Grant`, registered in the
  owning service's `init()`: `Perks` (Forgemaster's Pass, Two More Podiums,
  Night Shift, Express Train: player perks, set again on every join and on
  `PromptGamePassPurchaseFinished`, never consumed), `Enchant` (Heartfire /
  Starbreaker: the Mythic enchant forever, `EnchantService`), `Hoverboard`
  (`HoverboardService`), `Capsule` (Royal x1/x3/x5/x10 and the limited
  Dragonforge x1/x3/x10/x50: paid, locked golems,
  the Triple Lucky odds stored at the prompt, golems past the save cap kept
  as a pending credit that wakes when there is room, never coins,
  `CapsuleService`), `Boost` (Triple / Hexa Lucky: paid time added
  uncapped, `BoostService`) and `CoinPack` (only while `CoinPacksEnabled`,
  `PodiumService`). Each grant is written together with
  `Purchases[PurchaseId]` and `PurchaseLog[PurchaseId] = { Product, At }`,
  saved, and only then answered `PurchaseGranted`. Receipts that arrive off
  policy (a paid random product for a restricted player: granted; an id
  still 0 or unknown, or a coin pack while packs are off: kept pending with
  `NotProcessedYet`, never acknowledged without the item) are logged with
  the player id, product id and purchase id. The receipts gate opens only
  when every live id has a handler (`MonetizationService.unhandled()` is
  empty; tests/Step8Receipts.spec.luau). Every id is still 0: the owner
  creates the passes and products and pastes each id into
  `MonetizationConfig` at the entry with the matching `Key` (table above).
- **Paid random items** (see 1.1 #12; the full list is in
  `MonetizationConfig.luau`, `PaidRandom = true`):
  - Show the exact odds of every result as percentages before every
    purchase or open (capsule cards and the CapsuleStall's OddsBoard:
    `CapsuleConfig.odds`), and for odds boosters the odds now AND the new
    odds (`BoostConfig.preview`, `CapsuleConfig.odds(id, true)`).
  - Hide or disable them where `ArePaidRandomItemsRestricted` is true (2.2).
  - A Royal capsule receipt uses the Triple Lucky state the player saw at
    the prompt (`MonetizationConfig`, step 8 contract), so the odds shown
    are the odds given.
  - Spin & Win spins are sold (owner's decision, 2026-10-20; the rule
    before was "no paid spins"): see the next point.
- **Spin & Win (the daily wheel and its bought spins):** one free spin a
  day (the timer runs while offline) for everyone, plus spins bought with
  Robux (`WheelSpins1/5/10`, 25 / 99 / 179 R$, the BUY SPINS panel). With
  spins for sale the wheel is a **paid random item**:
  - **Odds before every buy and every spin.** Every segment's exact chance
    is printed on the wheel's face, and the BUY step itself (a BUY SPINS
    row opens it before any prompt: `WheelView.showBuy`) lists all 8
    segments with their exact % and what each pays this player (coins at
    their income, the capsules' rarity odds, the ore prize's own odds);
    Details shows the same list and every capsule golem's chance. The
    jackpot card shows the Crystal Capsule's golem odds.
  - **A full inventory or pen never swaps a paid prize silently.** With
    a full golem inventory a bought spin is refused before it is used
    (`WheelService.spin` answers "InventoryFull", the spin stays saved;
    the same rule as 2.6a "No pressure"), a "Buy" answers "Full" and the
    BUY step says "Your golem inventory is full: make room before using
    a bought spin". A full Ore Pen is disclosed instead of refused: the
    ore row (and, for the free spin with a full inventory, the capsule
    rows) starts with "Ore Pen full: pays $X coins instead" / "Golem
    inventory full: pays $X coins instead", the real fallback amounts
    (`WheelView.fullNote`), on the BUY step and in Details, before any
    spin or buy. The free daily spin pays those coins as before.
  - **Paid golems.** A golem won with a bought spin is saved `Paid = true`
    and `Locked` like every golem from a Robux purchase (trading can block
    it, see `IsPaidItemTradingAllowed`); its opening is logged with Source
    "PaidSpin".
  - **Same odds for paid and free spins.** A bought spin draws from the
    same server table as the free one (`WheelConfig.pick`,
    `WheelConfig.Segments`); there are no paid-only prizes.
  - **PolicyService.** Where `ArePaidRandomItemsRestricted` is true, or
    while the policy isn't known (strict default), the BUY SPINS rows are
    hidden, a "Buy" answers "Restricted" (`MonetizationConfig.promptStatus`
    through `BoostService.promptPurchase`, the capsules' path), and spins
    bought earlier stay saved but can't be spun (`WheelService.spin`
    answers "Restricted"). The free daily spin stays free for everyone.
  - **Receipts.** The "WheelSpins" grant only banks the spins in
    `data.Wheel.Spins` (MonetizationService: once per PurchaseId, saved
    before PurchaseGranted); nothing spins inside ProcessReceipt. A
    receipt is never refused (past `WheelConfig.MaxSpins` held only the
    prompt says "Full"); a receipt that arrives for a restricted player
    is credited and logged like every off-policy receipt.
  It replaced the old 7-day Ember Chest streak (retired; the EmberChest on
  the wheel's stairs now opens the wheel). The big lobby wheel shows the
  same 8 prizes as the wheel screen, in the same order (`WheelConfig.
  Segments`; the screen paints them in its own bright faces; players who
  can't buy capsules see their substitute prize's icon), and when you
  spin it lands on your own result (client-side, `WheelController`), so
  it never promises a prize the wheel can't give. Its segments are equal
  like the screen's; the odds are on the screen.

### 2.6a Golem capsules: what the game does (step 7)

Three capsules wake random golems (`CapsuleConfig`): **Stone** and
**Crystal** for coins, **Royal** for Robux (`RoyalCapsule1/3/10`, still
placeholder ids). The code (`CapsuleService`, `CapsuleController`,
`CapsuleView`) follows these rules:

- **Exact odds before every open.** The capsule screen lists every golem
  of the selected capsule with its own chance in percent
  (`CapsuleConfig.odds`, three significant digits, never rounded to 0),
  its rarity and its bonus, next to the OPEN x1 / x3 / x10 buttons. With
  Triple Lucky running, the list shows the boosted odds (marked "x3") and
  says so; the opening screen says "TRIPLE LUCKY ODDS" (and, at its end,
  "Triple Lucky ended: normal odds now" when OPEN AGAIN would use the
  normal odds). The CapsuleStall's odds board in town shows each rarity's
  total chance in big text and says that each golem's own odds are in the
  capsule menu (filled on each player's screen with that player's odds).
- **The odds shown are the odds rolled.** Every open sends which odds its
  screen showed (normal or Triple Lucky); the server rolls exactly those,
  or refuses with "The odds just changed: check them and open again" (and
  sends the new state) when they no longer hold, for example when the boost
  ended more than 3 seconds ago. A screen that already shows the normal
  odds in the boost's last 1.5 seconds (the server's clock counts whole
  seconds) gets those normal odds, not a refusal. A coin open never gets
  better or worse odds than the ones on the screen.
- **Royal capsules (Robux) are paid random items.** Their tab is hidden for
  players whose `ArePaidRandomItemsRestricted` is true, and while that
  answer isn't known yet (`Policy.prefetch` asks on join and retries); the
  server answers a request from such a player with PurchasePrompt
  "Restricted" and never prompts. Each of OPEN 1 / 3 / 10 is decided on
  its own: while its product id is a placeholder (0), **or** step 8's
  ProcessReceipt handler isn't registered yet (it calls
  `Receipts.setReady(true)`, also reachable as
  `CapsuleService.setReceiptsReady(true)`), the button is greyed "Coming
  soon" and the server answers "ComingSoon" without prompting, so nobody
  can pay Robux in the game before it can deliver. The same one gate
  (src/server/Receipts.luau, ReplicatedStorage attribute `ReceiptsReady`)
  holds back every other Robux sale too: the Triple / Hexa Lucky packs and
  the Heartfire / Starbreaker passes (BoostService.promptPurchase) answer
  "ComingSoon" and their cards show COMING SOON / "20 R$ • SOON" until
  step 8 grants receipts and passes; with none of the three live
  the tab shows the odds and "Coming soon!" instead of buttons.
  **The gate only blocks in-game prompts.** Game passes (`BigPass`,
  `Podiums`, `OfflineExtension`, `TrainExpress`, `EnchantHeartfire`,
  `EnchantStarbreaker`) are also sold on the game page's **Store tab**
  (website and app) with no prompt at all, and nothing grants a pass before
  step 8 (`Perks` are set by the coming MonetizationService, the Mythic
  enchant passes are granted by step 8). So create the passes and products
  to get their ids, but keep every game pass **Off Sale** (Creator
  Dashboard → Monetization → Passes → Sales) until step 8 is live and calls
  `Receipts.setReady(true)`. Developer products go through `ProcessReceipt`
  (also step 8); if the Dashboard offers to list one on the Store tab, leave
  that off until then too. Nothing is
  ever granted outside ProcessReceipt (step 8: `CapsuleService.grantProduct`).
  A receipt rolls Triple Lucky when the prompt the player saw had it **or**
  it runs when the receipt is processed, so a purchase never gets worse
  odds than any screen showed, whichever way it was bought (our prompt,
  the Store tab, a prompt opened elsewhere). A boosted prompt is kept at
  most 2 minutes past the boost's end, so a later purchase uses the odds
  of its own moment, and a prompt closed without buying is forgotten at
  once (`PromptProductPurchaseFinished`). Golems bought with Robux are
  saved with `Paid = true` (for the trading rules) and come **locked**: a
  locked golem can't be deleted, and the delete box says "bought with
  Robux: Robux are not refunded" when the player unlocks and deletes one.
- **Coin capsules: paid random items** since the owner turned coin packs
  on (2026-10-20, `MonetizationConfig.CoinPacksEnabled = true`):
  `CapsuleConfig.isPaidRandom` is true for them, the client hides the
  Stone and Crystal tabs for restricted players (or players whose policy
  isn't known), the server refuses their opens ("Restricted"), the exact
  odds are shown before every open, and the questionnaire answer for paid
  random items (1.1 #12) must be Yes.
  Robux items that only raise how fast a player earns coins (the income
  and podium game passes, Royal golems with an Income or Sell value bonus)
  are **not** treated as buying coins: the coins still have to be earned
  by playing, as most games read the rule. This judgment call changes if
  a Robux item ever pays out coins directly (a coin pack, a pass or
  product that grants a lump of coins, a "skip" that converts Robux into
  coins): then `MonetizationConfig.coinsBuyable()` must return true
  (today it reads `CoinPacksEnabled`) so coin capsules count as paid
  random items.
- **Free capsules** (the daily wheel's prize) aren't paid and always open.
- **No pressure:** a capsule only opens after the player presses OPEN; a
  full golem inventory (60) refuses the open before anything is spent (and
  a Royal prompt is refused with "Your golem inventory is full: delete
  some golems first"); every refusal names the reason.

### 2.7 Group join and like rewards: what is safe

What we could verify:

- Roblox gives games an official, native **group join prompt**
  (`GroupService:PromptJoinAsync`) and a membership check
  (`Player:IsInGroupAsync`). No Roblox doc we found forbids a one-time,
  optional reward for joining the game's group, and it is common practice.
- We found **no official rule that allows rewarding likes or favorites**.
  Likes can't be verified by any API. The DevForum consensus is that
  rewarding likes or favorites manipulates the rating system and goes
  against Community Standards. A Roblox Community Standards section titled
  "Misusing Roblox Systems" exists, but we could not read its exact text from
  here.

**So, for Terra Forge:**

| Reward | Verdict | How |
|---|---|---|
| **Join the game's Roblox group → 500 coins once** (**TODO:** create the group, put its id in config) | **OK, with care** | A small "Join our group" button in the menu, with no pop-up on join. Open `GroupService:PromptJoinAsync` (it runs on the player's client) only when the button is tapped. Grant only after `Player:IsInGroupAsync` returns true on the **server** (`GroupClaim` remote), and save `GroupRewardClaimed`. The server caches `IsInGroupAsync` results, so don't call it on the server before the player taps "Claim"; an early `false` can stick for the rest of the session. If the check still says no, say "Rejoin the game to claim your reward". Keep the reward small; it must never unlock content or be needed to progress. No nagging, no repeat pop-ups, no "you must join to play" screens. If the prompt returns `None` (the player closed it or can't join), just close it quietly. |
| **Like / thumbs-up reward** | **Don't** | Drop the "like reward" from the plan. It's fine to show *one* gentle, unrewarded message after the tutorial: "Enjoying Terra Forge? A thumbs-up on the game page helps us a lot!" It must be easy to close and shown once. |
| **Favorite reward** | **Don't** | Same reason as likes. |
| **"Code for everyone at X likes"** | **Skip** | One DevForum reply calls this OK, but it still ties a reward to likes. Not worth the risk. |
| **Discord / YouTube / X follow rewards** | **Never** | Off-platform, and you can't mention them in the game anyway (2.3). |
| **Inviting friends** | OK, using Roblox's own tools | Not in the design today. Roblox has built-in invite prompts and a "Friend referral system" that rewards players for bringing in new players. Use those features only as documented. **TODO:** read the "Player invite prompts" and "Friend referral system" docs before adding this. |

**TODO (before launch):** read Roblox Community Standards (link at the end),
especially the spam and "Misusing Roblox Systems" sections, and the new Terms
of Use (effective 1 November 2026). Check that nothing now covers group-join
rewards. If anything is unclear, remove the coin reward and keep only the
group button.

### 2.8 Original IP

- Never mention other games, brands or creators by name in player-facing text:
  title, description, thumbnails, icons, badge and pass names, signs, NPC lines,
  update notes. Terra Forge's names (Emberfall, Heartstone, Pell's Trading Post,
  Forgemaster Ulda…) are all original.
- Internal docs (`PLAN.md`) and two code comments mention the games that
  inspired the feel: `src/shared/Builders/Geo.luau` (replicated to clients)
  and `src/server/Services/CarryService.luau` (server only). Players never
  see these, but a comment-cleanup pass is an easy optional **TODO**.
- **TODO:** before launch, search Roblox for existing games named
  "Terra Forge" so the name isn't confused with someone else's game.
- Only use sounds, meshes and images you made, Roblox-made assets, or assets
  whose license allows it (see `SoundConfig.luau`).

### 2.9 Age guidelines and audience (Roblox Kids & Select)

Roblox sorts players into **Roblox Kids** (5–8), **Roblox Select** (9–15) and
standard Roblox (16+). With a **Minimal** label, Terra Forge *can* reach all
of them, but only after these steps:

1. **Before going public at all** (16+ audience), and also before you can use
   any **Limited** audience (Playtesters, Friends, Community Members): your
   account must be in good standing and at least 2 days old, you must
   complete an age check (face age estimation or government ID), and the
   questionnaire must be submitted.
2. **For Kids and Select (all ages), the creator also needs to:**
   - verify age (government ID if you are 18+; face age estimation if under 18),
   - turn on **2-step verification**,
   - **either** keep Roblox Plus or Roblox Premium active for 2 months in a
     row, **or** pay a one-time, refundable per-game fee (1,000 Robux at the
     time of writing; read the refund rules on the publishing page). If you
     use Plus/Premium, it has to be active whenever you publish a new version
     for all ages; the game stays published if it runs out later. **TODO:**
     choose which.
3. **The game is then evaluated:** first it is only available to age-checked
   players aged 16+ (a trial). Roblox then needs about **250 unique plays from
   "highly engaged" players within 60 days**, followed by a safety review.
   You can follow progress in the **Audience Reach** dashboard. An optional
   50,000 Robux (refundable) expedited review exists. It lets you skip the
   wait for the 250 plays (useful for a timed launch), but the game must
   still pass the same safety review.
4. **Group or personal account?** Roblox recommends publishing under a group.
   For a group-owned game, the **group owner's** account must meet all the
   creator requirements above. **TODO:** decide.

**Design rules for young players** (keep them in mind while the shop,
tutorial and daily reward are being built): simple words, no chat needed, no
pushy purchase prompts, no fake urgency (the monthly limited edition has a
real, fixed end date and a calm "ends on" line, never a "last chance!"
rush), and a short, friendly tutorial.

### 2.10 Data and privacy

- **Only gameplay data is saved.** DataStore `TerraForge_PlayerData_v1`, key
  `Player_<UserId>`, contains coins, pickaxes, carry level, upgrades,
  machines (owned and placed), stored items, the Ore Codex, stats, tutorial
  step, daily streak, badge cache, the group-reward flag, the raw forge name
  and purchase ids (`DataTemplate.luau`), plus a session lock (server id and
  time, `ProfileStore.luau`).
- **Never save:** real names, emails, birthdays, IP addresses, device ids,
  chat logs or anything else players type, apart from the forge name.
- **Analytics** (`AnalyticsTracker`, planned): only gameplay events (ore
  mined, tutorial step, shop opened). No free text and no forge names in
  custom fields.
- **Right to be Forgotten (data deletion):** when a player asks Roblox to
  delete their data, you must delete it from your data stores too. Roblox
  sends a daily message listing the requests.
  **TODO:** set up automatic deletion once the game is published:
  Dashboard → your game → **Configure → Data Stores Manager → RTBF Deletion →
  Create Template**:
  - Type: **Standard Key**
  - Data Store: `TerraForge_PlayerData_v1`
  - Key Pattern: `Player_{UserId}` (exactly this capitalisation)
  - Scope: `global`
  The four leaderboards (`LeaderboardConfig`, key = the player's UserId)
  need one template each:
  - Type: **Ordered Key**, Scope: `global`, Key Pattern: `{UserId}`
  - Data Stores: `TF_LB_MoneyPerSec_v1`, `TF_LB_TotalEarned_v1`,
    `TF_LB_Artifacts_v1`, `TF_LB_HoursPlayed_v1`
  When a board's name gets a new `_vN` suffix, add a template for the new
  name too. Add one template per extra data store you create later.
  By hand (a request before the templates exist, or a cheater's score):
  Studio command bar with API access on,
  `require(game.ServerScriptService.Server.Services.LeaderboardService).removeUser(12345)`
  deletes the user's entry from all four boards and hides the user at once
  on every server (a runtime hidden list in the `TF_LB_Hidden_v1` data
  store, key `Hidden`, read on start and every 5 minutes, plus a
  MessagingService message to the running servers), so nobody writes it
  back, even while the user plays; no deploy is needed. A server writes
  no score before it has read that list once (a failed first read is
  tried again within 10-30 seconds), so a server started later can't
  bring a removed user back either.
  `LeaderboardConfig.Hidden` is the same list in code (optional).
  (Studio play sessions read the live boards but never write them.)
- **Testing in Studio:** Roblox warns that Studio access to data stores is
  dangerous for live games. Once the game is live, test in a **separate test
  place/game** or turn the setting off (see section 3).

---

## 3. Experience settings to set

| Setting | Where | Value for Terra Forge |
|---|---|---|
| **Name** | Dashboard → Configure → Basic Info | `Terra Forge` (**TODO:** confirm). No other game names, no "free Robux", no emoji spam. |
| **Description** | Same | **TODO:** write 2–4 friendly lines about mining, cleaning ore by hand, smelting, forging and building your workshop. No links, no "hangout" wording (see 1.1 #9), and no other games' names as keywords (Roblox demotes keyword spam). |
| **Genre** | Dashboard → Configure → Settings | **Simulation → Tycoon**: you build up your own plot with machines and conveyors and sell to grow. Alternative: **Simulation → Sandbox**, only if building the plot becomes the main activity (not Incremental Simulator, see `STORE_PAGE.md`). You can only change genre **once every 3 months**, so choose carefully. **TODO:** pick one. |
| **Devices** | Studio settings → Basic Info → Playable Devices (also asked in the first Publish window) | **Computer: on. Phone: on. Tablet: on. Console: on**: mining, carrying and cleaning already support a gamepad (X grab, RB throw, Y at the Cleaning Station and B to take the ore back out, left stick + A or R2 in cleaning, B to leave). **VR: off.** **TODO:** the shop and other menus aren't built yet; make sure they work with a D-pad too, hide the chat window on console (see 2.5), and test on a real controller and on a phone before launch. If console isn't tested yet, leave it off and add it later. |
| **Audience** | Dashboard → Configure → Settings | Keep **Private** while building (only people with Edit access can join). **Limited → Playtesters** lets testers in, but it already needs the 16+ publishing requirements (age-checked account, questionnaire; see 2.9). Switch to **Public** at launch. |
| **Minimum age / regions** | Audience → Access Settings | No minimum age; all regions on. |
| **Max players per server** | Place settings (server size / max players) | **8**, matching the 8 forge plots and `GameConfig.MaxPlayers = 8`. If these numbers differ, a 9th player would have no plot. |
| **Private servers** | Audience → Access Settings → Allow private servers | **On**, suggested **100 Robux/month** (**TODO:** decide; free is also fine). Changing the price later cancels every existing subscription, so choose once. Private servers can't be combined with paid access, which Terra Forge doesn't use anyway. Private servers don't bypass Forge VIP: the Grotto still checks the pass. |
| **Paid access** | Monetization | **Off.** Terra Forge is free to play. |
| **Allowed gear** | Studio settings → Permissions (if still shown) | **None**: untick all gear types. Gear would break the carry/mining balance. |
| **Comments** | — | We found no current comments toggle for games. Player feedback arrives as ratings and feedback in the Dashboard. **TODO:** if your Dashboard shows a comments option, leave it off unless you will moderate it. |
| **Text chat** | `TextChatService` in Studio (on by default) | **On** (Roblox handles filtering and age groups), except hide the chat window on console (see 2.5). |
| **Allow Strong Language** | Audience → Communication Settings | **Off.** |
| **Voice chat / camera** | Studio settings → Communication | **Off** (not needed). Voice is **on by default** for new games, so switch off **Enable Voice Chat** and **Enable Camera**, then publish. |
| **Enable Studio Access to API Services** | Studio settings → Security | **On only before launch, or in a separate test copy.** It's needed for saving while testing in Studio (`GameConfig.SaveInStudio = true`). After launch, Roblox advises against using it on the live game, because Studio play-tests would write to real player data. **TODO:** at launch, either make a test copy of the game for Studio testing or turn this off. |
| **Allow HTTP Requests** | Studio settings → Security | **Off.** Terra Forge makes no web requests. DataStores and `HttpService:GenerateGUID` (used in `ItemService`) don't need it. |
| **Allow Third Party Sales** | Studio settings → Security | **Off.** We only sell our own passes and products. |
| **Allow Third Party Teleports** | Studio settings → Security | **Off.** No teleports to other games. |
| **LoadStringEnabled** | ServerScriptService property | **Off** (default). |
| **Allow copying** | Places → Permissions | **Off** (the place stays copylocked). |
| **Social links** | Dashboard → Engagement → Social Links | Optional (needs 16+ verification; see 2.3). |
| **Icon & thumbnails** | Dashboard → Configure → Places → start place | **Icon:** square, 512×512. **Thumbnails:** up to 10 images or videos, 16:9, ideally 1920×1080, under 3 MB; keep text away from the bottom edge (the player count covers it). All of them are moderated. **TODO:** use real screenshots of the **launch build**. The files in `docs/screenshots/` (1600×900) are from development builds: only use ones that show features that work at launch (for example, no machines or shop until they exist), and treat `items.jpg` (a lineup of item models) as a showcase, not a scene players see. No fake UI, no other games' art, no "FREE ROBUX" or "ADMIN" text, no misleading promises. Videos must show real gameplay (3 uploads per month). |
| **Badges** | Dashboard → Engagement → Badges | **TODO:** create Welcome, First Ore, First Clean, First Flawless, First Legendary, First Mythic, First Gear, Tutorial Done, Tycoon. 5 badges per game per day are free (then 100 Robux each), so spread these 9 over two days. Images (512×512) and names must follow Community Standards. |
| **Game passes / developer products** | Dashboard → Monetization → Passes / Developer Products | **TODO:** create them and paste the ids into the config (see 2.6). Create the passes and products to get their ids, but keep every game pass **Off Sale** (Dashboard → Monetization → Passes → Sales) until step 8 is live and calls `Receipts.setReady(true)`. The gate only blocks in-game prompts, and passes are also sold on the Store tab (see 2.6a). |

---

## 4. Pre-launch compliance checklist

### Content and label
- [ ] Re-read section 1.1 against the current build. Nothing new (enemies, damage, scary sounds, crates, trading, drawing)?
- [ ] Questionnaire submitted (Configure → Questionnaire); preview shows **Minimal**, no descriptors.
- [ ] Title and description contain no "hangout", other game names, links or misleading claims.
- [ ] Icon, thumbnails, badge, pass and product images are original and honest; thumbnails come from the launch build and only show features that exist.

### Text and safety
- [ ] Forge name: filtered on the server with `FilterStringAsync` + `GetNonChatStringForBroadcastAsync`, both in `pcall`.
- [ ] Forge name changes accepted at most once per minute per player (server cooldown).
- [ ] Filter failure keeps the default sign ("<DisplayName>'s Forge") and never shows the raw text.
- [ ] Forge name filtered again every time it's shown (on owner join); sign back to "Free Plot" when the owner leaves.
- [ ] Name box says "don't use your real name or personal info"; length limit and RichText off.
- [ ] No URLs, Discord/YouTube/X mentions, invite codes or emails anywhere in the game.
- [ ] Nothing in the game asks for personal info.
- [ ] Game fully playable with chat off; voice and camera switched off (they start on); strong language off; chat window hidden on console.

### Monetization
- [ ] One `ProcessReceipt` callback; dedupe by `PurchaseId`; grant only on the server holding the session lock; grant + save before `PurchaseGranted`; `NotProcessedYet` on any failure.
- [ ] Tested: buy a coin pouch, leave right away, rejoin → coins arrive exactly once.
- [ ] Passes: ownership checked on join (in `pcall`, with a retry) and on purchase; perks work as described.
- [ ] Every game pass stayed **Off Sale** until step 8 went live (ProcessReceipt and the pass grants connected, `Receipts.setReady(true)` called); only then put them On Sale (the receipts gate only blocks in-game prompts, and the Store tab sells passes without one).
- [ ] Pass and product descriptions match exactly what the code does; the Forge VIP description lists the Grotto's ore odds in numbers.
- [ ] Purchase prompts only open after a player taps a button; no fake timers or fake discounts; close button easy to find on mobile.
- [ ] Paid random items (Royal and limited capsules, Robux luck packs, Starbreaker): exact odds shown before every buy, odds boosters show the new odds in numbers, hidden where `ArePaidRandomItemsRestricted` is true; questionnaire answered **Yes** once any of them is live.
- [ ] The limited edition's `LimitedGolems.Current.EndsAt` is the real end the owner chose for this launch, and the banner says that date.
- [ ] Coin packs are on (`CoinPacksEnabled = true`): every coin capsule / coin boost / coin odds-booster is treated as a paid random item (hidden where restricted, odds shown).
- [ ] Spin & Win: the wheel's face shows every segment's exact %, the BUY step (before every spin purchase) lists all 8 segments with their % and what each pays, bought and free spins use the same odds, the BUY SPINS panel is hidden and "Buy" refused where `ArePaidRandomItemsRestricted` is true (or unknown), the free daily spin works for everyone; with a full golem inventory a bought spin is refused (kept) and "Buy" says why, a full Ore Pen / inventory shows "pays $X coins instead" in the rows; golems from bought spins are Paid and Locked; the questionnaire says **Yes** for paid random items once `WheelSpins1/5/10` are live.
- [ ] PolicyService wrapper in place (`src/server/Policy.luau`: `pcall`, strict defaults when the call fails, retried).

### Engagement rewards
- [ ] Group reward: button only (no pop-up on join), `PromptJoinAsync` on tap, server `IsInGroupAsync` check only when the player claims, one-time, small, saved flag, never needed to progress.
- [ ] No rewards for likes, favorites, Discord or social follows.
- [ ] Community Standards and the 1 November 2026 Terms of Use re-read; group reward still OK.

### Data and privacy
- [ ] Save data holds only gameplay fields (`DataTemplate.luau`); analytics hold no free text.
- [ ] RTBF deletion template created (`TerraForge_PlayerData_v1`, `Player_{UserId}`, `global`).
- [ ] RTBF **Ordered Key** templates for the four leaderboards (`TF_LB_MoneyPerSec_v1`, `TF_LB_TotalEarned_v1`, `TF_LB_Artifacts_v1`, `TF_LB_HoursPlayed_v1`; `{UserId}`, `global`).
- [ ] Someone checks the daily RTBF message in the Roblox inbox. **TODO:** name the person: __________

### Settings
- [ ] Genre chosen (Simulation → Tycoon, or Sandbox).
- [ ] Devices: Computer, Phone, Tablet on; Console on only if tested (menus work with a D-pad); VR off.
- [ ] Server size 8 = plots = `GameConfig.MaxPlayers`.
- [ ] Private servers on with chosen price (or free).
- [ ] Gear none; HTTP off; third-party sales off; third-party teleports off; copying off.
- [ ] Studio API access: test copy set up, or turned off for the live game.
- [ ] Badges created (5 free per day, so over two days).

### Audience (Kids & Select)
- [ ] Creator account at least 2 days old, in good standing, age-checked.
- [ ] Account verified (government ID if 18+, face age estimation if under 18), 2-step verification on. For a group game: the group owner.
- [ ] Roblox Plus/Premium for 2 months **or** the refundable per-game fee paid.
- [ ] Watching the Audience Reach dashboard after launch (needs about 250 highly engaged plays in 60 days).
- [ ] Set a reminder to resubmit the questionnaire whenever an update changes an answer.

---

## Sources

Checked on 12 October 2026. This tool could not open `create.roblox.com`,
`devforum.roblox.com`, `en.help.roblox.com` or `about.roblox.com` directly.
The Creator Hub pages were read from Roblox's official source repository for
those docs, `github.com/Roblox/creator-docs`, which is what create.roblox.com
is built from (re-checked against the version of 10 October 2026). DevForum
and Help Center pages were read through search results. Pages marked
*(read by hand)* should be opened in a browser before launch.

**Roblox Creator Hub docs**
- Content maturity and compliance (questionnaire, labels, categories): https://create.roblox.com/docs/production/promotion/content-maturity
  (source: https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/promotion/content-maturity.md)
- Roblox Kids and Select (creator requirements, evaluation, chat): https://create.roblox.com/docs/production/publishing/kids-and-select
- Publish games and places (audiences, fees, requirements): https://create.roblox.com/docs/production/publishing/publish-games-and-places
- Configure games (age/region, strong language, copying): https://create.roblox.com/docs/projects/configure-games
- Game genres: https://create.roblox.com/docs/production/publishing/experience-genres
- Text filtering: https://create.roblox.com/docs/ui/text-filtering
- Chat system guidelines (TextChatService required, 1-minute rate limit for signs): https://create.roblox.com/docs/chat/guidelines
- Rate-limited text inputs (example): https://create.roblox.com/docs/chat/examples/rate-limit-public-text-inputs
- Voice chat (on by default, Communication settings): https://create.roblox.com/docs/chat/voice-chat
- Console guidelines (hide the chat window on console): https://create.roblox.com/docs/production/publishing/console-guidelines
- TextService (FilterStringAsync): https://create.roblox.com/docs/reference/engine/classes/TextService
- TextFilterResult (GetNonChatStringForBroadcastAsync): https://create.roblox.com/docs/reference/engine/classes/TextFilterResult
- PolicyService (GetPolicyInfoForPlayerAsync keys): https://create.roblox.com/docs/reference/engine/classes/PolicyService
- GroupService (PromptJoinAsync): https://create.roblox.com/docs/reference/engine/classes/GroupService
- Player (IsInGroupAsync, caching): https://create.roblox.com/docs/reference/engine/classes/Player
- MarketplaceService (ProcessReceipt guarantees, two servers at once): https://create.roblox.com/docs/reference/engine/classes/MarketplaceService
- Monetization overview (presenting products, no pressure, genuine discounts, PolicyService required): https://create.roblox.com/docs/production/monetization
- Paid random items (chance-based monetization, odds disclosure, odds-boosting items): https://create.roblox.com/docs/production/monetization/paid-random-items
- Developer products (ProcessReceipt): https://create.roblox.com/docs/production/monetization/developer-products
- Passes: https://create.roblox.com/docs/production/monetization/passes
- Private servers: https://create.roblox.com/docs/production/monetization/private-servers
- Social media links (16+ rule, no links inside games): https://create.roblox.com/docs/production/promotion/social-media-links
- Promotion overview (invites, social links): https://create.roblox.com/docs/production/promotion
- Friend referral system: https://create.roblox.com/docs/production/promotion/referral-system
- Badges (5 free per day): https://create.roblox.com/docs/production/publishing/badges
- Thumbnails (sizes, video accuracy): https://create.roblox.com/docs/production/publishing/thumbnails
- Game icons: https://create.roblox.com/docs/production/publishing/experience-icons
- Data stores (Studio access warning): https://create.roblox.com/docs/cloud-services/data-stores
- Data store right to be forgotten (deletion templates): https://create.roblox.com/docs/cloud-services/data-stores/right-to-be-forgotten
- RTBF and creators: https://create.roblox.com/docs/production/publishing/RTBF-and-creators
- HTTP service (Allow HTTP Requests): https://create.roblox.com/docs/cloud-services/http-service

**Roblox Help Center / newsroom**
- Roblox Community Standards *(read by hand)*: https://en.help.roblox.com/hc/en-us/articles/203313410-Roblox-Community-Standards
- Roblox Terms of Use *(read by hand)*: https://en.help.roblox.com/hc/articles/115004647846
- Content Maturity Labels (player-facing): https://en.help.roblox.com/hc/en-us/articles/8862768451604-Content-Maturity-Labels
- Advertising Standards (no rewards for ad engagement): https://en.help.roblox.com/hc/en-us/articles/13722260778260-Advertising-Standards
- Age checks required to chat (January 2026): https://about.roblox.com/newsroom/2026/01/roblox-age-checks-required-to-chat
- Roblox Kids and Select accounts (April 2026): https://about.roblox.com/newsroom/2026/04/introducing-roblox-kids-and-select-accounts

**Roblox DevForum**
- Updates to the Roblox Terms of Use [November 2026] *(read by hand)*: https://devforum.roblox.com/t/updates-to-the-roblox-terms-of-use-november-2026/4907620
- Social hangout clarification thread: https://devforum.roblox.com/t/request-for-clarification-on-social-hangout-element-in-maturity-compliance-questionnaire/4100104
- Rewarding likes/favorites (community answers, not official policy): https://devforum.roblox.com/t/is-rewarding-players-for-liking-favoriting-a-game-allowed/2926286
- "The issue of bribing players for likes" (2026 discussion): https://devforum.roblox.com/t/the-issue-of-bribing-players-for-likes/4495969
