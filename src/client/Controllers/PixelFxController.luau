--[[
	PixelFxController: the pixel reels' motion (owner 2026-10-22: "make the
	shop, inventory and icons exactly like the videos") on the Pop kit. The
	kit marks things with the attribute PixelFx (Pop.fxTag):

	  Spin   a sunburst (Pop.rays) turns slowly behind a picture
	  Gleam  a light band (Pop.gleam) sweeps across its face every few seconds
	  Lean   a picture tilts while its button is hovered or selected
	  Press  hover grows, press squishes: UI/Motion's press + hover, which
	         follow Config/AnimConfig.UIMotion (off until the owner says yes)

	The switch: Config/AnimConfig.PixelFx. Off, start() returns at once.
	Reduce motion (Roblox's own setting or the SETTINGS toggle): nothing spins
	or sweeps, and a lean snaps instead of tweening.
	A rays group another script turns itself (LevelView's LEVEL UP) clears its
	PixelFx attribute right after Pop.rays: it is never picked up here.

	Cheap: marks are picked up from PlayerGui.DescendantAdded in one deferred
	batch (the kit sets the attribute right after parenting); one loop at 30
	steps a second turns only the rays whose ScreenGui is on; gleams are
	TweenService tweens started only for a shown gui; destroyed things drop
	out of the lists.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.AnimConfig)
local Motion = require(script.Parent.Parent.UI.Motion)

local PixelFxController = {}

PixelFxController.SpinSpeed = 18 -- degrees a second
PixelFxController.GleamTime = 0.7 -- seconds for one sweep
PixelFxController.GleamGap = { 3.5, 7 } -- seconds between two sweeps (random in this range)
PixelFxController.LeanAngle = -10 -- degrees while hovered
PixelFxController.StepRate = 1 / 30

type Gleam = { Band: GuiObject, Gui: LayerCollector?, Next: number }

local spins: { [GuiObject]: LayerCollector? } = {}
local seen: { [GuiObject]: { At: number, Shown: boolean } } = {} -- (a spin's last visibility check)
local gleams: { Gleam } = {}
local leaning: { [GuiObject]: boolean } = {}
local pressed: { [GuiObject]: boolean } = {}
local queue: { Instance } = {}
local queued = false
local settingReduced = false

-- The next gap before a gleam sweeps again (pure: tests).
function PixelFxController.nextGap(random01: number): number
	local gap = PixelFxController.GleamGap
	return gap[1] + (gap[2] - gap[1]) * math.clamp(random01, 0, 1)
end

-- A spin's rotation `t` seconds in (pure: tests).
function PixelFxController.spinAt(t: number): number
	return (t * PixelFxController.SpinSpeed) % 360
end

local function reduced(): boolean
	local ok, on = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return settingReduced or (ok and on == true)
end

local function guiOf(thing: Instance): LayerCollector?
	return thing:FindFirstAncestorWhichIsA("LayerCollector")
end

local function on(gui: LayerCollector?): boolean
	if gui == nil then
		return false
	end
	if gui:IsA("ScreenGui") then
		return gui.Enabled
	end
	return (gui :: any).Enabled == true
end

local function buttonOf(thing: Instance): GuiButton?
	local at: Instance? = thing.Parent
	while at do
		if at:IsA("GuiButton") then
			return at
		end
		if at:IsA("LayerCollector") then
			return nil
		end
		at = at.Parent
	end
	return nil
end

local function tween(thing: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(thing, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- Whether two screen rectangles overlap (pure: tests).
function PixelFxController.overlaps(aPos: Vector2, aSize: Vector2, bPos: Vector2, bSize: Vector2): boolean
	return aPos.X < bPos.X + bSize.X and bPos.X < aPos.X + aSize.X and aPos.Y < bPos.Y + bSize.Y and bPos.Y < aPos.Y + aSize.Y
end

-- Is a spin on screen: every parent Visible and its card inside the scrolling list's view?
local function shown(spin: GuiObject): boolean
	local card = spin.Parent
	local at: Instance? = spin
	while at and not at:IsA("LayerCollector") do
		if at:IsA("GuiObject") then
			if not at.Visible then
				return false
			end
			if at:IsA("ScrollingFrame") and card and card:IsA("GuiObject") then
				if not PixelFxController.overlaps(card.AbsolutePosition, card.AbsoluteSize, at.AbsolutePosition, at.AbsoluteSize) then
					return false
				end
			end
		end
		at = at.Parent
	end
	return true
end

-- The same, re-checked at most 4 times a second per spin.
local function shownNow(spin: GuiObject, now: number): boolean
	local last = seen[spin]
	if last and now - last.At < 0.25 then
		return last.Shown
	end
	local ok = shown(spin)
	seen[spin] = { At = now, Shown = ok }
	return ok
end

local function lean(icon: GuiObject)
	if leaning[icon] then
		return
	end
	local button = buttonOf(icon)
	if not button then
		return
	end
	leaning[icon] = true
	local rest = icon.Rotation
	local function tilt(onIt: boolean)
		local goal = if onIt then rest + PixelFxController.LeanAngle else rest
		if reduced() then
			icon.Rotation = goal -- (reduce motion: it snaps)
		else
			tween(icon, 0.16, { Rotation = goal })
		end
	end
	button.MouseEnter:Connect(function()
		tilt(true)
	end)
	button.MouseLeave:Connect(function()
		tilt(false)
	end)
	-- (touch: a tap fires MouseEnter but not always MouseLeave; the finger lifting untilts)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			tilt(false)
		end
	end)
	button.SelectionGained:Connect(function()
		tilt(true)
	end)
	button.SelectionLost:Connect(function()
		tilt(false)
	end)
	icon.Destroying:Connect(function()
		leaning[icon] = nil
	end)
end

local function press(button: GuiObject)
	if pressed[button] or not button:IsA("GuiButton") or AnimConfig.UIMotion then
		-- (UIMotionController gives every Pop button press + hover when it is on)
		return
	end
	pressed[button] = true
	Motion.press(button)
	Motion.hover(button)
	button.Destroying:Connect(function()
		pressed[button] = nil
	end)
end

local function take(thing: Instance)
	local kind = thing:GetAttribute("PixelFx")
	if type(kind) ~= "string" or not thing:IsA("GuiObject") then
		return
	end
	local gui = guiOf(thing)
	if gui == nil or gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
		return -- (the world's labels stay still)
	end
	if kind == "Spin" then
		spins[thing] = gui
	elseif kind == "Gleam" then
		table.insert(gleams, { Band = thing, Gui = gui, Next = os.clock() + PixelFxController.nextGap(math.random()) })
	elseif kind == "Lean" then
		lean(thing)
	elseif kind == "Press" then
		press(thing)
	end
end

local function flush()
	queued = false
	local batch = queue
	queue = {}
	for _, thing in batch do
		if thing.Parent then
			take(thing)
		end
	end
end

local function enqueue(thing: Instance)
	table.insert(queue, thing)
	if not queued then
		queued = true
		task.defer(flush)
	end
end

local function step(now: number)
	local still = reduced()
	for spin, gui in spins do
		if spin.Parent == nil then
			spins[spin] = nil
			seen[spin] = nil
		elseif not still and on(gui) and shownNow(spin, now) then
			spin.Rotation = PixelFxController.spinAt(now)
		end
	end
	local i = 1
	while i <= #gleams do
		local g = gleams[i]
		if g.Band.Parent == nil then
			table.remove(gleams, i)
		else
			if now >= g.Next then
				g.Next = now + PixelFxController.GleamTime + PixelFxController.nextGap(math.random())
				if not still and on(g.Gui) and g.Band.Visible then
					g.Band.Position = UDim2.new(-0.3, 0, 0.5, 0)
					local sweep = TweenService:Create(
						g.Band,
						TweenInfo.new(PixelFxController.GleamTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ Position = UDim2.new(1.3, 0, 0.5, 0) }
					)
					sweep:Play()
				end
			end
			i += 1
		end
	end
end

function PixelFxController.init() end

function PixelFxController.start()
	if not AnimConfig.PixelFx then
		return
	end
	local SettingsController = require(script.Parent.SettingsController)
	SettingsController.onChanged(function(current)
		settingReduced = current.ReduceMotion == true
	end)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(enqueue)
	for _, d in playerGui:GetDescendants() do
		enqueue(d)
	end
	local last = 0
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now - last < PixelFxController.StepRate then
			return
		end
		last = now
		step(now)
	end)
end

return PixelFxController
