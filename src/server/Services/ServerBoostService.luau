--[[
	ServerBoostService: Server Luck (the Store's "ServerLuck15", owner
	2026-10-20). A player buys it; everyone on this server gets x2 ore luck
	while it runs. Not saved: it ends with the server (the product's text
	says "while it runs").

	- The "ServerBoost" receipt handler (MonetizationService.register)
	  extends LuckUntil by the product's Seconds, stacking, at most
	  MaxSeconds ahead, and thanks the buyer in a server-wide Notify.
	  MonetizationService writes the buyer's PurchaseLog as for every grant.
	- The effect is a Bonuses provider "ServerLuck": OreLuckMult x2 while it
	  runs. OreLuckMult is capped at x2.5 (StatConfig), the same stat Hexa
	  Lucky uses: with Hexa Lucky on, the bigger one counts (the product's
	  description says so). It changes ore odds: a paid random item
	  (MonetizationConfig PaidRandom, PolicyService rules in the Store).
	- Clients read ReplicatedStorage attributes ServerLuckUntil (seconds on
	  workspace:GetServerTimeNow()'s clock, 0 = off) and ServerLuckBy (the
	  last buyer's display name) for the HUD chip.
	- When it runs out every player's Bonuses cache is cleared and a fresh
	  State pushed (one timer, re-planned on every extend).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Net = require(Shared.Net)
local Bonuses = require(script.Parent.Parent.Bonuses)
local StateService = require(script.Parent.StateService)
local MonetizationService = require(script.Parent.MonetizationService)

local ServerBoostService = {}

ServerBoostService.Mult = 2 -- x ore luck
ServerBoostService.MaxSeconds = 6 * 3600 -- at most this far ahead
ServerBoostService.UntilAttribute = "ServerLuckUntil"
ServerBoostService.ByAttribute = "ServerLuckBy"

local luckUntil = 0 -- os.time() second the luck ends (0 = off)
local plannedFor = 0

-- (tests swap the clock and the timer)
local clock: () -> number = os.time
local after: (seconds: number, fn: () -> ()) -> () = function(seconds, fn)
	task.delay(seconds, fn)
end

-- Seconds of Server Luck left.
function ServerBoostService.left(now: number?): number
	return math.max(0, luckUntil - (now or clock()))
end

-- Is it running?
function ServerBoostService.active(now: number?): boolean
	return ServerBoostService.left(now) > 0
end

-- Would `seconds` more pass MaxSeconds? (the Store answers "Full")
function ServerBoostService.full(seconds: number, now: number?): boolean
	return ServerBoostService.left(now) + seconds > ServerBoostService.MaxSeconds
end

-- A ReplicatedStorage attribute for the clients (the Lune tests' stand-in has none).
local function share(name: string, value: any)
	pcall(function()
		ReplicatedStorage:SetAttribute(name, value)
	end)
end

local function publish(now: number)
	local left = ServerBoostService.left(now)
	local ok, serverNow = pcall(function(): number
		return Workspace:GetServerTimeNow()
	end)
	local base = if ok then serverNow else now
	share(ServerBoostService.UntilAttribute, if left > 0 then base + left else 0)
end

-- (tests swap the player list)
local everyone: () -> { Player } = function()
	return Players:GetPlayers()
end

local function refreshAll()
	for _, player in everyone() do
		Bonuses.invalidate(player)
		StateService.push(player)
	end
end

local function plan()
	local target = luckUntil
	if target <= 0 or target == plannedFor then
		return
	end
	plannedFor = target
	after(math.max(0, target - clock()) + 0.5, function()
		if luckUntil ~= target or clock() < target then
			return -- extended since: a newer timer handles it
		end
		luckUntil = 0
		plannedFor = 0
		publish(clock())
		refreshAll()
		Net.fireAll("Notify", { Text = "Server Luck ran out.", Kind = "Info" })
	end)
end

-- Adds `seconds` of Server Luck (capped at MaxSeconds ahead). Returns the seconds left.
function ServerBoostService.extend(seconds: number, buyer: Player?): number
	local now = clock()
	local start = math.max(now, luckUntil)
	luckUntil = math.min(start + seconds, now + ServerBoostService.MaxSeconds)
	publish(now)
	if buyer then
		share(ServerBoostService.ByAttribute, buyer.DisplayName)
	end
	refreshAll()
	plan()
	return luckUntil - now
end

-- The "ServerBoost" receipt handler.
local function grantServerBoost(player: Player, _data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local seconds = entry.Seconds
	if entry.ServerBoost ~= "Luck" or type(seconds) ~= "number" or seconds <= 0 then
		return false
	end
	local left = ServerBoostService.extend(seconds, player)
	Net.fireAll("Notify", {
		Text = `Server Luck x{ServerBoostService.Mult}: {math.ceil(left / 60)} min for everyone. Thanks, {player.DisplayName}!`,
		Kind = "Reward",
	})
	return true
end

-- Registers the "ServerBoost" receipt handler (init(); idempotent).
function ServerBoostService.registerGrants()
	MonetizationService.register("ServerBoost", grantServerBoost)
end

function ServerBoostService.init()
	ServerBoostService.registerGrants()
	Bonuses.register("ServerLuck", function()
		if ServerBoostService.active() then
			return { OreLuckMult = ServerBoostService.Mult }
		end
		return {}
	end)
	share(ServerBoostService.UntilAttribute, 0)
end

function ServerBoostService.start() end

-- Test hooks.
ServerBoostService._test = {
	setClock = function(fn: () -> number)
		clock = fn
	end,
	setAfter = function(fn: (number, () -> ()) -> ())
		after = fn
	end,
	reset = function()
		luckUntil = 0
		plannedFor = 0
	end,
	setPlayers = function(fn: () -> { Player })
		everyone = fn
	end,
	grant = grantServerBoost,
}

return ServerBoostService
