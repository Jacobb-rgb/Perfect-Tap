--[[
	EmoteService: the server side of the emotes (Config/EmoteConfig, the
	EMOTES menu: EmoteController; owner 2026-10-21 "add the emotes"; live
	while AnimConfig.Emotes is on, else nothing here runs).

	Net "Emote" (client -> server, rate limited in Net.luau): (name) starts
	an emote, ("") stops yours. A name is Guard.string + the whitelist
	(EmoteRules.allowed: EmoteConfig.List only, never a free-form string),
	with a cooldown per emote (EmoteRules.Cooldown). It never starts while
	you carry ore, clean at a station, ride a hoverboard, sit or are dead,
	and the Blaster Spin only with the blaster in hand. The server alone
	sets the character attribute EmoteRules.Attribute = "<Name>:<seq>"
	("" = stopped); every client plays it (MoveController) and stops it
	there when that character moves. Every Poll seconds the players with an
	emote on are checked again: carrying, cleaning, a board, a seat or the
	blaster put away clear it. Emotes are looks only: no gameplay, no
	physics, no save.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimConfig = require(Shared.Config.AnimConfig)
local HoverboardData = require(Shared.Config.HoverboardData)
local MoveConfig = require(Shared.Config.MoveConfig)
local EmoteRules = require(Shared.Moves.EmoteRules)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local CleaningService = require(script.Parent.CleaningService)

local EmoteService = {}

EmoteService.Poll = 0.5

local seqs: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastStart: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local playing: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

-- swappable for the Lune tests
local clock: () -> number = os.clock
local isCleaning: (Player) -> boolean = function(player: Player): boolean
	return CleaningService.isCleaning(player)
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function holdsBlaster(player: Player): boolean
	local character = player.Character
	local tool = character and character:FindFirstChild(EmoteRules.BlasterTool)
	return tool ~= nil and tool:IsA("Tool")
end

-- Why `player` can't emote now (nil = they can).
function EmoteService.blocked(player: Player): string?
	local root = Guard.rootPart(player)
	local character = player.Character
	local humanoid = humanoidOf(player)
	local carrying = tonumber(player:GetAttribute(MoveConfig.CarryAttribute)) or 0
	return EmoteRules.blocked({
		Dead = root == nil,
		Carrying = carrying > 0,
		Cleaning = isCleaning(player),
		Riding = character ~= nil and character:GetAttribute(HoverboardData.Attribute) ~= nil,
		Seated = humanoid ~= nil and humanoid.Sit,
	})
end

local function setAttribute(player: Player, value: string)
	local character = player.Character
	if character and character:GetAttribute(EmoteRules.Attribute) ~= value then
		character:SetAttribute(EmoteRules.Attribute, value)
	end
end

-- Starts `name` on the player's character; false (and nothing changes) when it may not.
function EmoteService.play(player: Player, name: string): boolean
	if not EmoteRules.allowed(name) then
		return false
	end
	if EmoteService.blocked(player) then
		return false
	end
	if not EmoteRules.toolOk(name, holdsBlaster(player)) then
		return false
	end
	local now = clock()
	local starts = lastStart[player]
	if not starts then
		starts = {}
		lastStart[player] = starts
	end
	if not EmoteRules.canPlay(starts[name], now, EmoteRules.Cooldown) then
		return false
	end
	starts[name] = now
	local seq = EmoteRules.nextSeq(seqs[player] or 0)
	seqs[player] = seq
	playing[player] = name
	setAttribute(player, EmoteRules.encode(name, seq))
	return true
end

function EmoteService.stop(player: Player)
	if playing[player] then
		playing[player] = nil
		setAttribute(player, "")
	end
end

function EmoteService.playing(player: Player): string?
	return playing[player]
end

-- Net "Emote"
local function onEmote(player: Player, nameArg: any)
	local name = Guard.string(nameArg, EmoteRules.MaxName)
	if name == nil then
		return
	end
	if name == "" then
		EmoteService.stop(player)
	else
		EmoteService.play(player, name)
	end
end

-- The players with an emote on: still allowed?
local function poll()
	for player, name in playing do
		if not player.Parent or EmoteService.blocked(player) or not EmoteRules.toolOk(name, holdsBlaster(player)) then
			EmoteService.stop(player)
		end
	end
end

-- Internals for the Lune tests only (tests/EmotesLive.spec.luau).
EmoteService._test = {
	onEmote = onEmote,
	poll = poll,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setCleaning = function(fn: (Player) -> boolean)
		isCleaning = fn
	end,
	reset = function()
		table.clear(seqs)
		table.clear(lastStart)
		table.clear(playing)
		clock = os.clock
		isCleaning = function(player: Player): boolean
			return CleaningService.isCleaning(player)
		end
	end,
}

function EmoteService.init()
	if not AnimConfig.Emotes then
		return
	end
	Net.on("Emote", onEmote)
	Players.PlayerRemoving:Connect(function(player: Player)
		seqs[player] = nil
		lastStart[player] = nil
		playing[player] = nil
	end)
end

function EmoteService.start()
	if not AnimConfig.Emotes then
		return
	end
	-- a respawn starts with no emote
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			playing[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	while true do
		task.wait(EmoteService.Poll)
		if next(playing) ~= nil then
			poll()
		end
	end
end

return EmoteService
