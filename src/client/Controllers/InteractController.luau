--[[
	InteractController: pick up / drop / throw physical items.

	  Grab / Drop : E        | gamepad X  | touch button "Grab"
	  Throw       : hold Q   | gamepad RB | touch button "Throw" (hold to charge)
	  (machine prompts use F / gamepad Y; the Cleaning Station's "Take Ore
	  Back" uses G / gamepad B)

	The nearest item you own (or the one under the mouse) is highlighted with
	its rarity color and a small hint shows its name and value. The server
	validates every request.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)

local InteractController = {}

local player = Players.LocalPlayer
local target: Model? = nil
local highlight: Highlight
local hint: BillboardGui
local hintName: TextLabel
local hintAction: TextLabel
local charging = false
local chargeStart = 0
local enabled = true
local throwBound = false

local CHARGE_TIME = 0.9

local function clearHint()
	local gui: any = hint
	gui.Adornee = nil
end

function InteractController.setEnabled(value: boolean)
	enabled = value
	if not value then
		target = nil
		highlight.Adornee = nil
		clearHint()
		hint.Enabled = false
	end
end

-- Removes the grab/throw buttons completely (cleaning close-up, build mode).
function InteractController.suspend()
	InteractController.setEnabled(false)
	ContextActionService:UnbindAction("TerraForgeGrab")
	if throwBound then
		throwBound = false
		ContextActionService:UnbindAction("TerraForgeThrow")
	end
end

local bindGrab: () -> () = function() end
function InteractController.resume()
	InteractController.setEnabled(true)
	bindGrab()
end

local function carryCount(): number
	return (player:GetAttribute("CarryCount") :: number?) or 0
end

local function itemFromPart(part: Instance?): Model?
	local node = part
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "Item") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function handsFull(): boolean
	local capacity = (player:GetAttribute("CarryCapacity") :: number?) or 1
	return carryCount() >= capacity
end

local function isPickable(model: Model, root: BasePart): boolean
	if model:GetAttribute("Owner") ~= player.UserId or model:GetAttribute("State") ~= "Loose" then
		return false
	end
	local primary = model.PrimaryPart
	-- Gloves reach further: the server mirrors the range in the PickupRange attribute
	local range = player:GetAttribute("PickupRange")
	local reach = if type(range) == "number" and range > 0 then range else GameConfig.PickupRange
	return primary ~= nil and (primary.Position - root.Position).Magnitude <= reach
end

local function chooseTarget(root: BasePart): Model?
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
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 60, params)
		local model = hit and itemFromPart(hit.Instance)
		if model and isPickable(model, root) then
			return model
		end
	end
	local camera = Workspace.CurrentCamera
	local look = if UserInputService.TouchEnabled or UserInputService.GamepadEnabled then root.CFrame.LookVector else camera.CFrame.LookVector
	local best, bestScore = nil, math.huge
	for _, model in CollectionService:GetTagged("Item") do
		if model:IsA("Model") and isPickable(model, root) then
			local offset = (model.PrimaryPart :: BasePart).Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local flatLook = Vector3.new(look.X, 0, look.Z)
			local facing = if flat.Magnitude > 0.5 and flatLook.Magnitude > 0.1 then flatLook.Unit:Dot(flat.Unit) else 1
			local score = offset.Magnitude * (1.7 - facing)
			if score < bestScore then
				best, bestScore = model, score
			end
		end
	end
	return best
end

local function updateHint()
	if not target then
		hint.Enabled = false
		clearHint()
		highlight.Adornee = nil
		return
	end
	local kind = target:GetAttribute("Kind") :: string
	local oreId = target:GetAttribute("OreId") :: string
	local grade = target:GetAttribute("Grade") :: string?
	local recipe = target:GetAttribute("Recipe") :: string?
	local ore = OreData.ById[oreId]
	-- dirty ore keeps its secret: no rarity color, no price (design v2)
	local dirty = kind == "Raw"
	local color = if ore and not dirty then Rarity.get(ore.Rarity).Color else Theme.Text
	highlight.Adornee = target
	highlight.OutlineColor = color
	hint.Adornee = target.PrimaryPart :: any
	hint.Enabled = true
	hintName.Text = ItemData.displayName(kind, oreId, grade, recipe)
	hintName.TextColor3 = color
	local value = (target:GetAttribute("Value") :: number?) or 0
	local key = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "X" elseif UserInputService.TouchEnabled then "Grab" else "E"
	hintAction.Text = if dirty
		then `[{key}] Pick up   •   clean it to see what it is`
		else `[{key}] Pick up   •   {Format.money(value)}`
end

local function grab(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not enabled then
		return Enum.ContextActionResult.Pass
	end
	if target then
		Net.send("CarryPickup", target)
	elseif carryCount() > 0 then
		Net.send("CarryDrop")
		Sfx.play("Drop")
	else
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

local function throw(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if not enabled or carryCount() == 0 then
		return Enum.ContextActionResult.Pass
	end
	local refs = HudController.refs()
	if state == Enum.UserInputState.Begin then
		charging = true
		chargeStart = os.clock()
		refs.ThrowBar.Visible = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if charging then
			charging = false
			refs.ThrowBar.Visible = false
			local charge = math.clamp((os.clock() - chargeStart) / CHARGE_TIME, 0, 1)
			local camera = Workspace.CurrentCamera
			local direction = camera.CFrame.LookVector
			if UserInputService.TouchEnabled then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					direction = (root.CFrame.LookVector + Vector3.new(0, 0.35, 0)).Unit
				end
			end
			Net.send("CarryThrow", direction, charge)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function updateBindings()
	local shouldBind = carryCount() > 0
	if shouldBind and not throwBound then
		throwBound = true
		ContextActionService:BindAction("TerraForgeThrow", throw, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)
		ContextActionService:SetTitle("TerraForgeThrow", "Throw")
		ContextActionService:SetPosition("TerraForgeThrow", UDim2.new(1, -95, 1, -215))
	elseif not shouldBind and throwBound then
		throwBound = false
		charging = false
		HudController.refs().ThrowBar.Visible = false
		ContextActionService:UnbindAction("TerraForgeThrow")
	end
end

function InteractController.init()
	highlight = Instance.new("Highlight")
	highlight.Name = "TerraForgeItemHighlight"
	highlight.FillTransparency = 0.82
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = Workspace -- client-only instance; renders reliably here

	hint = UIKit.new("BillboardGui", {
		Name = "TerraForgeItemHint",
		Size = UDim2.fromOffset(260, 58),
		StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0),
		AlwaysOnTop = true,
		Enabled = false,
		LightInfluence = 0,
		MaxDistance = 40,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	hintName = UIKit.label(hint, "", 22, { Size = UDim2.new(1, 0, 0, 28) })
	hintAction = UIKit.label(hint, "", 16, {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = Theme.TextDim,
	})
end

function InteractController.start()
	bindGrab = function()
		ContextActionService:BindAction("TerraForgeGrab", grab, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		ContextActionService:SetTitle("TerraForgeGrab", "Grab")
		ContextActionService:SetPosition("TerraForgeGrab", UDim2.new(1, -170, 1, -150))
		updateBindings()
	end
	bindGrab()
	player:GetAttributeChangedSignal("CarryCount"):Connect(function()
		if enabled then
			updateBindings()
		end
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		if charging then
			local charge = math.clamp((os.clock() - chargeStart) / CHARGE_TIME, 0, 1)
			HudController.refs().ThrowFill.Size = UDim2.fromScale(charge, 1)
		end
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		if not enabled then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- with full hands there is no pickup target, so E/Grab drops instead
		local newTarget = if root and not handsFull() then chooseTarget(root) else nil
		if newTarget ~= target then
			target = newTarget
		end
		updateHint()
	end)
end

return InteractController
