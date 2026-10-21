--[[
	MoveController: the player's procedural moves (Config/MoveConfig) on
	every R15 character near you, yours and the others'. No uploaded
	animations: Moves/MoveMath poses go onto Motor6D.Transform through
	Moves/MoveRig, on top of the default Animate script (walk, idle, tool
	hold), in ONE RunService.Stepped for all characters (after the Animator
	wrote the frame's Transforms). Looks only: the server never sees them,
	the HumanoidRootPart and the physics never move.

	Triggers
	  Carry      your / their CarryCount player attribute > 0 (CarryService)
	  Spray, Hammer  the character attribute MoveLoop (MoveService: cleaning,
	             forging; your own camera is in that close-up, the others see it)
	  Throw      the throw input (InteractController calls playLocal("Throw"):
	             Q / RB / the Throw button, no new binding); Net "Move" tells
	             the server, which shows it to the others
	  Recoil     your blaster firing (MiningController.isFiring: mouse, touch
	             or R2): a kick when the beam starts, smaller ones every
	             MoveConfig.RecoilRepeat while it stays on; the others' from
	             their BlastHit effects (the Fx event)
	  Wave       you equipped a golem (ActionResult Golem Equip / EquipBest)
	  Shrug      the server refused something (a Notify of Kind "Deny"), at
	             most every MoveConfig.ShrugGap
	  Celebrate, BigCelebrate, CashToss   the character attribute Move
	             "<Name>:<seq>" (MoveService); one that reaches YOUR
	             character during a close-up waits until it ends (at most
	             MoveConfig.PendingSeconds)

	Never fights other systems: no moves while seated, swimming, climbing,
	ragdolled or dead, on a hoverboard (HoverboardController drives that
	pose), and none on your own character while a close-up camera holds
	it (cleaning, the Foundry, build mode, the Vault, the elevator ride:
	a Scriptable camera or PlayerControls claimed). R6 characters are
	skipped. Range / on-screen / state are checked every
	MoveConfig.CheckInterval; characters farther than MoveConfig.Range or
	off screen cost nothing per frame. The player's Roblox "Reduce Motion"
	(GuiService.ReducedMotionEnabled) swaps the spin jump for the plain
	celebration (MoveConfig.ReducedMotion). setEnabled(false) turns every
	move off (for a settings toggle).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoveConfig = require(Shared.Config.MoveConfig)
local HoverboardData = require(Shared.Config.HoverboardData)
local MoveMath = require(Shared.Moves.MoveMath)
local MoveRig = require(Shared.Moves.MoveRig)
local MoveRules = require(Shared.Moves.MoveRules)
local Net = require(Shared.Net)
local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)

local MoveController = {}

type Slot = {
	Move: MoveConfig.Move?,
	Start: number,
	Stop: number?,
	Scale: number,
	Layer: MoveRig.Layer,
}
type Entry = {
	Player: Player,
	Character: Model,
	Local: boolean,
	Humanoid: Humanoid?,
	Root: BasePart?,
	Rig: MoveRig.Rig?,
	R6: boolean,
	Slots: { Slot },
	Layers: { MoveRig.Layer },
	Active: boolean,
	Blocked: boolean,
	Holding: boolean,
	Seq: number?,
	LoopName: string?,
	Pending: string?,
	PendingAt: number,
	KickAt: number,
	Connections: { RBXScriptConnection },
}

local SLOT_INDEX = { Loop = 1, Action = 2, Kick = 3 } :: { [string]: number }
local NO_OVERRIDE: { [string]: boolean } = {}
local SEND_GAP = 0.35 -- seconds between Net "Move" sends (under its rate limit)

local entries: { [Model]: Entry } = {}
local list: { Entry } = {}
local enabled = true
local localPlayer: Player? = nil
local isFiring: () -> boolean = function(): boolean
	return false
end
local wasFiring = false
local nextKick = 0
local lastShrug = -math.huge
local lastSend = -math.huge
local checkTimer = 0

---------------------------------------------------------------- slots

local function newSlot(): Slot
	return { Move = nil, Start = 0, Stop = nil, Scale = 1, Layer = { Pose = {}, Weight = 0, Override = NO_OVERRIDE } }
end

-- Starts a move in its slot; false when the slot keeps a stronger move (MoveRules.replaces).
local function start(entry: Entry, name: string, scale: number?): boolean
	local move = MoveConfig.Moves[MoveRules.substitute(name, GuiService.ReducedMotionEnabled)]
	if not move then
		return false
	end
	local slot = entry.Slots[SLOT_INDEX[move.Slot] or 2]
	local now = os.clock()
	local running = slot.Move
	if running then
		local finished = MoveMath.done(running, now - slot.Start, if slot.Stop then slot.Stop - slot.Start else nil)
		if not MoveRules.replaces(running, finished, move) then
			return false -- a shrug never cuts a celebration short
		end
	end
	slot.Move = move
	slot.Start = now
	slot.Stop = nil
	slot.Scale = scale or 1
	table.clear(slot.Layer.Pose)
	slot.Layer.Override = MoveMath.overrides(move)
	return true
end

-- Starts / stops the entry's loop (Carry, Spray, Hammer) to match its attributes.
local function updateLoop(entry: Entry)
	local carry = entry.Player:GetAttribute(MoveConfig.CarryAttribute)
	local want = MoveRules.loopFor(carry, entry.Character:GetAttribute(MoveConfig.LoopAttribute))
	if want == entry.LoopName then
		return
	end
	entry.LoopName = want
	local slot = entry.Slots[1]
	if want then
		local current = slot.Move
		local stop = slot.Stop
		if current and current.Name == want and (not stop or not MoveMath.done(current, os.clock() - slot.Start, stop - slot.Start)) then
			slot.Stop = nil -- the same loop again while it was fading out: keep it going
		else
			start(entry, want)
		end
	elseif slot.Move and not slot.Stop then
		slot.Stop = os.clock()
	end
end

---------------------------------------------------------------- entries

local function removeEntry(entry: Entry)
	if entries[entry.Character] ~= entry then
		return
	end
	entries[entry.Character] = nil
	local index = table.find(list, entry)
	if index then
		table.remove(list, index)
	end
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	local rig = entry.Rig
	if rig and entry.Holding then
		MoveRig.release(rig)
	end
end

local function onMoveAttribute(entry: Entry)
	local name, seq = MoveRules.decode(entry.Character:GetAttribute(MoveConfig.Attribute))
	if not name or seq == entry.Seq then
		return
	end
	entry.Seq = seq
	if entry.Local and MoveConfig.ClientMoves[name] then
		return -- you played it the moment you pressed
	end
	if entry.Blocked then
		if entry.Local then
			entry.Pending = name
			entry.PendingAt = os.clock()
		end
		return
	end
	start(entry, name)
end

local function addEntry(player: Player, character: Model)
	if entries[character] then
		return
	end
	local entry: Entry = {
		Player = player,
		Character = character,
		Local = player == localPlayer,
		Humanoid = nil,
		Root = nil,
		Rig = nil,
		R6 = false,
		Slots = { newSlot(), newSlot(), newSlot() },
		Layers = {},
		Active = false,
		Blocked = false,
		Holding = false,
		Seq = nil,
		LoopName = nil,
		Pending = nil,
		PendingAt = 0,
		KickAt = -math.huge,
		Connections = {},
	}
	for i, slot in entry.Slots do
		entry.Layers[i] = slot.Layer
	end
	-- a move set before this character reached you is old news
	local _, seq = MoveRules.decode(character:GetAttribute(MoveConfig.Attribute))
	entry.Seq = seq
	entries[character] = entry
	table.insert(list, entry)
	table.insert(
		entry.Connections,
		character:GetAttributeChangedSignal(MoveConfig.Attribute):Connect(function()
			onMoveAttribute(entry)
		end)
	)
	table.insert(
		entry.Connections,
		character:GetAttributeChangedSignal(MoveConfig.LoopAttribute):Connect(function()
			updateLoop(entry)
		end)
	)
	updateLoop(entry)
end

local function entryOf(player: Player?): Entry?
	local character = player and player.Character
	return if character then entries[character] else nil
end

local function hookPlayer(player: Player)
	if player.Character then
		addEntry(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character: Model)
		addEntry(player, character)
	end)
	player.CharacterRemoving:Connect(function(character: Model)
		local entry = entries[character]
		if entry then
			removeEntry(entry)
		end
	end)
	player:GetAttributeChangedSignal(MoveConfig.CarryAttribute):Connect(function()
		local entry = entryOf(player)
		if entry then
			updateLoop(entry)
		end
	end)
end

---------------------------------------------------------------- checks (every CheckInterval)

local function closeUp(camera: Camera?): boolean
	return (camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable) or PlayerControls.owner() ~= nil
end

local function refreshParts(entry: Entry)
	local character = entry.Character
	local humanoid = entry.Humanoid
	if not humanoid or humanoid.Parent ~= character then
		humanoid = character:FindFirstChildOfClass("Humanoid")
		entry.Humanoid = humanoid
	end
	local root = entry.Root
	if not root or root.Parent ~= character then
		local found = character:FindFirstChild("HumanoidRootPart")
		root = if found and found:IsA("BasePart") then found else nil
		entry.Root = root
	end
	if humanoid then
		entry.R6 = humanoid.RigType == Enum.HumanoidRigType.R6
	end
	local rig = entry.Rig
	if not entry.R6 and humanoid and (not rig or not MoveRig.alive(rig)) then
		entry.Rig = MoveRig.find(character)
		entry.Holding = false
	end
end

local function check(now: number)
	local camera = Workspace.CurrentCamera
	local localCloseUp = closeUp(camera)
	for i = #list, 1, -1 do
		local entry = list[i]
		local character = entry.Character
		if not character.Parent then
			removeEntry(entry)
			continue
		end
		refreshParts(entry)
		local humanoid, root, rig = entry.Humanoid, entry.Root, entry.Rig
		local visible = false
		if rig and root and camera then
			local distance = (camera.CFrame.Position - root.Position).Magnitude
			local _, onScreen = camera:WorldToViewportPoint(root.Position)
			visible = MoveRules.visible(distance, onScreen)
		end
		local blocked = MoveRules.blocked(
			if humanoid then humanoid:GetState().Name else nil,
			humanoid ~= nil and humanoid.Sit,
			character:GetAttribute(HoverboardData.Attribute) ~= nil,
			entry.Local and localCloseUp,
			if humanoid then humanoid.Health else nil
		)
		entry.Blocked = blocked
		local active = enabled and visible and not blocked and rig ~= nil
		if entry.Active and not active and rig and entry.Holding then
			MoveRig.release(rig)
			entry.Holding = false
		end
		if blocked then
			-- whatever played stops here (it never resumes half-way after a ride or a seat)
			entry.Slots[2].Move = nil
			entry.Slots[3].Move = nil
		end
		entry.Active = active
		updateLoop(entry)
		local pending = entry.Pending
		if pending and not blocked then
			entry.Pending = nil
			if now - entry.PendingAt <= MoveConfig.PendingSeconds then
				start(entry, pending)
			end
		end
	end
end

---------------------------------------------------------------- every frame

local function stepEntry(entry: Entry, now: number)
	local rig = entry.Rig
	if not rig then
		return
	end
	local any = false
	for i = 1, 3 do
		local slot = entry.Slots[i]
		local layer = slot.Layer
		local move = slot.Move
		if move then
			local t = now - slot.Start
			local stop = if slot.Stop then slot.Stop - slot.Start else nil
			if MoveMath.done(move, t, stop) then
				slot.Move = nil
				layer.Weight = 0
			else
				local weight = MoveMath.weight(move, t, stop) * slot.Scale
				MoveMath.evaluate(move, t, weight, layer.Pose)
				layer.Weight = weight
				any = true
			end
		else
			layer.Weight = 0
		end
	end
	if any or entry.Holding then
		MoveRig.step(rig, entry.Layers, 3)
		entry.Holding = any
	end
end

local function kick(entry: Entry, scale: number)
	if not entry.Blocked then
		start(entry, "Recoil", scale)
	end
end

-- your blaster: a kick when the beam starts, smaller ones while it stays on
local function updateRecoil(now: number)
	local entry = entryOf(localPlayer)
	local firing = isFiring()
	if entry and firing then
		if not wasFiring then
			kick(entry, 1)
			nextKick = now + MoveConfig.RecoilRepeat
		elseif now >= nextKick then
			kick(entry, MoveConfig.RecoilRepeatWeight)
			nextKick = now + MoveConfig.RecoilRepeat
		end
	end
	wasFiring = firing
end

local function onStepped(_time: number, dt: number)
	local now = os.clock()
	checkTimer += dt
	if checkTimer >= MoveConfig.CheckInterval then
		checkTimer = 0
		check(now)
	end
	if not enabled then
		return
	end
	updateRecoil(now)
	for i = 1, #list do
		local entry = list[i]
		if entry.Active then
			stepEntry(entry, now)
		end
	end
end

---------------------------------------------------------------- public

-- Plays a client move on your character now and tells the server (Throw, Wave, Shrug).
function MoveController.playLocal(name: string)
	if not MoveRules.clientAllowed(name) then
		return
	end
	local entry = entryOf(localPlayer)
	if not entry or entry.Blocked then
		return
	end
	if not start(entry, name) then
		return
	end
	local now = os.clock()
	if now - lastSend >= SEND_GAP then
		lastSend = now
		Net.send("Move", name)
	end
end

-- All moves on / off (a settings toggle can call this).
function MoveController.setEnabled(on: boolean)
	enabled = on
	if not on then
		for _, entry in list do
			local rig = entry.Rig
			if rig and entry.Holding then
				MoveRig.release(rig)
			end
			entry.Holding = false
			entry.Active = false
		end
	end
end

function MoveController.isEnabled(): boolean
	return enabled
end

function MoveController.init()
	localPlayer = Players.LocalPlayer
end

function MoveController.start()
	-- required here, not at the top: the moves never need the mining code to load
	local MiningController = require(script.Parent.MiningController)
	isFiring = MiningController.isFiring

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		for i = #list, 1, -1 do
			if list[i].Player == player then
				removeEntry(list[i])
			end
		end
	end)

	-- the others' blasters: a kick on their BlastHit effects (yours come from isFiring)
	Net.listen("Fx", function(kind: any, _position: any, _glow: any, _stage: any, shooter: any)
		if kind ~= "BlastHit" or typeof(shooter) ~= "Instance" or not shooter:IsA("Player") or shooter == localPlayer then
			return
		end
		local entry = entryOf(shooter :: Player)
		if not entry or not entry.Active then
			return
		end
		local now = os.clock()
		if now - entry.KickAt < MoveConfig.RecoilRepeat then
			return
		end
		local fresh = now - entry.KickAt > 0.6
		entry.KickAt = now
		kick(entry, if fresh then 1 else MoveConfig.RecoilRepeatWeight)
	end)
	-- you equipped a golem: wave
	Net.listen("ActionResult", function(result: any)
		if type(result) == "table" and result.Action == "Golem" and result.Ok == true then
			if result.Op == "Equip" or result.Op == "EquipBest" then
				MoveController.playLocal("Wave")
			end
		end
	end)
	-- the server refused something: shrug (not too often)
	Net.listen("Notify", function(message: any)
		if type(message) ~= "table" or message.Kind ~= "Deny" then
			return
		end
		local now = os.clock()
		if now - lastShrug >= MoveConfig.ShrugGap then
			lastShrug = now
			MoveController.playLocal("Shrug")
		end
	end)

	RunService.Stepped:Connect(onStepped)
end

return MoveController
