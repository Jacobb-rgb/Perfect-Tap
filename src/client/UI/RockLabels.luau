--[[
	RockLabels: keeps a RockLabel (name + HP) over the nearest mine rocks
	(client only, started by MiningController).

	- 4 times a second (RockLabel.Refresh) it picks the ~12 nearest alive rocks
	  within RockLabel.MaxDistance of the player (8 on phones) and points a
	  pooled label at each; no per-frame work and no labels are created after
	  the pool is full.
	- HP is live: every labeled rock's Health attribute is watched, so the bar
	  moves with the server's damage ticks while anyone blasts it. A Health drop
	  also calls the onHealthDrop listeners (RockFx shakes the rock).
	- "Lv N" in red when the player's blaster level (State snapshot) is below
	  the rock's MinBlaster, "VIP" for VIP rocks without the perk.
	- The rock the player aims at (setFocus) keeps its label up to
	  RockLabel.FocusDistance, a little bigger, with a note ("Needs Lv 3",
	  "VIP only", "Get closer"): this replaces the old aimed-rock sign.
	- A label that would cover a nearer one (or the aimed rock's) on screen
	  is hidden until there is room again (RockLabel.declutter).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local Theme = require(Shared:WaitForChild("Config"):WaitForChild("UITheme"))
local RockLabel = require(script.Parent.RockLabel)

local RockLabels = {}

local ROCK_TAG = "Rock"
local FOCUS_SCALE = 1.12

type Slot = {
	Refs: RockLabel.Refs,
	Rock: Model?,
	Conns: { RBXScriptConnection },
	LastHp: number,
	Visible: boolean, -- false while a nearer label covers it on screen
}

local player = Players.LocalPlayer
local slots: { Slot } = {}
local byRock: { [Model]: Slot } = {}
local focusRock: Model? = nil
local focusNote = ""
local getLevel: () -> number = function()
	return 1
end
local dropListeners: { (Model) -> () } = {}
local started = false
local enabled = true

local function number(rock: Model, name: string): number?
	local value = rock:GetAttribute(name)
	return if type(value) == "number" and value == value then value else nil
end

local function alive(rock: Instance): boolean
	if not rock:IsA("Model") or not rock.Parent or not rock.PrimaryPart then
		return false
	end
	local health = number(rock, "Health")
	return health == nil or health > 0
end

-- MaxHealth, else the floor's HP for the kind (rocks that just spawned), else 1.
local function maxHealthOf(rock: Model): number
	local max = number(rock, "MaxHealth")
	if max then
		return max
	end
	local floor = number(rock, "Floor")
	local kind = rock:GetAttribute("Kind")
	if floor and type(kind) == "string" then
		return MineFloors.rockHealth(floor, kind :: any)
	end
	return 1
end

local function minBlasterOf(rock: Model): number?
	local needed = number(rock, "MinBlaster")
	if needed then
		return needed
	end
	local floor = number(rock, "Floor")
	return if floor and MineFloors.ByIndex[floor] then MineFloors.ByIndex[floor].MinBlaster else nil
end

-- Studs from the rock's PrimaryPart up to its top (the label hangs just above).
local function heightOf(rock: Model): number
	local primary = rock.PrimaryPart :: BasePart
	local cf, size = rock:GetBoundingBox()
	local half = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
	return math.max(1, cf.Position.Y + half - primary.Position.Y)
end

local function updateHp(slot: Slot)
	local rock = slot.Rock
	if not rock then
		return
	end
	local max = maxHealthOf(rock)
	local hp = number(rock, "Health") or max
	local locked, vip =
		RockLabel.lockOf(getLevel(), minBlasterOf(rock), rock:GetAttribute("VipOnly"), player:GetAttribute("Perk_ForgeVip") == true)
	RockLabel.set(slot.Refs, hp, max, locked, vip)
	if hp <= 0 then
		slot.Refs.Gui.Enabled = false
	end
end

local function release(slot: Slot)
	for _, connection in slot.Conns do
		connection:Disconnect()
	end
	table.clear(slot.Conns)
	local rock = slot.Rock
	if rock and byRock[rock] == slot then
		byRock[rock] = nil
	end
	slot.Rock = nil
	slot.Refs.Gui.Enabled = false
	slot.Refs.Gui.Adornee = nil :: any
end

local function bind(slot: Slot, rock: Model)
	local refs = slot.Refs
	local name, color = RockLabel.rockInfo(rock:GetAttribute("Floor"), rock:GetAttribute("Kind"))
	RockLabel.retarget(refs, name, color, heightOf(rock))
	slot.Rock = rock
	byRock[rock] = slot
	slot.Visible = true
	slot.LastHp = number(rock, "Health") or math.huge
	refs.Gui.Adornee = rock.PrimaryPart :: BasePart
	updateHp(slot)
	table.insert(
		slot.Conns,
		rock:GetAttributeChangedSignal("Health"):Connect(function()
			if slot.Rock ~= rock then
				return
			end
			local hp = number(rock, "Health") or math.huge
			local dropped = hp < slot.LastHp
			slot.LastHp = hp
			updateHp(slot)
			if dropped then
				for _, listener in dropListeners do
					task.spawn(listener, rock)
				end
			end
		end)
	)
	table.insert(
		slot.Conns,
		rock.AncestryChanged:Connect(function()
			if slot.Rock == rock and not rock:IsDescendantOf(Workspace) then
				release(slot)
			end
		end)
	)
	refs.Gui.Enabled = enabled and alive(rock)
end

local function newSlot(): Slot
	local refs = RockLabel.build("", MineFloors.LabelColors.Rock, 1, 1)
	refs.Gui.Enabled = false
	refs.Gui.Parent = player:WaitForChild("PlayerGui")
	local slot: Slot = { Refs = refs, Rock = nil, Conns = {}, LastHp = math.huge, Visible = true }
	table.insert(slots, slot)
	return slot
end

-- Distance, fade, lock and the focus note of a labeled rock.
local function style(slot: Slot, distance: number, viewScale: number)
	local rock = slot.Rock
	if not rock then
		return
	end
	local focused = rock == focusRock
	local scale, fade = RockLabel.fade(distance)
	if focused then
		scale, fade = math.max(scale, 1) * FOCUS_SCALE, 0
	end
	RockLabel.setLook(slot.Refs, scale * viewScale, fade)
	RockLabel.setNote(slot.Refs, if focused then focusNote else "", if focusNote == "Get closer" then Theme.TextDim else Theme.Bad)
	slot.Refs.Gui.MaxDistance = if focused
		then RockLabel.FocusDistance + RockLabel.CameraSlack
		else RockLabel.MaxDistance + RockLabel.CameraSlack
	updateHp(slot)
end

-- Picks the rocks to label and points the pooled labels at them.
function RockLabels.refresh()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin: Vector3? = if root and root:IsA("BasePart") then root.Position elseif camera then camera.Focus.Position else nil
	if not origin or not enabled then
		for _, slot in slots do
			if slot.Rock then
				release(slot)
			end
		end
		return
	end
	local viewHeight = if camera then camera.ViewportSize.Y else 720
	local camCf = if camera then camera.CFrame else CFrame.new(origin)
	local candidates: { RockLabel.Candidate } = {}
	local distances: { [Model]: number } = {}
	for _, rock in CollectionService:GetTagged(ROCK_TAG) do
		if alive(rock) then
			local model = rock :: Model
			local position = (model.PrimaryPart :: BasePart).Position
			local distance = (position - origin).Magnitude
			distances[model] = distance
			local behind = (position - camCf.Position):Dot(camCf.LookVector) < 0
			table.insert(candidates, { Rock = model, Distance = distance, Behind = behind })
		end
	end
	local wanted: { [Model]: boolean } = {}
	for _, candidate in RockLabel.pick(candidates, RockLabel.maxLabels(viewHeight)) do
		wanted[candidate.Rock] = true
	end
	local focus = focusRock
	if focus and distances[focus] and distances[focus] <= RockLabel.FocusDistance then
		wanted[focus] = true
	end
	-- free labels of rocks that left the set, then label the new ones
	local free: { Slot } = {}
	for _, slot in slots do
		local rock = slot.Rock
		if rock and not wanted[rock] then
			release(slot)
		end
		if not slot.Rock then
			table.insert(free, slot)
		end
	end
	for rock in wanted do
		if not byRock[rock] then
			local slot = table.remove(free) or newSlot()
			bind(slot, rock)
		end
	end
	local viewScale = RockLabel.screenScale(viewHeight)
	local order: { Slot } = {}
	for _, slot in slots do
		local rock = slot.Rock
		if rock then
			style(slot, distances[rock] or 0, viewScale)
			table.insert(order, slot)
		end
	end
	-- hide labels that would cover a nearer one on screen (the aimed rock first)
	table.sort(order, function(a, b)
		local fa, fb = a.Rock == focus, b.Rock == focus
		if fa ~= fb then
			return fa
		end
		return (distances[a.Rock :: Model] or 0) < (distances[b.Rock :: Model] or 0)
	end)
	local rects: { RockLabel.Rect } = {}
	if camera then
		for _, slot in order do
			local rock = slot.Rock :: Model
			local anchor = (rock.PrimaryPart :: BasePart).Position + slot.Refs.Gui.StudsOffsetWorldSpace
			local point = camera:WorldToViewportPoint(anchor)
			if point.Z > 0 then
				table.insert(rects, RockLabel.rect(slot, point.X, point.Y, slot.Refs.Shown.Scale, slot.Visible))
			end
		end
	end
	local shown = RockLabel.declutter(rects)
	for _, rect in rects do
		local slot = rect.Key :: Slot
		slot.Visible = shown[slot] == true
	end
	for _, slot in order do
		slot.Refs.Gui.Enabled = slot.Visible and alive(slot.Rock :: Model)
	end
end

-- The rock the player aims at (nil = none) and the note under its bar ("" = none).
function RockLabels.setFocus(rock: Model?, note: string)
	local changed = rock ~= focusRock
	focusRock = rock
	focusNote = note
	if not started then
		return
	end
	if changed then
		RockLabels.refresh()
	elseif rock and byRock[rock] then
		local slot = byRock[rock]
		RockLabel.setNote(slot.Refs, note, if note == "Get closer" then Theme.TextDim else Theme.Bad)
	end
end

-- Calls `listener(rock)` when a labeled rock loses HP (any player's blaster).
function RockLabels.onHealthDrop(listener: (Model) -> ())
	table.insert(dropListeners, listener)
end

-- Hides all labels (e.g. a cutscene); refresh brings them back.
function RockLabels.setEnabled(on: boolean)
	enabled = on
	if started then
		RockLabels.refresh()
	end
end

-- Starts the refresh loop. `level` returns the player's blaster level.
function RockLabels.start(level: () -> number)
	getLevel = level
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				RockLabels.refresh()
			end)
			if not ok then
				warn("[RockLabels] " .. tostring(err))
			end
			task.wait(RockLabel.Refresh)
		end
	end)
end

return RockLabels
