--[[
	CleaningService: the Cleaning Station (signature minigame), server side.

	Flow:
	1. Raw ore gets onto the station: the owner uses the station prompt while
	   carrying raw ore, or drops/throws a raw chunk into the vise.
	2. The server starts a session with a random seed and tells the client
	   (CleanBegin). The client builds the same pattern from the seed.
	3. The client sends its recorded input (CleanSubmit). The server re-scores
	   it with the shared CleaningScoring code (it never trusts a client grade),
	   sanity-checks the timing, and turns the raw chunk into a clean ore of
	   that grade on the station's output tray.
	Cancelling leaves the ore in the vise; "Take Ore Back" (G / gamepad B)
	gives it back.
	The station has no canAccept, so IntakeService leaves it alone: its own
	vise scan below mounts dropped raw ore. Moving the station carries the
	vise ore along; packing it up (or leaving) stashes it.
	The vise scan (every INTAKE_PERIOD seconds) walks only the stations:
	a set kept by the station's spawned / removed hooks, never every placed
	machine. Its OverlapParams filter is set again only when the Items
	folder changes, and a pass with no empty station does no work.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local CleaningPatterns = require(Shared.Cleaning.CleaningPatterns)
local CleaningScoring = require(Shared.Cleaning.CleaningScoring)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local Discovery = require(script.Parent.Parent.Discovery)
local CleaningGuard = require(script.Parent.Parent.CleaningGuard)
local ItemService = require(script.Parent.ItemService)
local CarryService = require(script.Parent.CarryService)
local MachineService = require(script.Parent.MachineService)

local CleaningService = {}

type Session = {
	Id: string,
	Player: Player,
	Machine: MachineService.PlacedMachine,
	Item: ItemService.ItemRecord,
	OreId: string,
	Seed: number,
	Pattern: CleaningPatterns.Pattern,
	StartedAt: number,
}

local sessions: { [Player]: Session } = {}
local random: Random? = nil -- made on first use (the Lune tests have no Random)
local cleanedCallbacks: { (Player, string, string, number) -> ...any } = {}
-- every Cleaning Station in the world (spawned / removed hooks)
local stations: { [MachineService.PlacedMachine]: boolean } = {}
local INTAKE_PERIOD = 0.3

local sessionStartCallbacks: { (Player) -> ...any } = {}

-- Listeners for a cleaning session starting (HoverboardService gets the player off the board).
function CleaningService.onSessionStart(callback: (Player) -> ...any)
	table.insert(sessionStartCallbacks, callback)
end

-- Listeners: tutorial, badges, analytics. (player, oreId, grade, score)
function CleaningService.onCleaned(callback: (Player, string, string, number) -> ...any)
	table.insert(cleanedCallbacks, callback)
end

local function stationItem(machine: MachineService.PlacedMachine): ItemService.ItemRecord?
	local record = machine.State.Item :: ItemService.ItemRecord?
	if record and record.State == "Machine" and record.Model.Parent then
		return record
	end
	machine.State.Item = nil
	return nil
end

local function updatePrompts(machine: MachineService.PlacedMachine)
	local hasOre = stationItem(machine) ~= nil
	local busy = machine.State.Session ~= nil
	machine.Model:SetAttribute("HasOre", hasOre)
	machine.Model:SetAttribute("Busy", busy)
	local main = machine.State.MainPrompt :: ProximityPrompt?
	local take = machine.State.TakePrompt :: ProximityPrompt?
	if main then
		main.ActionText = if hasOre then "Clean Ore" else "Place Raw Ore"
		main.Enabled = not busy
	end
	if take then
		take.Enabled = hasOre and not busy
	end
end

-- Puts the record into the vise; false when it can't be (no OrePoint, or a
-- record ItemService refuses: a consumed one, security audit #11).
local function mount(machine: MachineService.PlacedMachine, record: ItemService.ItemRecord): boolean
	local orePoint = MachineService.point(machine, "OrePoint")
	if not orePoint then
		return false
	end
	if not ItemService.mount(record, orePoint * CFrame.new(0, -0.55, 0)) then
		return false
	end
	machine.State.Item = record
	updatePrompts(machine)
	return true
end

local function endSession(session: Session)
	sessions[session.Player] = nil
	session.Machine.State.Session = nil
	if session.Machine.Model.Parent then
		updatePrompts(session.Machine)
	end
end

local function startSession(player: Player, machine: MachineService.PlacedMachine)
	if sessions[player] or machine.State.Session then
		return
	end
	local record = stationItem(machine)
	if not record then
		return
	end
	local rng = random or Random.new()
	random = rng
	local seed = rng:NextInteger(1, 2 ^ 30)
	local session: Session = {
		Id = HttpService:GenerateGUID(false),
		Player = player,
		Machine = machine,
		Item = record,
		OreId = record.OreId,
		Seed = seed,
		Pattern = CleaningPatterns.generate(record.OreId, seed),
		StartedAt = os.clock(),
	}
	sessions[player] = session
	machine.State.Session = session
	updatePrompts(machine)
	for _, callback in sessionStartCallbacks do
		task.spawn(callback, player)
	end
	Net.fire("CleanBegin", player, {
		Id = session.Id,
		OreId = session.OreId,
		Seed = seed,
		Station = machine.Model,
	})
end

local function onPrompt(player: Player, machine: MachineService.PlacedMachine)
	if machine.Owner ~= player then
		Net.fire("Notify", player, { Text = "That's not your Cleaning Station.", Kind = "Deny" })
		return
	end
	if machine.State.Session then
		return
	end
	if not stationItem(machine) then
		-- only a chunk really in the hands (CarryService.takeTop skips others too: #11)
		local record = CarryService.takeTop(player, function(r)
			return r.Kind == "Raw" and r.State == "Carried"
		end)
		if not record then
			Net.fire("Notify", player, { Text = "Bring a raw ore chunk to clean it.", Kind = "Info" })
			return
		end
		if not mount(machine, record) then
			return
		end
	end
	startSession(player, machine)
end

local function onTake(player: Player, machine: MachineService.PlacedMachine)
	if machine.Owner ~= player or machine.State.Session then
		return
	end
	local record = stationItem(machine)
	if not record then
		return
	end
	machine.State.Item = nil
	local output = MachineService.point(machine, "Output") or record.Model:GetPivot()
	ItemService.release(record, output)
	CarryService.pickup(player, record)
	updatePrompts(machine)
end

local function makePrompt(
	machine: MachineService.PlacedMachine,
	name: string,
	actionText: string,
	hold: number,
	order: number
): ProximityPrompt
	local base = machine.Model.PrimaryPart :: BasePart
	local attachment = base:FindFirstChild("Prompt") :: Attachment
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = "Cleaning Station"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt.Parent = attachment
	return prompt
end

local function onSubmit(player: Player, sessionId: any, payload: any)
	local session = sessions[player]
	if not session or type(sessionId) ~= "string" or sessionId ~= session.Id then
		return
	end
	-- the session ends whatever happens below (a bad submission can't be retried endlessly)
	endSession(session)
	local machine = session.Machine
	local record = session.Item
	if not machine.Model.Parent or record.State ~= "Machine" or machine.State.Item ~= record then
		Net.fire("CleanResult", player, { Id = sessionId, Ok = false, Reason = "The ore is gone." })
		return
	end
	local elapsed = os.clock() - session.StartedAt
	local result = CleaningScoring.score(session.Pattern, payload)
	if result.Valid and elapsed < GameConfig.CleaningMinSeconds then
		result = { Valid = false, Reason = "too fast" } :: any
	end
	if result.Valid then
		-- Every timestamp must fit inside the real session time, with the steps in order and
		-- the real client's pauses between them (CleaningScoring.fitsSession). So a bot needs
		-- at least as long as a perfect player going through the real client.
		local fits, why = CleaningScoring.fitsSession(payload, elapsed)
		if not fits then
			result = { Valid = false, Reason = why } :: any
		end
	end
	if not result.Valid then
		warn(`[CleaningService] rejected cleaning from {player.Name}: {result.Reason}`)
		Net.fire(
			"CleanResult",
			player,
			{ Id = sessionId, Ok = false, Reason = "Something went wrong. Your ore is still in the vise: try again!" }
		)
		return
	end

	-- scripted runs keep at most Pristine: FLAWLESS needs real hands (CleaningGuard, audit #4)
	local verdict = CleaningGuard.check(payload)
	CleaningGuard.note(player, verdict, result.Grade)
	result.Grade = CleaningGuard.gradeFor(result.Grade, verdict)

	-- success: raw chunk becomes clean ore on the output tray
	machine.State.Item = nil
	ItemService.destroy(record)
	local output = MachineService.point(machine, "Output") or machine.Model:GetPivot()
	local clean = ItemService.spawn({ Kind = "Clean", OreId = session.OreId, Grade = result.Grade }, player.UserId, output)
	updatePrompts(machine)

	local data = DataService.get(player)
	local isNew = false
	if data then
		isNew = Discovery.mark(player, data, session.OreId)
		data.Stats.OresCleaned += 1
		if result.Grade == "Flawless" then
			data.Stats.FlawlessCleans += 1
		end
		DataService.changed(player)
	end
	local value = ItemData.value("Clean", session.OreId, result.Grade)
	Net.fire("CleanResult", player, {
		Id = sessionId,
		Ok = true,
		Grade = result.Grade,
		Score = result.Score,
		Chisel = result.Chisel,
		Scrape = result.Scrape,
		Polish = result.Polish,
		Chips = result.Chips,
		Value = value,
		OreId = session.OreId,
		ItemId = if clean then clean.Id else nil,
		New = isNew,
	})
	for _, callback in cleanedCallbacks do
		task.spawn(callback, player, session.OreId, result.Grade, result.Score)
	end
end

local function onCancel(player: Player, sessionId: any)
	local session = sessions[player]
	if session and sessionId == session.Id then
		endSession(session)
	end
end

-- What one vise scan keeps between passes: the overlap params and the
-- Items folder their filter was last set to.
type IntakeScan = { Params: OverlapParams, Folder: Instance? }

-- A station whose vise is empty and nobody cleans at.
local function waiting(machine: MachineService.PlacedMachine): boolean
	return not machine.Removed and not machine.State.Session and stationItem(machine) == nil
end

--[[
	One vise scan: raw chunks dropped or thrown into an empty vise get
	mounted (owner's items only). Walks the station set only; the filter is
	set again only when the Items folder changed. Returns how many stations
	it looked into.
]]
local function intakePass(scan: IntakeScan): number
	local items = Workspace:FindFirstChild("Items")
	if not items then
		return 0
	end
	local looked = 0
	for machine in stations do
		if machine.Removed then
			stations[machine] = nil
			continue
		end
		if not waiting(machine) then
			continue
		end
		local base = machine.Model.PrimaryPart
		local intake = base and base:FindFirstChild("Intake") :: Attachment?
		if not base or not intake then
			continue
		end
		if scan.Folder ~= items then
			scan.Folder = items
			scan.Params.FilterDescendantsInstances = { items }
		end
		looked += 1
		local size = intake:GetAttribute("IntakeSize") :: Vector3? or Vector3.new(3, 3, 3)
		-- the attachment's WorldCFrame, worked out from the Base (the Lune tests can run it)
		local box = base.CFrame * intake.CFrame
		for _, part in Workspace:GetPartBoundsInBox(box, size, scan.Params) do
			local record = ItemService.fromPart(part)
			if
				record
				and record.State == "Loose"
				and record.Kind == "Raw"
				and record.Owner == machine.Owner.UserId
				and ItemService.isTrusted(record, os.clock())
			then
				-- start right away if the owner is close by
				if mount(machine, record) then
					local root = Guard.rootPart(machine.Owner)
					if root and (root.Position - (base :: BasePart).Position).Magnitude < 22 then
						startSession(machine.Owner, machine)
					end
				end
				break
			end
		end
	end
	return looked
end

local function newScan(): IntakeScan
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	return { Params = params, Folder = nil }
end

local function intakeLoop()
	local scan = newScan()
	local warnedAt = -math.huge
	while true do
		task.wait(INTAKE_PERIOD)
		local ok, err = pcall(intakePass, scan)
		if not ok and os.clock() - warnedAt >= 10 then
			warnedAt = os.clock()
			warn("[CleaningService] vise scan failed: " .. tostring(err))
		end
	end
end

local stationBehaviour: MachineService.Behaviour = {
	spawned = function(machine)
		stations[machine] = true
		local main = makePrompt(machine, "CleanPrompt", "Place Raw Ore", 0, 0)
		local take = makePrompt(machine, "TakePrompt", "Take Ore Back", 0.4, 1)
		-- its own keys (G / gamepad B; F and Y stay "Clean Ore"), and always shown next to
		-- "Clean Ore". No other prompt uses G or B, so one press never fires two prompts.
		take.KeyboardKeyCode = Enum.KeyCode.G
		take.GamepadKeyCode = Enum.KeyCode.ButtonB
		take.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		take.Enabled = false
		machine.State.MainPrompt = main
		machine.State.TakePrompt = take
		main.Triggered:Connect(function(player)
			onPrompt(player, machine)
		end)
		take.Triggered:Connect(function(player)
			onTake(player, machine)
		end)
		updatePrompts(machine)
	end,
	-- packed up or unloaded: the same either way (the vise ore goes to Storage)
	removed = function(machine, _reason)
		stations[machine] = nil
		local session = machine.State.Session :: Session?
		if session then
			endSession(session)
		end
		local record = stationItem(machine)
		if record then
			machine.State.Item = nil
			ItemService.stash(record, nil)
		end
	end,
	-- moved in build mode: the ore in the vise moves with the station
	moved = function(machine)
		local record = stationItem(machine)
		if record then
			mount(machine, record)
		end
	end,
}

function CleaningService.init()
	MachineService.register("CleaningStation", stationBehaviour)
	Net.on("CleanSubmit", onSubmit)
	Net.on("CleanCancel", onCancel)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			endSession(session)
		end
	end)
end

function CleaningService.start()
	task.spawn(intakeLoop)
	-- expire sessions nobody finished
	while true do
		task.wait(10)
		local now = os.clock()
		for _, session in sessions do
			if now - session.StartedAt > GameConfig.CleaningTimeout then
				endSession(session)
				if session.Player.Parent then
					Net.fire("CleanResult", session.Player, { Id = session.Id, Ok = false, Reason = "Cleaning timed out." })
				end
			end
		end
	end
end

-- Is a cleaning session of this player running right now? (Teleport and
-- other systems that must wait for the minigame ask this; stationOf only
-- says where the player's station is.)
function CleaningService.isCleaning(player: Player): boolean
	return sessions[player] ~= nil
end

-- For the tutorial arrow.
function CleaningService.stationOf(player: Player): Model?
	for machine in stations do
		if machine.Owner == player and not machine.Removed then
			return machine.Model
		end
	end
	return nil
end

-- Internals for the Lune tests only (tests/CleaningService.spec.luau).
CleaningService._test = {
	behaviour = stationBehaviour,
	newScan = newScan,
	intakePass = intakePass,
	stations = function(): { MachineService.PlacedMachine }
		local list = {}
		for machine in stations do
			if not machine.Removed then
				table.insert(list, machine)
			end
		end
		return list
	end,
	reset = function()
		table.clear(stations)
	end,
}

local _ = OreData
return CleaningService
