--[[
	TutorialService: the first-time tutorial's progress (TutorialConfig, step
	8 of V2_PLAN).

	data.Tutorial = { Step, Done } (DataTemplate). Step is the index of the
	step the player is on (1 .. Total; Total + 1 once all are done). A step
	past Total that isn't Done is a newer build's (more steps): this server
	shows nothing for it and leaves it as it is (docs/SAVE_AUDIT.md #1(b)).
	It only moves on from the save data and server signals, never from a
	client claim:
	  - every DataService.onChanged (and right after the data loads) runs
	    TutorialConfig.advance, which walks past every step whose check holds
	  - Signals the save data doesn't hold: NearStation (a TutorialConfig.
	    PollSeconds loop checks where the character stands, only while the
	    player is on the "Station" step) and Carrying (the CarryCount attribute
	    CarryService sets; its change signal re-runs the check)
	When Step passes Total, Done = true and the player gets TutorialConfig.
	Reward coins (EconomyService.award, source "Tutorial"), but not when the
	steps were all done already the moment the data loaded (an old save that
	had played through them) and never for a skip.

	TutorialAction (Net, rate limited) from the client:
	  "Skip"  Done = true right away (no reward)
	  "Ack"   "Got it" on an Optional (info) step: moves past it; ignored on
	          any other step
	Anything else is ignored. Every change: DataService.changed (State has
	Tutorial in its snapshot) and Net "Tutorial" to the player:
	  { Step, Done, Total, Reward?, How }  How = "Step" | "Done" | "Skip" | "Load"
	(Reward = the coins just paid, on "Done"). Checks wait for the load check:
	a DataService.changed that comes first (another service's load callback)
	is not live progress.

	TutorialService.onStep(cb) for the analytics funnel later:
	cb(player, { Step, Id?, Done, How, CatchUp }) on every change (CatchUp =
	this is the check right after the data loaded).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.TutorialConfig)
local TrainConfig = require(Shared.Config.TrainConfig)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local TutorialService = {}

export type How = "Step" | "Done" | "Skip" | "Load"
export type StepInfo = { Step: number, Id: string?, Done: boolean, How: How, CatchUp: boolean }

local signals: { [Player]: TutorialConfig.Signals } = {}
-- players whose load check ran: a DataService.changed from another service's
-- load callback (the starter kit) must not count as live progress before it
local ready: { [Player]: boolean } = {}
local stepListeners: { (Player, StepInfo) -> () } = {}
-- a saved step is kept up to here (a junk guard: a newer build may have more steps)
local MAX_STEP_KEPT = 99

-- The player's tutorial table, repaired (a whole Step in range, a boolean Done).
local function stateOf(data: { [string]: any }): { Step: number, Done: boolean }
	local t = data.Tutorial
	if type(t) ~= "table" then
		t = { Step = 1, Done = false }
		data.Tutorial = t
	end
	local step = t.Step
	t.Step = if type(step) == "number" and step == step then math.clamp(math.floor(step), 1, MAX_STEP_KEPT) else 1
	t.Done = t.Done == true
	return t
end

local function emit(player: Player, info: StepInfo)
	for _, callback in stepListeners do
		task.spawn(callback, player, info)
	end
end

local function push(player: Player, t: { Step: number, Done: boolean }, how: How, reward: number?)
	Net.fire("Tutorial", player, {
		Step = t.Step,
		Done = t.Done,
		Total = TutorialConfig.Total,
		Reward = reward,
		How = how,
	})
end

local function signalsOf(player: Player): TutorialConfig.Signals
	local s = signals[player]
	if not s then
		s = {}
		signals[player] = s
	end
	return s
end

-- Moves the player to `step` (Total + 1 = all done): the reward, the save, the pushes.
local function moveTo(player: Player, t: { Step: number, Done: boolean }, step: number, catchUp: boolean)
	t.Step = step
	local how: How = "Step"
	local reward: number? = nil
	if step > TutorialConfig.Total then
		t.Done = true
		how = "Done"
		if not catchUp and TutorialConfig.Reward > 0 then
			EconomyService.award(player, TutorialConfig.Reward, "Tutorial")
			reward = TutorialConfig.Reward
		end
	end
	DataService.changed(player)
	if not catchUp then
		push(player, t, how, reward) -- (the load pushes once itself)
	end
	local def = TutorialConfig.get(step)
	emit(player, { Step = step, Id = if def then def.Id else nil, Done = t.Done, How = how, CatchUp = catchUp })
end

-- Re-checks the player's progress. `catchUp` = the first check after the data loaded.
function TutorialService.evaluate(player: Player, catchUp: boolean?)
	if not catchUp and not ready[player] then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local t = stateOf(data)
	if t.Done then
		return
	end
	if t.Step > TutorialConfig.Total then
		-- a newer build's step (it has more): nothing to show or change here
		return
	end
	local s = signalsOf(player)
	s.Carrying = tonumber(player:GetAttribute("CarryCount")) or 0
	local step = TutorialConfig.advance(t.Step, data, s)
	if step ~= t.Step then
		moveTo(player, t, step, catchUp == true)
	end
end

-- Is the player's character near the Mine Station?
function TutorialService.nearStation(player: Player): boolean
	local root = Guard.rootPart(player)
	if not root then
		return false
	end
	local offset = root.CFrame.Position - TrainConfig.Station.Platform.Center
	return offset.Magnitude <= TutorialConfig.StationRadius
end

-- The step the player is on (nil while the data isn't loaded or once done).
function TutorialService.stepOf(player: Player): number?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local t = stateOf(data)
	return if t.Done then nil else t.Step
end

local function poll()
	for _, player in Players:GetPlayers() do
		local step = TutorialService.stepOf(player)
		local def = if step then TutorialConfig.get(step) else nil
		if def and def.Id == "Station" and TutorialService.nearStation(player) then
			signalsOf(player).NearStation = true
			TutorialService.evaluate(player)
		end
	end
end

local function onAction(player: Player, action: any)
	local name = Guard.string(action, 8)
	if name ~= "Skip" and name ~= "Ack" then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local t = stateOf(data)
	if t.Done then
		return
	end
	if name == "Skip" then
		t.Done = true
		DataService.changed(player)
		push(player, t, "Skip")
		local def = TutorialConfig.get(t.Step)
		emit(player, { Step = t.Step, Id = if def then def.Id else nil, Done = true, How = "Skip", CatchUp = false })
		return
	end
	local def = TutorialConfig.get(t.Step)
	if not def or not def.Optional then
		return
	end
	-- past the hint, then on past anything already done
	moveTo(player, t, TutorialConfig.advance(t.Step + 1, data, signalsOf(player)), false)
end

local function watchCarry(player: Player)
	player:GetAttributeChangedSignal("CarryCount"):Connect(function()
		local step = TutorialService.stepOf(player)
		if step then
			TutorialService.evaluate(player)
		end
	end)
end

local function onLoaded(player: Player, data: { [string]: any })
	local t = stateOf(data)
	TutorialService.evaluate(player, true)
	ready[player] = true
	push(player, t, "Load")
end

-- cb(player, { Step, Id?, Done, How, CatchUp }) on every change of a player's tutorial.
function TutorialService.onStep(callback: (Player, StepInfo) -> ())
	table.insert(stepListeners, callback)
end

-- Internals for the Lune tests only (tests/Tutorial.spec.luau).
TutorialService._test = {
	action = onAction,
	loaded = onLoaded,
	poll = poll,
	signals = signalsOf,
	reset = function()
		table.clear(signals)
		table.clear(ready)
	end,
}

function TutorialService.init()
	Net.on("TutorialAction", onAction)
	DataService.onLoaded(onLoaded)
	DataService.onChanged(function(player: Player)
		TutorialService.evaluate(player)
	end)
	Players.PlayerAdded:Connect(watchCarry)
	for _, player in Players:GetPlayers() do
		watchCarry(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		signals[player] = nil
		ready[player] = nil
	end)
end

function TutorialService.start()
	task.spawn(function()
		while true do
			task.wait(TutorialConfig.PollSeconds)
			poll()
		end
	end)
end

return TutorialService
