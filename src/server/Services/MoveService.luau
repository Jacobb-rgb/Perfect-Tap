--[[
	MoveService: the server side of the player's moves (Config/MoveConfig,
	client: Controllers/MoveController). Moves are looks only: nothing here
	changes gameplay, physics or the save, and the server never animates a
	part. It only sets two character attributes every client reads:

	  Move      "<Name>:<seq>"  a one-shot move to play now (seq makes the same
	            move twice a change: MoveRules.encode)
	  MoveLoop  "Spray" while the player cleans at a station, "Hammer" while
	            they forge at their Foundry, nil otherwise (checked every
	            MoveConfig.LoopPoll seconds; Carry needs nothing: every
	            client reads the CarryCount player attribute)

	MoveService.play(player, name) plays a one-shot move (at most once per its
	MinGap). Celebrations come from existing server results, through the
	hooks those services already have (no edits there):
	  CleaningService.onCleaned  Legendary+ ore -> BigCelebrate; a new ore
	                             (Discovery.onDiscovered just before) or a
	                             Flawless grade -> Celebrate
	  CapsuleService.onOpened    a Legendary / Mythic golem -> BigCelebrate
	  DataService.onChanged      a higher BlasterLevel (forged at the Foundry
	                             or bought at the Vault) or one more rebirth
	                             -> BigCelebrate (MoveRules.forProgress)
	  SellService.onSold         MoveConfig.BigSell.Items or more sold within
	                             BigSell.Window while at Tobin's -> CashToss

	AnimConfig.PlayerMoves (owner 2026-10-21: built, not approved yet) off:
	init / start do nothing (no Net "Move" handler, no hooks, no loop) and
	play / setLoop set no attribute.

	Net "Move" (client -> server, rate limited in Net.luau): (name) a move the
	client already plays for itself (Throw on the throw input, Wave, Shrug).
	Only MoveConfig.ClientMoves names (Guard.string + the whitelist, never a
	free-form string), only with a living character, Throw only while
	carrying; then play() tells the others.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GolemConfig = require(Shared.Config.GolemConfig)
local AnimConfig = require(Shared.Config.AnimConfig)
local MoveConfig = require(Shared.Config.MoveConfig)
local OreData = require(Shared.Config.OreData)
local MoveRules = require(Shared.Moves.MoveRules)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local Discovery = require(script.Parent.Parent.Discovery)
local DataService = require(script.Parent.DataService)
local CleaningService = require(script.Parent.CleaningService)
local CapsuleService = require(script.Parent.CapsuleService)
local SellService = require(script.Parent.SellService)
local FoundryService = require(script.Parent.FoundryService)
local PlotService = require(script.Parent.PlotService)

local MoveService = {}

MoveService.SellTag = "SellCounter"
MoveService.FreshSeconds = 2 -- a discovery this recent makes the cleaned ore "new"

local seqs: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastPlayed: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local fresh: { [Player]: { Ore: string, At: number } } = setmetatable({}, { __mode = "k" }) :: any
local progress: { [Player]: MoveRules.Progress } = setmetatable({}, { __mode = "k" }) :: any
local sells: { [Player]: { Count: number } } = setmetatable({}, { __mode = "k" }) :: any

-- swappable for the Lune tests
local clock: () -> number = os.clock

---------------------------------------------------------------- playing

function MoveService.play(player: Player, name: string): boolean
	if not AnimConfig.PlayerMoves then
		return false
	end
	local move = MoveConfig.Moves[name]
	if not move or move.Loop then
		return false
	end
	local character = player.Character
	if not character or not character.Parent then
		return false
	end
	local now = clock()
	local played = lastPlayed[player]
	if not played then
		played = {}
		lastPlayed[player] = played
	end
	if not MoveRules.canPlay(played[name], now, move.MinGap) then
		return false
	end
	played[name] = now
	local seq = MoveRules.nextSeq(seqs[player] or 0)
	seqs[player] = seq
	character:SetAttribute(MoveConfig.Attribute, MoveRules.encode(name, seq))
	return true
end

-- The loop every client shows on this player's character (nil = none).
function MoveService.setLoop(player: Player, name: string?)
	local character = player.Character
	if not character or not AnimConfig.PlayerMoves then
		return
	end
	local value = if name and MoveConfig.Moves[name] and MoveConfig.Moves[name].Loop then name else nil
	if character:GetAttribute(MoveConfig.LoopAttribute) ~= value then
		character:SetAttribute(MoveConfig.LoopAttribute, value)
	end
end

-- Net "Move": a client move the others should see.
local function onMove(player: Player, nameArg: any)
	local name = Guard.string(nameArg, MoveConfig.MaxNameLength)
	if not name or not MoveRules.clientAllowed(name) then
		return
	end
	if not Guard.rootPart(player) then
		return
	end
	if name == "Throw" then
		local carrying = tonumber(player:GetAttribute(MoveConfig.CarryAttribute)) or 0
		if not (carrying > 0) then
			return
		end
	end
	MoveService.play(player, name)
end

---------------------------------------------------------------- celebrations

local function onDiscovered(player: Player, oreId: string)
	fresh[player] = { Ore = oreId, At = clock() }
end

local function onCleaned(player: Player, oreId: string, grade: string, _score: number)
	local found = fresh[player]
	local isNew = found ~= nil and found.Ore == oreId and clock() - found.At <= MoveService.FreshSeconds
	if isNew then
		fresh[player] = nil
	end
	local ore = OreData.ById[oreId]
	local name = MoveRules.forClean(if ore then ore.Rarity else nil, grade, isNew)
	if name then
		MoveService.play(player, name)
	end
end

local function onOpened(player: Player, info: CapsuleService.Opened)
	local rarities: { string } = {}
	for _, kind in info.Kinds do
		local golem = GolemConfig.ById[kind]
		if golem then
			table.insert(rarities, golem.Rarity)
		end
	end
	local name = MoveRules.forCapsule(rarities)
	if name then
		MoveService.play(player, name)
	end
end

local function progressOf(data: { [string]: any }): MoveRules.Progress
	local blaster = tonumber(data.BlasterLevel) or 0
	local rebirths = tonumber(data.Rebirths) or 0
	return {
		Blaster = if blaster == blaster then blaster else 0,
		Rebirths = if rebirths == rebirths then rebirths else 0,
	}
end

local function onLoaded(player: Player, data: { [string]: any })
	progress[player] = progressOf(data)
end

local function onChanged(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = progressOf(data)
	local before = progress[player]
	progress[player] = now
	local name = MoveRules.forProgress(before, now)
	if name then
		MoveService.play(player, name)
	end
end

-- Is the player standing at Tobin's (a SellCounter within MoveConfig.SellRange)?
local function atCounter(player: Player): boolean
	local root = Guard.rootPart(player)
	if not root then
		return false
	end
	for _, counter in CollectionService:GetTagged(MoveService.SellTag) do
		if counter:IsA("BasePart") and (counter.Position - root.Position).Magnitude <= MoveConfig.SellRange then
			return true
		end
	end
	return false
end

local counterCheck: (Player) -> boolean = atCounter

local function flushSell(player: Player)
	local batch = sells[player]
	sells[player] = nil
	if batch and player.Parent and MoveRules.bigSell(batch.Count) and counterCheck(player) then
		MoveService.play(player, "CashToss")
	end
end

local function onSold(player: Player, _desc: any, _value: number)
	local batch = sells[player]
	if not batch then
		batch = { Count = 0 }
		sells[player] = batch
		task.delay(MoveConfig.BigSell.Window, flushSell, player)
	end
	batch.Count += 1
end

---------------------------------------------------------------- loops

local function loopOf(player: Player): string?
	if CleaningService.isCleaning(player) then
		return "Spray"
	end
	local plotId = PlotService.plotOf(player)
	local building = if plotId then FoundryService.building(plotId) else nil
	if building and building:GetAttribute("Forging") == true then
		return "Hammer"
	end
	return nil
end

local function pollLoops()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(function()
			MoveService.setLoop(player, loopOf(player))
		end)
		if not ok then
			warn(`[MoveService] loop of {player.Name}: {err}`)
		end
	end
end

---------------------------------------------------------------- lifecycle

-- Internals for the Lune tests only (tests/Moves.spec.luau).
MoveService._test = {
	onMove = onMove,
	onCleaned = onCleaned,
	onDiscovered = onDiscovered,
	onOpened = onOpened,
	onLoaded = onLoaded,
	onChanged = onChanged,
	onSold = onSold,
	flushSell = flushSell,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setCounterCheck = function(fn: (Player) -> boolean)
		counterCheck = fn
	end,
	reset = function()
		table.clear(seqs)
		table.clear(lastPlayed)
		table.clear(fresh)
		table.clear(progress)
		table.clear(sells)
		clock = os.clock
		counterCheck = atCounter
	end,
}

function MoveService.init()
	if not AnimConfig.PlayerMoves then
		return -- off (AnimConfig): no Net "Move" handler (Net's sink drops it), no hooks, no loop
	end
	Net.on("Move", onMove)
	Discovery.onDiscovered(onDiscovered)
	CleaningService.onCleaned(onCleaned)
	CapsuleService.onOpened(onOpened)
	DataService.onLoaded(onLoaded)
	DataService.onChanged(onChanged)
	SellService.onSold(onSold)
	Players.PlayerRemoving:Connect(function(player: Player)
		seqs[player] = nil
		lastPlayed[player] = nil
		fresh[player] = nil
		progress[player] = nil
		sells[player] = nil
	end)
end

function MoveService.start()
	if not AnimConfig.PlayerMoves then
		return
	end
	while true do
		task.wait(MoveConfig.LoopPoll)
		pollLoops()
	end
end

return MoveService
