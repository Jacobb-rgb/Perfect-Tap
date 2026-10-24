--[[
	HoverboardController: hoverboards on the client (the server decides
	everything: HoverboardService, MonetizationService).

	- Hoverboards panel (HoverboardView): the HOVER button of main's left side
	  menu (SideMenuView entry "Hoverboards", SideMenuController action: open /
	  toggle / isOpen / close; MenuPanels: one panel at a time, build mode
	  closes it) opens it from anywhere; it closes the other panels when it
	  opens. Cards: BUY sends HoverboardAction { Action = "Buy", Board }
	  (greyed out with a lock while you can't afford it: pressing it says how
	  much is missing), EQUIP sends { Action = "Equip" }, the Robux button
	  prompts the board's game pass (MarketplaceService:PromptGamePassPurchase,
	  only for MonetizationConfig ids > 0; "COMING SOON" otherwise; the server
	  grants it, never this client). The cards
	  refresh on every State. Closes with the X, B (gamepad), Backspace or
	  HOVER again; gamepads get a selected card on open.
	- RIDE: a round button in the HUD's right menu (above BUILD: clear of the
	  touch jump button at the bottom right), the H key and the gamepad's
	  GamepadKey (L2: the D-pad is taken: Up build mode, Down the teleport
	  bar, Left the side menu, Right the luck boosts) send { Action = "Ride", On } (no board yet:
	  the panel opens). The button shows only while a board is equipped:
	  RIDE / STOP, with an "H" chip or the gamepad glyph (none on touch).
	  Refused on the client while a minigame or build mode holds the controls.
	- Every rider's board (also other players): when a character has the
	  attribute HoverboardData.Attribute, this client builds that board
	  (HoverboardBuilder, rigged: massless, no collision; pooled per board,
	  PoolPerBoard spares) into a ClientHoverboards folder and welds it under
	  the HumanoidRootPart (Weld C0: down by HRP half height + HipHeight, +2
	  for R6 legs: the deck top meets the feet). Every frame the weld's C0 adds
	  a slow bob, a nose-up lean with speed and a roll into turns. Range
	  (StreamingEnabled friendly, checked every LodInterval): beyond ShowRange
	  studs or streamed out = no board; beyond FxRange = no effects; your own
	  board always shows. Every board gets its HoverboardFx (pooled; lite on
	  phones and with many riders), the rates follow the speed; the "Start"
	  burst fires when a rider hops on (within StartBurstWindow), the "Boost"
	  burst when a rider reaches top speed (HoverboardFx.BoostAt).
	- Riding pose (your own character only; animations replicate): the
	  character's own idle animation (Animate.idle, nothing uploaded) plays at
	  Action priority and the walk / run tracks are silenced (weight 0, so the
	  Animate script's state machine stays happy; weight back on dismount).
	  No Animate script or no idle animation = no pose, nothing breaks.
	- The surfer pose (owner 2026-10-24: "no cool animation, it looks like
	  I'm bugged onto a flying thing"): on every R15 rider within PoseRange
	  (yours always) Moves/BoardPose replaces the whole body pose through
	  Moves/MoveRig in one RunService.Stepped (after the Animator): side-on
	  stance, knees bent, arms out, swaying, crouching and leaning with speed
	  and into turns. Hopping on plays the hop (crouch, jump into the stance,
	  squash) while the board flies in from below with a spin and lightning
	  strikes it from the sky; a jump tucks the knees while the board does a
	  kickflip; a landing squashes and splashes. R6 riders keep the old pose.
	- Lightning (HoverboardFx.flicker, every HoverboardBolts.FlickerEvery):
	  arcs crackle out of every board near you, more with speed and while
	  surging (hop on, top speed, landing). The strike from the sky holds one
	  shape (re-shaped once half way), it does not strobe. Reduce Motion (the
	  SETTINGS toggle or Roblox's own) calms it down: no strike, no surges,
	  at most one arc, re-shaped every CalmFlickerEvery (about 3 a second).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HoverboardData = require(Shared.Config.HoverboardData)
local Theme = require(Shared.Config.UITheme)
local HoverboardBuilder = require(Shared.Builders.HoverboardBuilder)
local HoverboardFx = require(Shared.Builders.HoverboardFx)
local HoverboardBolts = require(Shared.Builders.HoverboardBolts)
local BoardPose = require(Shared.Moves.BoardPose)
local MoveRig = require(Shared.Moves.MoveRig)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local HoverboardView = require(script.Parent.Parent.UI.HoverboardView)
local Sfx = require(script.Parent.Parent.Effects.Sfx)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
local HudController = require(script.Parent.HudController)
local StateController = require(script.Parent.StateController)
local CleaningController = require(script.Parent.CleaningController)
local SettingsController = require(script.Parent.SettingsController)
local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)

local HoverboardController = {}

HoverboardController.ShowRange = 150 -- studs: farther boards aren't built
HoverboardController.FxRange = 80 -- studs: farther boards get no particles / trails
HoverboardController.LodInterval = 0.3
HoverboardController.PoolPerBoard = 3
HoverboardController.LiteRiders = 4 -- more riders with effects than this: lite effects
HoverboardController.StartBurstWindow = 1.5 -- seconds after hopping on: the Start burst still fires
HoverboardController.PoseRange = 70 -- studs: riders farther away keep their plain pose
HoverboardController.SurgeTime = 0.7 -- seconds the lightning surges after a hop on / top speed / landing
HoverboardController.StrikeTime = 0.3 -- seconds the strike from the sky lasts
HoverboardController.JumpSpeed = 5 -- studs/s up: the rider jumped (the kickflip starts)
HoverboardController.CalmFlickerEvery = 0.3 -- Reduce Motion: seconds between lightning re-shapes
HoverboardController.Key = Enum.KeyCode.H
HoverboardController.GamepadKey = Enum.KeyCode.ButtonL2

local RIDE_ACTION = "TerraForgeHoverRide"
local CLOSE_ACTION = "TerraForgeHoverClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 10
local SEND_LOCK = 1
local RIDE_LOCK = 0.35
local MESSAGE_TIME = 5
local BOB_HEIGHT = 0.09
local BOB_SPEED = 2.6
local MESSAGE_COLORS: { [string]: Color3 } = {
	Reward = Theme.Good,
	Deny = Theme.Bad,
	Info = Theme.Info,
}

type Rider = {
	Player: Player,
	Character: Model,
	BoardId: string,
	Speed: number,
	Model: Model?,
	Weld: Weld?,
	Fx: HoverboardFx.FxSet?,
	Since: number, -- os.clock() when the rider hopped on (or came into view)
	Started: boolean, -- the Start burst has had its chance
	Fast: boolean, -- at top speed (the Boost burst fired)
	Phase: number,
	Pitch: number,
	Roll: number,
	Yaw: number?,
	-- the pose and the moves (BoardPose)
	MountAt: number, -- os.clock() of the hop on (the hop and the board flying in)
	Air: number, -- 0..1 smoothed airborne amount
	AirAt: number?, -- os.clock() the current jump started (the kickflip)
	LandAt: number, -- os.clock() of the last landing
	SurgeUntil: number, -- lightning surges until then
	StrikeUntil: number, -- the strike from the sky shows until then
	Striking: boolean,
	BoltAt: number, -- next lightning flicker
	Rig: MoveRig.Rig?,
	State: BoardPose.State,
	Layers: { MoveRig.Layer },
}

local player = Players.LocalPlayer
local refs: HoverboardView.Refs? = nil
local ride: HoverboardView.RideButton? = nil
local isOpen = false
local lockedUntil = 0
local rideLockedUntil = 0
local messageToken = 0
local progress: NumberValue? = nil
local animTween: Tween? = nil
local riders: { [Player]: Rider } = {}
local pools: { [string]: { Model } } = {}
local folder: Folder? = nil
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local settingsReduced = false -- the SETTINGS Reduce Motion toggle
local systemReduced = false -- Roblox's own Reduce Motion
local ALL_JOINTS: { [string]: boolean } = {}
for _, name in BoardPose.Joints do
	ALL_JOINTS[name] = true
end
local poseTrack: AnimationTrack? = nil
local poseConnection: RBXScriptConnection? = nil
local silenced: { AnimationTrack } = {}

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function snapshotBoards(): ({ [string]: boolean }, string, number)
	local snapshot = StateController.get()
	local record = snapshot and snapshot.Hoverboards
	local owned = HoverboardView.ownedSet(if type(record) == "table" then record.Owned else nil)
	local equipped = if type(record) == "table" and type(record.Equipped) == "string" then record.Equipped else ""
	local coins = if snapshot and type(snapshot.Coins) == "number" then snapshot.Coins else 0
	return owned, equipped, coins
end

-- True while your own character stands on a board.
function HoverboardController.isRiding(): boolean
	local character = player.Character
	return character ~= nil and HoverboardData.get(character:GetAttribute(HoverboardData.Attribute)) ~= nil
end

function HoverboardController.isOpen(): boolean
	return isOpen
end

---------------------------------------------------------------- the riding pose

local function stopPose()
	if poseConnection then
		poseConnection:Disconnect()
		poseConnection = nil
	end
	local track = poseTrack
	poseTrack = nil
	if track then
		track:Stop(0.2)
		task.delay(0.3, function()
			track:Destroy()
		end)
	end
	for _, silencedTrack in silenced do
		if silencedTrack.IsPlaying then
			silencedTrack:AdjustWeight(1, 0.2)
		end
	end
	table.clear(silenced)
end

local function animationIds(animate: Instance, names: { string }): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for _, name in names do
		local holder = animate:FindFirstChild(name)
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("Animation") then
					ids[child.AnimationId] = true
				end
			end
		end
	end
	return ids
end

local function startPose(character: Model)
	stopPose()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	if not animator or not animate or not idle then
		return
	end
	local animation: Animation? = nil
	for _, child in idle:GetChildren() do
		if child:IsA("Animation") then
			animation = child
			break
		end
	end
	if not animation then
		return
	end
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation :: Animation)
	end)
	if not ok or not track then
		return
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.2)
	poseTrack = track
	local moving = animationIds(animate, { "walk", "run" })
	local function quiet(other: AnimationTrack)
		if other ~= track and other.Animation and moving[other.Animation.AnimationId] then
			other:AdjustWeight(0.001, 0.1)
			if not table.find(silenced, other) then
				table.insert(silenced, other)
			end
		end
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		quiet(playing)
	end
	poseConnection = animator.AnimationPlayed:Connect(quiet)
end

---------------------------------------------------------------- boards under the riders

local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ClientHoverboards"
	made.Parent = Workspace
	folder = made
	return made
end

local function acquireModel(boardId: string): Model
	local pool = pools[boardId]
	if pool and #pool > 0 then
		return table.remove(pool) :: Model
	end
	local model = HoverboardBuilder.build(boardId)
	HoverboardBuilder.rig(model)
	return model
end

local function releaseModel(boardId: string, model: Model)
	model.Parent = nil
	local pool = pools[boardId]
	if not pool then
		pool = {}
		pools[boardId] = pool
	end
	if #pool < HoverboardController.PoolPerBoard then
		table.insert(pool, model)
	else
		model:Destroy()
	end
end

-- Where the board's Root sits under a character (the deck top at the feet), or nil.
local function boardOffset(character: Model): CFrame?
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil
	end
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
	return CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight + legs), 0)
end

local function hideFx(rider: Rider)
	local set = rider.Fx
	rider.Fx = nil
	if set then
		HoverboardFx.release(set)
	end
end

local function hide(rider: Rider)
	hideFx(rider)
	local weld = rider.Weld
	rider.Weld = nil
	if weld then
		weld:Destroy()
	end
	local model = rider.Model
	rider.Model = nil
	if model then
		releaseModel(rider.BoardId, model)
	end
end

local function show(rider: Rider): boolean
	if rider.Model then
		return true
	end
	local root = rider.Character:FindFirstChild("HumanoidRootPart")
	local offset = boardOffset(rider.Character)
	if not root or not root:IsA("BasePart") or not offset then
		return false
	end
	local model = acquireModel(rider.BoardId)
	local boardRoot = model.PrimaryPart
	if not boardRoot then
		model:Destroy()
		return false
	end
	-- put the board under the rider before it enters the world (a pooled or freshly
	-- built model sits wherever it was made; owner's playtest 2026-10-20: board unseen)
	model:PivotTo(root.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "HoverboardWeld"
	weld.Part0 = root
	weld.Part1 = boardRoot
	weld.C0 = offset
	weld.Parent = boardRoot
	model.Parent = ensureFolder()
	rider.Model = model
	rider.Weld = weld
	return true
end

local function fxCount(): number
	local n = 0
	for _, rider in riders do
		if rider.Fx then
			n += 1
		end
	end
	return n
end

local function showFx(rider: Rider)
	local model = rider.Model
	if rider.Fx or not model then
		return
	end
	local lite = isPhone() or fxCount() >= HoverboardController.LiteRiders
	local set = HoverboardFx.acquire(rider.BoardId, lite)
	if not set then
		return
	end
	if HoverboardFx.mount(set, model) then
		rider.Fx = set
		-- the hop-on splash, only right after the rider appeared (not when a rider who
		-- rode out of range comes back; once for riders already riding when you join)
		if not rider.Started and os.clock() - rider.Since <= HoverboardController.StartBurstWindow then
			HoverboardFx.burst(set, "Start")
			-- lightning strikes the board as it flies in
			local now = os.clock()
			rider.StrikeUntil = now + HoverboardController.StrikeTime
			rider.SurgeUntil = now + HoverboardController.SurgeTime + 0.3
			rider.BoltAt = now
		end
		rider.Started = true
	else
		HoverboardFx.release(set)
	end
end

local function releaseRig(rider: Rider)
	local rig = rider.Rig
	if rig and MoveRig.alive(rig) then
		MoveRig.release(rig)
	end
end

local function removeRider(p: Player)
	local rider = riders[p]
	if rider then
		releaseRig(rider)
		hide(rider)
		riders[p] = nil
	end
	if p == player then
		stopPose()
	end
end

local updateRideButton: () -> () = function() end

-- Builds / drops the rider entry from the character's attribute.
local function refreshRider(p: Player)
	local character = p.Character
	local board = if character then HoverboardData.get(character:GetAttribute(HoverboardData.Attribute)) else nil
	local existing: Rider? = riders[p]
	if existing and (not board or existing.Character ~= character or existing.BoardId ~= board.Id) then
		removeRider(p)
		existing = nil
	end
	if board and character and not existing then
		local rider: Rider = {
			Player = p,
			Character = character,
			BoardId = board.Id,
			Speed = board.Speed,
			Model = nil,
			Weld = nil,
			Fx = nil,
			Since = os.clock(),
			Started = false,
			Fast = false,
			Phase = math.random() * math.pi * 2,
			Pitch = 0,
			Roll = 0,
			Yaw = nil,
			MountAt = os.clock(),
			Air = 0,
			AirAt = nil,
			LandAt = -math.huge,
			SurgeUntil = 0,
			StrikeUntil = 0,
			Striking = false,
			BoltAt = 0,
			Rig = nil,
			State = { T = 0, Speed = 0, Turn = 0, Mount = 0, Air = 0, Land = 0 },
			Layers = { { Pose = {}, Weight = 0, Override = ALL_JOINTS } },
		}
		riders[p] = rider
		if p == player then
			show(rider)
			showFx(rider)
			startPose(character)
		end
	end
	if p == player then
		updateRideButton()
	end
end

local function watchCharacter(p: Player, character: Model)
	if watched[character] then
		refreshRider(p)
		return
	end
	watched[character] = true
	character:GetAttributeChangedSignal(HoverboardData.Attribute):Connect(function()
		refreshRider(p)
	end)
	refreshRider(p)
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(function(character: Model)
		watchCharacter(p, character)
	end)
	p.CharacterRemoving:Connect(function()
		removeRider(p)
	end)
	if p.Character then
		watchCharacter(p, p.Character)
	end
end

-- Every LodInterval: boards in / out of range, streamed-out characters, effects on / off.
local function lodStep()
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	-- characters that streamed in with the attribute already set
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character and not riders[p] and character:GetAttribute(HoverboardData.Attribute) ~= nil then
			watchCharacter(p, character)
		end
	end
	local stale: { Player } = {}
	for p, rider in riders do
		if p.Parent == nil or p.Character ~= rider.Character then
			table.insert(stale, p)
		end
	end
	-- stale riders are rebuilt here, between the loops (no keys added while iterating)
	for _, p in stale do
		removeRider(p)
		if p.Parent then
			refreshRider(p)
		end
	end
	for p, rider in riders do
		local root = rider.Character.Parent and rider.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			hide(rider)
			continue
		end
		local isLocal = p == player
		local distance = (root.Position - focus).Magnitude
		if isLocal or distance <= HoverboardController.ShowRange then
			show(rider)
		else
			hide(rider)
		end
		if rider.Model and (isLocal or distance <= HoverboardController.FxRange) then
			showFx(rider)
			local set = rider.Fx
			if set then
				local velocity = root.AssemblyLinearVelocity
				local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				local k = math.clamp(speed / rider.Speed, 0, 1)
				HoverboardFx.setActive(set, true, math.max(0.2, k))
				if not rider.Fast and k >= HoverboardFx.BoostAt then
					rider.Fast = true
					HoverboardFx.burst(set, "Boost")
					rider.SurgeUntil = os.clock() + HoverboardController.SurgeTime
				elseif rider.Fast and k < HoverboardFx.BoostReset then
					rider.Fast = false
				end
			end
		else
			hideFx(rider)
		end
	end
end

-- Is the rider in the air? Yours from the Humanoid's state, the others' from the vertical speed.
local function airborne(rider: Rider, vy: number): boolean
	if rider.Player == player then
		local humanoid = rider.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local state = humanoid:GetState()
			return state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
		end
	end
	return vy > HoverboardController.JumpSpeed or vy < -8
end

-- Every frame: bob, lean and roll of the boards on screen, the hop on, the kickflip,
-- jumps and landings, and the lightning.
local function animate(dt: number)
	local now = os.clock()
	for _, rider in riders do
		local weld = rider.Weld
		local root = weld and weld.Part0
		if weld and root then
			local offset = boardOffset(rider.Character)
			if offset then
				local velocity = root.AssemblyLinearVelocity
				local speed01 = math.clamp(Vector3.new(velocity.X, 0, velocity.Z).Magnitude / rider.Speed, 0, 1)
				local look = root.CFrame.LookVector
				local yaw = math.atan2(look.X, look.Z)
				local last = rider.Yaw or yaw
				local turn = (yaw - last + math.pi) % (2 * math.pi) - math.pi
				rider.Yaw = yaw
				local rate = if dt > 0 then turn / dt else 0
				local k = math.min(1, dt * 6)
				rider.Roll += (math.clamp(rate * 0.07, -0.22, 0.22) - rider.Roll) * k
				rider.Pitch += (speed01 * 0.07 - rider.Pitch) * math.min(1, dt * 4)
				local bob = math.sin(now * BOB_SPEED + rider.Phase) * BOB_HEIGHT * (1 - 0.5 * speed01)

				-- jumps: the kickflip once per jump, a squash + splash + surge on landing
				local inAir = airborne(rider, velocity.Y)
				if inAir and not rider.AirAt then
					rider.AirAt = now
				elseif not inAir and rider.AirAt then
					if now - rider.AirAt > 0.25 then
						rider.LandAt = now
						rider.SurgeUntil = now + HoverboardController.SurgeTime * 0.7
						local set = rider.Fx
						if set then
							HoverboardFx.burst(set, "Start")
						end
					end
					rider.AirAt = nil
				end
				rider.Air += ((if inAir then 1 else 0) - rider.Air) * math.min(1, dt * (if inAir then 10 else 16))
				local flip = 0
				local airAt = rider.AirAt
				if airAt and now - airAt < BoardPose.FlipTime then
					flip = BoardPose.flip(now - airAt)
				end

				-- the hop on: the board rises from below with a spin
				local mount = math.clamp((now - rider.MountAt) / BoardPose.MountTime, 0, 1)
				local rise, spin = 0, 0
				if mount < 1 then
					rise, spin = BoardPose.boardMount(mount)
				end
				weld.C0 = offset * CFrame.new(0, bob + rise, 0) * CFrame.Angles(rider.Pitch, spin, rider.Roll) * BoardPose.flipFrame(flip)

				-- the pose state for the Stepped pass
				local state = rider.State
				state.T = now + rider.Phase
				state.Speed = speed01
				state.Turn = rider.Roll / 0.22
				state.Mount = mount
				state.Air = rider.Air
				state.Land = math.clamp(1 - (now - rider.LandAt) / BoardPose.LandTime, 0, 1)

				-- lightning (calm with Reduce Motion: no strike, no surge, one arc, slow)
				local set = rider.Fx
				if set and now >= rider.BoltAt then
					local calm = settingsReduced or systemReduced
					rider.BoltAt = now + (if calm then HoverboardController.CalmFlickerEvery else HoverboardBolts.FlickerEvery)
					local surge = if now < rider.SurgeUntil and not calm then 0.6 else 0
					HoverboardFx.flicker(set, math.random, if calm then 0 else speed01, surge, if calm then 1 else nil)
					local striking = now < rider.StrikeUntil and not calm
					-- the strike holds its shape: drawn when it starts and once more half way, never strobing
					local half = rider.StrikeUntil - HoverboardController.StrikeTime / 2
					if striking and (not rider.Striking or (now >= half and now - HoverboardBolts.FlickerEvery < half)) then
						HoverboardFx.strike(set, math.random, 1)
					elseif not striking and rider.Striking then
						HoverboardFx.strike(set, math.random, 0)
					end
					rider.Striking = striking
				end
			end
		end
	end
end

-- After the Animator (RunService.Stepped): the surfer pose on every R15 rider near you.
local function poseStep()
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	for p, rider in riders do
		local root = rider.Character:FindFirstChild("HumanoidRootPart")
		local near = rider.Model ~= nil
			and root ~= nil
			and root:IsA("BasePart")
			and (p == player or (root.Position - focus).Magnitude <= HoverboardController.PoseRange)
		if not near then
			releaseRig(rider)
			continue
		end
		local rig = rider.Rig
		if not rig or not MoveRig.alive(rig) then
			rig = MoveRig.find(rider.Character)
			rider.Rig = rig
		end
		if rig then
			local layer = rider.Layers[1]
			BoardPose.evaluate(rider.State, layer.Pose)
			layer.Weight = 1 -- the pose eases in by itself (BoardPose.weight)
			MoveRig.step(rig, rider.Layers, 1)
		end
	end
end

---------------------------------------------------------------- RIDE

local function rideHint(): (string, string)
	if usingGamepad() then
		local ok, image = pcall(function(): string
			return UserInputService:GetImageForKeyCode(HoverboardController.GamepadKey)
		end)
		return "", if ok and type(image) == "string" then image else ""
	elseif isPhone() then
		return "", ""
	end
	return "H", ""
end

updateRideButton = function()
	local button = ride
	if not button then
		return
	end
	local _, equipped = snapshotBoards()
	local riding = HoverboardController.isRiding()
	button.Holder.Visible = equipped ~= "" or riding
	local hint, glyph = rideHint()
	HoverboardView.setRiding(button, riding, hint, glyph)
end

local function showMessage(text: string, kind: string?)
	local view = refs
	if not view then
		return
	end
	messageToken += 1
	local token = messageToken
	HoverboardView.showMessage(view, text, MESSAGE_COLORS[kind or "Info"] or Theme.Info)
	task.delay(MESSAGE_TIME, function()
		if token == messageToken and refs then
			HoverboardView.hideMessage(refs)
		end
	end)
end

-- The RIDE button / H / L2: on or off the equipped board (no board: the panel opens).
function HoverboardController.toggleRide()
	local _, equipped = snapshotBoards()
	local riding = HoverboardController.isRiding()
	if equipped == "" and not riding then
		HudController.toast("Get a hoverboard first!", "Info")
		HoverboardController.open()
		return
	end
	if PlayerControls.owner() ~= nil or CleaningController.isActive() then
		return
	end
	local now = os.clock()
	if now < rideLockedUntil then
		return
	end
	rideLockedUntil = now + RIDE_LOCK
	Net.send("HoverboardAction", { Action = "Ride", On = not riding })
	Sfx.play("UIClick")
end

local function onRideKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	-- while a menu has the gamepad selection it keeps its buttons: leave it alone
	if input.KeyCode == HoverboardController.GamepadKey and GuiService.SelectedObject ~= nil then
		return Enum.ContextActionResult.Pass
	end
	HoverboardController.toggleRide()
	return Enum.ContextActionResult.Sink
end

---------------------------------------------------------------- the panel

local function locked(): boolean
	return os.clock() < lockedUntil
end

local function send(payload: { [string]: any })
	lockedUntil = os.clock() + SEND_LOCK
	Net.send("HoverboardAction", payload)
	Sfx.play("UIClick")
end

local function refresh()
	local view = refs
	if not view then
		return
	end
	local owned, equipped, coins = snapshotBoards()
	HoverboardView.setCards(view, owned, equipped, coins)
end

local function fit(view: HoverboardView.Refs)
	local camera = Workspace.CurrentCamera
	local scale = HudController.uiScale()
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local compact = isPhone() or scale <= 0.75 or size.Y < 520
	HoverboardView.layout(view, compact, size.X / scale, (size.Y - inset.Y) / scale)
end

local function applyHint(view: HoverboardView.Refs)
	if usingGamepad() then
		local ok, image = pcall(function(): string
			return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		end)
		view.HintGlyph.Image = if ok and type(image) == "string" then image else ""
		HoverboardView.setHint(view, "Gamepad", "Choose a board · B: close")
	elseif isPhone() then
		HoverboardView.setHint(view, "Touch", "Tap a card")
	else
		HoverboardView.setHint(view, "Mouse", "Click a card · H: ride · Backspace: close")
	end
end

local function selectDefault(view: HoverboardView.Refs)
	if usingGamepad() and isOpen then
		GuiService.SelectedObject = HoverboardView.firstButton(view)
	end
end

local function onCard(card: HoverboardView.Card)
	if not isOpen then
		return
	end
	local board = card.Board
	local state = card.State
	if state == "Buy" then
		if not locked() then
			send({ Action = "Buy", Board = board.Id })
		end
	elseif state == "BuyLocked" then
		local _, _, coins = snapshotBoards()
		local missing = math.max(1, (board.Price or 0) - coins)
		showMessage(`The {board.Name} costs {Format.money(board.Price or 0)}. You need {Format.money(missing)} more.`, "Deny")
	elseif state == "Equip" then
		if not locked() then
			send({ Action = "Equip", Board = board.Id })
		end
	elseif state == "Robux" then
		local id = HoverboardData.passId(board)
		if HoverboardData.canPrompt(board) and HoverboardView.receiptsReady() and id > 0 then
			Sfx.play("UIClick")
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, id)
			end)
		end
	elseif state == "Soon" then
		showMessage(`The {board.Name} is coming soon!`, "Info")
	else
		showMessage(`The {board.Name} is your board. Press RIDE to hover.`, "Info")
	end
end

local function stopAnimation()
	local tween = animTween
	animTween = nil
	if tween then
		tween:Cancel()
	end
end

local function ensureProgress(): NumberValue
	local existing = progress
	if existing then
		return existing
	end
	local value = Instance.new("NumberValue")
	value.Name = "HoverboardsOpening"
	value.Value = HoverboardView.OpenTime
	value.Changed:Connect(function(seconds: number)
		local view = refs
		if view then
			HoverboardView.pose(view, seconds)
		end
	end)
	progress = value
	return value
end

local function play(to: number, seconds: number, done: (() -> ())?)
	stopAnimation()
	local value = ensureProgress()
	local tween = TweenService:Create(value, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Value = to })
	animTween = tween
	tween.Completed:Connect(function()
		if animTween == tween then
			animTween = nil
			if done then
				done()
			end
		end
	end)
	tween:Play()
end

local function ensureView(): HoverboardView.Refs
	local existing = refs
	if existing then
		return existing
	end
	local view = HoverboardView.build(false)
	view.Gui.Parent = player:WaitForChild("PlayerGui")
	view.Close.Activated:Connect(function()
		HoverboardController.close()
		Sfx.play("UIClick")
	end)
	for _, card in view.Cards do
		card.Button.Activated:Connect(function()
			onCard(card)
		end)
	end
	refs = view
	return view
end

local function onClose(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not isOpen then
		return Enum.ContextActionResult.Pass
	end
	HoverboardController.close()
	Sfx.play("UIClick")
	return Enum.ContextActionResult.Sink
end

function HoverboardController.open()
	local view = ensureView()
	if isOpen then
		refresh()
		return
	end
	isOpen = true
	MenuPanels.closeOthers("HoverboardController")
	fit(view)
	HoverboardView.hideMessage(view)
	applyHint(view)
	refresh()
	view.Gui.Enabled = true
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, onClose, false, CLOSE_PRIORITY, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ensureProgress().Value = 0
	HoverboardView.pose(view, 0)
	play(HoverboardView.OpenTime, HoverboardView.OpenTime)
	selectDefault(view)
	Sfx.play("UIClick")
end

function HoverboardController.close(instant: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local view = refs
	if not view then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.Gui) then
		GuiService.SelectedObject = nil
	end
	local gui = view.Gui
	if instant then
		stopAnimation()
		gui.Enabled = false
		return
	end
	local value = ensureProgress()
	play(0, HoverboardView.CloseTime * value.Value / HoverboardView.OpenTime, function()
		if not isOpen then
			gui.Enabled = false
		end
	end)
end

-- The side menu's HOVER button: opens the panel, or closes it when it is open.
function HoverboardController.toggle()
	if isOpen then
		HoverboardController.close()
	else
		HoverboardController.open()
	end
end

---------------------------------------------------------------- the RIDE button

local function bounce(scale: UIScale, target: number, seconds: number)
	TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end

local function hookBounce(button: GuiButton, scale: UIScale)
	button.MouseEnter:Connect(function()
		bounce(scale, 1.08, 0.18)
	end)
	button.MouseLeave:Connect(function()
		bounce(scale, 1, 0.18)
	end)
	button.SelectionGained:Connect(function()
		bounce(scale, 1.08, 0.18)
	end)
	button.SelectionLost:Connect(function()
		bounce(scale, 1, 0.18)
	end)
	button.MouseButton1Down:Connect(function()
		bounce(scale, 0.9, 0.08)
	end)
	button.MouseButton1Up:Connect(function()
		bounce(scale, 1, 0.25)
	end)
end

local function buildRide()
	local hud = HudController.refs()
	local button = HoverboardView.rideButton(hud.Menu)
	ride = button
	hookBounce(button.Button, button.Scale)
	button.Button.Activated:Connect(HoverboardController.toggleRide)
	updateRideButton()
end

---------------------------------------------------------------- lifecycle

function HoverboardController.init()
	Net.listen("HoverboardResult", function(result)
		if type(result) ~= "table" then
			return
		end
		-- an answer arrived: the next request may go
		lockedUntil = 0
		if result.Action == "Ride" and result.Ok == false and result.Reason == "NoBoard" then
			HoverboardController.open()
		end
	end)
	Net.listen("Notify", function(message)
		if isOpen and type(message) == "table" and type(message.Text) == "string" then
			showMessage(message.Text, message.Kind)
		end
	end)
	StateController.onChanged(function()
		lockedUntil = 0
		refresh()
		updateRideButton()
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(buyer: Player, passId: number, purchased: boolean)
		-- never grant here (the server's MonetizationService does): only a friendly line
		if buyer == player and purchased and isOpen and HoverboardData.byPass(passId) then
			showMessage("Thank you! Unlocking your board...", "Reward")
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		updateRideButton()
		local view = refs
		if view and isOpen then
			applyHint(view)
			selectDefault(view)
		end
	end)
	player.CharacterRemoving:Connect(function()
		HoverboardController.close(true)
	end)
end

function HoverboardController.start()
	buildRide()
	ContextActionService:BindAction(RIDE_ACTION, onRideKey, false, HoverboardController.Key, HoverboardController.GamepadKey)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerRemoving:Connect(removeRider)
	local function readSystem()
		local ok, on = pcall(function(): boolean
			return GuiService.ReducedMotionEnabled
		end)
		systemReduced = ok and on == true
	end
	readSystem()
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(readSystem)
	end)
	SettingsController.onChanged(function(current: any)
		settingsReduced = current.ReduceMotion == true
	end)
	RunService.RenderStepped:Connect(animate)
	RunService.Stepped:Connect(function()
		local ok, err: any = pcall(poseStep)
		if not ok then
			warn("[HoverboardController] pose: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(HoverboardController.LodInterval)
			local ok, err: any = pcall(lodStep)
			if not ok then
				warn("[HoverboardController] " .. tostring(err))
			end
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local view = refs
			if view and isOpen then
				fit(view)
			end
		end)
	end
end

return HoverboardController
