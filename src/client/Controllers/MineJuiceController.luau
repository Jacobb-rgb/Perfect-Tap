--[[
	MineJuiceController: the extras from the owner's mining reel (2026-10-27,
	"How do games make MINING feel satisfying?", docs/plans/REELS_2026-10-27_BRIEF.md;
	switches in Config/JuiceConfig.Mining). Client only: it listens, the
	server decides everything as before.

	  a hit      every Health drop of a labeled rock (UI/RockLabels.onHealthDrop,
	             about 3 a second while anyone blasts it; one per HitGap):
	             the crack grows and its gold glints flare (Effects/RockCracks),
	             a dry "tok" (RockTok, at most TokPerSecond), a few chips fly
	             out of the crack (RockFx.chips, rocks near the camera only).
	             RockFx keeps the tremble, MiningController the hit sparks.
	  Fx NodeCrack    a crunch (RockCrunch) and a warm gold sparkle at the crack
	  Fx NodeShatter  your own break (RockFx.wasMine): SMASH! pops over the
	                  rock (UI/PopWord on the UI/BagFly overlay) with a boom
	                  (RockSmash); RockFx keeps the dust, chunks, ring and shake
	  Fx Pickup       (position, oreId or nil for dirty ore): CarryService
	                  fires it to the picker only when an item really goes in
	                  (hands today, the backpack on feat/backpack: the same
	                  event). The ore pops up glowing at its spot, flies on an
	                  arc into the HUD's carry slot (TerraForgeHud.Carry: the
	                  "Backpack" button, else Slots.Slot<CarryCount>, else the
	                  panel, else the bottom centre) and a +1 bumps there with
	                  a pop (BagRise, BagPop). The HUD is only read, never
	                  changed: onLanded(callback) is the hook for a HUD owner
	                  who wants the slot itself to bounce.
	The overlay hides with the HUD (the cleaning close-up). WorldMotionController's
	ore pop (AnimConfig.WorldFx, off) is separate: this starts at the pickup,
	so both can run together.

	Perf (phones first): nothing is made per hit except RockFx's pooled
	chips; the overlay's icons, bumps and word are made once (BagFly.build);
	one RenderStepped connection runs only while something flies or pops and
	makes no tables. Reduce motion (UI/Motion.reduced): no flight (only the
	bump, still), SMASH! fades in and out straight.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared.Config.JuiceConfig)
local OreData = require(Shared.Config.OreData)
local Net = require(Shared.Net)
local RockLabels = require(script.Parent.Parent.UI.RockLabels)
local BagFly = require(script.Parent.Parent.UI.BagFly)
local PopWord = require(script.Parent.Parent.UI.PopWord)
local Motion = require(script.Parent.Parent.UI.Motion)
local RockCracks = require(script.Parent.Parent.Effects.RockCracks)
local RockFx = require(script.Parent.Parent.Effects.RockFx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)

local MineJuiceController = {}

MineJuiceController.ChipRange = 60 -- studs from the camera: farther hits throw no chips
MineJuiceController.MergeGap = 0.3 -- seconds: landings closer than this on one target count up (+2, +3)

type Flight = { Flyer: BagFly.Flyer, From: Vector2, Target: GuiObject?, Start: number, Seed: number }
type Landing = { Bump: BagFly.Bump, Target: GuiObject?, Start: number, Count: number, Reduced: boolean }

local player = Players.LocalPlayer
local view: BagFly.View? = nil
local connection: RBXScriptConnection? = nil
local flights: { Flight } = {}
local busy: { [BagFly.Flyer]: boolean } = {}
local landings: { Landing } = {}
local smashStart: number? = nil
local smashWorld = Vector3.zero
local smashReduced = false
local lastHit: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local tokens = JuiceConfig.TokPerSecond
local tokenAt = 0
local landedListeners: { (GuiObject?) -> () } = {}

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

---------------------------------------------------------------- screen points

-- A world point on the overlay (pixels), nil when it is off screen.
local function toGui(world: Vector3): Vector2?
	local camera = Workspace.CurrentCamera
	local v = view
	if not camera or not v then
		return nil
	end
	local point, onScreen = camera:WorldToViewportPoint(world)
	if not onScreen then
		return nil
	end
	-- viewport -> under the top bar inset -> the overlay's own corner
	local inset = GuiService:GetGuiInset()
	return Vector2.new(point.X, point.Y) - inset - v.Gui.AbsolutePosition
end

local function characterPoint(): Vector2?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return toGui(root.Position + Vector3.new(0, 1.5, 0))
	end
	return nil
end

-- Where the ore goes: the backpack button, else the newest carry slot, else the carry panel (read only).
local function hudTarget(): GuiObject?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local hud = gui and gui:FindFirstChild("TerraForgeHud")
	local carry = hud and hud:FindFirstChild("Carry")
	if not carry or not carry:IsA("GuiObject") then
		return nil
	end
	local pack = carry:FindFirstChild("Backpack", true)
	if pack and pack:IsA("GuiObject") and pack.Visible then
		return pack
	end
	local slots = carry:FindFirstChild("Slots")
	if slots then
		local count = player:GetAttribute("CarryCount")
		local n = math.clamp(if type(count) == "number" then math.floor(count) else 1, 1, 24)
		for i = n, 1, -1 do
			local slot = slots:FindFirstChild("Slot" .. i)
			if slot and slot:IsA("GuiObject") then
				return slot
			end
		end
	end
	return carry
end

-- The target's centre and size on the overlay (the bottom centre when there is none).
local function targetPoint(target: GuiObject?, scale: number): (Vector2, Vector2)
	local v = view
	if not v then
		return Vector2.zero, Vector2.zero
	end
	if target and target.Parent and target.AbsoluteSize.X > 0 then
		return target.AbsolutePosition + target.AbsoluteSize / 2 - v.Gui.AbsolutePosition, target.AbsoluteSize
	end
	local size = v.Gui.AbsoluteSize
	return Vector2.new(size.X / 2, size.Y - 60 * scale), Vector2.new(64, 64) * scale
end

local function uiScale(): number
	return HudController.uiScale()
end

---------------------------------------------------------------- the frame loop

local step: (number) -> ()

local function ensureLoop()
	if not connection then
		connection = RunService.RenderStepped:Connect(function(dt: number)
			step(dt)
		end)
	end
end

local function land(target: GuiObject?, now: number)
	local v = view
	if not v then
		return
	end
	for _, callback in landedListeners do
		task.spawn(callback, target)
	end
	Sfx.play("BagPop")
	-- more ore on the same target right away counts up: +2, +3 ...
	for _, l in landings do
		if l.Target == target and now - l.Start < MineJuiceController.MergeGap then
			l.Count += 1
			l.Start = now
			l.Bump.Plus.Label.Text = "+" .. l.Count
			return
		end
	end
	local bump: BagFly.Bump? = nil
	for _, b in v.Bumps do
		local used = false
		for _, l in landings do
			if l.Bump == b then
				used = true
				break
			end
		end
		if not used then
			bump = b
			break
		end
	end
	if not bump then
		-- every bump is playing: the oldest one starts over here
		local oldest = table.remove(landings, 1)
		bump = if oldest then oldest.Bump else v.Bumps[1]
	end
	local b = bump :: BagFly.Bump
	b.Plus.Label.Text = "+1"
	table.insert(landings, { Bump = b, Target = target, Start = now, Count = 1, Reduced = Motion.reduced() })
	ensureLoop()
end

step = function(_dt: number)
	local v = view
	if not v then
		return
	end
	local now = os.clock()
	local hud = HudController.refs()
	v.Gui.Enabled = hud == nil or hud.Gui.Enabled
	local scale = uiScale()
	for i = #flights, 1, -1 do
		local f = flights[i]
		local to = targetPoint(f.Target, scale)
		if BagFly.poseFlyer(f.Flyer, f.From, to, now - f.Start, scale, f.Seed) then
			busy[f.Flyer] = nil
			table.remove(flights, i)
			land(f.Target, now)
		end
	end
	for i = #landings, 1, -1 do
		local l = landings[i]
		local at, size = targetPoint(l.Target, scale)
		if BagFly.poseBump(l.Bump, at, size, now - l.Start, scale, l.Reduced) then
			table.remove(landings, i)
		end
	end
	local started = smashStart
	if started then
		local point = toGui(smashWorld)
		if point then
			v.SmashAt.Position = UDim2.fromOffset(math.floor(point.X + 0.5), math.floor(point.Y + 0.5))
		end
		v.SmashFit.Scale = scale
		if PopWord.pose(v.Smash, now - started, smashReduced) then
			smashStart = nil
		end
	end
	if #flights == 0 and #landings == 0 and smashStart == nil then
		local current = connection
		connection = nil
		if current then
			current:Disconnect()
		end
	end
end

---------------------------------------------------------------- hits

-- One token per tok; TokPerSecond come back every second.
local function takeToken(now: number): boolean
	local rate = JuiceConfig.TokPerSecond
	tokens = math.min(rate, tokens + (now - tokenAt) * rate)
	tokenAt = now
	if tokens >= 1 then
		tokens -= 1
		return true
	end
	return false
end

local function nearCamera(position: Vector3, range: number): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= range
end

-- A labeled rock lost HP (any player's blaster): the crack grows, a tok, chips.
function MineJuiceController.onHit(rock: Model)
	local now = os.clock()
	if now - (lastHit[rock] or -math.huge) < JuiceConfig.HitGap then
		return
	end
	lastHit[rock] = now
	local primary = rock.PrimaryPart
	if not primary or not rock.Parent then
		return
	end
	local mining = JuiceConfig.Mining
	local origin, normal = RockCracks.hit(rock)
	local at = origin or primary.Position
	if mining.Tok and takeToken(now) then
		Sfx.play("RockTok", at)
	end
	if mining.Chips and nearCamera(at, MineJuiceController.ChipRange) then
		local out = normal
		if not out then
			local camera = Workspace.CurrentCamera
			local toward = if camera then camera.CFrame.Position - at else Vector3.new(0, 0, 1)
			out = if toward.Magnitude > 0.01 then toward.Unit else Vector3.new(0, 0, 1)
		end
		RockFx.chips(at, primary.Color, out, if isPhone() then 2 else 3, rock)
	end
end

---------------------------------------------------------------- SMASH! and the bag

local function smash(position: Vector3, radius: number)
	local v = view
	if not v then
		return
	end
	smashWorld = position + Vector3.new(0, radius * 0.15 + 0.5, 0)
	local point = toGui(smashWorld)
	if not point then
		return
	end
	v.SmashAt.Position = UDim2.fromOffset(math.floor(point.X + 0.5), math.floor(point.Y + 0.5))
	smashStart = os.clock()
	smashReduced = Motion.reduced()
	Sfx.play("RockSmash")
	ensureLoop()
end

local function freeFlyer(v: BagFly.View): BagFly.Flyer?
	for _, f in v.Flyers do
		if not busy[f] then
			return f
		end
	end
	return nil
end

-- An item went into your carry at `position` (oreId: a cleaned ore's id; nil = dirty ore).
local function pickup(position: Vector3, oreId: any)
	local v = view
	if not v then
		return
	end
	local now = os.clock()
	local target = hudTarget()
	local flyer = if Motion.reduced() then nil else freeFlyer(v)
	local from = toGui(position + Vector3.new(0, 0.6, 0)) or characterPoint()
	if not flyer or not from then
		-- Reduce motion, every icon in the air, or nothing on screen: only the bump
		land(target, now)
		return
	end
	local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
	BagFly.setOre(flyer, if ore then ore.Color else nil)
	busy[flyer] = true
	table.insert(flights, { Flyer = flyer, From = from, Target = target, Start = now, Seed = math.random() * 10 })
	Sfx.play("BagRise")
	ensureLoop()
end

local function onFx(kind: any, a: any, b: any, _c: any, _d: any, _e: any, f: any)
	if typeof(a) ~= "Vector3" or a.X ~= a.X or a.Y ~= a.Y or a.Z ~= a.Z then
		return
	end
	local mining = JuiceConfig.Mining
	if kind == "NodeCrack" then
		-- (position, crust, stage, glow, stages): the crunch and a neutral gold sparkle
		if mining.Tok then
			Sfx.play("RockCrunch", a)
		end
		if mining.Glints and nearCamera(a, JuiceConfig.CrackRange) then
			Vfx.burst("Glint", a, if isPhone() then 3 else 5, JuiceConfig.GlintColor)
		end
	elseif kind == "NodeShatter" then
		-- (position, crust, glow, floor, kind, radius)
		local radius = if type(f) == "number" and f == f then math.clamp(f, 0.5, 30) else 2.5
		if mining.Smash and RockFx.wasMine(a, radius) then
			smash(a, radius)
		end
	elseif kind == "Pickup" then
		if mining.BagFly then
			pickup(a, b)
		end
	end
end

-- `callback(target)` when an ore lands in the bag (target = the HUD object it flew into, nil = none).
function MineJuiceController.onLanded(callback: (GuiObject?) -> ())
	table.insert(landedListeners, callback)
end

function MineJuiceController.init()
	local v = BagFly.build()
	v.Gui.Parent = player:WaitForChild("PlayerGui")
	view = v
end

function MineJuiceController.start()
	RockLabels.onHealthDrop(MineJuiceController.onHit)
	Net.listen("Fx", onFx)
end

return MineJuiceController
