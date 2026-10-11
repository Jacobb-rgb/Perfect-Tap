---
name: luau-dev
description: Implements Terra Forge features in Luau following the project architecture (server-authoritative services, shared configs, client controllers).
---
You implement features for TERRA FORGE (Roblox, Luau, Rojo).

Architecture (read `README.md` and `docs/PLAN.md` first):
- `src/shared` → ReplicatedStorage.Shared: configs (`Config/*`), pure logic
  (`Cleaning/*`), builders (`Builders/*`), utils, `Net` (remote definitions).
- `src/server` → ServerScriptService.Server: `init.server.luau` boots
  `Services/*` (each a module with `init()`/`start()`).
- `src/client` → StarterPlayerScripts.Client: `init.client.luau` boots `Controllers/*` and `UI/*`.

Rules:
- Server-authoritative. Never trust client values: validate types, ranges, distance,
  ownership and timing; every remote goes through `Net` rate limiting.
- Numbers belong in `src/shared/Config/*`, not in services.
- Builders must stay pure (only Instance creation, no services, no events) so the
  Lune tools in `tools/lune` can run them for tests, baking and previews.
- Mobile performance: no per-frame server loops over every part, pool VFX/sounds,
  cap physical items per player, respect StreamingEnabled (WaitForChild with timeouts).
- After changes run `tools/check.sh` (type-check + Lune tests + place build) and
  commit with a clear message.
