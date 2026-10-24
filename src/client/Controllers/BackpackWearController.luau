--[[
	BackpackWearController: the backpacks you see (client only; the server only
	sets which pack a player wears).

	- Worn packs: every player whose attribute Attribute ("Backpack", set by
	  the server's BackpackService to the equipped BackpackData id) names a
	  pack wears it. This client builds it (BackpackBuilder, rigged: massless,
	  no collision; pooled per pack, PoolPerPack spares) into a ClientBackpacks
	  folder and welds its Root to the character's UpperTorso (R15) or Torso
	  (R6) at the middle of its back face, the pack's top level with the
	  torso's top. The pack is scaled to the torso (Model:ScaleTo: a big avatar
	  gets a big pack).
	- Range (StreamingEnabled friendly, checked every LodInterval): beyond
	  ShowRange studs from the camera or streamed out = no pack; beyond
	  FxRange = no particles; your own pack always shows. Particles
	  (BackpackFx) run at half rate on other players' packs and on phones,
	  and not at all with Reduce motion (the SETTINGS toggle or Roblox's own).
	  The pack's light shines for your own pack only (one small light, no
	  shadows, like the head lamps' budget).
	- The BACKPACKS stall's display packs: in the model of every part tagged
	  CounterTag (the stall's counter), the parts with the attribute
	  DisplayAttribute (the shelf and the plinth plates: the pack id) show that
	  pack standing on them, its outer face toward the marker's front (-Z),
	  built here (the display look: no shoulder straps) within DisplayRange
	  and dropped beyond DisplayRange + DisplayHysteresis, so the stall costs
	  the map no parts for them. Their particles follow FxRange, their lights
	  stay off. (The markers carry no tag: Plaza Life keeps its miners off
	  tagged parts as prompt spots.)
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BackpackData = require(Shared.Config.BackpackData)
local BackpackBuilder = require(Shared.Builders.BackpackBuilder)
local BackpackFx = require(Shared.Builders.BackpackFx)

local BackpackWearController = {}

BackpackWearController.Attribute = "Backpack" -- player attribute: the equipped pack id
BackpackWearController.CounterTag = "BackpackCounter" -- the stall's counter (Lobby/Districts/Backpacks)
BackpackWearController.DisplayAttribute = "BackpackId" -- on the stall's display markers
BackpackWearController.ShowRange = 120 -- studs: farther packs aren't built
BackpackWearController.FxRange = 50 -- studs: farther packs get no particles
BackpackWearController.DisplayRange = 70
BackpackWearController.DisplayHysteresis = 20
BackpackWearController.LodInterval = 0.3
BackpackWearController.PoolPerPack = 2

type Wearer = {
	Player: Player,
	Character: Model,
	PackId: string,
	Model: Model?,
	Weld: Weld?,
}

type Display = {
	Marker: BasePart,
	PackId: string,
	Model: Model?,
}

local player = Players.LocalPlayer
local wearers: { [Player]: Wearer } = {}
local displays: { [BasePart]: Display } = {}
local pools: { [string]: { Model } } = {}
local folder: Folder? = nil
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local settingsModule: any = nil
local settingsTried = false

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- The SETTINGS ReduceMotion toggle, or Roblox's own reduced motion.
local function reduceMotion(): boolean
	if not settingsTried then
		settingsTried = true
		local module = script.Parent:FindFirstChild("SettingsController")
		if module and module:IsA("ModuleScript") then
			local ok, controller = pcall(require, module :: any)
			if ok and type(controller) == "table" and type((controller :: any).get) == "function" then
				settingsModule = controller
			end
		end
	end
	if settingsModule then
		local ok, settings = pcall(settingsModule.get)
		if ok and type(settings) == "table" and settings.ReduceMotion == true then
			return true
		end
	end
	local ok, on = pcall(function(): boolean
		return (GuiService :: any).ReducedMotionEnabled == true
	end)
	return ok and on == true
end

local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ClientBackpacks"
	made.Parent = Workspace
	folder = made
	return made
end

---------------------------------------------------------------- effects

-- Puts the pack's effects in once (emitters off until `setFx`), remembering each rate.
local function ensureFx(model: Model)
	if model:GetAttribute("FxReady") then
		return
	end
	model:SetAttribute("FxReady", true)
	local emitters = BackpackFx.apply(model, false)
	for _, e in emitters do
		e:SetAttribute("BaseRate", e.Rate)
		e.Enabled = false
	end
end

-- Particles on / off (`lite`: half rate) and the pack's light on / off (only when that changes).
local function setFx(model: Model, particles: boolean, lite: boolean, light: boolean)
	local calm = reduceMotion()
	local key = `{particles and not calm}|{lite}|{light}`
	if model:GetAttribute("FxState") == key then
		return
	end
	model:SetAttribute("FxState", key)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local base = d:GetAttribute("BaseRate")
			local rate = if type(base) == "number" then base else d.Rate
			d.Rate = if lite then rate * 0.5 else rate
			d.Enabled = particles and not calm
		elseif d:IsA("PointLight") and d.Name == BackpackFx.LightName then
			d.Enabled = light
		end
	end
end

---------------------------------------------------------------- the pool

local function acquire(packId: string, rigged: boolean): Model
	local key = packId .. (if rigged then "" else "|display")
	local pool = pools[key]
	if pool and #pool > 0 then
		return table.remove(pool) :: Model
	end
	local model = BackpackBuilder.build(packId, not rigged)
	if rigged then
		BackpackBuilder.rig(model)
	end
	model:SetAttribute("PoolKey", key)
	return model
end

local function release(model: Model)
	model.Parent = nil
	setFx(model, false, false, false)
	local key = model:GetAttribute("PoolKey")
	if type(key) ~= "string" then
		model:Destroy()
		return
	end
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	if #pool < BackpackWearController.PoolPerPack then
		table.insert(pool, model)
	else
		model:Destroy()
	end
end

---------------------------------------------------------------- worn packs

-- The torso the pack hangs on and how big it is against the default 2 stud wide torso.
local function torsoOf(character: Model): (BasePart?, number)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil, 1
	end
	return torso, math.clamp(torso.Size.X / 2, 0.5, 2.5)
end

local function hide(wearer: Wearer)
	local weld = wearer.Weld
	wearer.Weld = nil
	if weld then
		weld:Destroy()
	end
	local model = wearer.Model
	wearer.Model = nil
	if model then
		release(model)
	end
end

local function show(wearer: Wearer): boolean
	if wearer.Model then
		return true
	end
	local torso, scale = torsoOf(wearer.Character)
	if not torso then
		return false
	end
	local model = acquire(wearer.PackId, true)
	local root = model.PrimaryPart
	if not root then
		model:Destroy()
		return false
	end
	if math.abs(model:GetScale() - scale) > 0.01 then
		model:ScaleTo(scale)
	end
	-- the Root at the middle of the back face, the pack's top level with the torso's top
	local offset = CFrame.new(0, torso.Size.Y / 2 - BackpackBuilder.Top * scale, torso.Size.Z / 2)
	model:PivotTo(torso.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "BackpackWeld"
	weld.Part0 = torso
	weld.Part1 = root
	weld.C0 = offset
	weld.Parent = root
	model.Parent = ensureFolder()
	wearer.Model = model
	wearer.Weld = weld
	return true
end

local function removeWearer(p: Player)
	local wearer = wearers[p]
	if wearer then
		hide(wearer)
		wearers[p] = nil
	end
end

-- Builds / drops the wearer entry from the player's attribute.
local function refreshWearer(p: Player)
	local character = p.Character
	local id = p:GetAttribute(BackpackWearController.Attribute)
	local pack = if type(id) == "string" then BackpackData.ById[id] else nil
	local existing: Wearer? = wearers[p]
	if existing and (not pack or existing.Character ~= character or existing.PackId ~= pack.Id) then
		removeWearer(p)
		existing = nil
	end
	if pack and character and not existing then
		local wearer: Wearer = { Player = p, Character = character, PackId = pack.Id, Model = nil, Weld = nil }
		wearers[p] = wearer
		if p == player then
			show(wearer)
		end
	end
end

local function watchCharacter(p: Player, character: Model)
	if not watched[character] then
		watched[character] = true
		-- R15 parts can arrive after the model (streaming): try again when the torso appears
		character.ChildAdded:Connect(function(child: Instance)
			if child.Name == "UpperTorso" or child.Name == "Torso" then
				local wearer = wearers[p]
				if wearer and wearer.Character == character and not wearer.Model then
					refreshWearer(p)
				end
			end
		end)
	end
	refreshWearer(p)
end

local function watchPlayer(p: Player)
	p:GetAttributeChangedSignal(BackpackWearController.Attribute):Connect(function()
		refreshWearer(p)
	end)
	p.CharacterAdded:Connect(function(character: Model)
		watchCharacter(p, character)
	end)
	p.CharacterRemoving:Connect(function()
		removeWearer(p)
	end)
	if p.Character then
		watchCharacter(p, p.Character)
	end
end

---------------------------------------------------------------- the stall's display packs

local function hideDisplay(display: Display)
	local model = display.Model
	display.Model = nil
	if model then
		release(model)
	end
end

local function showDisplay(display: Display)
	if display.Model then
		return
	end
	local pack = BackpackData.ById[display.PackId]
	if not pack then
		return
	end
	local model = acquire(display.PackId, false)
	local bottom = model:GetAttribute("BottomY")
	local lift = if type(bottom) == "number" then -bottom else pack.Size.Y
	local marker = display.Marker
	-- turned to face the marker's front, its bag centred on the marker, standing on its top
	model:PivotTo(
		marker.CFrame * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, marker.Size.Y / 2 + lift, -(BackpackBuilder.Gap + pack.Size.Z / 2))
	)
	model.Parent = ensureFolder()
	display.Model = model
end

local function addMarker(marker: Instance)
	if not marker:IsA("BasePart") or displays[marker] then
		return
	end
	local id = marker:GetAttribute(BackpackWearController.DisplayAttribute)
	if type(id) ~= "string" or not BackpackData.ById[id] then
		return
	end
	displays[marker] = { Marker = marker, PackId = id, Model = nil }
end

-- The markers in the models of the stall counters that are streamed in (they may stream in after the counter).
local function scanMarkers()
	for _, counter in CollectionService:GetTagged(BackpackWearController.CounterTag) do
		local stall = counter.Parent
		if stall and counter:IsA("BasePart") then
			for _, child in stall:GetChildren() do
				if not displays[child :: any] and child:GetAttribute(BackpackWearController.DisplayAttribute) ~= nil then
					addMarker(child)
				end
			end
		end
	end
end

---------------------------------------------------------------- the range check

local function lodStep()
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	local lite = isPhone()
	-- characters that streamed in with the attribute already set
	for _, p in Players:GetPlayers() do
		if p.Character and not wearers[p] and p:GetAttribute(BackpackWearController.Attribute) ~= nil then
			watchCharacter(p, p.Character)
		end
	end
	local stale: { Player } = {}
	for p, wearer in wearers do
		if p.Parent == nil or p.Character ~= wearer.Character then
			table.insert(stale, p)
		end
	end
	for _, p in stale do
		removeWearer(p)
		if p.Parent then
			refreshWearer(p)
		end
	end
	for p, wearer in wearers do
		local torso = if wearer.Character.Parent then torsoOf(wearer.Character) else nil
		if not torso then
			hide(wearer)
			continue
		end
		local isLocal = p == player
		local distance = (torso.Position - focus).Magnitude
		if isLocal or distance <= BackpackWearController.ShowRange then
			show(wearer)
		else
			hide(wearer)
		end
		local model = wearer.Model
		if model then
			local near = isLocal or distance <= BackpackWearController.FxRange
			if near then
				ensureFx(model)
			end
			setFx(model, near, lite or not isLocal, isLocal)
		end
	end
	scanMarkers()
	local gone: { BasePart } = {}
	for marker, display in displays do
		if not marker:IsDescendantOf(Workspace) then
			hideDisplay(display)
			table.insert(gone, marker)
			continue
		end
		local distance = (marker.Position - focus).Magnitude
		if distance <= BackpackWearController.DisplayRange then
			showDisplay(display)
		elseif distance > BackpackWearController.DisplayRange + BackpackWearController.DisplayHysteresis then
			hideDisplay(display)
		end
		local model = display.Model
		if model then
			local near = distance <= BackpackWearController.FxRange
			if near then
				ensureFx(model)
			end
			setFx(model, near, true, false)
		end
	end
	-- streamed-out markers are forgotten (their stall streams back in with new parts)
	for _, marker in gone do
		displays[marker] = nil
	end
end

---------------------------------------------------------------- lifecycle

function BackpackWearController.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerRemoving:Connect(removeWearer)
	task.spawn(function()
		while true do
			task.wait(BackpackWearController.LodInterval)
			local ok, err: any = pcall(lodStep)
			if not ok then
				warn("[BackpackWearController] " .. tostring(err))
			end
		end
	end)
end

return BackpackWearController
