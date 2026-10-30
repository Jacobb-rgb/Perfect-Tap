--[[
	RoyalCapeController: the Dragon King's royal cape (owner 2026-10-30), an
	exclusive cosmetic for owning the Dragon King: every player with it
	equipped wears the cape (Builders/RoyalCape) on their back, seen by
	everyone.

	- Who: the player attribute GolemConfig.EquippedAttribute (GolemService
	  keeps it: "PebbleGolem,DragonKing,...") holding RoyalCape.Golem. Like
	  the golem followers (GolemController), each client builds every
	  wearer's cape itself: the server makes no parts and sends nothing new.
	  Unequipping the Dragon King takes the cape off at once; equipping it
	  again builds one cape, never a second.
	- Where: a Weld from the cape's Root to the character's UpperTorso (R15)
	  or Torso (R6), never a Motor6D (Roblox's Avatar Joint Upgrade swaps the
	  character's Motor6Ds for AnimationConstraints). Sized to the character
	  and its worn backpack (RoyalCape.fit: the player attribute
	  PackAttribute; the cape goes under the pack and flows from below it).
	  Every cape part is massless and never collides, touches or is queried,
	  so the body, its movement and the camera stay exactly as they were.
	  The capes live in a ClientCapes folder (attribute NoStuds: the studded
	  style leaves the velvet smooth).
	- When: built only for wearers within ShowRange of the camera (yours
	  always), at most one new cape per LodInterval (the nearest first), and
	  dropped beyond ShowRange + Hysteresis, when the character respawns or
	  leaves, when its torso streams out (StreamingEnabled; the cape never
	  falls off on its own) and when the player leaves. A new character, a
	  torso arriving late or another backpack build it again.
	- Motion: RoyalCape.step at most RoyalCape.Flow.Rate times a second per
	  cape within AnimateRange (yours always), from the character's own speed
	  (its position each update: walking, running, boards, falling,
	  turning), then kept behind its legs and arms (RoyalCape.clearance:
	  heels kicked back push it out). Farther capes hang still. Reduce motion
	  (UI/Motion.reduced: SETTINGS or Roblox's own) keeps only a smaller,
	  smooth lift and turns the sparkles off.
	- Sparkles: the cape's emitter runs within FxRange (yours always), at
	  half rate on other players' capes and on phones.
	Works the same on PC, phones and consoles (no input, no UI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local RoyalCape = require(Shared.Builders.RoyalCape)
local Motion = require(script.Parent.Parent.UI.Motion)

local RoyalCapeController = {}

RoyalCapeController.PackAttribute = "Backpack" -- BackpackService.Attribute: the worn pack's id
RoyalCapeController.FolderName = "ClientCapes"
RoyalCapeController.ShowRange = GolemConfig.FollowerHideDistance -- studs: farther capes aren't built
RoyalCapeController.Hysteresis = 10 -- studs past ShowRange before a cape is dropped
RoyalCapeController.AnimateRange = GolemConfig.FollowerLodDistance -- studs: farther capes hang still
RoyalCapeController.FxRange = 50 -- studs: farther capes don't sparkle
RoyalCapeController.LodInterval = 0.25
RoyalCapeController.TeleportStuds = 12 -- a jump this far in one update is a teleport: no flow from it
RoyalCapeController.Container = nil :: Instance? -- (tests: where capes go instead of the ClientCapes folder)

type Wearer = {
	Player: Player,
	Character: Model?, -- the character the cape is on
	PackId: string?, -- the pack it was fitted for
	Cape: Model?,
	Torso: BasePart?,
	Root: BasePart?, -- HumanoidRootPart
	Top: BasePart?, -- CapeTop
	Mid: Weld?,
	Hem: Weld?,
	MidRest: CFrame, -- CapeMid's hinge at rest in CapeTop's space
	Shape: RoyalCape.Shape?,
	Limbs: { BasePart },
	Emitter: ParticleEmitter?,
	Flow: RoyalCape.FlowState,
	LastPos: Vector3?,
	LastYaw: number,
	Wait: number, -- seconds gathered toward the next update
	Animated: boolean,
	FxKey: string,
	Watch: RBXScriptConnection?,
}

local player = Players.LocalPlayer
local wearers: { [Player]: Wearer } = {}
RoyalCapeController.wearers = wearers -- (tests)
local folder: Folder? = nil

local function container(): Instance
	local override = RoyalCapeController.Container
	if override then
		return override
	end
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = RoyalCapeController.FolderName
	made:SetAttribute(RoyalCape.SkipTag, true)
	made.Parent = Workspace
	folder = made
	return made
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function packOf(p: Player): string?
	local id = p:GetAttribute(RoyalCapeController.PackAttribute)
	return if type(id) == "string" and id ~= "" then id else nil
end

-- Does `p` have the Dragon King equipped?
function RoyalCapeController.wants(p: Player): boolean
	return RoyalCape.wears(p:GetAttribute(GolemConfig.EquippedAttribute))
end

---------------------------------------------------------------- putting it on, taking it off

local function drop(w: Wearer)
	local watch = w.Watch
	w.Watch = nil
	if watch then
		watch:Disconnect()
	end
	local cape = w.Cape
	w.Cape = nil
	w.Character, w.Torso, w.Root, w.Top, w.Mid, w.Hem, w.Shape, w.Emitter = nil, nil, nil, nil, nil, nil, nil, nil
	w.Limbs = {}
	w.LastPos = nil
	w.Animated = false
	w.FxKey = ""
	if cape then
		cape:Destroy()
	end
end

-- The cape's character is still whole and in the world (not respawned, not streamed out).
local function intact(w: Wearer): boolean
	local character, torso, root = w.Character, w.Torso, w.Root
	return character ~= nil
		and character.Parent ~= nil
		and torso ~= nil
		and torso.Parent == character
		and root ~= nil
		and root.Parent == character
end

local function build(w: Wearer, character: Model, packId: string?): boolean
	local fit = RoyalCape.fit(character, packId)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not fit or not root or not root:IsA("BasePart") then
		return false -- (not streamed in yet: the next LodInterval tries again)
	end
	local cape = RoyalCape.build({ Scale = fit.Scale, Length = fit.Length, Pin = fit.Pin, Crest = fit.Crest })
	cape.Name = `{w.Player.Name}_RoyalCape`
	RoyalCape.attach(cape, fit.Torso)
	local mid, hem = RoyalCape.hinges(cape)
	local top = cape:FindFirstChild("CapeTop")
	local emitter = cape:FindFirstChild("CapeSparkle", true)
	w.Cape = cape
	w.Character = character
	w.PackId = packId
	w.Torso = fit.Torso
	w.Root = root
	w.Top = if top and top:IsA("BasePart") then top else nil
	w.Mid, w.Hem = mid, hem
	local midRest = if mid then mid:GetAttribute("RestC0") else nil
	w.MidRest = if typeof(midRest) == "CFrame" then midRest else CFrame.identity
	w.Shape = RoyalCape.shape(cape)
	w.Limbs = RoyalCape.limbs(character)
	w.Emitter = if emitter and emitter:IsA("ParticleEmitter") then emitter else nil
	w.Flow = RoyalCape.newFlow((w.Player.UserId % 97) * 0.37)
	w.LastPos = nil
	w.Wait = math.random() / RoyalCape.Flow.Rate -- (spreads the capes' updates over the frames)
	w.Animated = false
	w.FxKey = ""
	-- the torso streaming out or the character going: off at once (an
	-- unwelded cape would fall)
	w.Watch = fit.Torso.AncestryChanged:Connect(function()
		if w.Cape == cape and not intact(w) then
			drop(w)
		end
	end)
	cape.Parent = container()
	return true
end

--[[
	Brings `p`'s cape in line with now: none without the Dragon King
	equipped (the wearer entry goes too); a new one for a new character or
	another backpack; built when `show` (in range) and the character is
	there, dropped when not `show`. Returns the cape.
]]
function RoyalCapeController.refresh(p: Player, show: boolean): Model?
	local w = wearers[p]
	if not RoyalCapeController.wants(p) then
		if w then
			drop(w)
			wearers[p] = nil
		end
		return nil
	end
	if not w then
		w = {
			Player = p,
			MidRest = CFrame.identity,
			Limbs = {},
			Flow = RoyalCape.newFlow(),
			LastYaw = 0,
			Wait = 0,
			Animated = false,
			FxKey = "",
		}
		wearers[p] = w
	end
	local wearer = w :: Wearer
	local character = p.Character
	local packId = packOf(p)
	if wearer.Cape and (wearer.Character ~= character or wearer.PackId ~= packId or not intact(wearer)) then
		drop(wearer)
	end
	if not show then
		drop(wearer)
	elseif not wearer.Cape and character then
		build(wearer, character, packId)
	end
	return wearer.Cape
end

-- The player left: the cape and the entry go.
function RoyalCapeController.remove(p: Player)
	local w = wearers[p]
	if w then
		drop(w)
		wearers[p] = nil
	end
end

---------------------------------------------------------------- range, sparkles

local function eye(): Vector3
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else Vector3.zero
end

local function distanceTo(p: Player, from: Vector3): number
	local character = p.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then (root.Position - from).Magnitude else math.huge
end

-- Hangs a cape still at rest (out of AnimateRange).
local function rest(w: Wearer)
	local f = RoyalCape.Flow
	if w.Mid and w.Hem then
		RoyalCape.bend(w.Mid, f.Rest[1], 0)
		RoyalCape.bend(w.Hem, f.Rest[2], 0)
	end
	w.Flow = RoyalCape.newFlow(w.Flow.Seed)
	w.LastPos = nil
end

local function setFx(w: Wearer, on: boolean, lite: boolean)
	local emitter = w.Emitter
	if not emitter then
		return
	end
	local key = `{on}|{lite}`
	if w.FxKey == key then
		return
	end
	w.FxKey = key
	emitter.Rate = if lite then RoyalCape.SparkleRate * 0.5 else RoyalCape.SparkleRate
	emitter.Enabled = on
end

--[[
	Every LodInterval: drops far capes, builds the nearest missing one (at
	most one per call: yours first), sets each cape's animation and
	sparkles by its distance.
]]
local function lodStep()
	local from = eye()
	local calm = Motion.reduced()
	local phone = isPhone()
	local best: Player? = nil
	local bestDistance = math.huge
	for _, p in Players:GetPlayers() do
		local w = wearers[p]
		if not w and not RoyalCapeController.wants(p) then
			continue
		end
		local isLocal = p == player
		local distance = if isLocal then 0 else distanceTo(p, from)
		local limit = RoyalCapeController.ShowRange + (if w and w.Cape then RoyalCapeController.Hysteresis else 0)
		local show = distance <= limit
		local had = w ~= nil and w.Cape ~= nil
		if had or not show then
			RoyalCapeController.refresh(p, show)
		elseif distance < bestDistance then
			best, bestDistance = p, distance
		end
		local now = wearers[p]
		if now and now.Cape and had then
			local animated = isLocal or distance <= RoyalCapeController.AnimateRange
			if now.Animated and not animated then
				rest(now)
			end
			now.Animated = animated
			setFx(now, (isLocal or distance <= RoyalCapeController.FxRange) and not calm, phone or not isLocal)
		end
	end
	if best then
		RoyalCapeController.refresh(best, true)
	end
end

---------------------------------------------------------------- the flow

-- The shortest turn from `a` to `b` (radians).
local function turnBetween(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

-- One update of a cape `dt` seconds after the last: the flow from the character's motion, kept behind its limbs.
local function animate(w: Wearer, dt: number, calm: boolean)
	local root, top, mid, hem, shape = w.Root, w.Top, w.Mid, w.Hem, w.Shape
	if not (root and top and mid and hem and shape) then
		return
	end
	local cf = root.CFrame
	local position = cf.Position
	local _, yaw, _ = cf:ToEulerAnglesYXZ()
	local last = w.LastPos
	local lastYaw = w.LastYaw
	w.LastPos = position
	w.LastYaw = yaw
	local forward, side, vertical, turn = 0, 0, 0, 0
	if last and (position - last).Magnitude < RoyalCapeController.TeleportStuds then
		local v = (position - last) / dt
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if look.Magnitude > 1e-3 then
			look = look.Unit
			forward = v.X * look.X + v.Z * look.Z
			side = v.X * -look.Z + v.Z * look.X -- (to its right)
		end
		vertical = v.Y
		turn = turnBetween(lastYaw, yaw) / dt
	end
	local lift1, roll1, lift2, roll2 = RoyalCape.step(w.Flow, dt, forward, side, vertical, turn, calm)
	local hinge = top.CFrame * w.MidRest
	local need1, need2 = RoyalCape.clearance(hinge, shape, w.Limbs, lift1)
	lift1, lift2 = RoyalCape.clear(w.Flow, dt, lift1, lift2, need1, need2)
	RoyalCape.bend(mid, lift1, roll1)
	RoyalCape.bend(hem, lift2, roll2)
end

local function heartbeat(dt: number)
	local period = 1 / RoyalCape.Flow.Rate
	local calm: boolean? = nil
	for _, w in wearers do
		if w.Cape and w.Animated then
			w.Wait += dt
			if w.Wait >= period then
				if calm == nil then
					calm = Motion.reduced()
				end
				-- (a long hitch counts as one update: no huge jumps)
				animate(w, math.min(w.Wait, 0.25), calm == true)
				w.Wait = 0
			end
		end
	end
end

---------------------------------------------------------------- lifecycle

-- In range now (yours always)?
local function inRange(p: Player): boolean
	if p == player then
		return true
	end
	local w = wearers[p]
	local limit = RoyalCapeController.ShowRange + (if w and w.Cape then RoyalCapeController.Hysteresis else 0)
	return distanceTo(p, eye()) <= limit
end

local function watch(p: Player)
	local function now()
		RoyalCapeController.refresh(p, inRange(p))
	end
	p:GetAttributeChangedSignal(GolemConfig.EquippedAttribute):Connect(now)
	p:GetAttributeChangedSignal(RoyalCapeController.PackAttribute):Connect(now)
	p.CharacterAdded:Connect(function()
		-- (R15 parts may still be arriving: LodInterval tries again)
		task.defer(now)
	end)
	p.CharacterRemoving:Connect(function()
		local w = wearers[p]
		if w then
			drop(w)
		end
	end)
	now()
end

function RoyalCapeController.start()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(RoyalCapeController.remove)
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err: any = pcall(heartbeat, dt)
		if not ok then
			warn("[RoyalCapeController] " .. tostring(err))
		end
	end)
	while true do
		local ok, err: any = pcall(lodStep)
		if not ok then
			warn("[RoyalCapeController] " .. tostring(err))
		end
		task.wait(RoyalCapeController.LodInterval)
	end
end

return RoyalCapeController
