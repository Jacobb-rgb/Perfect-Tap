--[[
	MoveController: the player's procedural moves (Config/MoveConfig) and the
	emotes (Config/EmoteConfig) on every R15 character near you, yours and
	the others'. No uploaded animations: Moves/MoveMath poses go onto
	Motor6D.Transform through Moves/MoveRig, on top of the default Animate
	script (walk, idle, tool hold), in ONE RunService.Stepped for all
	characters (after the Animator wrote the frame's Transforms). Looks
	only: the HumanoidRootPart and the physics never move.

	Switches (Config/AnimConfig, owner 2026-10-21):
	  PlayerMoves  the moves below. Off (today): nothing of them runs: no
	               Stepped loop for them, no Fx / ActionResult / Notify
	               listeners, no Move / MoveLoop / CarryCount listeners, no
	               sends (playLocal returns at once), no tag scans
	  Emotes       the 12 emotes (the EMOTES menu: EmoteController). The
	               Stepped loop runs only while an emote plays on a
	               character within range and on screen; it disconnects when
	               none does (a slow check every SlowCheck seconds while an
	               emote plays out of range only)

	Moves (PlayerMoves)
	  Carry      your / their CarryCount player attribute > 0 (CarryService)
	  Spray          the character attribute MoveLoop (MoveService)
	  Throw      the throw input (InteractController calls playLocal("Throw"))
	  Recoil     your blaster firing (MiningController.isFiring), the others'
	             BlastHit effects (the Fx event)
	  Wave       you equipped a golem (ActionResult Golem Equip / EquipBest)
	  Shrug      a Notify of Kind "Deny", at most every MoveConfig.ShrugGap
	  Celebrate, BigCelebrate, CashToss   the character attribute Move
	             (MoveService); yours waits out a close-up (PendingSeconds)

	Emotes (Emotes)
	  playEmote(name) starts one on your character at once and asks the server
	  (Net "Emote"); the server sets the character attribute Emote =
	  "<Name>:<seq>" ("" = stopped) and every client plays it on that
	  character. Not while carrying ore, in a close-up (cleaning, build mode,
	  the vault...), on a hoverboard, seated or dead; the Blaster Spin only
	  with the blaster in hand (EmoteRules). A playing emote stops with its
	  outro (the finishing pose; quicker while moving) when the character
	  moves or jumps, picks a tool up (the Blaster Spin: puts the blaster
	  away), fires, starts carrying, or (yours) a menu panel opens, or you
	  pick it again; a seat, a board or death stop it at once. Picking any
	  emote but the Blaster Spin puts a tool in your hand away first (as
	  cleaning and build mode do). Yours tells the server (Net "Emote" "")
	  whenever its start was sent (also before the server's echo came back),
	  the others' stop on every client by the same rules. Reduce Motion
	  keeps the emotes (you picked them). The Gem Juggle juggles three small
	  pooled Neon gems (Moves/EmoteProps; at most EmoteProps.MaxJugglers
	  characters, within range only; any other emote gives them back). The
	  Blaster Spin twirls the blaster: its RightGrip pose turns the RightGrip
	  weld's C0 on every client (BlasterFx's kick moves C1), put back when it
	  ends. A stopped emote on a character out of range is dropped, so the
	  slow check sleeps.

	Never fights other systems: no moves while seated, swimming, climbing,
	ragdolled or dead, on a hoverboard (HoverboardController drives that
	pose), and none on your own character in a close-up (a Scriptable camera
	or PlayerControls claimed). R6 characters are skipped. Characters
	farther than MoveConfig.Range or off screen cost nothing per frame.
	setEnabled(false) turns everything off.

	Reduce Motion (the game's SETTINGS toggle or Roblox's own) changes what
	YOU see of the moves: Celebrate / BigCelebrate / CashToss become their
	calm versions, the extras (Wave, Shrug) are skipped. The blaster arm: an
	extra never plays while you hold a tool or fire; while a blaster fires
	every move but the Recoil kick leaves the arms alone (MoveRules).

	Env: the services and the lazily required modules the controller uses,
	swappable for the Lune tests (tests/EmotesLive.spec.luau proves the
	switches by the connections made).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimConfig = require(Shared.Config.AnimConfig)
local EmoteConfig = require(Shared.Config.EmoteConfig)
local HoverboardData = require(Shared.Config.HoverboardData)
local MoveConfig = require(Shared.Config.MoveConfig)
local EmoteProps = require(Shared.Moves.EmoteProps)
local EmoteRules = require(Shared.Moves.EmoteRules)
local MoveMath = require(Shared.Moves.MoveMath)
local MoveRig = require(Shared.Moves.MoveRig)
local MoveRules = require(Shared.Moves.MoveRules)
local Net = require(Shared.Net)

local MoveController = {}

MoveController.SlowCheck = 0.5 -- seconds between checks while emotes play only out of range
MoveController.MovingOutro = 2.5 -- an outro plays this much faster when the character walks off
MoveController.EchoGrace = 1.0 -- seconds: a "" echo this soon after you started a new emote is your earlier stop's

type Slot = {
	Move: MoveConfig.Move?,
	Start: number,
	Stop: number?,
	Scale: number,
	OutroSpeed: number,
	Layer: MoveRig.Layer,
}
type Entry = {
	Player: Player,
	Character: Model,
	Local: boolean,
	Humanoid: Humanoid?,
	Root: BasePart?,
	RightHand: BasePart?,
	LeftHand: BasePart?,
	Rig: MoveRig.Rig?,
	R6: boolean,
	Slots: { Slot },
	Layers: { MoveRig.Layer },
	Active: boolean,
	Blocked: boolean,
	Holding: boolean,
	Seq: number?,
	EmoteSeq: number?,
	LoopName: string?,
	Pending: string?,
	PendingAt: number,
	KickAt: number,
	FiredAt: number,
	StateName: string?,
	Gems: { BasePart }?,
	Grip: Weld?, -- the RightGrip weld the Blaster Spin turns
	GripBase: CFrame?, -- its C0 before
	Connections: { RBXScriptConnection },
}

export type Env = {
	RunService: any,
	Players: any,
	GuiService: any,
	Workspace: any,
	listen: (name: string, handler: (...any) -> ()) -> any,
	send: (name: string, ...any) -> (),
	firing: (() -> boolean)?,
	controlsOwner: (() -> string?)?,
	panelOpen: (() -> boolean)?,
	onSettings: ((callback: (any) -> ()) -> ())?,
	propsFolder: (() -> Instance)?,
	clock: () -> number,
}

MoveController.Env = {
	RunService = game:GetService("RunService"),
	Players = game:GetService("Players"),
	GuiService = game:GetService("GuiService"),
	Workspace = game:GetService("Workspace"),
	listen = function(name: string, handler: (...any) -> ()): any
		return Net.listen(name, handler)
	end,
	send = function(name: string, ...: any)
		Net.send(name, ...)
	end,
	clock = os.clock,
} :: Env

local SLOT_INDEX = { Loop = 1, Action = 2, Kick = 3, Emote = 4 } :: { [string]: number }
local SLOT_NAMES = { "Loop", "Action", "Kick", "Emote" }
local EMOTE = 4
local SLOTS = 4
local NO_OVERRIDE: { [string]: boolean } = {}
local SEND_GAP = 0.35 -- seconds between Net "Move" sends (under its rate limit)
local PALM = CFrame.new(0, -0.35, -0.1)

local entries: { [Model]: Entry } = {}
local list: { Entry } = {}
local enabled = true
local started = false
local playerMoves = false
local emotesOn = false
local localPlayer: Player? = nil
local stepConnection: RBXScriptConnection? = nil
local slowQueued = false
local generation = 0 -- a reset (tests) drops the slow checks queued before it
local isFiring: () -> boolean = function(): boolean
	return false
end
local controlsOwner: () -> string? = function(): string?
	return nil
end
local panelOpen: () -> boolean = function(): boolean
	return false
end
local wasFiring = false
local nextKick = 0
local lastShrug = -math.huge
local lastSend = -math.huge
local lastEmoteStart: { [string]: number } = {}
local emoteSent = false -- your emote's start went to the server and no "" since
local checkTimer = 0
local settingsReduced = false -- the game's SETTINGS "Reduce motion"
local systemReduced = false -- Roblox's own Reduce Motion
local gemPool = EmoteProps.newPool(EmoteProps.makeGem)
local gemFolder: Instance? = nil

local function clockNow(): number
	return MoveController.Env.clock()
end

local function reducedMotion(): boolean
	return settingsReduced or systemReduced
end

---------------------------------------------------------------- slots

local function newSlot(): Slot
	return { Move = nil, Start = 0, Stop = nil, Scale = 1, OutroSpeed = 1, Layer = { Pose = {}, Weight = 0, Override = NO_OVERRIDE } }
end

-- the slot's move time: after a stop the outro may run faster
local function slotTime(slot: Slot, now: number): (number, number?)
	local stop = slot.Stop
	if stop then
		return stop - slot.Start + (now - stop) * slot.OutroSpeed, stop - slot.Start
	end
	return now - slot.Start, nil
end

-- Starts a move in its slot; false when the slot keeps a stronger move (MoveRules.replaces).
local function start(entry: Entry, name: string, scale: number?): boolean
	local chosen = MoveRules.substitute(name, reducedMotion())
	local move = if chosen then MoveConfig.Moves[chosen] else nil
	if not move then
		return false -- an extra under Reduce Motion
	end
	local slot = entry.Slots[SLOT_INDEX[move.Slot] or 2]
	local now = clockNow()
	local running = slot.Move
	if running then
		local t, stop = slotTime(slot, now)
		if not MoveRules.replaces(running, MoveMath.done(running, t, stop), move) then
			return false -- a shrug never cuts a celebration short
		end
	end
	slot.Move = move
	slot.Start = now
	slot.Stop = nil
	slot.Scale = scale or 1
	slot.OutroSpeed = 1
	table.clear(slot.Layer.Pose)
	slot.Layer.Override = MoveMath.overrides(move)
	return true
end

-- Starts / stops the entry's loop (Carry, Spray) to match its attributes.
local function updateLoop(entry: Entry)
	if not playerMoves then
		return
	end
	local carry = entry.Player:GetAttribute(MoveConfig.CarryAttribute)
	local want = MoveRules.loopFor(carry, entry.Character:GetAttribute(MoveConfig.LoopAttribute))
	if want == entry.LoopName then
		return
	end
	entry.LoopName = want
	local slot = entry.Slots[1]
	if want then
		local current = slot.Move
		local t, stop = slotTime(slot, clockNow())
		if current and current.Name == want and (not stop or not MoveMath.done(current, t, stop)) then
			slot.Stop = nil -- the same loop again while it was fading out: keep it going
		else
			start(entry, want)
		end
	elseif slot.Move and not slot.Stop then
		slot.Stop = clockNow()
	end
end

---------------------------------------------------------------- the emote slot

local function releaseGems(entry: Entry)
	if entry.Gems then
		entry.Gems = nil
		gemPool.release(entry)
	end
end

local function emoteName(entry: Entry): string?
	local slot = entry.Slots[EMOTE]
	local move = slot.Move
	return if move and not slot.Stop then move.Name else nil
end

local function startEmote(entry: Entry, name: string)
	local move = EmoteConfig.Emotes[name]
	if not move then
		return
	end
	if move.Name ~= "GemJuggle" then
		releaseGems(entry) -- (switching from the Gem Juggle: the gems go back, none hang in the air)
	end
	local slot = entry.Slots[EMOTE]
	slot.Move = move
	slot.Start = clockNow()
	slot.Stop = nil
	slot.Scale = 1
	slot.OutroSpeed = 1
	table.clear(slot.Layer.Pose)
	slot.Layer.Override = MoveMath.overrides(move)
end

--[[
	The Blaster Spin's twirl: its RightGrip pose turns the held tool about
	the hand, on the RightGrip weld's C0 (Handle = hand * C0 * pose *
	C1:Inverse(), like the preview; BlasterFx's kick moves C1 only).
	`pose` nil puts the grip back as it was.
]]
local function setGrip(entry: Entry, pose: CFrame?)
	local weld = entry.Grip
	if weld and (pose == nil or weld.Parent ~= entry.RightHand) then
		-- put back (or the tool was equipped again: a new weld)
		local base = entry.GripBase
		entry.Grip = nil
		entry.GripBase = nil
		if base and weld.Parent then
			weld.C0 = base
		end
		weld = nil
	end
	if pose == nil then
		return
	end
	if not weld then
		local hand = entry.RightHand
		local found = if hand then hand:FindFirstChild("RightGrip") else nil
		if not found or not found:IsA("Weld") then
			return
		end
		weld = found
		entry.Grip = found
		entry.GripBase = found.C0
	end
	local base = entry.GripBase
	if weld and base then
		weld.C0 = base * pose
	end
end

-- The emote's outro starts (quicker when the character walks off); `hard`: gone at once.
local function stopEmote(entry: Entry, hard: boolean?, speed: number?)
	local slot = entry.Slots[EMOTE]
	if not slot.Move then
		return
	end
	releaseGems(entry)
	if hard then
		slot.Move = nil
		slot.Layer.Weight = 0
		setGrip(entry, nil)
		return
	end
	if not slot.Stop then
		slot.Stop = clockNow()
		slot.OutroSpeed = speed or 1
	end
end

--[[
	Your emote stopped: the server clears the attribute, so the others stop
	too. Sent whenever your start was sent (the server's echo may not be
	back yet: the attribute can still read "" from the emote before), or
	the attribute still names one; "" while nothing plays is a no-op there.
	Net "Emote" keeps the order: the start always comes first.
]]
local function tellStopped(entry: Entry)
	if not entry.Local then
		return
	end
	if emoteSent or EmoteRules.decode(entry.Character:GetAttribute(EmoteRules.Attribute)) ~= nil then
		emoteSent = false
		MoveController.Env.send("Emote", "")
	end
end

---------------------------------------------------------------- the loop (connected while needed)

local onStepped: (number, number) -> ()
local check: (number) -> ()

local function connectLoop()
	if not stepConnection then
		checkTimer = MoveConfig.CheckInterval -- the first frame checks
		stepConnection = MoveController.Env.RunService.Stepped:Connect(function(time: number, dt: number)
			onStepped(time, dt)
		end)
	end
end

local function disconnectLoop()
	local connection = stepConnection
	if connection then
		stepConnection = nil
		connection:Disconnect()
	end
	for _, entry in list do
		local rig = entry.Rig
		if rig and entry.Holding then
			MoveRig.release(rig)
		end
		entry.Holding = false
		setGrip(entry, nil)
	end
end

local function emoting(entry: Entry): boolean
	return entry.Slots[EMOTE].Move ~= nil or entry.Holding
end

-- With PlayerMoves off: the loop runs only while an emote plays near you, on screen.
local function wake()
	if playerMoves or not started then
		return
	end
	local any, near = false, false
	for _, entry in list do
		if emoting(entry) then
			any = true
			if entry.Active then
				near = true
				break
			end
		end
	end
	if near then
		connectLoop()
	else
		disconnectLoop()
		if any and not slowQueued then
			slowQueued = true
			local queuedIn = generation
			task.delay(MoveController.SlowCheck, function()
				if queuedIn ~= generation or not started then
					return
				end
				slowQueued = false
				check(clockNow())
				wake()
			end)
		end
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
	releaseGems(entry)
	setGrip(entry, nil)
	local rig = entry.Rig
	if rig and entry.Holding then
		MoveRig.release(rig)
	end
end

-- Is this character's blaster firing? (yours: the trigger; the others': a recent BlastHit)
local function firingOf(entry: Entry, now: number): boolean
	if entry.Local then
		return isFiring()
	end
	return now - entry.FiredAt < MoveConfig.FiringHold
end

local function holdsTool(entry: Entry): boolean
	return entry.Character:FindFirstChildOfClass("Tool") ~= nil
end

local function holdsBlaster(entry: Entry): boolean
	local tool = entry.Character:FindFirstChild(EmoteRules.BlasterTool)
	return tool ~= nil and tool:IsA("Tool")
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
	if MoveRules.skipArmed(name, holdsTool(entry), firingOf(entry, clockNow())) then
		return -- an extra never takes the gun arm
	end
	if entry.Blocked then
		if entry.Local then
			entry.Pending = name
			entry.PendingAt = clockNow()
		end
		return
	end
	start(entry, name)
end

-- The server's Emote attribute changed: play / stop it on that character.
local function onEmoteAttribute(entry: Entry)
	local value = entry.Character:GetAttribute(EmoteRules.Attribute)
	local name, seq = EmoteRules.decode(value)
	if not name then
		-- (yours: a "" just after you started a new emote is the echo of your stop before it; your
		-- own rules stop it for every reason the server has)
		local slot = entry.Slots[EMOTE]
		local stale = entry.Local and emoteSent and clockNow() - slot.Start < MoveController.EchoGrace
		if emoteName(entry) and not stale then
			stopEmote(entry)
		end
	elseif seq ~= entry.EmoteSeq then
		entry.EmoteSeq = seq
		-- yours started when you picked it (a late echo after you walked off never restarts it);
		-- the others' play now
		if not entry.Local then
			startEmote(entry, name)
		end
	end
	check(clockNow())
	wake()
end

local function addEntry(player: Player, character: Model)
	if entries[character] then
		return
	end
	local slots: { Slot } = {}
	for _ = 1, SLOTS do
		table.insert(slots, newSlot())
	end
	local entry: Entry = {
		Player = player,
		Character = character,
		Local = player == localPlayer,
		Humanoid = nil,
		Root = nil,
		RightHand = nil,
		LeftHand = nil,
		Rig = nil,
		R6 = false,
		Slots = slots,
		Layers = {},
		Active = false,
		Blocked = false,
		Holding = false,
		Seq = nil,
		EmoteSeq = nil,
		LoopName = nil,
		Pending = nil,
		PendingAt = 0,
		KickAt = -math.huge,
		FiredAt = -math.huge,
		StateName = nil,
		Gems = nil,
		Grip = nil,
		GripBase = nil,
		Connections = {},
	}
	for i, slot in entry.Slots do
		entry.Layers[i] = slot.Layer
	end
	entries[character] = entry
	table.insert(list, entry)
	if playerMoves then
		-- a move set before this character reached you is old news
		local _, seq = MoveRules.decode(character:GetAttribute(MoveConfig.Attribute))
		entry.Seq = seq
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
	if emotesOn then
		-- an emote already on when this character reached you plays from now
		table.insert(
			entry.Connections,
			character:GetAttributeChangedSignal(EmoteRules.Attribute):Connect(function()
				onEmoteAttribute(entry)
			end)
		)
		if EmoteRules.decode(character:GetAttribute(EmoteRules.Attribute)) then
			onEmoteAttribute(entry)
		end
	end
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
			wake()
		end
	end)
	if playerMoves then
		player:GetAttributeChangedSignal(MoveConfig.CarryAttribute):Connect(function()
			local entry = entryOf(player)
			if entry then
				updateLoop(entry)
			end
		end)
	end
end

---------------------------------------------------------------- checks (every CheckInterval)

local function closeUp(camera: any): boolean
	return (camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable) or controlsOwner() ~= nil
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
		local right = character:FindFirstChild("RightHand")
		local left = character:FindFirstChild("LeftHand")
		entry.RightHand = if right and right:IsA("BasePart") then right else nil
		entry.LeftHand = if left and left:IsA("BasePart") then left else nil
	end
end

-- Why your / their playing emote stops now (nil = it plays on). `full`: the slower checks too.
local function emoteStop(entry: Entry, name: string, now: number): string?
	local humanoid = entry.Humanoid
	local carrying = tonumber(entry.Player:GetAttribute(MoveConfig.CarryAttribute)) or 0
	return EmoteRules.stopReason(name, {
		Speed = if humanoid then humanoid.MoveDirection.Magnitude else 0,
		State = entry.StateName,
		Seated = humanoid ~= nil and humanoid.Sit,
		Riding = entry.Character:GetAttribute(HoverboardData.Attribute) ~= nil,
		Tool = holdsTool(entry),
		Blaster = holdsBlaster(entry),
		Firing = firingOf(entry, now),
		Panel = entry.Local and panelOpen(),
		Carrying = carrying > 0,
	})
end

check = function(now: number)
	local camera = MoveController.Env.Workspace.CurrentCamera
	local localCloseUp = closeUp(camera)
	for i = #list, 1, -1 do
		local entry = list[i]
		local character = entry.Character
		if not character.Parent then
			removeEntry(entry)
			continue
		end
		if not playerMoves and not emoting(entry) then
			continue -- (moves off: only emoting characters need a look)
		end
		refreshParts(entry)
		local humanoid, root, rig = entry.Humanoid, entry.Root, entry.Rig
		local visible = false
		if rig and root and camera then
			local distance = (camera.CFrame.Position - root.Position).Magnitude
			local _, onScreen = camera:WorldToViewportPoint(root.Position)
			visible = MoveRules.visible(distance, onScreen)
		end
		local stateName = if humanoid then humanoid:GetState().Name else nil
		entry.StateName = stateName
		local blocked = MoveRules.blocked(
			stateName,
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
			if entry.Slots[EMOTE].Move then
				local wasPlaying = emoteName(entry) ~= nil
				stopEmote(entry, true)
				if wasPlaying then
					tellStopped(entry)
				end
			end
		end
		if not active then
			releaseGems(entry)
			setGrip(entry, nil)
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
		-- the emote's slower stop rules (tools, carrying, a panel, a board...)
		local name = emoteName(entry)
		if name then
			local reason = emoteStop(entry, name, now)
			if reason then
				stopEmote(entry, false, if reason == "Moving" then MoveController.MovingOutro else 1)
				tellStopped(entry)
			end
		end
		-- out of range / off screen, a stopped emote has nothing left to show: it ends here (then
		-- emoting() is false and the slow check sleeps)
		local slot = entry.Slots[EMOTE]
		if not active and slot.Move and slot.Stop then
			slot.Move = nil
			slot.Layer.Weight = 0
		end
	end
end

---------------------------------------------------------------- every frame

-- the three gems of a Gem Juggle, `u` seconds into its loop
local function placeGems(entry: Entry, u: number)
	local right, left = entry.RightHand, entry.LeftHand
	if not right or not left then
		return
	end
	local gems: { BasePart }
	local current = entry.Gems
	if current then
		gems = current
	else
		local set = gemPool.acquire(entry)
		if not set then
			return -- (enough jugglers with gems already)
		end
		gems = set
		entry.Gems = set
		local getFolder = MoveController.Env.propsFolder
		local folder = gemFolder
		if not folder and getFolder then
			folder = getFolder()
			gemFolder = folder
		end
		for _, gem in set do
			gem.Parent = folder
		end
	end
	local rightPalm = (right.CFrame * PALM).Position
	local leftPalm = (left.CFrame * PALM).Position
	for i, gem in gems do
		local p = EmoteProps.juggle(u, i, rightPalm, leftPalm)
		gem.CFrame = CFrame.new(p) * CFrame.Angles(u * 4 + i, u * 3, 0)
	end
end

local function stepEntry(entry: Entry, now: number)
	local rig = entry.Rig
	if not rig then
		return
	end
	-- an emote stops the moment its character walks off or jumps
	local playingName = emoteName(entry)
	local humanoid = entry.Humanoid
	if playingName and humanoid and EmoteRules.moving(humanoid.MoveDirection.Magnitude, nil) then
		stopEmote(entry, false, MoveController.MovingOutro)
		tellStopped(entry)
	end
	local any = false
	local firing = playerMoves and firingOf(entry, now)
	for i = 1, SLOTS do
		local slot = entry.Slots[i]
		local layer = slot.Layer
		layer.Mask = if MoveRules.maskArms(SLOT_NAMES[i], firing) then MoveRules.ArmJoints else nil
		local move = slot.Move
		if move then
			local t, stop = slotTime(slot, now)
			if MoveMath.done(move, t, stop) then
				slot.Move = nil
				layer.Weight = 0
				if i == EMOTE then
					releaseGems(entry)
				end
			else
				local weight = MoveMath.weight(move, t, stop) * slot.Scale
				MoveMath.evaluate(move, t, weight, layer.Pose, stop)
				layer.Weight = weight
				any = true
				if i == EMOTE and move.Name == "GemJuggle" and not stop then
					placeGems(entry, t - (move.LoopFrom or 0))
				end
			end
		else
			layer.Weight = 0
		end
	end
	-- the Blaster Spin twirls the blaster (the grip goes back when it ends)
	local emoteSlot = entry.Slots[EMOTE]
	local emoteMove = emoteSlot.Move
	if emoteMove and emoteMove.NeedsTool and emoteSlot.Layer.Weight > 0 then
		setGrip(entry, emoteSlot.Layer.Pose.RightGrip)
	elseif entry.Grip then
		setGrip(entry, nil)
	end
	if any or entry.Holding then
		MoveRig.step(rig, entry.Layers, SLOTS)
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

onStepped = function(_time: number, dt: number)
	local now = clockNow()
	checkTimer += dt
	local checked = false
	if checkTimer >= MoveConfig.CheckInterval then
		checkTimer = 0
		check(now)
		checked = true
	end
	if not enabled then
		return
	end
	if playerMoves then
		updateRecoil(now)
	end
	for i = 1, #list do
		local entry = list[i]
		if entry.Active then
			stepEntry(entry, now)
		end
	end
	if checked then
		wake()
	end
end

---------------------------------------------------------------- public

-- Plays a client move on your character now and tells the server (Throw, Wave, Shrug).
function MoveController.playLocal(name: string)
	if not playerMoves or not MoveRules.clientAllowed(name) then
		return
	end
	local entry = entryOf(localPlayer)
	if not entry or entry.Blocked then
		return
	end
	if MoveRules.skipArmed(name, holdsTool(entry), isFiring()) then
		return -- not on the arm holding the blaster: nobody sees it (the others only get what you send)
	end
	local calmSkip = MoveRules.substitute(name, reducedMotion()) == nil -- Reduce Motion: not for you, still for the others
	if not start(entry, name) and not calmSkip then
		return
	end
	local now = clockNow()
	if now - lastSend >= SEND_GAP then
		lastSend = now
		MoveController.Env.send("Move", name)
	end
end

-- Why your character can't start an emote now (nil = it can).
local function emoteBlocked(entry: Entry): string?
	refreshParts(entry)
	local humanoid = entry.Humanoid
	local carrying = tonumber(entry.Player:GetAttribute(MoveConfig.CarryAttribute)) or 0
	return EmoteRules.blocked({
		Dead = humanoid == nil or humanoid.Health <= 0,
		Carrying = carrying > 0,
		Building = closeUp(MoveController.Env.Workspace.CurrentCamera),
		Riding = entry.Character:GetAttribute(HoverboardData.Attribute) ~= nil,
		Seated = humanoid ~= nil and humanoid.Sit,
	})
end

-- May you pick `name` now? (false, reason): "Off", "NoCharacter", an EmoteRules.blocked reason, "NoBlaster".
function MoveController.canEmote(name: string): (boolean, string?)
	if not emotesOn or not EmoteRules.allowed(name) then
		return false, "Off"
	end
	local entry = entryOf(localPlayer)
	if not entry then
		return false, "NoCharacter"
	end
	local reason = emoteBlocked(entry)
	if reason then
		return false, reason
	end
	if not EmoteRules.toolOk(name, holdsBlaster(entry)) then
		return false, "NoBlaster"
	end
	return true, nil
end

-- Does your character hold the blaster? (the menu greys the Blaster Spin without it)
function MoveController.holdingBlaster(): boolean
	local entry = entryOf(localPlayer)
	return entry ~= nil and holdsBlaster(entry)
end

-- The emote your character plays now (nil = none).
function MoveController.emote(): string?
	local entry = entryOf(localPlayer)
	return if entry then emoteName(entry) else nil
end

-- Plays emote `name` on your character (picking the playing one again stops it).
-- Returns (true, "Playing" | "Stopped") or (false, reason).
function MoveController.playEmote(name: string): (boolean, string?)
	local entry = entryOf(localPlayer)
	if entry and emotesOn and emoteName(entry) == name then
		MoveController.stopEmote()
		return true, "Stopped"
	end
	local ok, reason = MoveController.canEmote(name)
	if not ok or not entry then
		return false, reason
	end
	local now = clockNow()
	if not EmoteRules.canPlay(lastEmoteStart[name], now, EmoteRules.Cooldown) then
		return false, "Cooldown"
	end
	lastEmoteStart[name] = now
	-- a tool in hand (the blaster stays out after mining) goes to the backpack for every emote but
	-- the Blaster Spin, as cleaning and build mode do (else the emote's "Tool" rule stops it at once)
	if not EmoteRules.needsTool(name) and holdsTool(entry) then
		local humanoid = entry.Humanoid
		if humanoid then
			humanoid:UnequipTools()
		end
	end
	startEmote(entry, name)
	MoveController.Env.send("Emote", name)
	emoteSent = true
	check(now)
	wake()
	return true, "Playing"
end

-- Stops your emote with its outro (and tells the server).
function MoveController.stopEmote()
	local entry = entryOf(localPlayer)
	if entry and emoteName(entry) then
		stopEmote(entry)
		tellStopped(entry)
	end
end

-- Is your character in a close-up now (a Scriptable camera or PlayerControls claimed: cleaning,
-- build mode, the vault...)? The EMOTES menu doesn't open there.
function MoveController.inCloseUp(): boolean
	return started and closeUp(MoveController.Env.Workspace.CurrentCamera)
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
			releaseGems(entry)
			setGrip(entry, nil)
			entry.Holding = false
			entry.Active = false
		end
	end
end

function MoveController.isEnabled(): boolean
	return enabled
end

-- What runs now (the tests read it): the Stepped loop, the characters followed, gems out.
function MoveController.status(): { Loop: boolean, Entries: number, Gems: number, PlayerMoves: boolean, Emotes: boolean }
	return {
		Loop = stepConnection ~= nil,
		Entries = #list,
		Gems = gemPool.active(),
		PlayerMoves = playerMoves,
		Emotes = emotesOn,
	}
end

function MoveController.init()
	localPlayer = MoveController.Env.Players.LocalPlayer
end

function MoveController.start()
	local env = MoveController.Env
	playerMoves = AnimConfig.PlayerMoves == true
	emotesOn = AnimConfig.Emotes == true
	if not playerMoves and not emotesOn then
		return -- both off: nothing at all
	end
	started = true
	localPlayer = env.Players.LocalPlayer
	-- required here, not at the top: these need a real client (Lune tests set Env)
	isFiring = env.firing
		or function(): boolean
			local MiningController = require(script.Parent.MiningController)
			isFiring = MiningController.isFiring
			return isFiring()
		end
	controlsOwner = env.controlsOwner
		or function(): string?
			local PlayerControls = require(script.Parent.Parent.Util.PlayerControls)
			controlsOwner = PlayerControls.owner
			return controlsOwner()
		end
	panelOpen = env.panelOpen
		or function(): boolean
			local MenuPanels = require(script.Parent.Parent.Util.MenuPanels)
			panelOpen = function(): boolean
				return MenuPanels.otherOpen("EmoteController")
			end
			return panelOpen()
		end
	if not env.propsFolder then
		env.propsFolder = function(): Instance
			local folder = Instance.new("Folder")
			folder.Name = "ClientEmoteProps"
			folder.Parent = env.Workspace
			return folder
		end
	end

	for _, player in env.Players:GetPlayers() do
		hookPlayer(player)
	end
	env.Players.PlayerAdded:Connect(hookPlayer)
	env.Players.PlayerRemoving:Connect(function(player: Player)
		for i = #list, 1, -1 do
			if list[i].Player == player then
				removeEntry(list[i])
			end
		end
		wake()
	end)

	if not playerMoves then
		return -- emotes only: the loop connects while one plays near you (wake)
	end

	-- Reduce Motion: Roblox's own setting and the game's SETTINGS toggle
	local GuiService = env.GuiService
	local function readSystem()
		local ok, on = pcall(function()
			return GuiService.ReducedMotionEnabled
		end)
		systemReduced = ok and on == true
	end
	readSystem()
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(readSystem)
	end)
	local onSettings = env.onSettings
	if onSettings then
		onSettings(function(current: any)
			settingsReduced = current.ReduceMotion == true
		end)
	else
		local SettingsController = require(script.Parent.SettingsController)
		SettingsController.onChanged(function(current)
			settingsReduced = current.ReduceMotion == true
		end)
	end

	-- the others' blasters: a kick on their BlastHit effects (yours come from isFiring)
	env.listen("Fx", function(kind: any, _position: any, _glow: any, _stage: any, shooter: any)
		if kind ~= "BlastHit" or typeof(shooter) ~= "Instance" or not shooter:IsA("Player") or shooter == localPlayer then
			return
		end
		local entry = entryOf(shooter :: Player)
		if not entry then
			return
		end
		local now = clockNow()
		entry.FiredAt = now
		if not entry.Active then
			return
		end
		if now - entry.KickAt < MoveConfig.RecoilRepeat then
			return
		end
		local fresh = now - entry.KickAt > 0.6
		entry.KickAt = now
		kick(entry, if fresh then 1 else MoveConfig.RecoilRepeatWeight)
	end)
	-- you equipped a golem: wave
	env.listen("ActionResult", function(result: any)
		if type(result) == "table" and result.Action == "Golem" and result.Ok == true then
			if result.Op == "Equip" or result.Op == "EquipBest" then
				MoveController.playLocal("Wave")
			end
		end
	end)
	-- the server refused something: shrug (not too often)
	env.listen("Notify", function(message: any)
		if type(message) ~= "table" or message.Kind ~= "Deny" then
			return
		end
		local now = clockNow()
		if now - lastShrug >= MoveConfig.ShrugGap then
			lastShrug = now
			MoveController.playLocal("Shrug")
		end
	end)

	connectLoop() -- the moves need the loop all the time
end

-- Internals for the Lune tests only (tests/EmotesLive.spec.luau).
MoveController._test = {
	entryOf = function(character: Model): any
		return entries[character]
	end,
	check = function()
		check(clockNow())
	end,
	step = function(dt: number)
		onStepped(0, dt)
	end,
	wake = wake,
	reset = function()
		disconnectLoop()
		for i = #list, 1, -1 do
			removeEntry(list[i])
		end
		table.clear(lastEmoteStart)
		emoteSent = false
		generation += 1
		started = false
		playerMoves = false
		emotesOn = false
		slowQueued = false
		gemFolder = nil
		gemPool = EmoteProps.newPool(EmoteProps.makeGem)
	end,
}

return MoveController
