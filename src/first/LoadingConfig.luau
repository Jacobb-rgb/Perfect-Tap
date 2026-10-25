--[[
	The loading screen's rules (LoadingScreen.client.luau draws it with
	LoadingView). ReplicatedFirst runs before ReplicatedStorage arrives, so
	nothing here may require the shared modules: the few world values are
	copied (tests/LoadingScreen.spec.luau checks they still match).

	Progress: five stages, each 0..1, weighted (Weights):
	  Game        game:IsLoaded()
	  Character   the player's character has a root part
	  Persistent  Workspace.PersistentLoaded fired (the horizon and the
	              planets), or PersistentGrace seconds passed after the game
	              loaded (the signal can fire before the script listens)
	  Spawn       the spawn area streamed in: RequestStreamAroundAsync
	              returned and the ground under the character is there
	  Assets      ContentProvider's queue drained from its peak
	The screen fades once every stage is done (and MinSeconds passed), at
	MaxSeconds whatever happens, or when the player skips (SkipAfter).
	Then ReplicatedFirst gets the attribute LoadingDone = true
	(src/client/Util/Loading.luau waits on it).
]]

export type State = {
	GameLoaded: boolean,
	Character: boolean,
	Persistent: boolean,
	Spawn: number, -- 0..1
	AssetsLeft: number, -- ContentProvider.RequestQueueSize now
	AssetsPeak: number, -- the largest queue seen
}

export type Layout = {
	Scale: number, -- UIScale on the design canvas
	Canvas: Vector2, -- the screen in design units
	Margin: number, -- design units kept clear at the edges (the TV safe area on consoles)
	SkipHeight: number, -- design units: never under MinTouch pt on touch screens
	TextBoost: number, -- the bottom block's size factor (bigger text on small touch screens)
	LogoWidth: number,
}

local LoadingConfig = {}

LoadingConfig.Attribute = "LoadingDone"

-- TODO(owner): the TERRA FORGE logo uploaded as a Decal / image
-- (NAHRAJ_DO_ROBLOXU/obchod/logo_terra_forge.png, NAVOD.md step 8). 0 = the
-- text logo in the same style (stone TERRA, molten FORGE, crossed hammers).
LoadingConfig.Logo = { Id = 0 }

-- simple English, only what the game has today
LoadingConfig.Tips = {
	"Clean your ore by hand to raise its grade. Flawless sells best!",
	"Put your best ores on podiums. They earn coins every second.",
	"Throw ore into the hopper at the Mine Station. Your train takes it home.",
	"A better blaster breaks tougher rocks. Earn coins and visit the Blaster Vault.",
	"Machines, belts and power turn your ore into ingots while you mine.",
	"Buy the next blaster level in the Blaster Vault.",
	"Press BASE, LOBBY or VAULT at the top to travel fast.",
	"Every ore can be mined without a game pass.",
	"Golems from capsules follow you around. Each one gives you a bonus!",
	"Spin the free wheel in town once every day.",
}

LoadingConfig.TipEvery = 4 -- seconds per tip
LoadingConfig.SkipAfter = 3 -- seconds before Skip shows
LoadingConfig.MinSeconds = 1.2 -- never just a flash
LoadingConfig.MaxSeconds = 12 -- the hard cap: the game shows whatever has loaded
LoadingConfig.PersistentGrace = 4 -- seconds after the game loaded that count as "persistent loaded"
LoadingConfig.FadeTime = 0.5
LoadingConfig.AssetsReady = 4 -- a queue this short counts as loaded (sounds trickle in all game long)
LoadingConfig.StreamTimeout = 8 -- RequestStreamAroundAsync's own time-out
LoadingConfig.GroundProbe = 60 -- studs the ground check looks down from the character

-- Copied from WorldLayout.SpawnPoint (the town spawn) and
-- Workspace.StreamingMinRadius (default.project.json): the spec checks them.
-- 112 (96 at 12x12 plots): a phone low on memory keeps the whole yard, out to
-- its far corners by the rail (~107 studs), while standing at the plot front (PlotService.spec).
LoadingConfig.SpawnPoint = Vector3.new(0, 0, 26)
LoadingConfig.StreamRadius = 112

LoadingConfig.Weights = { Game = 0.25, Character = 0.15, Persistent = 0.15, Spawn = 0.3, Assets = 0.15 }

-- the design canvas (1280 x 720 at Scale 1) and the touch minimum (pt)
LoadingConfig.Design = Vector2.new(1280, 720)
LoadingConfig.MinTouch = 44
LoadingConfig.SkipDesignHeight = 56
LoadingConfig.MinTipPt = 15

-- The logo's content id, or nil for the text logo.
function LoadingConfig.logoId(): string?
	local id = LoadingConfig.Logo.Id
	if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
		return nil
	end
	return "rbxassetid://" .. string.format("%d", id)
end

function LoadingConfig.newState(): State
	return { GameLoaded = false, Character = false, Persistent = false, Spawn = 0, AssetsLeft = 0, AssetsPeak = 0 }
end

-- The assets stage: how much of the largest queue seen has drained.
function LoadingConfig.assets(state: State): number
	if state.AssetsLeft <= LoadingConfig.AssetsReady then
		return 1
	end
	local peak = math.max(state.AssetsPeak, state.AssetsLeft, 1)
	return math.clamp(1 - state.AssetsLeft / peak, 0, 1)
end

-- Weighted progress 0..1.
function LoadingConfig.progress(state: State): number
	local w = LoadingConfig.Weights
	local total = w.Game + w.Character + w.Persistent + w.Spawn + w.Assets
	local sum = (if state.GameLoaded then w.Game else 0)
		+ (if state.Character then w.Character else 0)
		+ (if state.Persistent then w.Persistent else 0)
		+ math.clamp(state.Spawn, 0, 1) * w.Spawn
		+ LoadingConfig.assets(state) * w.Assets
	return math.clamp(sum / total, 0, 1)
end

-- Every stage done?
function LoadingConfig.ready(state: State): boolean
	return state.GameLoaded and state.Character and state.Persistent and state.Spawn >= 1 and state.AssetsLeft <= LoadingConfig.AssetsReady
end

-- Time to fade? (`elapsed` seconds since the screen showed)
function LoadingConfig.shouldFinish(state: State, elapsed: number, skipped: boolean): boolean
	if skipped or elapsed >= LoadingConfig.MaxSeconds then
		return true
	end
	return elapsed >= LoadingConfig.MinSeconds and LoadingConfig.ready(state)
end

function LoadingConfig.canSkip(elapsed: number): boolean
	return elapsed >= LoadingConfig.SkipAfter
end

-- The tip to show `elapsed` seconds in, starting from tip `first`.
function LoadingConfig.tipIndex(first: number, elapsed: number): number
	local n = #LoadingConfig.Tips
	return (first - 1 + math.floor(math.max(elapsed, 0) / LoadingConfig.TipEvery)) % n + 1
end

-- The displayed bar eases toward the real progress and never goes back.
function LoadingConfig.smooth(shown: number, target: number, dt: number): number
	if target <= shown then
		return shown
	end
	return math.min(target, shown + (target - shown) * math.min(1, dt * 6) + dt * 0.05)
end

-- The layout for a `viewport` in pt. `touch`: a phone or tablet; `tenFoot`: a console on a TV.
function LoadingConfig.layout(viewport: Vector2, touch: boolean, tenFoot: boolean): Layout
	local design = LoadingConfig.Design
	local vx, vy = math.max(viewport.X, 1), math.max(viewport.Y, 1)
	local scale = math.clamp(math.min(vx / design.X, vy / design.Y), 0.4, 1.6)
	local canvas = Vector2.new(vx / scale, vy / scale)
	local margin = if tenFoot then math.max(canvas.X, canvas.Y) * 0.05 else 24
	local skip = LoadingConfig.SkipDesignHeight
	local boost = 1
	if touch then
		skip = math.max(skip, math.ceil(LoadingConfig.MinTouch / scale)) -- (UDim offsets are whole numbers)
		-- the tip's 22 design units stay at least ~15 pt
		boost = math.clamp(LoadingConfig.MinTipPt / (22 * scale), 1, 1.6)
	end
	return {
		Scale = scale,
		Canvas = canvas,
		Margin = margin,
		SkipHeight = skip,
		TextBoost = boost,
		LogoWidth = math.min(canvas.X - margin * 2, 860),
	}
end

return LoadingConfig
