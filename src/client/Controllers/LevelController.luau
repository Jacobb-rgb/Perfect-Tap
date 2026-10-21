--[[
	LevelController: plays the player LEVEL on screen (LevelView, the world
	burst Effects/LevelBurst). The server decides everything (LevelService):
	  - State Level = { Level, Xp, Need } sets the bar (join, resync).
	  - XpGain: orbs fly from the character into the bar (a few per gain);
	    the fill follows once the first one lands, smoothly; past
	    LevelView.GlowFrom the bar glows and pulses (the build-up).
	  - LevelUp: the bar fills up to the end first, then the moment plays
	    (burst at the feet, flash, LEVEL UP!, the reward rows counting up),
	    the bar starts over from 0. Several level ups play one after another.
	The bar hides with the HUD (the cleaning close-up turns it off).
	Reduce motion (Motion.reduced): no orbs (the fill jumps), a steady glow,
	no flash, rays or burst; LEVEL UP! and the rewards fade in at full size.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.Config.LevelConfig)
local Net = require(Shared.Net)
local LevelView = require(script.Parent.Parent.UI.LevelView)
local Motion = require(script.Parent.Parent.UI.Motion)
local LevelBurst = require(script.Parent.Parent.Effects.LevelBurst)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local StateController = require(script.Parent.StateController)
local HudController = require(script.Parent.HudController)

local LevelController = {}

LevelController.OrbSeconds = 0.6
LevelController.OrbGap = 0.06
LevelController.MaxOrbs = 6
LevelController.FillRate = 5 -- how fast the shown fill catches up (per second)

local player = Players.LocalPlayer
local view: LevelView.View? = nil

-- what the bar shows and where it is going
local shownLevel = 1
local shown = 0 -- fill 0..1 shown
local target = { Level = 1, Xp = 0, Need = LevelConfig.need(1) }
local holdUntil = 0 -- the fill waits for the first orb
local known = false

type Flight = { Orb: Frame, Start: number, Seed: number, From: Vector2 }
local flights: { Flight } = {}
local nextOrb = 1

type Up = { Level: number, Coins: number, Bonus: number, Increase: number?, Milestone: boolean }
local ups: { [number]: Up } = {} -- level -> the server's reward info
local moment: { Up: Up, Start: number, Burst: LevelBurst.Burst?, Reduced: boolean }? = nil
local waiting: { Up } = {}

local function frac(xp: number, need: number): number
	return if need > 0 then math.clamp(xp / need, 0, 1) else 0
end

local function characterPoint(): Vector2?
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root or not root:IsA("BasePart") then
		return nil
	end
	local point, onScreen = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 1.5, 0))
	if not onScreen then
		return nil
	end
	-- viewport -> the gui (IgnoreGuiInset off: below the top bar inset)
	local inset = game:GetService("GuiService"):GetGuiInset()
	return Vector2.new(point.X, point.Y - inset.Y)
end

local function barEnd(v: LevelView.View): Vector2
	local track = v.Track
	local orbs = v.Orbs
	local base = orbs.AbsolutePosition
	return track.AbsolutePosition - base + Vector2.new(track.AbsoluteSize.X * math.max(shown, 0.04), track.AbsoluteSize.Y / 2)
end

local function launchOrbs(gain: number)
	local v = view
	if not v then
		return
	end
	local from = characterPoint()
	if not from or Motion.reduced() then
		holdUntil = os.clock()
		return
	end
	local count = math.clamp(math.ceil(gain / 6), 1, LevelController.MaxOrbs)
	local now = os.clock()
	for i = 1, count do
		local orb = v.OrbList[nextOrb]
		nextOrb = nextOrb % #v.OrbList + 1
		table.insert(flights, { Orb = orb, Start = now + (i - 1) * LevelController.OrbGap, Seed = math.random() * 10, From = from })
	end
	holdUntil = math.max(holdUntil, now + LevelController.OrbSeconds * 0.85)
end

-- one burst, built once and moved to the feet each time (pooled)
local pooled: LevelBurst.Burst? = nil

local function startMoment(up: Up)
	local burst: LevelBurst.Burst? = nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hud = HudController.refs()
	local closeUp = hud ~= nil and not hud.Gui.Enabled -- the cleaning close-up: no burst in the shot
	local reduced = Motion.reduced()
	if root and root:IsA("BasePart") and not closeUp and not reduced then
		local feet = root.CFrame * CFrame.new(0, -3, 0)
		local flat = CFrame.new(feet.Position) * CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
		if not pooled then
			pooled = LevelBurst.build(Workspace, flat, up.Milestone)
		end
		burst = pooled
		if burst then
			LevelBurst.setOrigin(burst, flat, up.Milestone)
		end
	end
	moment = { Up = up, Start = os.clock(), Burst = burst, Reduced = reduced }
	Sfx.play("ElevatorDing")
	Sfx.play("CaseBurst")
	task.delay(0.9, function()
		Sfx.play("CoinBurst")
	end)
end

local function onLevelReached(level: number)
	local up = ups[level]
	ups[level] = nil
	local info = up
		or {
			Level = level,
			Coins = 0,
			Bonus = LevelConfig.bonusFor(level),
			Increase = LevelConfig.bonusFor(level) - LevelConfig.bonusFor(level - 1),
			Milestone = LevelConfig.isMilestone(level),
		}
	if moment then
		table.insert(waiting, info)
	else
		startMoment(info)
	end
end

local function step(dt: number)
	local v = view
	if not v then
		return
	end
	local hud = HudController.refs()
	local visible = known and (hud == nil or hud.Gui.Enabled)
	v.Gui.Enabled = visible
	v.Orbs.Enabled = visible
	local now = os.clock()

	-- orbs in flight
	local scale = HudController.uiScale()
	local to = barEnd(v)
	for i = #flights, 1, -1 do
		local f = flights[i]
		local u = (now - f.Start) / LevelController.OrbSeconds
		LevelView.poseOrb(f.Orb, f.From, to, u, scale, f.Seed)
		if u >= 1 then
			table.remove(flights, i)
			Sfx.play("Pickup")
		end
	end

	-- the fill: up to the end for a level up, else to the target
	if target.Level - shownLevel > LevelConfig.MaxShownLevels then
		-- a big jump: only the last few levels fill and play
		shownLevel = target.Level - LevelConfig.MaxShownLevels
		shown = 0
		for level in ups do
			if level <= shownLevel then
				ups[level] = nil
			end
		end
	end
	local reduced = Motion.reduced()
	if now >= holdUntil then
		if shownLevel < target.Level then
			shown = if reduced then 1 else math.min(1, shown + dt * (0.4 + LevelController.FillRate * (1.02 - shown)))
			if shown >= 1 then
				shownLevel += 1
				shown = 0
				onLevelReached(shownLevel)
			end
		else
			local goal = frac(target.Xp, target.Need)
			shown = if reduced then goal else shown + (goal - shown) * math.min(1, dt * LevelController.FillRate)
		end
	end
	local barNeed = if shownLevel < target.Level then LevelConfig.need(shownLevel) else target.Need
	local barXp = if shownLevel < target.Level then shown * barNeed else target.Xp
	LevelView.setBar(v, shownLevel, shown, barXp, barNeed)
	LevelView.poseGlow(v, shown, now, reduced)

	-- the moment
	local m = moment
	if m then
		local t = now - m.Start
		local uiScale = HudController.uiScale()
		LevelView.fit(v, LevelView.fitFor(v.Gui.AbsoluteSize.Y / math.max(uiScale, 0.1)))
		LevelView.poseMoment(v, t, m.Up, m.Reduced)
		local burst = m.Burst
		if burst then
			LevelBurst.pose(burst, t)
			if t >= LevelBurst.Seconds then
				m.Burst = nil -- every part hidden: no more poses
			end
		end
		-- the next one waits for most of this one
		local done = t >= LevelView.MomentSeconds or (#waiting > 0 and t >= 1.8)
		if done then
			if m.Burst then
				LevelBurst.pose(m.Burst, -1)
			end
			moment = nil
			LevelView.hideMoment(v)
			local nextUp = table.remove(waiting, 1)
			if nextUp then
				startMoment(nextUp)
			end
		end
	end
end

local function fromState(state: { [string]: any }?)
	local record = state and state.Level
	if type(record) ~= "table" or type(record.Level) ~= "number" then
		return
	end
	if not known then
		known = true
		shownLevel = record.Level
		shown = frac(record.Xp or 0, record.Need or 1)
	end
	if record.Level >= target.Level then
		target = { Level = record.Level, Xp = record.Xp or 0, Need = record.Need or LevelConfig.need(record.Level) }
	end
end

function LevelController.init()
	local v = LevelView.build()
	v.Gui.Parent = player:WaitForChild("PlayerGui")
	v.Orbs.Parent = player:WaitForChild("PlayerGui")
	v.Gui.Enabled = false
	v.Orbs.Enabled = false
	view = v
end

function LevelController.start()
	fromState(StateController.get())
	StateController.onChanged(fromState)
	Net.listen("XpGain", function(payload: any)
		if type(payload) ~= "table" or type(payload.Level) ~= "number" then
			return
		end
		if not known then
			known = true
			shownLevel = payload.Level
		end
		target = { Level = payload.Level, Xp = tonumber(payload.Xp) or 0, Need = tonumber(payload.Need) or LevelConfig.need(payload.Level) }
		launchOrbs(tonumber(payload.Gain) or 0)
	end)
	Net.listen("LevelUp", function(payload: any)
		if type(payload) ~= "table" or type(payload.Level) ~= "number" then
			return
		end
		ups[payload.Level] = {
			Level = payload.Level,
			Coins = tonumber(payload.Coins) or 0,
			Bonus = tonumber(payload.Bonus) or 0,
			Increase = tonumber(payload.Increase),
			Milestone = payload.Milestone == true,
		}
	end)
	RunService.RenderStepped:Connect(step)
end

return LevelController
