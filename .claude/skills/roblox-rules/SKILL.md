---
name: roblox-rules
description: Check Terra Forge features against Roblox rules (monetization, paid random items, odds, text filtering, rewards, maturity questionnaire, console requirements). Use before building or changing anything with Robux, random rewards (capsules, wheel, luck boosts), player text, trading, social rewards, or publishing settings.
---
# Roblox rules (so the game doesn't get moderated)

Full guide: docs/COMPLIANCE.md (verify against current Roblox docs when unsure; update the doc when rules change).
Design v2 specifics: docs/DESIGN_V2_NOTES.md.

## Must-haves
- **Random rewards** (golem capsules, open x3/x10, daily wheel, luck boosts): show exact odds before buying/spinning;
  paid boosts must show the NEW odds in numbers before purchase. Capsules can be bought with Robux or with coins
  that can be bought with Robux → **paid random items**: check
  `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` and hide/disable them where true;
  answer the Maturity & Compliance questionnaire accordingly.
- **Purchases:** MarketplaceService ProcessReceipt grants only on the server holding the player's ProfileStore session
  lock, records PurchaseId in the profile, saves, then returns PurchaseGranted. Game passes via
  UserOwnsGamePassAsync + PromptGamePassPurchaseFinished. All IDs in one config (placeholders until the owner creates them).
- **Text:** any player-written text shown to others (forge name, trade notes) goes through
  TextService:FilterStringAsync → GetNonChatStringForBroadcastAsync, max one change per minute.
- **Rewards:** no rewards for likes/favorites/follows. Group-join reward only via PromptJoinAsync + server
  IsInGroupAsync when claiming.
- **Trading:** both players confirm a final summary, 3-second countdown, server re-validates ownership, log trades;
  no trading for Robux or off-platform value.
- **Originality:** no copied names, logos, characters (e.g. no Minecraft Iron Golem look), no misleading thumbnails.
- **Offline earnings / AFK:** fine, but don't reward bots with paid items; keep server checks.
