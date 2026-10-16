# Design v2 – owner's new direction (2026-10-16)

The owner changed core parts of the game. **This overrides docs/GAME_DESIGN.md where they conflict.**
Open questions are at the bottom; once answered, fold everything into GAME_DESIGN.md and a new plan.

## New references (Kenney, all CC0 like the Factory Kit; rebuild their look from Roblox parts)
| Kit | Link | Used for |
|---|---|---|
| Train Kit | https://kenney.nl/assets/train-kit | trains that carry ore from the mine to the player's base |
| Blaster Kit | https://kenney.nl/assets/blaster-kit | **blasters replace pickaxes** (laser mining) |
| Mini Dungeon | https://kenney.nl/assets/mini-dungeon | style reference for decorations in general |
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

### Answers
(not answered yet)
