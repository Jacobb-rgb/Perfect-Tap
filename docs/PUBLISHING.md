# Publishing TERRA FORGE (V2_PLAN step 8)

The order to take a build from Studio to a public game. It links the detailed docs instead of repeating them:

| Doc | What is in it |
|---|---|
| [STORE_PAGE.md](STORE_PAGE.md) | the page text (title, descriptions EN + CS), genre, keywords, image rules, trailer, update posts |
| [COMPLIANCE.md](COMPLIANCE.md) | the Maturity & Compliance questionnaire answers (section 1), fair monetization and odds (2.6), text filtering, audience rules, **the place settings table (section 3)** and the pre-launch checklist (section 4) |
| [STUDIO_CHECKLIST.md](STUDIO_CHECKLIST.md) | the few things done by hand in Studio |
| [PERF_AUDIT.md](PERF_AUDIT.md) | phone performance numbers and the fixes still open |
| [SERVER_PERF_AUDIT.md](SERVER_PERF_AUDIT.md) | a full 8-player server: CPU loops, network per client, item churn, DataStore budget, top 10 fixes by chat |
| Owner guide (Czech) | `Terra Forge Roblox game KIT/NAHRAJ_DO_ROBLOXU/obchod/NAVOD.md`, with the logo, icons and thumbnails |

## 1. Store art (ready, nothing uploaded)

In `NAHRAJ_DO_ROBLOXU/obchod/` (renders from the game's own preview renderer, light framing only):

| File | Size | Shows | Built from |
|---|---|---|---|
| `logo_terra_forge.png` | 1800x900, transparent | the TERRA FORGE logo (stone TERRA, molten FORGE, crossed-hammers emblem, "MINE • CLEAN • FORGE • BUILD") | rebuilt from the owner's concept logo |
| `icon_1_blaster.png` | 512x512 | a forgekeeper blasting a glowing ore rock in the Quarry | main 54b13c8 (`blaster_fire` scene) |
| `icon_2_forge.png` | 512x512 | THE GREAT FORGE gable | main 54b13c8 |
| `icon_3_crate.png` | 512x512 | the blaster crate burst | main 54b13c8 (crate opening, level 10) |
| `thumb_1_town.png` | 1920x1080 | the town from above: Candy mountains, horizon, plaza, plots | **review/hory-noc** (miners, stream, lanterns: only after it is merged) |
| `thumb_2_mine.png` | 1920x1080 | "BLAST GLOWING ORE": the blaster beam on a Quarry rock | main |
| `thumb_3_factory.png` | 1920x1080 | "BUILD YOUR FACTORY": furnace, robot arm, belts, power | main (`factory` scene) |
| `thumb_4_vault.png` | 1920x1080 | "FORGE EPIC BLASTERS": the Blaster Vault crate opening | main |
| `thumb_5_capsules.png` | 1920x1080 | "COLLECT GOLEM HELPERS": the CAPSULES stall | main stall; **use only once golems are in the live game** (steps 6-7) |

Rules (STORE_PAGE.md section 5, COMPLIANCE.md section 3): only show what the live build has, text away from the
bottom edge (the player count covers it), under 3 MB each (all are), no fake UI, no "FREE ROBUX". Re-render from
the launch build before launch if the game has changed.

## 2. Page text

STORE_PAGE.md sections 1-4 hold the title, the hook, both descriptions (updated 2026-10-18 for the blaster /
36-ore build), genre (**Simulation -> Tycoon**) and the keywords. Before launch, tick every claim against the live
build (STORE_PAGE.md section 0) and update the "What's new" line.

## 3. Settings, rules and launch order

1. **Place settings**: COMPLIANCE.md section 3 (devices, max players **8** = `GameConfig.MaxPlayers` = the 8 plots,
   private servers, no paid access, no gear, voice/camera off, HTTP off, copying off).
2. **Streaming**: `StreamingEnabled = true`, MinRadius 96, TargetRadius 384 (default.project.json); check in Studio
   (Workspace properties) that the published place kept them. Phone budget: tests/PhoneBudget.spec.luau.
3. **Console**: tick Console only after a real controller test of every menu (COMPLIANCE.md section 3 "Devices").
4. **Questionnaire**: COMPLIANCE.md section 1 (no combat, no blood, no paid random items unless odds are shown;
   see 5).
5. **Monetization**: create the passes and products, paste their ids (the blaster chat's
   `NAHRAJ_DO_ROBLOXU/robux_produkty/`). **Any paid random item (e.g. Robux capsules) must show its odds before
   buying** (COMPLIANCE.md 2.6).
6. **Badges**: `NAHRAJ_DO_ROBLOXU/odznaky/NAVOD.md` (11 badges, 5 a day free; ids go into BadgeConfig).
7. **Music**: `NAHRAJ_DO_ROBLOXU/hudba/NAVOD.md` (4 tracks; ids go into MusicConfig).
8. **Sky** (optional): `NAHRAJ_DO_ROBLOXU/obloha_mlecna_draha/NAVOD.md` (6 faces; ids go into LightingConfig.Skybox).
9. **Store art and text**: section 1 and 2 above.
10. **Test with friends**: Audience **Limited -> Playtesters** (needs the 16+ steps, COMPLIANCE.md 2.9), 2-4 people
    on PC + phone (+ controller) for 30 minutes: tutorial, mining, cleaning, podiums, train, factory, vault, saving
    after a rejoin. Fix, republish.
11. **Public**: switch Audience to Public, post the update (STORE_PAGE.md section 7).

Nothing in this branch uploads or publishes anything; every step above is done by the owner.
