--[[
	PowerController: power cables on the plots and the small info signs on
	your own poles, generators, machines that use power and Detail machines.
	Everything comes from the attributes PowerService sets (Machines/PowerLogic
	encodes the cell lists); no remotes, no input, so it is the same on PC,
	phones and consoles.

	- Cables: for every pole, a Beam from its insulators (the CableL /
	  CableR attachments of the PowerPole model, the nearer one) to each
	  pole in its Links (drawn once per pair) and to each generator or
	  machine in its Feeds (to the top of the model: its Status attachment
	  less STATUS_LIFT, never higher than the insulator, so a tall machine
	  takes the cable in its side). Beams are cheap: a solid dark rubber
	  ribbon, no texture, sagging a little (CurveSize along attachments
	  that point down at the pole and up at the far end). Their client-only
	  attachments sit on the models' Bases, so they move and vanish with
	  the models.
	- Machines are found by the 'Machine' tag (streaming in and out just
	  works) and grouped by their plot's Machines folder. A plot's cables
	  are drawn again (FLUSH_DELAY after the first change, once for any
	  number of changes) when a pole's Links / Feeds change, a machine
	  model arrives or goes (a model rebuilt after an upgrade, a fed machine
	  streaming in), or the plot comes into or out of range. Nothing runs
	  per frame.
	- Your own plot always has its cables; other plots only within
	  OTHER_RANGE studs (checked every SELECT_INTERVAL seconds).
	- Info signs (MachineBillboard.attachInfo: "Network 35/50" on a pole,
	  "+40 power" on a generator, "Power 100%" / "No power 60%" on a machine
	  that uses power (the Robot Arm; processors mostly show the full sign,
	  whose status row says "No power: 60%"), the Detail line of e.g. a
	  Sorter) on your own nearest INFO_MAX such machines within INFO_RANGE
	  (wantsInfo), unless the machine already shows its full sign
	  (MachineFxController), which has the same lines. Refreshed every
	  SELECT_INTERVAL seconds.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineData = require(Shared.Config.MachineData)
local PowerLogic = require(Shared.Machines.PowerLogic)
local MachineBillboard = require(script.Parent.Parent.UI.MachineBillboard)

local PowerController = {}

type Group = {
	Folder: Instance,
	Models: { [Model]: boolean },
	Poles: number, -- pole models in Models
	Made: { Instance }, -- the cables now drawn (drawCables)
	Dirty: boolean,
	Wanted: boolean, -- cables shown (own plot, or near the camera)
}
type Candidate = { Model: Model, Distance: number }

PowerController.CableColor = Color3.fromRGB(34, 31, 33) -- dark rubber
PowerController.CableWidth = 0.16
PowerController.SagPerStud = 0.045 -- studs of sag in the middle per stud of cable
PowerController.MinSag = 0.25
PowerController.MaxSag = 1.6
PowerController.CableName = "PowerCable"

local TAG = "Machine"
local INSULATORS = { "CableL", "CableR" }
local POLE_TOP = 6.5 -- studs above a pole's Base when it has no insulators
local STATUS_LIFT = 1.5 -- the Status attachment sits this far above a model's top
local FALLBACK_TOP = 3 -- top of a model without a Status attachment
local BELOW_INSULATOR = 0.4 -- a feed cable ends at most this far below its insulator
local SEGMENTS = 10
-- a cubic Bezier's middle sinks 3/4 of its control points' drop
local CURVE_PER_SAG = 1 / 0.75
local FLUSH_DELAY = 0.1
local SELECT_INTERVAL = 0.5
local OTHER_RANGE = 160
local INFO_RANGE = 26
local INFO_MAX = 4

-- attachment frames on a Base: X axis (the Beam curve axis) down at the pole, up at the far end
local AXIS_DOWN = CFrame.Angles(0, 0, -math.pi / 2)
local AXIS_UP = CFrame.Angles(0, 0, math.pi / 2)

local groups: { [Instance]: Group } = {}
local groupOf: { [Model]: Group } = {}
local connections: { [Model]: { RBXScriptConnection } } = {}
local signs: { [Model]: MachineBillboard.Refs } = {}
local flushQueued = false

---------------------------------------------------------------- helpers

local function infoOf(model: Model): MachineData.Machine?
	local id = model:GetAttribute("MachineId")
	return if type(id) == "string" then MachineData.ById[id] else nil
end

local function isPole(model: Model): boolean
	local info = infoOf(model)
	return info ~= nil and info.IsPole == true
end

local function cellOf(model: Model): string?
	local x, z = model:GetAttribute("GridX"), model:GetAttribute("GridZ")
	if type(x) == "number" and type(z) == "number" then
		return PowerLogic.cellKey(x, z)
	end
	return nil
end

-- World position of a point given in a part's space (works in Lune too).
local function worldOf(base: BasePart, offset: Vector3): Vector3
	return (base.CFrame * CFrame.new(offset)).Position
end

-- The insulator of a pole nearest a world point: its offset on the pole's Base and its side letter.
local function insulator(base: BasePart, toward: Vector3): (Vector3, string)
	local bestOffset, bestSide, bestDistance = Vector3.new(0, POLE_TOP, 0), "C", math.huge
	for _, name in INSULATORS do
		local attachment = base:FindFirstChild(name)
		if attachment and attachment:IsA("Attachment") then
			local distance = (worldOf(base, attachment.CFrame.Position) - toward).Magnitude
			if distance < bestDistance then
				bestOffset, bestSide, bestDistance = attachment.CFrame.Position, name:sub(-1), distance
			end
		end
	end
	return bestOffset, bestSide
end

-- Where a feed cable ends on a model's Base: on its top, at most `maxY` (world) high.
local function feedOffset(base: BasePart, maxY: number): Vector3
	local status = base:FindFirstChild("Status")
	local top = if status and status:IsA("Attachment") then status.CFrame.Position.Y - STATUS_LIFT else FALLBACK_TOP
	return Vector3.new(0, math.min(top, maxY - base.CFrame.Position.Y), 0)
end

-- How far a cable of this length sags in the middle.
function PowerController.sagOf(length: number): number
	return math.clamp(length * PowerController.SagPerStud, PowerController.MinSag, PowerController.MaxSag)
end

---------------------------------------------------------------- cables

--[[
	Draws the cables of one plot. `models` are the machine models of that
	plot (PowerService attributes on them). Returns every Instance it made
	(Beams, Attachments; all on the models' Bases) for clearCables. A cell
	with no model (not streamed in yet) is skipped.
]]
function PowerController.drawCables(models: { Model }): { Instance }
	local made: { Instance } = {}
	local byCell: { [string]: Model } = {}
	local poles: { Model } = {}
	for _, model in models do
		local cell = cellOf(model)
		if cell and model.PrimaryPart then
			-- a deck machine shares its cell with the platform or a belt under it:
			-- the cable goes to whatever uses power there (or a pole), never to those
			local info = infoOf(model)
			local powered = isPole(model) or (info ~= nil and (info.Power or 0) > 0)
			local existing: Model? = byCell[cell]
			if powered or not existing then
				byCell[cell] = model
			end
			if isPole(model) then
				table.insert(poles, model)
			end
		end
	end
	table.sort(poles, function(a: Model, b: Model): boolean
		local az, bz = a:GetAttribute("GridZ") :: number, b:GetAttribute("GridZ") :: number
		if az ~= bz then
			return az < bz
		end
		return (a:GetAttribute("GridX") :: number) < (b:GetAttribute("GridX") :: number)
	end)

	-- one attachment per Base and name, shared by every cable that uses it
	local points: { [BasePart]: { [string]: Attachment } } = {}
	local function point(base: BasePart, name: string, offset: Vector3, axis: CFrame): Attachment
		local list = points[base]
		if not list then
			list = {}
			points[base] = list
		end
		local attachment = list[name]
		if not attachment then
			local a = Instance.new("Attachment")
			a.Name = name
			a.CFrame = CFrame.new(offset) * axis
			a.Parent = base
			table.insert(made, a)
			list[name] = a
			attachment = a
		end
		return attachment
	end
	local function cable(fromBase: BasePart, from: Attachment, to: Attachment, length: number)
		local beam = Instance.new("Beam")
		beam.Name = PowerController.CableName
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.Color = ColorSequence.new(PowerController.CableColor)
		beam.Transparency = NumberSequence.new(0)
		beam.Width0 = PowerController.CableWidth
		beam.Width1 = PowerController.CableWidth
		beam.FaceCamera = true
		beam.Segments = SEGMENTS
		beam.LightInfluence = 1
		beam.LightEmission = 0
		local curve = PowerController.sagOf(length) * CURVE_PER_SAG
		beam.CurveSize0 = curve
		beam.CurveSize1 = curve
		beam.Parent = fromBase
		table.insert(made, beam)
	end

	local drawnLinks: { [string]: boolean } = {}
	for _, pole in poles do
		local base = pole.PrimaryPart :: BasePart
		local myCell = cellOf(pole) :: string
		for _, cell in PowerLogic.decodeCells(pole:GetAttribute("Links")) do
			local key = PowerLogic.cellKey(cell.X, cell.Z)
			local other = byCell[key]
			local pair = if myCell < key then myCell .. "|" .. key else key .. "|" .. myCell
			if not other or other == pole or not isPole(other) or drawnLinks[pair] then
				continue
			end
			drawnLinks[pair] = true
			local otherBase = other.PrimaryPart :: BasePart
			local fromOffset, fromSide = insulator(base, otherBase.CFrame.Position)
			local toOffset, toSide = insulator(otherBase, base.CFrame.Position)
			local from = point(base, "PowerDown" .. fromSide, fromOffset, AXIS_DOWN)
			local to = point(otherBase, "PowerUp" .. toSide, toOffset, AXIS_UP)
			cable(base, from, to, (worldOf(base, fromOffset) - worldOf(otherBase, toOffset)).Magnitude)
		end
		for _, cell in PowerLogic.decodeCells(pole:GetAttribute("Feeds")) do
			local target = byCell[PowerLogic.cellKey(cell.X, cell.Z)]
			if not target or target == pole then
				continue
			end
			local targetBase = target.PrimaryPart :: BasePart
			local fromOffset, fromSide = insulator(base, targetBase.CFrame.Position)
			local fromWorld = worldOf(base, fromOffset)
			local toOffset = feedOffset(targetBase, fromWorld.Y - BELOW_INSULATOR)
			local from = point(base, "PowerDown" .. fromSide, fromOffset, AXIS_DOWN)
			local to = point(targetBase, "PowerIn", toOffset, AXIS_UP)
			cable(base, from, to, (fromWorld - worldOf(targetBase, toOffset)).Magnitude)
		end
	end
	return made
end

-- Removes what drawCables made.
function PowerController.clearCables(made: { Instance })
	for _, instance in made do
		instance:Destroy()
	end
	table.clear(made)
end

---------------------------------------------------------------- plots

local function localUserId(): number?
	local player = Players.LocalPlayer
	return if player then player.UserId else nil
end

local function isOwn(model: Model): boolean
	local me = localUserId()
	return me ~= nil and model:GetAttribute("Owner") == me
end

local function focusPosition(): Vector3?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

local function flush()
	flushQueued = false
	for folder, group in groups do
		if not group.Dirty then
			continue
		end
		group.Dirty = false
		PowerController.clearCables(group.Made)
		if group.Wanted and group.Poles > 0 then
			local list: { Model } = {}
			for model in group.Models do
				if model.Parent == folder then
					table.insert(list, model)
				end
			end
			local ok, made = pcall(PowerController.drawCables, list)
			if ok then
				group.Made = made
			else
				warn("[PowerController] cables failed: " .. tostring(made))
			end
		end
		if next(group.Models) == nil and #group.Made == 0 then
			groups[folder] = nil
		end
	end
end

local function markDirty(group: Group)
	group.Dirty = true
	if not flushQueued then
		flushQueued = true
		task.delay(FLUSH_DELAY, flush)
	end
end

local function register(instance: Instance)
	if not instance:IsA("Model") or groupOf[instance :: Model] then
		return
	end
	local model = instance :: Model
	local folder = model.Parent
	if not folder then
		return
	end
	local group = groups[folder]
	if not group then
		group = { Folder = folder, Models = {}, Poles = 0, Made = {}, Dirty = false, Wanted = isOwn(model) }
		groups[folder] = group
	end
	local g = group :: Group
	g.Models[model] = true
	groupOf[model] = g
	if isOwn(model) then
		g.Wanted = true
	end
	if isPole(model) then
		g.Poles += 1
		local function changed()
			markDirty(g)
		end
		connections[model] = {
			model:GetAttributeChangedSignal("Links"):Connect(changed),
			model:GetAttributeChangedSignal("Feeds"):Connect(changed),
		}
	end
	if g.Poles > 0 then
		markDirty(g)
	end
end

local function unregister(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local model = instance :: Model
	local group = groupOf[model]
	groupOf[model] = nil
	local list = connections[model]
	local wasPole = list ~= nil
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		connections[model] = nil
	end
	local refs = signs[model]
	if refs then
		signs[model] = nil
		MachineBillboard.detach(refs)
	end
	if not group then
		return
	end
	group.Models[model] = nil
	if wasPole then
		group.Poles = math.max(0, group.Poles - 1)
	end
	-- a fed machine went (or was rebuilt): its cable must go too
	if group.Poles > 0 or #group.Made > 0 then
		markDirty(group)
	elseif next(group.Models) == nil then
		groups[group.Folder] = nil
	end
end

---------------------------------------------------------------- range and info signs

-- Whether a model gets an info sign: poles, generators, machines that use
-- power, and any machine with a Detail.
function PowerController.wantsInfo(model: Model): boolean
	local info = infoOf(model)
	if info and (info.IsPole or (info.PowerOut or 0) > 0 or (info.Power or 0) > 0) then
		return true
	end
	local detail = model:GetAttribute("Detail")
	return type(detail) == "string" and detail ~= ""
end

local function hasFullSign(model: Model): boolean
	return MachineBillboard.anchorOf(model):FindFirstChild(MachineBillboard.Name) ~= nil
end

local function refresh()
	local focus = focusPosition()
	-- cables: own plot always, others near the camera
	for _, group in groups do
		local wanted = false
		for model in group.Models do
			if isOwn(model) then
				wanted = true
				break
			end
			if focus and group.Poles > 0 and model.Parent and (model:GetPivot().Position - focus).Magnitude <= OTHER_RANGE then
				wanted = true
				break
			end
		end
		if wanted ~= group.Wanted then
			group.Wanted = wanted
			markDirty(group)
		end
	end
	-- info signs: your nearest poles, generators, powered and Detail machines
	local candidates: { Candidate } = {}
	if focus then
		for model in groupOf do
			if model.Parent and model.PrimaryPart and isOwn(model) and PowerController.wantsInfo(model) and not hasFullSign(model) then
				local distance = (model:GetPivot().Position - focus).Magnitude
				if distance <= INFO_RANGE then
					table.insert(candidates, { Model = model, Distance = distance })
				end
			end
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.Distance < b.Distance
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(INFO_MAX, #candidates) do
		local model = candidates[i].Model
		keep[model] = true
		local refs = signs[model]
		if refs then
			MachineBillboard.refreshInfo(refs)
		else
			signs[model] = MachineBillboard.attachInfo(model)
		end
	end
	for model, refs in signs do
		if not keep[model] then
			signs[model] = nil
			MachineBillboard.detach(refs)
		end
	end
end

---------------------------------------------------------------- lifecycle

function PowerController.init() end

function PowerController.start()
	for _, instance in CollectionService:GetTagged(TAG) do
		register(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(unregister)
	task.spawn(function()
		while true do
			task.wait(SELECT_INTERVAL)
			local ok, err = pcall(function()
				refresh()
			end)
			if not ok then
				warn("[PowerController] update failed: " .. tostring(err))
			end
		end
	end)
end

return PowerController
