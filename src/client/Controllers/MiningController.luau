--[[
	MiningController: hold to fire the laser Blaster at rocks.

	  PC       hold the left mouse button, aim with the mouse
	  Touch    hold the round FIRE button (aims at the nearest rock in front of
	           the camera) or touch and hold a rock directly
	  Gamepad  hold R2 (aim assist: the nearest rock in front of the camera)

	Fires only while the Blaster is in hand; starting to fire near a rock
	equips it. The local beam is drawn every frame from the tool's Muzzle to
	the hit point; the server only hears about target changes (MineBlast,
	at most every BlasterData.Beam.ClientRetarget seconds, nil = stop) and
	decides all damage. Every rock near you wears a name + HP label
	(UI/RockLabels); the one you aim at gets a note there ("Needs Lv N",
	"VIP only", "Get closer"). Hits make the rock tremble and cracks /
	shatters play Effects/RockFx. Cleaning and build mode set busy (setBusy)
	and nothing fires while PlayerControls is claimed (anvil, build mode).
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlasterData = require(Shared.Config.BlasterData)
local MovementConfig = require(Shared.Config.MovementConfig)
local Theme = require(Shared.Config.UITheme)
local Net = require(Shared.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RockLabels = require(script.Parent.Parent.UI.RockLabels)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local RockFx = require(script.Parent.Parent.Effects.RockFx)
local CameraShake = require(script.Parent.Parent.Effects.CameraShake)
local BlasterFx = require(script.Parent.Parent.Effects.BlasterFx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local StateController = require(script.Parent.StateController)

local MiningController = {}

local ROCK_TAG = "Rock"
local TOOL_NAME = "Blaster"
local AIM_DISTANCE = 300 -- mouse / touch ray length
local ASSIST_FACING = 0.35 -- aim assist only looks this far to the sides (dot product)
local ASSIST_REFRESH = 0.1 -- seconds between aim assist searches
local NEAR_EXTRA = 6 -- studs past the range that still count as "near a rock" (FIRE button, hint)
local SPARK_GAP = 0.07
local DUST_GAP = 0.3
local TURN_SPEED = 14
local DEFAULT_GLOW = Color3.fromRGB(255, 150, 70)

type Device = "Mouse" | "Touch" | "Gamepad"

local player = Players.LocalPlayer
local busy = false -- set while the cleaning minigame / build mode owns the input
local rumbleOn = true

local holding: { [string]: boolean } = {} -- Mouse | Gamepad | FireButton | TouchRock
local touchRockInput: InputObject? = nil
local touchRockPos: Vector2? = nil
local fireButtonInput: InputObject? = nil

local firing = false
local target: Model? = nil -- the rock the beam hits (in range), nil = none
local lastSent: Model? = nil
local lastSendAt = -math.huge
local assistAt = -math.huge
local assistTarget: Model? = nil
local aimRock: Model? = nil -- the rock the player aims at (also when not firing)
local aimTooFar = false
local seenStage = 0
local sparkAt, dustAt = 0, 0
local savedAutoRotate: boolean? = nil
local device: Device = "Mouse"

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- UI
local gui: ScreenGui
local fireHolder: Frame
local fireButton: TextButton
local hint: Frame
local hintIcon: ImageLabel
local hintText: TextLabel

function MiningController.setBusy(value: boolean)
	busy = value
	if value then
		table.clear(holding)
		touchRockInput, fireButtonInput = nil, nil
	end
end

-- Gamepad rumble while blasting (a settings menu can turn it off).
function MiningController.setRumble(on: boolean)
	rumbleOn = on
end

function MiningController.isFiring(): boolean
	return firing
end

---------------------------------------------------------------- helpers

local function deviceOf(inputType: Enum.UserInputType): Device?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" then
		return "Mouse"
	end
	return nil
end

local function characterParts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return character, nil, nil
	end
	return character, humanoid, root
end

local function equippedTool(): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(TOOL_NAME)
	return if tool and tool:IsA("Tool") then tool else nil
end

local function backpackTool(): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(TOOL_NAME)
	return if tool and tool:IsA("Tool") then tool else nil
end

local function anyTool(): Tool?
	return equippedTool() or backpackTool()
end

local function levelOf(tool: Tool?): number
	local level = tool and tool:GetAttribute("Level")
	return if type(level) == "number" then level else 1
end

-- The player's blaster level: the saved one from the State snapshot (what the server gates on), else the tool's.
local function blasterLevel(tool: Tool?): number
	local state = StateController.get()
	local level = state and state.BlasterLevel
	return if type(level) == "number" then level else levelOf(tool)
end

-- The Reach enchant's extra studs (State.Bonuses.Reach: the same capped
-- bonus MiningService adds to the range it accepts).
local function bonusReach(): number
	local state = StateController.get()
	local bonuses = if state then state.Bonuses else nil
	local reach = if type(bonuses) == "table" then bonuses.Reach else nil
	return if type(reach) == "number" and reach == reach and reach > 0 then math.min(reach, 40) else 0
end

local function rangeOf(tool: Tool?): number
	local range = tool and tool:GetAttribute("Range")
	local base = if type(range) == "number" then range else BlasterData.get(levelOf(tool)).Range
	return base + bonusReach()
end

local function glowOf(tool: Tool?): Color3
	local glow = tool and tool:GetAttribute("Glow")
	return if typeof(glow) == "Color3" then glow else DEFAULT_GLOW
end

local function muzzleOf(tool: Tool?): Attachment?
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

local function rockFromPart(part: Instance?): Model?
	local node = part
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, ROCK_TAG) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function radiusOf(rock: Model): number
	local primary = rock.PrimaryPart
	return if primary then math.max(primary.Size.X, primary.Size.Z) * 0.5 + 0.5 else 2
end

-- Why the local player can't mine this rock yet ("" = they can).
local function gateText(rock: Model, tool: Tool?): string
	if rock:GetAttribute("VipOnly") == true and player:GetAttribute("Perk_ForgeVip") ~= true then
		return "VIP only"
	end
	local needed = rock:GetAttribute("MinBlaster")
	if type(needed) == "number" and needed > blasterLevel(tool) then
		return "Needs Lv " .. needed
	end
	return ""
end

local function refreshFilter()
	local list: { Instance } = {}
	local character = player.Character
	if character then
		table.insert(list, character)
	end
	for _, name in { "Items", "ClientFx", "Debris" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function cast(origin: Vector3, direction: Vector3): RaycastResult?
	return Workspace:Raycast(origin, direction, rayParams)
end

-- Ray through a point on the screen. `viewport` = coordinates include the top bar inset.
local function screenRay(point: Vector2, viewport: boolean): Ray?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	return if viewport then camera:ViewportPointToRay(point.X, point.Y) else camera:ScreenPointToRay(point.X, point.Y)
end

-- The nearest rock in front of the camera within `range` of the character.
-- The server deals no damage through walls (BeamSight): aim assist only
-- locks onto a rock the head can see. Like BeamSight, a line to the rock
-- box's closest point and one to its top, each stopping BeamStopShort
-- before the rock; characters, items, debris, the rocks and BeamIgnore
-- parts never block (the filter is rebuilt at most once a second).
local sightParams: RaycastParams? = nil
local sightAt = -math.huge
local sightRocks: Instance? = nil

local function sightFilter(rocks: Instance?): RaycastParams
	local now = os.clock()
	local current = sightParams
	if current and sightRocks == rocks and now - sightAt < 1 then
		return current
	end
	local ignore: { Instance } = {}
	for _, name in { "Items", "Debris" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	if rocks and rocks ~= Workspace then
		table.insert(ignore, rocks)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	for _, tagged in CollectionService:GetTagged(MovementConfig.BeamIgnoreTag) do
		table.insert(ignore, tagged)
	end
	local fresh = current or RaycastParams.new()
	fresh.FilterType = Enum.RaycastFilterType.Exclude
	fresh.FilterDescendantsInstances = ignore
	fresh.IgnoreWater = true
	fresh.RespectCanCollide = true
	sightParams, sightAt, sightRocks = fresh, now, rocks
	return fresh
end

local function canSee(eye: Vector3, rock: Model): boolean
	if not MovementConfig.BeamLos then
		return true
	end
	local cf, size = rock:GetBoundingBox()
	local half = size / 2
	local p = cf:PointToObjectSpace(eye)
	local closest = cf:PointToWorldSpace(
		Vector3.new(math.clamp(p.X, -half.X, half.X), math.clamp(p.Y, -half.Y, half.Y), math.clamp(p.Z, -half.Z, half.Z))
	)
	local top = cf:PointToWorldSpace(Vector3.new(0, half.Y, 0))
	local params = sightFilter(rock.Parent)
	for _, target in { closest, top } do
		local line = target - eye
		local length = line.Magnitude - MovementConfig.BeamStopShort
		if length <= 0 then
			return true
		end
		local hit = Workspace:Raycast(eye, line.Unit * length, params)
		if not hit or hit.Instance:GetAttribute(MovementConfig.BeamIgnoreAttribute) == true then
			return true
		end
	end
	return false
end

local function findAssist(root: BasePart, range: number): Model?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	local flatLook = if look.Magnitude > 0.05 then look.Unit else root.CFrame.LookVector
	local best: Model? = nil
	local bestScore = math.huge
	local head = player.Character and player.Character:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	for _, rock in CollectionService:GetTagged(ROCK_TAG) do
		if rock:IsA("Model") and rock.PrimaryPart then
			local offset = rock.PrimaryPart.Position - root.Position
			local flat = offset * Vector3.new(1, 0, 1)
			local distance = offset.Magnitude - radiusOf(rock)
			if distance <= range then
				local facing = if flat.Magnitude > 0.5 then flatLook:Dot(flat.Unit) else 1
				if facing > ASSIST_FACING then
					local score = math.max(distance, 0) + 1 + (1 - facing) * 12
					-- the line-of-sight raycast only for a would-be best
					if score < bestScore and canSee(eye, rock) then
						best, bestScore = rock, score
					end
				end
			end
		end
	end
	return best
end

-- Any rock within reach of the character (for the FIRE button and auto-equip)?
local function rockNear(root: BasePart, range: number): boolean
	for _, rock in CollectionService:GetTagged(ROCK_TAG) do
		if rock:IsA("Model") and rock.PrimaryPart then
			if (rock.PrimaryPart.Position - root.Position).Magnitude - radiusOf(rock) <= range + NEAR_EXTRA then
				return true
			end
		end
	end
	return false
end

-- Where the beam from `from` hits `rock` (its surface facing the shooter).
local function surfacePoint(from: Vector3, rock: Model): Vector3
	local center = (rock.PrimaryPart :: BasePart).Position
	local result = cast(from, (center - from) * 1.2)
	if result and rockFromPart(result.Instance) == rock then
		return result.Position
	end
	return center
end

--[[
	Aims the blaster. Returns the rock to damage (in range, else nil), the
	beam's end point and whether that point is on something solid.
]]
local function aim(root: BasePart, tool: Tool, now: number): (Model?, Vector3, boolean)
	local range = rangeOf(tool)
	local muzzle = muzzleOf(tool)
	local origin = if muzzle then muzzle.WorldPosition else root.Position + Vector3.new(0, 1.5, 0)
	local ray: Ray? = nil
	if holding.TouchRock and touchRockPos then
		ray = screenRay(touchRockPos, false)
	elseif holding.Mouse then
		ray = screenRay(UserInputService:GetMouseLocation(), true)
	end
	if ray then
		local result = cast(ray.Origin, ray.Direction * AIM_DISTANCE)
		local point = if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
		local rock = if result then rockFromPart(result.Instance) else nil
		local offset = point - origin
		if (point - root.Position).Magnitude <= range + 1 then
			return rock, point, result ~= nil
		end
		-- too far: the beam fizzles out at its range
		local direction = if offset.Magnitude > 0.01 then offset.Unit else root.CFrame.LookVector
		return nil, origin + direction * range, false
	end
	-- FIRE button / R2: aim assist
	if now - assistAt >= ASSIST_REFRESH or (assistTarget and not assistTarget.Parent) then
		assistAt = now
		assistTarget = findAssist(root, range)
	end
	local rock = assistTarget
	if rock and rock.PrimaryPart then
		return rock, surfacePoint(origin, rock), true
	end
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local forward = (look * Vector3.new(1, 0, 1))
	local direction = if forward.Magnitude > 0.05 then (forward.Unit + Vector3.new(0, -0.08, 0)).Unit else root.CFrame.LookVector
	local result = cast(origin, direction * range)
	if result then
		return nil, result.Position, true
	end
	return nil, origin + direction * range, false
end

---------------------------------------------------------------- feedback

local function rumble(motor: Enum.VibrationMotor, strength: number)
	if not rumbleOn or device ~= "Gamepad" then
		return
	end
	pcall(function()
		local pad = Enum.UserInputType.Gamepad1
		if HapticService:IsVibrationSupported(pad) and HapticService:IsMotorSupported(pad, motor) then
			HapticService:SetMotor(pad, motor, strength)
		end
	end)
end

local function stopRumble()
	pcall(function()
		local pad = Enum.UserInputType.Gamepad1
		if HapticService:IsVibrationSupported(pad) then
			HapticService:SetMotor(pad, Enum.VibrationMotor.Small, 0)
			HapticService:SetMotor(pad, Enum.VibrationMotor.Large, 0)
		end
	end)
end

local function faceTowards(humanoid: Humanoid, root: BasePart, point: Vector3, dt: number)
	if savedAutoRotate == nil then
		savedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
	end
	local flat = Vector3.new(point.X, root.Position.Y, point.Z)
	if (flat - root.Position).Magnitude < 0.5 then
		return
	end
	local goal = CFrame.lookAt(root.Position, flat)
	root.CFrame = root.CFrame:Lerp(goal, math.min(1, dt * TURN_SPEED))
end

local function restoreRotate()
	local saved = savedAutoRotate
	if saved == nil then
		return
	end
	savedAutoRotate = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = saved
	end
end

local function startFiring(tool: Tool)
	firing = true
	BlasterFx.start(tool) -- the flash, the zap, the hum, the kick (Config/BlasterFeel)
	rumble(Enum.VibrationMotor.Small, 0.18)
end

local function stopFiring()
	if not firing then
		return
	end
	firing = false
	target = nil
	Vfx.hideBeam("local")
	BlasterFx.stop()
	stopRumble()
	restoreRotate()
end

-- Tell the server about the current target (throttled; nil = stop).
local function syncTarget(now: number)
	local desired = if firing then target else nil
	if desired ~= lastSent and now - lastSendAt >= BlasterData.Beam.ClientRetarget then
		lastSent = desired
		lastSendAt = now
		Net.send("MineBlast", desired)
	end
end

---------------------------------------------------------------- UI

local function buildUI()
	gui = UIKit.screen("TerraForgeBlaster", 3)
	gui:SetAttribute("TerraForge", true)
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)

	-- hint: "[R2] Hold to blast"
	hint = UIKit.panel(gui, {
		Name = "BlastHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -122),
		Size = UDim2.fromOffset(250, 40),
		Visible = false,
	})
	hintIcon = UIKit.new("ImageLabel", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(10, 5),
		Visible = false,
	}, hint)
	hintText = UIKit.label(hint, "", 18, {
		Name = "Text",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- the round FIRE button (touch), in its own unscaled gui next to the jump button
	local touchGui = UIKit.new("ScreenGui", {
		Name = "TerraForgeFire",
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	fireHolder = UIKit.new("Frame", {
		Name = "FireHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.BadDark,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(92, 92),
		Position = UDim2.new(1, -240, 1, -100),
	}, touchGui)
	UIKit.corner(fireHolder, 999)
	UIKit.stroke(fireHolder, 3)
	fireButton = UIKit.new("TextButton", {
		Name = "Fire",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -5),
		Size = UDim2.fromScale(1, 1),
		Text = "FIRE",
		TextColor3 = Theme.Text,
		TextSize = 24,
		FontFace = Theme.Font,
	}, fireHolder)
	UIKit.corner(fireButton, 999)
	UIKit.gradient(fireButton, Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
	UIKit.textStroke(fireButton)

	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	touchGui.Parent = playerGui
end

local function layoutFireButton()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local small = math.min(size.X, size.Y) <= 500
	-- left of Grab / Throw and the jump button, in reach of the right thumb
	if small then
		fireHolder.Size = UDim2.fromOffset(88, 88)
		fireHolder.Position = UDim2.new(1, -240, 1, -100)
	else
		fireHolder.Size = UDim2.fromOffset(116, 116)
		fireHolder.Position = UDim2.new(1, -310, 1, -140)
	end
end

local function updateHint(show: boolean)
	if not show or firing then
		hint.Visible = false
		return
	end
	hint.Visible = true
	if device == "Gamepad" then
		local image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonR2)
		hintIcon.Image = image
		hintIcon.Visible = image ~= ""
		local key = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonR2)
		hintText.Text = if image ~= "" then "Hold to blast" else "Hold " .. (if key ~= "" then key else "R2") .. " to blast"
	elseif device == "Touch" then
		hintIcon.Visible = false
		hintText.Text = "Hold FIRE or touch a rock"
	else
		hintIcon.Visible = false
		hintText.Text = "Hold left mouse to blast"
	end
	hintText.Position = UDim2.fromOffset(if hintIcon.Visible then 40 else 10, 0)
	hintText.Size = UDim2.new(1, if hintIcon.Visible then -50 else -20, 1, 0)
end

-- The aimed / blasted rock's label gets a note: why you can't mine it, or "Get closer".
local function updateFocus(tool: Tool?)
	local rock = if firing and target then target else aimRock
	if not rock or not rock.Parent or not rock.PrimaryPart then
		RockLabels.setFocus(nil, "")
		return
	end
	local note = gateText(rock, tool)
	if note == "" and aimTooFar and not firing then
		note = "Get closer"
	end
	RockLabels.setFocus(rock, note)
end

---------------------------------------------------------------- input

local function anyHolding(): boolean
	for _, on in holding do
		if on then
			return true
		end
	end
	return false
end

local function canUse(): boolean
	return not busy and PlayerControls.owner() == nil
end

-- Starting to fire with the blaster in the backpack equips it when a rock is near.
local function tryEquip()
	if equippedTool() or not canUse() then
		return
	end
	local tool = backpackTool()
	local _, humanoid, root = characterParts()
	if tool and humanoid and root and rockNear(root, rangeOf(tool)) then
		humanoid:EquipTool(tool)
	end
end

local function press(source: string)
	if not canUse() then
		return
	end
	holding[source] = true
	tryEquip()
end

local function release(source: string)
	holding[source] = nil
end

local function onInputBegan(input: InputObject, processed: boolean)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 then
		if not processed then
			press("Mouse")
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		if not processed and GuiService.SelectedObject == nil then
			press("Gamepad")
		end
	elseif kind == Enum.UserInputType.Touch and not processed and not holding.TouchRock then
		-- touch and hold a rock directly
		local _, _, root = characterParts()
		local tool = anyTool()
		local ray = screenRay(Vector2.new(input.Position.X, input.Position.Y), false)
		if root and tool and ray then
			refreshFilter()
			local result = cast(ray.Origin, ray.Direction * AIM_DISTANCE)
			local rock = result and rockFromPart(result.Instance)
			if rock and result and (result.Position - root.Position).Magnitude <= rangeOf(tool) + NEAR_EXTRA then
				touchRockInput = input
				touchRockPos = Vector2.new(input.Position.X, input.Position.Y)
				press("TouchRock")
			end
		end
	end
end

local function onInputChanged(input: InputObject)
	if input == touchRockInput then
		touchRockPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end

local function onInputEnded(input: InputObject)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 then
		release("Mouse")
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		release("Gamepad")
	end
	if input == touchRockInput then
		touchRockInput, touchRockPos = nil, nil
		release("TouchRock")
	end
	if input == fireButtonInput then
		fireButtonInput = nil
		release("FireButton")
		fireButton.Position = UDim2.fromOffset(0, -5)
	end
end

---------------------------------------------------------------- frame update

local function update(dt: number)
	local now = os.clock()
	local _, humanoid, root = characterParts()
	local tool = equippedTool()
	local usable = canUse() and humanoid ~= nil and root ~= nil
	if not usable then
		table.clear(holding)
	end
	local wantFire = usable and tool ~= nil and anyHolding()

	if wantFire and humanoid and root and tool then
		if not firing then
			startFiring(tool)
			seenStage = 0
		end
		local rock, point, solid = aim(root, tool, now)
		if rock ~= target then
			target = rock
			seenStage = if rock then (rock:GetAttribute("Stage") :: number?) or 0 else 0
		end
		local muzzle = muzzleOf(tool)
		local from = if muzzle then muzzle.WorldPosition else root.Position
		local glow = glowOf(tool)
		Vfx.setBeam("local", muzzle, from, point, glow, nil, BlasterFx.beamStyle())
		faceTowards(humanoid, root, point, dt)
		local gated = rock ~= nil and gateText(rock, tool) ~= ""
		if solid and now - sparkAt >= SPARK_GAP then
			sparkAt = now
			-- sparks; on a rock you can mine also the hit pulses (chips, sounds, recoil)
			local primary = rock and rock.PrimaryPart
			BlasterFx.hit(point, glow, from - point, gated, if primary then primary.Color else nil)
		end
		if rock and not gated then
			-- the rock trembles right away (other players' hits arrive as Health drops, RockLabels)
			RockFx.markShooter(rock)
			RockFx.shake(rock)
			if now - dustAt >= DUST_GAP then
				dustAt = now
				local primary = rock.PrimaryPart
				Vfx.burst("Dust", point, 1, if primary then primary.Color else nil)
			end
			local stage = rock:GetAttribute("Stage")
			if type(stage) == "number" and stage > seenStage then
				seenStage = stage
				CameraShake.add(0.12)
				rumble(Enum.VibrationMotor.Large, 0.45)
				task.delay(0.15, function()
					rumble(Enum.VibrationMotor.Large, 0)
				end)
			end
		end
		if rock and not rock.Parent then
			target = nil
		end
	elseif firing then
		stopFiring()
	end
	syncTarget(now)
end

-- 10 times a second: what the player aims at, hints, the FIRE button.
local function slowUpdate()
	local _, _, root = characterParts()
	local tool = equippedTool()
	local someTool = tool or backpackTool()
	aimRock, aimTooFar = nil, false
	local near = false
	if root and someTool and canUse() then
		refreshFilter()
		local range = rangeOf(someTool)
		near = rockNear(root, range)
		if firing then
			aimRock = target
		elseif device == "Mouse" and UserInputService.MouseEnabled then
			local ray = screenRay(UserInputService:GetMouseLocation(), true)
			local result = ray and cast(ray.Origin, ray.Direction * AIM_DISTANCE)
			local rock = result and rockFromPart(result.Instance)
			if rock and result then
				aimRock = rock
				aimTooFar = (result.Position - root.Position).Magnitude > range + 1
			end
		elseif tool and near then
			aimRock = findAssist(root, range)
		end
	end
	updateFocus(someTool)
	updateHint(near and someTool ~= nil and (aimRock ~= nil or device ~= "Mouse"))
	local touchGui = fireHolder.Parent :: ScreenGui
	touchGui.Enabled = device == "Touch" and canUse() and someTool ~= nil and (tool ~= nil or near)
end

function MiningController.init()
	buildUI()
end

function MiningController.start()
	local last = UserInputService:GetLastInputType()
	local fallback: Device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Mouse"
	device = deviceOf(last) or fallback
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local newDevice: Device? = deviceOf(inputType)
		if newDevice == nil then
			return
		end
		device = newDevice :: Device
		if device ~= "Gamepad" then
			stopRumble()
		end
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.TouchEnded:Connect(function(touch: InputObject)
		onInputEnded(touch)
	end)
	fireButton.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			fireButtonInput = input
			fireButton.Position = UDim2.fromOffset(0, -1)
			press("FireButton")
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutFireButton)
	end
	layoutFireButton()
	player.CharacterAdded:Connect(function()
		table.clear(holding)
		touchRockInput, fireButtonInput = nil, nil
		savedAutoRotate = nil
		stopFiring()
	end)
	refreshFilter()
	RockLabels.onHealthDrop(function(rock: Model)
		RockFx.shake(rock)
	end)
	RockLabels.start(function(): number
		return blasterLevel(anyTool())
	end)
	RunService.RenderStepped:Connect(update)
	while true do
		local ok, err = pcall(function()
			slowUpdate()
		end)
		if not ok then
			warn("[MiningController] " .. tostring(err))
		end
		task.wait(0.1)
	end
end

return MiningController
