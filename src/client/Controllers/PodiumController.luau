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
	    empty, a cleaned ore in
	    your backpack           -> "Put On Podium" (canPutOn, Util/BackpackState)
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
local SecretOreFx = require(Shared.Builders.SecretOreFx)
local Net = require(Shared.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Motion = require(script.Parent.Parent.UI.Motion)
local BackpackState = require(script.Parent.Parent.Util.BackpackState)
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

-- Does the backpack hold an ore "Put On Podium" takes (a cleaned one: EconomyConfig.Podiums.Kinds)?
function PodiumController.canPutOn(backpack: BackpackState.Backpack): boolean
	return BackpackState.has(BackpackState.podiumOre, backpack)
end

local function hasPodiumOre(): boolean
	return PodiumController.canPutOn(BackpackState.get())
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

local function applyPrompt(instance: Instance, state: { [string]: any }?, hasOre: boolean)
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
		prompt.Enabled = not occupied and unlocked and hasOre
	else
		prompt.Enabled = not occupied and not (unlocked and hasOre)
		prompt.ActionText = if unlocked then "Place Ore" else "Locked"
		prompt.ObjectText = if unlocked then `Podium {slot}` else `Podium {slot} - 100 R$`
	end
end

local function refreshPrompts()
	local state = StateController.get()
	local hasOre = hasPodiumOre()
	for _, prompt in CollectionService:GetTagged("PodiumPrompt") do
		applyPrompt(prompt, state, hasOre)
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

type Spinner = {
	Pivot: CFrame,
	Parts: { { Part: BasePart, Offset: CFrame, Mote: boolean } },
	Phase: number,
	Light: PointLight?,
	LightBase: number,
	Rig: SecretOreFx.Rig?, -- a secret ore's moving parts (SecretOreFx), posed after the turn
}
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
					-- turn around the ore's visual middle (ItemBuilder.display sets Center)
					local center = display:GetAttribute("Center")
					local base = display:GetPivot()
					local pivot = if typeof(center) == "Vector3" then CFrame.new(center) * base.Rotation else base
					if (pivot.Position - eye).Magnitude <= SPIN_RANGE then
						seen[display] = true
						if not spinners[display] then
							local parts = {}
							local light: PointLight? = nil
							for _, d in display:GetDescendants() do
								if d:IsA("BasePart") then
									table.insert(parts, { Part = d, Offset = pivot:ToObjectSpace(d.CFrame), Mote = d.Name == "Mote" })
								elseif d:IsA("PointLight") and display:GetAttribute("Pulse") == true then
									light = d
								end
							end
							local rig = SecretOreFx.rig(display, pivot)
							spinners[display] = {
								Pivot = pivot,
								Parts = parts,
								Phase = math.random() * 6,
								Light = light,
								LightBase = if light then light.Brightness else 0,
								Rig = if #rig.Entries > 0 then rig else nil,
							}
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
			-- Mythic motes circle faster than the ore turns
			local orbit = cf * CFrame.Angles(0, t * SPIN_SPEED * 2.5, 0)
			for _, entry in s.Parts do
				entry.Part.CFrame = (if entry.Mote then orbit else cf) * entry.Offset
			end
			local light = s.Light
			if light then
				light.Brightness = s.LightBase * (0.75 + 0.35 * math.sin(t * 2.2 + s.Phase))
			end
			if s.Rig then
				SecretOreFx.pose(s.Rig, cf, t + s.Phase, Motion.reduced())
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
		applyPrompt(prompt, StateController.get(), hasPodiumOre())
	end)
	refreshPrompts()
	-- "Put On Podium" follows the backpack: CarryCount here, every State push (its items) in init
	player:GetAttributeChangedSignal(BackpackState.CountAttribute):Connect(refreshPrompts)
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
