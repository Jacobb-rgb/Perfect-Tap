--[[
	SecretService: the SECRET ores (owner 2026-10-29, SecretOreConfig).

	  rollDrop(luck, floorId) -> oreId?   the server's roll for one ore a rock drops
	      (MiningService.dropChunk; luck = Bonuses.oreLuck of the miner's
	      stats): it raises the chance by its square root, at most x2.5.
	      The ore then drops as a SPARKLY dirty ore (ItemBuilder Raw of the
	      secret: rainbow glints); nothing is shown until it is cleaned.
	  found(player, oreId)   CleaningService, once the dirt of a secret ore is
	      off (before Discovery.mark records it: NEW! on a first find): counts
	      it (data.Stats.SecretsFound), sends the jackpot to the finder
	      (SecretFound) and announces it.
	  announce(player, oreId)   the chat line for everyone on this server
	      (SecretChat: UserId, DisplayName and the ore id; every client
	      builds the line from OreData, so no player text travels), and for
	      Rainbow Nova every server (MessagingService Topic: the same three
	      fields + this server's JobId; the receivers check them and fire
	      their own SecretChat with Global = true).
	Rate limits (Limiter, a sliding window per key): the chat line at most
	ChatPerPlayer per player and ChatPerServer per server a minute; a
	publish at most PublishPerPlayer per player per 10 minutes and
	PublishPerServer per server a minute (well inside MessagingService's
	per-server quota); received messages at most ReceivePerServer a
	minute. A failed publish (pcall) only warns: the drop and the save never
	wait for it or fail with it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local OreData = require(Shared.Config.OreData)
local SecretOreConfig = require(Shared.Config.SecretOreConfig)

local SecretService = {}

SecretService.Topic = "TerraForgeSecretNova"
SecretService.ChatPerPlayer = 3 -- chat lines a minute per finder
SecretService.ChatPerServer = 8 -- chat lines a minute on one server
SecretService.PublishPerPlayer = 2 -- every-server messages per finder per 10 minutes
SecretService.PublishPerServer = 2 -- every-server messages a minute from one server
SecretService.ReceivePerServer = 6 -- every-server messages shown a minute on one server
SecretService.MaxName = 20 -- characters (code points): a DisplayName is at most 20; anything longer is not one
SecretService.SubscribeRetry = { First = 5, Max = 300 } -- seconds between tries of SubscribeAsync, doubling
SecretService.PillarRadius = 160 -- studs: who sees the column of light over the station (Fx "SecretPillar")

---------------------------------------------------------------- pure parts (specced)

export type Limiter = { Cap: number, Window: number, Hits: { [any]: { number } } }

-- At most `cap` takes per key in any `window` seconds.
function SecretService.newLimiter(cap: number, window: number): Limiter
	return { Cap = cap, Window = window, Hits = {} }
end

-- Takes one for `key` at `now` if there is room (old takes fall out of the window).
function SecretService.take(limiter: Limiter, key: any, now: number): boolean
	local hits = limiter.Hits[key]
	if not hits then
		hits = {}
		limiter.Hits[key] = hits
	end
	local kept = {}
	for _, at in hits do
		if now - at < limiter.Window then
			table.insert(kept, at)
		end
	end
	if #kept >= limiter.Cap then
		limiter.Hits[key] = kept
		return false
	end
	table.insert(kept, now)
	limiter.Hits[key] = kept
	return true
end

-- Does this ore get announced on every server (Rainbow Nova: the secrets of every floor)?
function SecretService.isGlobal(oreId: any): boolean
	local secret = if type(oreId) == "string" then SecretOreConfig.ByOre[oreId] else nil
	return secret ~= nil and secret.Floor == nil
end

-- At most MaxName characters of `name`, cut between two characters (never inside one).
function SecretService.shortName(name: string): string
	local length = utf8.len(name)
	if not length then
		return "" -- not UTF-8
	end
	if length <= SecretService.MaxName then
		return name
	end
	local cut = utf8.offset(name, SecretService.MaxName + 1) :: number
	return string.sub(name, 1, cut - 1)
end

-- The every-server message for a find (nil for anything but a global secret).
function SecretService.payload(userId: number, name: string, oreId: string, jobId: string): { [string]: any }?
	if not SecretService.isGlobal(oreId) then
		return nil
	end
	return { U = userId, N = SecretService.shortName(name), O = oreId, J = jobId }
end

-- A received message checked: (userId, name, oreId, jobId), or nil for anything broken or unknown.
function SecretService.read(data: any): (number?, string?, string?, string?)
	if type(data) ~= "table" then
		return nil
	end
	local u, n, o, j = data.U, data.N, data.O, data.J
	if type(u) ~= "number" or u ~= u or u % 1 ~= 0 or u <= 0 then
		return nil
	end
	local length = if type(n) == "string" then utf8.len(n) else nil
	if type(n) ~= "string" or not length or length == 0 or length > SecretService.MaxName or n:find("[%c<>]") then
		return nil
	end
	if not SecretService.isGlobal(o) or not OreData.exists(o) then
		return nil
	end
	if type(j) ~= "string" or #j > 64 then
		return nil
	end
	return u, n, o, j
end

---------------------------------------------------------------- the server

local chatPlayer = SecretService.newLimiter(SecretService.ChatPerPlayer, 60)
local chatServer = SecretService.newLimiter(SecretService.ChatPerServer, 60)
local publishPlayer = SecretService.newLimiter(SecretService.PublishPerPlayer, 600)
local publishServer = SecretService.newLimiter(SecretService.PublishPerServer, 60)
local receiveServer = SecretService.newLimiter(SecretService.ReceivePerServer, 60)

-- (tests) fresh limits
function SecretService.resetLimits()
	for _, limiter in { chatPlayer, chatServer, publishPlayer, publishServer, receiveServer } do
		table.clear(limiter.Hits)
	end
end

-- Hooks the tests swap: the clock, the publish, the player data, the dice.
SecretService.clock = os.clock
SecretService.publish = function(payload: { [string]: any }): boolean
	-- (Studio never tells the live servers: a test Nova stays in the test)
	local studio = false
	pcall(function()
		studio = game:GetService("RunService"):IsStudio()
	end)
	if studio then
		return false
	end
	local ok, err = pcall(function()
		game:GetService("MessagingService"):PublishAsync(SecretService.Topic, payload)
	end)
	if not ok then
		warn(`[SecretService] telling the servers about a {payload.O} failed: {err}`)
	end
	return ok
end
SecretService.dataOf = function(_player: Player): any
	return nil
end
SecretService.changed = function(_player: Player) end
-- this server's JobId ("" where there is none)
SecretService.jobId = function(): string
	local ok, id = pcall(function()
		return game.JobId
	end)
	return if ok and type(id) == "string" then id else ""
end
SecretService.random = function(): number
	return math.random()
end

function SecretService.rollDrop(luck: number, floorId: string?): string?
	return SecretOreConfig.roll(floorId, luck, SecretService.random)
end

function SecretService.announce(player: Player, oreId: string)
	if not SecretOreConfig.isSecret(oreId) then
		return
	end
	local now = SecretService.clock()
	if SecretService.take(chatPlayer, player.UserId, now) and SecretService.take(chatServer, "server", now) then
		Net.fireAll("SecretChat", { UserId = player.UserId, Name = player.DisplayName, OreId = oreId, Global = false })
	end
	local payload = SecretService.payload(player.UserId, player.DisplayName, oreId, SecretService.jobId())
	if payload and SecretService.take(publishPlayer, player.UserId, now) and SecretService.take(publishServer, "server", now) then
		task.spawn(SecretService.publish, payload)
	end
end

-- A message from MessagingService (another server's Rainbow Nova).
function SecretService.receive(message: any)
	local u, n, o, j = SecretService.read(if type(message) == "table" then message.Data else nil)
	if not u or not n or not o then
		return
	end
	if j == SecretService.jobId() then
		return -- this server showed it already
	end
	if not SecretService.take(receiveServer, "server", SecretService.clock()) then
		return
	end
	Net.fireAll("SecretChat", { UserId = u, Name = n, OreId = o, Global = true })
end

function SecretService.found(player: Player, oreId: string)
	if not SecretOreConfig.isSecret(oreId) then
		return
	end
	local data = SecretService.dataOf(player)
	local new = true
	if type(data) == "table" then
		new = not (type(data.Discovered) == "table" and data.Discovered[oreId] == true)
		if type(data.Stats) == "table" then
			local count = data.Stats.SecretsFound
			data.Stats.SecretsFound = (if type(count) == "number" and count == count then count else 0) + 1
		end
		SecretService.changed(player)
	end
	local secret = SecretOreConfig.ByOre[oreId]
	Net.fire("SecretFound", player, { OreId = oreId, New = new, Stars = secret.Stars })
	SecretService.announce(player, oreId)
end

function SecretService.init()
	local Services = script.Parent
	local DataService = require(Services:WaitForChild("DataService")) :: any
	SecretService.dataOf = function(player: Player): any
		return DataService.get(player)
	end
	SecretService.changed = function(player: Player)
		DataService.changed(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		chatPlayer.Hits[player.UserId] = nil
	end)
end

function SecretService.start()
	-- listen for the other servers' Rainbow Novas; a failed subscribe is tried again, later each time
	task.spawn(function()
		local wait = SecretService.SubscribeRetry.First
		while true do
			local ok, err = pcall(function()
				game:GetService("MessagingService"):SubscribeAsync(SecretService.Topic, SecretService.receive)
			end)
			if ok then
				return
			end
			warn(`[SecretService] listening for other servers' Rainbow Novas failed (again in {wait} s): {err}`)
			task.wait(wait)
			wait = math.min(wait * 2, SecretService.SubscribeRetry.Max)
		end
	end)
end

return SecretService
