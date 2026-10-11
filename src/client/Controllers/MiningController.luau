--[[
	MiningController: swing the pickaxe at ore nodes.

	- PC: click (aims at the node under the mouse, else the nearest node in front)
	- Mobile: tap the screen / tool button; Console: R2. Both aim at the
	  nearest node in front of the character.
	- The character turns toward the node, plays the slash animation and
	  shows sparks/sound/shake immediately (prediction); the server decides
	  damage and drops.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)

local MiningController = {}

local player = Players.LocalPlayer
local lastSwing = 0
local busy = false -- set while the cleaning minigame owns the input

function MiningController.setBusy(value: boolean)
	busy = value
end

local function nodeFromPart(part: Instance?): Model?
	local node = part
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "OreNode") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function nodeRadius(model: Model): number
	local primary = model.PrimaryPart
	return if primary then primary.Size.Magnitude / 2 else 3
end

local function inRange(root: BasePart, model: Model): boolean
	local primary = model.PrimaryPart
	if not primary then
		return false
	end
	return (primary.Position - root.Position).Magnitude - nodeRadius(model) <= GameConfig.MineRange - 1
end

local function findTarget(root: BasePart): Model?
	-- 1) mouse aim (PC)
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local camera = Workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local character = player.Character
		if character then
			params.FilterDescendantsInstances = { character }
		end
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 80, params)
		local model = hit and nodeFromPart(hit.Instance)
		if model and inRange(root, model) then
			return model
		end
	end
	-- 2) nearest node in front of the character
	local best, bestScore = nil, math.huge
	local look = root.CFrame.LookVector
	for _, model in CollectionService:GetTagged("OreNode") do
		if model:IsA("Model") and model.PrimaryPart and inRange(root, model) then
			local offset = model.PrimaryPart.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local facing = if flat.Magnitude > 0.1 then look:Dot(flat.Unit) else 1
			if facing > -0.2 then
				local score = flat.Magnitude * (1.6 - facing)
				if score < bestScore then
					best, bestScore = model, score
				end
			end
		end
	end
	return best
end

local function playSlash(tool: Tool)
	-- The default Animate script plays its slash animation when it sees this.
	local value = Instance.new("StringValue")
	value.Name = "toolanim"
	value.Value = "Slash"
	value.Parent = tool
	task.delay(0.5, function()
		value:Destroy()
	end)
end

local function swing(tool: Tool)
	if busy then
		return
	end
	local cooldown = (tool:GetAttribute("Cooldown") :: number?) or 0.6
	local now = os.clock()
	if now - lastSwing < cooldown then
		return
	end
	lastSwing = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local target = findTarget(root)
	if target and target.PrimaryPart then
		local p = target.PrimaryPart.Position
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(p.X, root.Position.Y, p.Z))
	end
	playSlash(tool)
	if not target then
		return
	end
	task.delay(0.14, function()
		local primary = target.PrimaryPart
		if not primary or not target.Parent then
			return
		end
		-- impact point on the side facing the player
		local toPlayer = (root.Position - primary.Position) * Vector3.new(1, 0, 1)
		local impact = primary.Position + (if toPlayer.Magnitude > 0.1 then toPlayer.Unit else Vector3.zero) * nodeRadius(target) * 0.7 + Vector3.new(0, 0.5, 0)
		local oreId = target:GetAttribute("OreId")
		local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
		local tier = (tool:GetAttribute("Tier") :: number?) or 1
		if ore and tier < ore.Tier then
			Vfx.burst("Sparks", impact, 4, Color3.fromRGB(200, 200, 220), toPlayer)
			Sfx.play("PickBounce", impact)
		else
			Vfx.burst("Sparks", impact, 10, nil, toPlayer)
			Vfx.burst("Dust", impact, 2, if ore then ore.Crust else nil)
			Sfx.play("PickHit", impact)
			CameraShake.add(0.12)
		end
		Net.send("MineSwing", target)
	end)
end

local function hookTool(tool: Instance)
	if tool:IsA("Tool") and tool.Name == "Pickaxe" and not tool:GetAttribute("_Hooked") then
		tool:SetAttribute("_Hooked", true)
		tool.Activated:Connect(function()
			swing(tool)
		end)
	end
end

local function hookCharacter(character: Model)
	for _, child in character:GetChildren() do
		hookTool(child)
	end
	character.ChildAdded:Connect(hookTool)
end

function MiningController.start()
	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(hookTool)
	for _, child in backpack:GetChildren() do
		hookTool(child)
	end
end

return MiningController
