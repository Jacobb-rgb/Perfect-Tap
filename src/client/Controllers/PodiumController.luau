--[[
	PodiumController: the podiums on your base yard (client side).

	- Mouse: hovering a podium that shows an ore puts a REMOVE button next
	  to it (a BillboardGui in PlayerGui, so it can be clicked); clicking it
	  sends PodiumAction(slot, "Remove"). The button stays while the mouse
	  moves over to it.
	- Touch and gamepad (and keyboard F): the server's ProximityPrompts on
	  every podium. This controller enables the one that fits on your own
	  podiums only:
	    an ore on it            -> "Remove"
	    empty, you carry clean  -> "Put On Podium"
	    empty otherwise         -> "Place Ore" (opens the pen in pick mode)
	    locked (no Podiums perk)-> "Place Ore" shown as "Locked" / "100 R$"
	  The server checks everything again.
	- Ores on podiums near the camera (any plot, SPIN_RANGE) turn slowly and
	  bob a little; far ones stand still (cheap on phones).
	- Fx "PodiumPlaced" / "PodiumRemoved": a glint burst / a puff.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayout = require(Shared.Config.BaseLayout)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local OreData = require(Shared.Config.OreData)
local Theme = require(Shared.Config.UITheme)
local WorldLayout = require(Shared.Config.WorldLayout)
local Net = require(Shared.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local FxController = require(script.Parent.FxController)
local PenController = require(script.Parent.PenController)
local StateController = require(script.Parent.StateController)

local PodiumController = {}

local HOVER_CHECK = 0.1 -- seconds between hover raycasts
local HOVER_GRACE = 0.5 -- the button stays this long after the mouse leaves the podium
local RAY_LENGTH = 250
local SPIN_RANGE = 70 -- studs from the camera
local SPIN_SCAN = 1 -- seconds between looks for podium ores to turn
local SPIN_SPEED = 0.6 -- radians per second
local BOB = 0.12 -- studs

local player = Players.LocalPlayer
local hoverGui: BillboardGui? = nil
local hoverButton: TextButton? = nil
local hoverSlot: number? = nil
local hoverSeen = 0 -- os.clock() the podium was last under the mouse
local overButton = false

---------------------------------------------------------------- helpers

local function myPlotId(): number?
	local id = player:GetAttribute("PlotId")
	return if type(id) == "number" and WorldLayout.Plots[id] then id else nil
end

local function podiumKey(state: { [string]: any }?, slot: number): string
	local list = state and state.Podiums
	local key = if type(list) == "table" then list[slot] else nil
	return if type(key) == "string" then key else ""
end

local function unlockedSlots(state: { [string]: any }?): number
	local slots = state and tonumber(state.PodiumSlots)
	return slots or EconomyConfig.Podiums.Free
end

local function carriesCleanOre(): boolean
	for _, item in CollectionService:GetTagged("Item") do
		if item:GetAttribute("CarriedBy") == player.UserId and EconomyConfig.Podiums.Kinds[item:GetAttribute("Kind") :: any] then
			return true
		end
	end
	return false
end

-- The yard's podium models of your plot that are streamed in.
local function myPodiums(): { [number]: Model }
	local found: { [number]: Model } = {}
	local plotId = myPlotId()
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local plot = plotId and plots and plots:FindFirstChild("Plot_" .. plotId)
	local yard = plot and plot:FindFirstChild("Yard")
	if yard then
		for slot = 1, EconomyConfig.Podiums.Max do
			local podium = yard:FindFirstChild("Podium" .. slot)
			if podium and podium:IsA("Model") then
				found[slot] = podium
			end
		end
	end
	return found
end

---------------------------------------------------------------- prompts

local function applyPrompt(instance: Instance, state: { [string]: any }?, carrying: boolean)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local prompt = instance :: ProximityPrompt
	local slot = prompt:GetAttribute("Slot")
	if prompt:GetAttribute("PlotId") ~= myPlotId() or type(slot) ~= "number" then
		prompt.Enabled = false
		return
	end
	local occupied = podiumKey(state, slot) ~= ""
	local unlocked = slot <= unlockedSlots(state)
	local action = prompt:GetAttribute("Action")
	if action == "Remove" then
		prompt.Enabled = occupied
	elseif action == "Put" then
		prompt.Enabled = not occupied and unlocked and carrying
	else
		prompt.Enabled = not occupied and not (unlocked and carrying)
		prompt.ActionText = if unlocked then "Place Ore" else "Locked"
		prompt.ObjectText = if unlocked then `Podium {slot}` else `Podium {slot} - 100 R$`
	end
end

local function refreshPrompts()
	local state = StateController.get()
	local carrying = carriesCleanOre()
	for _, prompt in CollectionService:GetTagged("PodiumPrompt") do
		applyPrompt(prompt, state, carrying)
	end
end

---------------------------------------------------------------- hover button (mouse)

local function hideHover()
	hoverSlot = nil
	overButton = false
	local gui = hoverGui
	if gui then
		gui.Enabled = false
		gui.Adornee = nil :: any
	end
end

local function ensureHover(): (BillboardGui, TextButton)
	local gui, button = hoverGui, hoverButton
	if gui and button and gui.Parent then
		return gui, button
	end
	local built = UIKit.new("BillboardGui", {
		Name = "TerraForgePodiumHover",
		Size = UDim2.fromOffset(150, 64),
		StudsOffset = Vector3.new(3.4, 1.2, 0),
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
	}) :: BillboardGui
	local remove = UIKit.button(built, "REMOVE", Theme.Bad, Theme.BadDark, {
		Name = "Remove",
		Position = UDim2.fromOffset(4, 10),
		Size = UDim2.fromOffset(142, 50),
		TextSize = 22,
	})
	remove.MouseEnter:Connect(function()
		overButton = true
	end)
	remove.MouseLeave:Connect(function()
		overButton = false
		hoverSeen = os.clock()
	end)
	remove.Activated:Connect(function()
		local slot = hoverSlot
		if slot then
			Sfx.play("UIClick")
			Net.send("PodiumAction", slot, "Remove")
		end
		hideHover()
	end)
	built.Parent = player:WaitForChild("PlayerGui")
	hoverGui, hoverButton = built, remove
	return built, remove
end

local function usingMouse(): boolean
	if not UserInputService.MouseEnabled then
		return false
	end
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseWheel
		or last == Enum.UserInputType.Keyboard
end

-- The podium slot under the mouse (your own podiums only), if any.
local function slotUnderMouse(podiums: { [number]: Model }): number?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local include: { Instance } = {}
	for _, podium in podiums do
		table.insert(include, podium)
	end
	if #include == 0 then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	if not hit then
		return nil
	end
	for slot, podium in podiums do
		if hit.Instance:IsDescendantOf(podium) then
			return slot
		end
	end
	return nil
end

local function nearPodium(slot: number): boolean
	local plotId = myPlotId()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not plotId or not root then
		return false
	end
	local rect = BaseLayout.Podiums[slot]
	local center = (WorldLayout.plotCFrame(WorldLayout.Plots[plotId]) * CFrame.new(rect.Center.X, 0, rect.Center.Z)).Position
	local offset = root.Position - center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= PenController.PodiumRange
end

local function updateHover()
	if not usingMouse() or not ProximityPromptService.Enabled or PenController.isOpen() then
		hideHover()
		return
	end
	local podiums = myPodiums()
	local slot = slotUnderMouse(podiums)
	local state = StateController.get()
	local now = os.clock()
	if slot and podiumKey(state, slot) ~= "" and nearPodium(slot) then
		hoverSeen = now
		if slot ~= hoverSlot then
			local gui = ensureHover()
			local top = podiums[slot]:FindFirstChild("Top")
			local adornee: Instance = if top and top:IsA("BasePart") then top else podiums[slot]
			gui.Adornee = adornee
			gui.Enabled = true
			hoverSlot = slot
		end
		return
	end
	-- keep it a moment (and while the mouse is on the button), then hide
	local current = hoverSlot
	if current and (podiumKey(state, current) == "" or (not overButton and now - hoverSeen > HOVER_GRACE)) then
		hideHover()
	end
end

---------------------------------------------------------------- turning ores

type Spinner = { Pivot: CFrame, Parts: { { Part: BasePart, Offset: CFrame } }, Phase: number }
local spinners: { [Model]: Spinner } = {}

local function scanSpinners()
	local camera = Workspace.CurrentCamera
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not camera or not plots then
		table.clear(spinners)
		return
	end
	local eye = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	for _, plot in plots:GetChildren() do
		local yard = plot:FindFirstChild("Yard")
		if yard then
			for slot = 1, EconomyConfig.Podiums.Max do
				local podium = yard:FindFirstChild("Podium" .. slot)
				local display = podium and podium:FindFirstChild("Display")
				if display and display:IsA("Model") then
					local pivot = display:GetPivot()
					if (pivot.Position - eye).Magnitude <= SPIN_RANGE then
						seen[display] = true
						if not spinners[display] then
							local parts = {}
							for _, d in display:GetDescendants() do
								if d:IsA("BasePart") then
									table.insert(parts, { Part = d, Offset = pivot:ToObjectSpace(d.CFrame) })
								end
							end
							spinners[display] = { Pivot = pivot, Parts = parts, Phase = math.random() * 6 }
						end
					end
				end
			end
		end
	end
	for display in spinners do
		if not seen[display] then
			spinners[display] = nil
		end
	end
end

local function spin(t: number)
	for display, s in spinners do
		if display.Parent then
			local cf = s.Pivot * CFrame.new(0, math.sin(t * 1.4 + s.Phase) * BOB, 0) * CFrame.Angles(0, t * SPIN_SPEED + s.Phase, 0)
			for _, entry in s.Parts do
				entry.Part.CFrame = cf * entry.Offset
			end
		else
			spinners[display] = nil
		end
	end
end

---------------------------------------------------------------- lifecycle

function PodiumController.init()
	FxController.register("PodiumPlaced", function(position: any, oreId: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
		Vfx.burst("Burst", position + Vector3.new(0, 0.6, 0), 14, if ore then ore.Glow else Theme.Coin)
		Sfx.play("Place", position)
		Sfx.play("CoinBurst")
	end)
	FxController.register("PodiumRemoved", function(position: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		Vfx.burst("Dust", position, 5)
		Sfx.play("Pickup")
	end)
	StateController.onChanged(function()
		refreshPrompts()
	end)
end

function PodiumController.start()
	CollectionService:GetInstanceAddedSignal("PodiumPrompt"):Connect(function(prompt)
		applyPrompt(prompt, StateController.get(), carriesCleanOre())
	end)
	refreshPrompts()
	-- an item's CarriedBy attribute may arrive a moment after CarryCount, so refresh twice
	player:GetAttributeChangedSignal("CarryCount"):Connect(function()
		refreshPrompts()
		task.delay(0.25, refreshPrompts)
	end)
	player:GetAttributeChangedSignal("PlotId"):Connect(function()
		hideHover()
		refreshPrompts()
	end)
	local elapsed, sinceScan, t = 0, SPIN_SCAN, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		sinceScan += dt
		if sinceScan >= SPIN_SCAN then
			sinceScan = 0
			scanSpinners()
		end
		if elapsed < HOVER_CHECK then
			return
		end
		elapsed = 0
		updateHover()
	end)
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		spin(t)
	end)
end

return PodiumController
