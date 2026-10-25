--[[
	InteractController: put your own loose items into the backpack (owner
	2026-10-24: everything goes into the backpack; nothing is carried, dropped
	or thrown any more, and the server also picks up what lies near you).

	  Pick up : F | gamepad X | touch button "Grab"  -> Net CarryPickup (item)
	  (every prompt, shops and machines, is on E / gamepad Y; the second one
	  on a spot, like the Cleaning Station's "Take Ore Back", on G / gamepad
	  B: PromptConfig. E stays free for them, owner 2026-10-20)

	The nearest item you own (or the one under the mouse) is highlighted with
	its rarity color and a small hint shows its name and value. A full
	backpack (CarryCount >= CarryCapacity) offers nothing to pick up. The
	server validates every request.
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
local GearConfig = require(Shared.Config.GearConfig)
local ItemData = require(Shared.Config.ItemData)
local OreData = require(Shared.Config.OreData)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Config.UITheme)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local BackpackState = require(script.Parent.Parent.Util.BackpackState)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
local StateController = require(script.Parent.StateController)

local InteractController = {}

local player = Players.LocalPlayer
local target: Model? = nil
local highlight: Highlight
local hint: BillboardGui
local hintName: TextLabel
local hintAction: TextLabel
local enabled = true

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

-- Removes the grab button completely (cleaning close-up, build mode).
function InteractController.suspend()
	InteractController.setEnabled(false)
	ContextActionService:UnbindAction("TerraForgeGrab")
end

local bindGrab: () -> () = function() end
function InteractController.resume()
	InteractController.setEnabled(true)
	bindGrab()
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

-- Beyond the bare-handed reach the server only lets you grab an item with a
-- clear line to it (CarryService.hasReach: BASE_REACH + PICKUP_SLACK).
local LINE_FREE_REACH = GearConfig.value("Gloves", 0) + 2
local lineParams: RaycastParams? = nil

-- Nothing solid between the root and the item (items and your own character
-- don't count): the same test as CarryService's defaultReachClear.
local function lineClear(root: BasePart, primary: BasePart): boolean
	local params = lineParams
	if not params then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.RespectCanCollide = true
		lineParams = made
		params = made
	end
	local p = params :: RaycastParams
	local ignore: { Instance } = {}
	local items = Workspace:FindFirstChild("Items")
	if items then
		table.insert(ignore, items)
	end
	if player.Character then
		table.insert(ignore, player.Character)
	end
	p.FilterDescendantsInstances = ignore
	return Workspace:Raycast(root.Position, primary.Position - root.Position, p) == nil
end

-- Within reach (Gloves: the server mirrors the range in the PickupRange
-- attribute). The wall check beyond the bare-handed reach runs only when
-- `checkLine` (it raycasts: the target loop asks only for a new best).
local function isPickable(model: Model, root: BasePart, checkLine: boolean?): boolean
	if model:GetAttribute("Owner") ~= player.UserId or model:GetAttribute("State") ~= "Loose" then
		return false
	end
	-- a dropper's Drop rides the belts only (the server refuses it too)
	if model:GetAttribute("Kind") == "Drop" then
		return false
	end
	local primary = model.PrimaryPart
	local range = player:GetAttribute("PickupRange")
	local reach = if type(range) == "number" and range > 0 then range else GameConfig.PickupRange
	if primary == nil then
		return false
	end
	local distance = (primary.Position - root.Position).Magnitude
	if distance > reach then
		return false
	end
	return checkLine == false or distance <= LINE_FREE_REACH or lineClear(root, primary)
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
		if model and isPickable(model, root, true) then
			return model
		end
	end
	local camera = Workspace.CurrentCamera
	local look = if UserInputService.TouchEnabled or UserInputService.GamepadEnabled
		then root.CFrame.LookVector
		else camera.CFrame.LookVector
	local best, bestScore = nil, math.huge
	for _, model in CollectionService:GetTagged("Item") do
		if model:IsA("Model") and isPickable(model, root, false) then
			local offset = (model.PrimaryPart :: BasePart).Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local flatLook = Vector3.new(look.X, 0, look.Z)
			local facing = if flat.Magnitude > 0.5 and flatLook.Magnitude > 0.1 then flatLook.Unit:Dot(flat.Unit) else 1
			local score = offset.Magnitude * (1.7 - facing)
			-- the wall check only for a would-be best (an item behind a wall is skipped)
			if score < bestScore and isPickable(model, root, true) then
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
	local dirty = kind == "Raw" or kind == "Relic"
	local color = if ore and not dirty then Rarity.get(ore.Rarity).Color else Theme.Text
	highlight.Adornee = target
	highlight.OutlineColor = color
	hint.Adornee = target.PrimaryPart :: any
	hint.Enabled = true
	hintName.Text = ItemData.displayName(kind, oreId, grade, recipe)
	hintName.TextColor3 = color
	-- what Tobin pays for it (the item's base Value x the player's sell bonus)
	local base = (target:GetAttribute("Value") :: number?) or 0
	local value = math.floor(base * StateController.sellMult() + 0.5)
	local key = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		then MenuPanels.padName(Enum.KeyCode.ButtonX) -- (Square on PlayStation, where Cross jumps)
		elseif UserInputService.TouchEnabled then "Grab"
		else "F"
	hintAction.Text = if kind == "Relic"
		then `[{key}] Pick up   •   clean it at a Cleaning Station or Restoration Table`
		elseif dirty then `[{key}] Pick up   •   clean it to see what it is`
		else `[{key}] Pick up   •   {Format.money(value)}`
end

local function grab(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not enabled or not target then
		return Enum.ContextActionResult.Pass
	end
	Net.send("CarryPickup", target)
	return Enum.ContextActionResult.Sink
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
		ContextActionService:BindAction("TerraForgeGrab", grab, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
		ContextActionService:SetTitle("TerraForgeGrab", "Grab")
		ContextActionService:SetPosition("TerraForgeGrab", UDim2.new(1, -170, 1, -150))
	end
	bindGrab()

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
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
		-- a full backpack takes nothing: no pickup target (F / Grab pass)
		local newTarget = if root and not BackpackState.isFull() then chooseTarget(root) else nil
		if newTarget ~= target then
			target = newTarget
		end
		updateHint()
	end)
end

return InteractController
