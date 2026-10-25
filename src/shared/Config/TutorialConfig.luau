--[[
	The first-time tutorial (V2_PLAN step 8: mine -> train -> pen -> clean ->
	podium, in under 3 minutes). TutorialService moves data.Tutorial.Step on
	from the save data and a few server signals, never from what a client
	claims; TutorialController shows the step in a bubble and points a 3D
	guide beam at its target.

	Each step has a `done` check over the save data and the server's Signals.
	The checks are absolute and pass for any later progress too, so a player
	who does things in another order (or an old save) isn't asked again:
	TutorialConfig.advance walks forward past every step that is already
	done. An Optional step is an info hint (steps 6-7: golems, the wheel): it
	waits for the player's "Got it" (TutorialAction "Ack"), or passes by
	itself once its check holds (the player already used the feature).
	UiTarget names a side-menu button (SideMenuView.Entries Id) that an
	on-screen arrow points at, next to the 3D guide.

	Targets (TutorialConfig.Targets) are what the client's guide looks for:
	tagged instances first (nearest, or the one on your own plot), else a
	point from the shared layout while the real thing hasn't streamed in.

	Text is English, short and simple (young players, COMPLIANCE.md 2.9).
	Controls follow docs/STORE_PAGE.md's controls table.
]]

local BaseLayout = require(script.Parent.BaseLayout)
local LobbyLayout = require(script.Parent.LobbyLayout)
local TrainConfig = require(script.Parent.TrainConfig)
local WorldLayout = require(script.Parent.WorldLayout)

local TutorialConfig = {}

export type Data = { [string]: any }

-- What the server knows beyond the save data (TutorialService fills it in).
export type Signals = {
	NearStation: boolean?, -- the character has stood within StationRadius of the Mine Station
	Carrying: number?, -- the CarryCount attribute (CarryService)
}

export type Input = string -- "Mouse" | "Touch" | "Gamepad"

-- "Station" | "Rock" | "Hopper" | "Pen" | "Cleaning" | "Podium" | "Sell" | "Vault" | "Capsules" | "Wheel"
export type Target = string

export type Step = {
	Id: string,
	Title: string,
	Text: string,
	Hint: { [string]: string }?, -- keyed by Input -- the control for this step, per input type
	Target: Target?, -- where the guide points
	EmptyTarget: Target?, -- where it points while you carry nothing (overrides Target)
	Optional: boolean?, -- an info hint: done on "Got it" (or when its check holds)
	UiTarget: string?, -- a side-menu button the on-screen arrow points at (SideMenuView.Entries Id)
	done: (data: Data, signals: Signals) -> boolean,
}

TutorialConfig.StationRadius = 30 -- studs from the Mine Station's platform centre that count as "there"
TutorialConfig.PollSeconds = 1 -- how often the server checks where the player stands (step 1 only)
TutorialConfig.Reward = 250 -- coins for finishing every step (GAME_DESIGN.md: 250); skipping gives none
TutorialConfig.ArriveRadius = 9 -- the guide beam fades out this close to its target (the arrow stays)

---------------------------------------------------------------- data checks

local function stat(data: Data, key: string): number
	local stats = data.Stats
	local value = if type(stats) == "table" then stats[key] else nil
	return if type(value) == "number" and value == value then value else 0
end

local function count(list: any): number
	return if type(list) == "table" then #list else 0
end

local function train(data: Data): { [string]: any }
	return if type(data.Train) == "table" then data.Train else {}
end

-- Mined anything yet?
function TutorialConfig.mined(data: Data): boolean
	return stat(data, "OresMined") > 0 or stat(data, "RocksBroken") > 0
end

-- Ore on the train (waiting at the station or on its way), or a trip done.
function TutorialConfig.loaded(data: Data): boolean
	local t = train(data)
	return count(t.Cargo) > 0 or count(t.TripCargo) > 0 or stat(data, "TrainTrips") > 0
end

-- Ore at home: a train trip unloaded, or the Ore Pen holds ore that came
-- home some other way (carried by hand, a save from before the train). The
-- daily wheel's ore prize goes straight into the pen (Stats.WheelOres), so
-- the pen counts only with more in it than the wheel ever gave: a new
-- player's wheel ore never skips the mine, hopper and train steps.
function TutorialConfig.home(data: Data): boolean
	return stat(data, "TrainTrips") > 0 or count(data.Storage) > stat(data, "WheelOres")
end

function TutorialConfig.cleaned(data: Data): boolean
	return stat(data, "OresCleaned") > 0
end

-- Cleaned more ores than the wheel gave, so one of them came out of a rock:
-- the first four steps' shortcut for an old save (cleaning a wheel ore early
-- teaches cleaning, not mining or the train).
function TutorialConfig.cleanedMined(data: Data): boolean
	return stat(data, "OresCleaned") > stat(data, "WheelOres")
end

-- Something on a podium now, or a podium has earned before.
function TutorialConfig.podium(data: Data): boolean
	if stat(data, "PodiumEarned") > 0 then
		return true
	end
	if type(data.Podiums) == "table" then
		for _, key in data.Podiums do
			if type(key) == "string" and key ~= "" then
				return true
			end
		end
	end
	return false
end

-- Machines beyond the starter kit (placed or still in the inventory).
function TutorialConfig.machinesBought(data: Data, starterCount: number): boolean
	if count(data.PlacedMachines) > starterCount then
		return true
	end
	if type(data.MachineInventory) == "table" then
		for _, n in data.MachineInventory do
			if type(n) == "number" and n > 0 then
				return true
			end
		end
	end
	return false
end

TutorialConfig.StarterMachines = 2 -- MachineData.StarterKit: Furnace + Crusher (the Cleaning Station is the yard's)

-- Woke a golem (a capsule opened, or one is owned).
function TutorialConfig.golems(data: Data): boolean
	local golems = data.Golems
	local owned = if type(golems) == "table" then golems.Owned else nil
	return stat(data, "CapsulesOpened") > 0 or count(owned) > 0
end

-- Spun the daily wheel at least once.
function TutorialConfig.spun(data: Data): boolean
	return stat(data, "WheelSpins") > 0
end

-- Sold something, or bought a machine.
function TutorialConfig.grown(data: Data): boolean
	return stat(data, "ItemsSold") > 0 or TutorialConfig.machinesBought(data, TutorialConfig.StarterMachines)
end

function TutorialConfig.blaster(data: Data): boolean
	local level = data.BlasterLevel
	return (type(level) == "number" and level >= 2) or stat(data, "BlastersForged") > 0 or stat(data, "BlastersBought") > 0
end

---------------------------------------------------------------- the steps

local M = TutorialConfig

-- Has the player built a Platform (the "Build upward" hint passes by itself)?
function TutorialConfig.hasPlatform(data: Data): boolean
	local placed = data.PlacedMachines
	if type(placed) ~= "table" then
		return false
	end
	for _, entry in placed do
		if type(entry) == "table" and entry.Id == "Platform" then
			return true
		end
	end
	return false
end

TutorialConfig.Steps = {
	{
		Id = "Station",
		Title = "To the mine!",
		Text = "Walk to the Mine Station down in the quarry.",
		Target = "Station",
		done = function(data: Data, signals: Signals): boolean
			return signals.NearStation == true or M.mined(data) or M.loaded(data) or M.home(data) or M.cleanedMined(data)
		end,
	},
	{
		Id = "Mine",
		Title = "Blast a rock",
		Text = "Blast a rock with your blaster, then grab the dirty ore.",
		Hint = { Mouse = "Click a rock · F grabs", Touch = "Tap a rock · tap Grab", Gamepad = "R2 blasts · X grabs" },
		Target = "Rock",
		done = function(data: Data, signals: Signals): boolean
			return (signals.Carrying or 0) > 0 or M.loaded(data) or M.home(data) or M.cleanedMined(data)
		end,
	},
	{
		Id = "Load",
		Title = "Load the train",
		Text = "Throw the ore into the big hopper at the station.",
		Hint = { Mouse = "Hold Q, then let go", Touch = "Hold Throw, then let go", Gamepad = "Hold R1, then let go" },
		Target = "Hopper",
		done = function(data: Data, _signals: Signals): boolean
			return M.loaded(data) or M.home(data) or M.cleanedMined(data)
		end,
	},
	{
		Id = "Train",
		Title = "Off it goes!",
		Text = "The train takes your ore home to your Ore Pen. Go to your base!",
		Hint = { Mouse = "BASE at the top takes you home", Touch = "Tap BASE at the top", Gamepad = "D-pad down, then BASE" },
		Target = "Pen",
		done = function(data: Data, _signals: Signals): boolean
			return M.home(data) or M.cleanedMined(data)
		end,
	},
	{
		Id = "Clean",
		Title = "Clean your ore",
		Text = "Take an ore out of your Ore Pen and clean it at the Cleaning Station.",
		Hint = {
			-- the pen's "Open Pen" is the second prompt (G / B), the station's "Clean Ore" the main one (E / Y)
			Mouse = "G opens the pen · E cleans it",
			Touch = "Tap the buttons that pop up",
			Gamepad = "B opens the pen · Y cleans it",
		},
		Target = "Cleaning",
		EmptyTarget = "Pen",
		done = function(data: Data, _signals: Signals): boolean
			return M.cleaned(data) or M.podium(data)
		end,
	},
	{
		Id = "Podium",
		Title = "Show it off",
		Text = "Put your clean ore on a podium. It earns coins every second!",
		Hint = { Mouse = "E at the podium", Touch = "Tap Place at the podium", Gamepad = "Y at the podium" },
		Target = "Podium",
		done = function(data: Data, _signals: Signals): boolean
			return M.podium(data)
		end,
	},
	{
		Id = "Grow",
		Title = "Grow your forge",
		Text = "Sell ore at Tobin's stall, or buy a machine at the Tech shop.",
		Target = "Sell",
		done = function(data: Data, _signals: Signals): boolean
			return M.grown(data)
		end,
	},
	{
		Id = "Blaster",
		Title = "A stronger blaster",
		Text = "Earn coins, then buy a better blaster at the Blaster Vault.",
		Target = "Vault",
		done = function(data: Data, _signals: Signals): boolean
			return M.blaster(data)
		end,
	},
	-- steps 6-7 hints (GOT IT, or done once the player has used the feature)
	{
		Id = "Golems",
		Title = "Golem helpers",
		Text = "Golems follow you and help you earn. Wake one from a capsule: GOLEMS in the side menu.",
		Hint = { Mouse = "GOLEMS is on the left", Touch = "Tap MENU, then GOLEMS", Gamepad = "D-pad left, then GOLEMS" },
		Target = "Capsules",
		UiTarget = "Golems",
		Optional = true,
		done = function(data: Data, _signals: Signals): boolean
			return M.golems(data)
		end,
	},
	{
		Id = "Wheel",
		Title = "A free spin",
		Text = "Spin the wheel at the SPIN & WIN chest once a day for a free prize.",
		Hint = {
			Mouse = "Follow the arrow to the chest",
			Touch = "Follow the arrow to the chest",
			Gamepad = "Follow the arrow to the chest",
		},
		Target = "Wheel",
		Optional = true,
		done = function(data: Data, _signals: Signals): boolean
			return M.spun(data)
		end,
	},
	-- platforms (owner's YES, 2026-10-20): GOT IT, or done once a Platform stands on the plot
	{
		Id = "Platforms",
		Title = "Build upward",
		Text = "Out of room? Build a Platform: a Belt Lift carries ore up, a Slide brings it down.",
		Hint = {
			Mouse = "B builds · V: deck or ground",
			Touch = "BUILD, then the DECK button",
			Gamepad = "D-pad up: build, then deck/ground",
		},
		Optional = true,
		done = function(data: Data, _signals: Signals): boolean
			return M.hasPlatform(data)
		end,
	},
} :: { Step }

TutorialConfig.Total = #TutorialConfig.Steps

TutorialConfig.ById = {} :: { [string]: Step }
for _, step in TutorialConfig.Steps do
	assert(TutorialConfig.ById[step.Id] == nil, "duplicate tutorial step " .. step.Id)
	TutorialConfig.ById[step.Id] = step
end

-- The step at an index (nil past the end).
function TutorialConfig.get(index: number): Step?
	return TutorialConfig.Steps[index]
end

-- A saved Step made safe: a whole number in 1 .. Total + 1.
function TutorialConfig.clamp(step: any): number
	if type(step) ~= "number" or step ~= step then
		return 1
	end
	return math.clamp(math.floor(step), 1, TutorialConfig.Total + 1)
end

-- Walks forward from `step` past every step whose check already holds.
-- Stops at an Optional step whose check doesn't hold yet (it waits for "Got it"). Total + 1 = all done.
function TutorialConfig.advance(step: number, data: Data, signals: Signals?): number
	local s = TutorialConfig.clamp(step)
	local known: Signals = signals or {}
	while s <= TutorialConfig.Total do
		local def = TutorialConfig.Steps[s]
		if not def.done(data, known) then
			break
		end
		s += 1
	end
	return s
end

-- Where the guide points for a step (EmptyTarget while the hands are empty).
function TutorialConfig.targetOf(step: Step, carrying: number): Target?
	if step.EmptyTarget and carrying <= 0 then
		return step.EmptyTarget
	end
	return step.Target
end

---------------------------------------------------------------- targets

-- The name over the guide's arrow.
TutorialConfig.TargetNames = {
	Station = "Mine Station",
	Rock = "Rock",
	Hopper = "Hopper",
	Pen = "Ore Pen",
	Cleaning = "Cleaning Station",
	Podium = "Podium",
	Sell = "Tobin's stall",
	Vault = "Blaster Vault",
	Capsules = "Capsule stall",
	Wheel = "SPIN & WIN",
} :: { [string]: string }

-- How high the guide's arrow floats over the target point (studs; ArrowHeight
-- when not listed): over the Mine Station's canopy and sign, not under it.
TutorialConfig.ArrowHeight = 5
TutorialConfig.ArrowHeights = {
	Station = 13,
	Hopper = 9,
	Capsules = 9,
	Wheel = 7,
} :: { [string]: number }

function TutorialConfig.arrowHeight(target: Target): number
	return TutorialConfig.ArrowHeights[target] or TutorialConfig.ArrowHeight
end

-- What the client's guide looks for first (CollectionService tags).
TutorialConfig.Tags = {
	Rock = "Rock", -- MiningService.RockTag (attributes MinBlaster, VipOnly)
	Hopper = "TrainHopper", -- the station's (and the lifts') invisible Intake
	Cleaning = "Machine", -- attribute MachineId "CleaningStation", Owner = your UserId
	Sell = "SellCounter", -- Tobin's counter in the lobby
	Vault = "VaultCounter", -- the Blaster Vault's counter in the lobby (VaultService.Tag)
	Capsules = "CapsuleStall", -- CapsuleService.Tag (a Model in the lobby)
	Wheel = "EmberChest", -- WheelConfig.Tag (the chest at the top of the SPIN & WIN stairs)
} :: { [string]: string }

local function plotFrame(plotId: number?): CFrame?
	for _, plot in WorldLayout.Plots do
		if plot.Id == plotId then
			return WorldLayout.plotCFrame(plot)
		end
	end
	return nil
end

-- A point for a target from the shared layout alone (no instances): the
-- guide uses it while the real thing hasn't streamed in. nil when the layout
-- doesn't say (Rock away from the quarry, the lobby's stall, no plot yet).
function TutorialConfig.layoutPoint(target: Target, plotId: number?): Vector3?
	if target == "Station" then
		return TrainConfig.Station.Platform.Center + Vector3.new(0, 3, 0)
	elseif target == "Hopper" then
		return TrainConfig.Station.Hopper + Vector3.new(0, 3, 0)
	elseif target == "Rock" then
		local q = WorldLayout.Quarry
		return Vector3.new((q.Min.X + q.Max.X) / 2, q.Min.Y + 2, (q.Min.Z + q.Max.Z) / 2)
	elseif target == "Vault" then
		return LobbyLayout.get("BlasterVault").Center + Vector3.new(0, 3, 0)
	end
	local frame = plotFrame(plotId)
	if not frame then
		return nil
	end
	if target == "Pen" then
		return BaseLayout.toWorld(frame, BaseLayout.Pen.PromptPoint).Position
	elseif target == "Podium" then
		return BaseLayout.toWorld(frame, BaseLayout.Podiums[1].Center + Vector3.new(0, 3, 0)).Position
	elseif target == "Cleaning" then
		-- the yard's own station (BaseLayout.CleaningStation); a bought one on the grid may be nearer
		return BaseLayout.toWorld(frame, BaseLayout.CleaningStation.Center + Vector3.new(0, 3, 0)).Position
	end
	return nil
end

-- "3 / 8" for the bubble's step counter.
function TutorialConfig.counter(step: number): string
	return `{math.min(step, TutorialConfig.Total)} / {TutorialConfig.Total}`
end

return TutorialConfig
