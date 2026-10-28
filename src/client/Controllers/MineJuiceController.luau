--[[
	MineJuiceController: the extras from the owner's mining reel (2026-10-27,
	"How do games make MINING feel satisfying?", docs/plans/REELS_2026-10-27_BRIEF.md;
	switches in Config/JuiceConfig.Mining). Client only: it listens, the
	server decides everything as before.

	  a hit      every Health drop of a labeled rock (UI/RockLabels.onHealthDrop,
	             about 3 a second while anyone blasts it; one per HitGap):
	             the crack grows and its gold glints flare (Effects/RockCracks),
	             a dry "tok" (RockTok in a 3-voice Sfx lane of its own, at most
	             TokPerSecond), a few chips fly out of the crack (RockFx.chips
	             under their own cap, rocks near the camera only; a rock with no
	             crack face, waiting for a slot, throws none). Your own
	             and your focused rock keep their crack (RockCracks.setKeep).
	             RockFx keeps the tremble, MiningController the hit sparks.
	  Fx NodeCrack    a crunch (RockCrunch, in a lane of its own: the toks never cut it)
	                  and a warm gold sparkle at the crack
	  (the break)     RockFx's own: dust, chunks, ground ring, its sounds and
	                  shake (no word over it: the owner turned it down)
	  Fx Pickup       (position, oreId or nil for dirty ore): CarryService
	                  fires it to the picker only when an item really goes in
	                  (hands today, the backpack on feat/backpack: the same
	                  event). The ore pops up glowing at its spot, flies on an
	                  arc into the HUD's carry slot (TerraForgeHud.Carry: the
	                  "Backpack" button, else Slots.Slot<CarryCount>, else the
	                  panel, else the bottom centre) and a +1 bumps there with
	                  a pop (BagRise, BagPop). More ores landing on it while
	                  its +N still shows only count it up and pop it again (no
	                  new flash, ring or pop); a new bump flashes white at most once per
	                  MineJuiceRules.flareGap per target, and pickups in one
	                  pass rise and pop once per JuiceConfig.SoundGap. The HUD
	                  is only read, never changed: onLanded(callback) is the
	                  hook for a HUD owner who wants the slot itself to bounce.
	The overlay hides with the HUD (the cleaning close-up). WorldMotionController's
	ore pop (AnimConfig.WorldFx, off) is separate: this starts at the pickup,
	so both can run together.

	Perf (phones first): nothing is made per hit except RockFx's pooled
	chips; the overlay's icons and bumps are made once (BagFly.build);
	one RenderStepped connection runs only while something flies or pops and
	makes no tables. Reduce motion (UI/Motion.reduced; the rules are in
	Effects/MineJuiceRules): the cracks still grow, their glints glow
	steady (no flare, no frame loop); no chips, no gold sparkle; a pickup
	plays only its sound (no flight, no bump). Glints flare at most
	JuiceConfig.GlintFlaresPerSecond a second per rock.
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
local Motion = require(script.Parent.Parent.UI.Motion)
local RockCracks = require(script.Parent.Parent.Effects.RockCracks)
local MineJuiceRules = require(script.Parent.Parent.Effects.MineJuiceRules)
local RockFx = require(script.Parent.Parent.Effects.RockFx)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local HudController = require(script.Parent.HudController)

local MineJuiceController = {}

type Flight = { Flyer: BagFly.Flyer, From: Vector2, Target: GuiObject?, Start: number, Seed: number }
type Landing = { Bump: BagFly.Bump, Target: GuiObject?, Start: number, PlusAt: number, Count: number, Flash: boolean }

local player = Players.LocalPlayer
local view: BagFly.View? = nil
local connection: RBXScriptConnection? = nil
local flights: { Flight } = {}
local busy: { [BagFly.Flyer]: boolean } = {}
local landings: { Landing } = {}
local lastHit: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local tokens = JuiceConfig.TokPerSecond
local tokenAt = 0
local landedListeners: { (GuiObject?) -> () } = {}
local NO_TARGET = {} -- lastFlash's key for landings with no HUD target
local lastFlash: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local popAt: number? = nil -- the last BagPop
local riseAt: number? = nil -- the last BagRise

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

-- The bag's pop, at most once per SoundGap (pickups in one pass land together).
local function pop(now: number)
	if MineJuiceRules.once(now, popAt, JuiceConfig.SoundGap) then
		popAt = now
		Sfx.play("BagPop")
	end
end

--[[
	An ore landed in the bag: the listeners; with Reduce motion only the pop.
	Else it merges into the bump still showing on that target (only its +N
	changes) or starts a new bump with the pop, whose white flash comes at most
	once per MineJuiceRules.flareGap() per target (MineJuiceRules.land).
]]
local function land(target: GuiObject?, now: number)
	local v = view
	if not v then
		return
	end
	for _, callback in landedListeners do
		task.spawn(callback, target)
	end
	if Motion.reduced() then
		pop(now)
		return
	end
	local last: Landing? = nil
	for _, l in landings do
		if l.Target == target then
			last = l
		end
	end
	local key: any = target or NO_TARGET
	local showing = last ~= nil and now - last.PlusAt < BagFly.BumpSeconds
	local merge, flash = MineJuiceRules.land(now, showing, lastFlash[key])
	if merge and last then
		-- more ore on the bump still showing: only the count goes up and pops again (+2, +3 ...)
		last.Count += 1
		last.PlusAt = now
		last.Bump.Plus.Label.Text = "+" .. last.Count
		return
	end
	pop(now)
	if flash then
		lastFlash[key] = now
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
	table.insert(landings, { Bump = b, Target = target, Start = now, PlusAt = now, Count = 1, Flash = flash })
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
		if BagFly.poseBump(l.Bump, at, size, now - l.Start, scale, false, l.Flash, now - l.PlusAt) then
			table.remove(landings, i)
		end
	end
	if #flights == 0 and #landings == 0 then
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

-- Studs from the camera (huge without one).
local function cameraDistance(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else math.huge
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
	local reduced = Motion.reduced()
	local origin, normal = RockCracks.hit(rock, reduced)
	if not origin then
		-- waiting for a crack slot: the face it had before, if any (never the rock's hidden middle)
		origin, normal = RockCracks.face(rock)
	end
	local at = origin or primary.Position
	if mining.Tok and takeToken(now) then
		Sfx.playIn("Rock", "RockTok", at)
	end
	local face = origin ~= nil and normal ~= nil
	local chips = if mining.Chips then MineJuiceRules.chips(reduced, cameraDistance(at), isPhone(), face) else 0
	if chips > 0 and normal then
		RockFx.chips(at, primary.Color, normal, chips, rock)
	end
end

---------------------------------------------------------------- the bag

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
	local flyer = freeFlyer(v)
	local from = toGui(position + Vector3.new(0, 0.6, 0)) or characterPoint()
	local mode = MineJuiceRules.pickup(Motion.reduced(), flyer ~= nil, from ~= nil)
	if mode ~= "Fly" or not flyer or not from then
		-- every icon in the air or nothing on screen: only the bump; Reduce motion: only the sound (land)
		land(target, now)
		return
	end
	local ore = if type(oreId) == "string" then OreData.ById[oreId] else nil
	BagFly.setOre(flyer, if ore then ore.Color else nil)
	busy[flyer] = true
	table.insert(flights, { Flyer = flyer, From = from, Target = target, Start = now, Seed = math.random() * 10 })
	if MineJuiceRules.once(now, riseAt, JuiceConfig.SoundGap) then
		riseAt = now
		Sfx.play("BagRise")
	end
	ensureLoop()
end

local function onFx(kind: any, a: any, b: any)
	if typeof(a) ~= "Vector3" or a.X ~= a.X or a.Y ~= a.Y or a.Z ~= a.Z then
		return
	end
	local mining = JuiceConfig.Mining
	if kind == "NodeCrack" then
		-- (position, crust, stage, glow, stages): the crunch and a neutral gold sparkle
		if mining.Tok then
			Sfx.playIn("Crunch", "RockCrunch", a)
		end
		if mining.Glints and MineJuiceRules.sparkle(Motion.reduced(), cameraDistance(a)) then
			Vfx.burst("Glint", a, if isPhone() then 3 else 5, JuiceConfig.GlintColor)
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
	-- your own rock (your beam is on it) and the one you aim at keep their crack
	RockCracks.setKeep(function(rock: Model): boolean
		return RockFx.isMine(rock) or RockLabels.focused() == rock
	end)
	RockLabels.onHealthDrop(MineJuiceController.onHit)
	Net.listen("Fx", onFx)
end

return MineJuiceController
