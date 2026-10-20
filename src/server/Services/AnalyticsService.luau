--[[
	AnalyticsService (V2_PLAN step 8): Roblox's AnalyticsService fed from save
	data and the coin flow, with no hooks in other services.

	- Onboarding funnel (AnalyticsService:LogOnboardingFunnelStepEvent): the
	  steps of AnalyticsService.Funnel, each logged when it first comes true
	  during a session (step 1 only for a new save). Returning players whose
	  steps were done before never log them again.
	- Progression: blaster levels (LogProgressionCompleteEvent "Blaster").
	- Custom: the number of ores discovered (LogCustomEvent "OresDiscovered").
	- Economy (LogEconomyEvent "Coins"): EconomyService.onEarned / onSpent,
	  summed per player and source and sent every FlushEvery seconds and when
	  the player leaves (the podiums pay every second: never one event each).
	- Throttle: at most MaxPerMinute events per player per minute; the rest is
	  dropped (economy sums stay and go out with the next flush).
	Only fixed names from the code are sent: no player names, no chat or
	other free text (the source/reason strings are cut to [A-Za-z0-9_], 32).
]]

local Players = game:GetService("Players")
local RobloxAnalytics = game:GetService("AnalyticsService")

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local AnalyticsService = {}

AnalyticsService.FlushEvery = 60
AnalyticsService.MaxPerMinute = 30
AnalyticsService.Currency = "Coins"

type Data = { [string]: any }

local function stat(data: Data, name: string): number
	local stats = data.Stats
	local v = if type(stats) == "table" then stats[name] else nil
	return if type(v) == "number" then v else 0
end

local function number(data: Data, name: string): number
	local v = data[name]
	return if type(v) == "number" then v else 0
end

local function discoveredCount(data: Data): number
	local n = 0
	if type(data.Discovered) == "table" then
		for _, yes in data.Discovered do
			if yes then
				n += 1
			end
		end
	end
	return n
end

-- The onboarding funnel, in order (step numbers are the list positions).
AnalyticsService.Funnel = {
	{
		Name = "Joined",
		Done = function(_data: Data): boolean
			return true
		end,
	},
	{
		Name = "FirstOre",
		Done = function(data: Data): boolean
			return stat(data, "OresMined") >= 1
		end,
	},
	{
		Name = "FirstClean",
		Done = function(data: Data): boolean
			return stat(data, "OresCleaned") >= 1
		end,
	},
	{
		Name = "FirstSale",
		Done = function(data: Data): boolean
			return stat(data, "ItemsSold") >= 1
		end,
	},
	{
		Name = "FirstPodiumIncome",
		Done = function(data: Data): boolean
			return stat(data, "PodiumEarned") > 0
		end,
	},
	{
		Name = "FirstTrainTrip",
		Done = function(data: Data): boolean
			return stat(data, "TrainTrips") >= 1
		end,
	},
	{
		Name = "FirstBlasterForged",
		Done = function(data: Data): boolean
			return stat(data, "BlastersForged") >= 1 or number(data, "BlasterLevel") >= 2
		end,
	},
	{
		Name = "TutorialDone",
		Done = function(data: Data): boolean
			local tutorial = data.Tutorial
			return type(tutorial) == "table" and tutorial.Done == true
		end,
	},
	-- (steps 6-7 funnel steps go here at their merge: first golem, first capsule, ...)
} :: { { Name: string, Done: (Data) -> boolean } }

-- A new save: no play time and nothing mined yet.
function AnalyticsService.isNew(data: Data): boolean
	return stat(data, "PlaySeconds") < 30 and stat(data, "OresMined") == 0
end

-- A code-defined label cut to [A-Za-z0-9_], at most 32 characters.
function AnalyticsService.label(text: any): string
	local s = if type(text) == "string" then string.gsub(text, "[^%w_]", "") else ""
	s = string.sub(s, 1, 32)
	return if s == "" then "Other" else s
end

export type Api = {
	funnel: (player: Player, step: number, name: string) -> (),
	progression: (player: Player, path: string, level: number) -> (),
	custom: (player: Player, name: string, value: number) -> (),
	economy: (player: Player, source: boolean, amount: number, balance: number, kind: string, sku: string) -> (),
	now: () -> number,
}

local api: Api = {
	funnel = function(player: Player, step: number, name: string)
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, name)
	end,
	progression = function(player: Player, path: string, level: number)
		RobloxAnalytics:LogProgressionCompleteEvent(player, path, level)
	end,
	custom = function(player: Player, name: string, value: number)
		RobloxAnalytics:LogCustomEvent(player, name, value)
	end,
	economy = function(player: Player, source: boolean, amount: number, balance: number, kind: string, sku: string)
		local flow = if source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
		RobloxAnalytics:LogEconomyEvent(player, flow, AnalyticsService.Currency, amount, balance, kind, sku)
	end,
	now = os.clock,
}

type Session = {
	funnel: { [number]: boolean }, -- steps already true (logged or done before)
	blaster: number,
	discovered: number,
	earned: { [string]: number },
	spent: { [string]: number },
	window: number, -- start of the current minute
	sent: number, -- events sent in it
	lastFlush: number,
}
local sessions: { [Player]: Session } = {}

-- Room for one more event this minute? (counts it)
local function allow(s: Session): boolean
	local now = api.now()
	if now - s.window >= 60 then
		s.window = now
		s.sent = 0
	end
	if s.sent >= AnalyticsService.MaxPerMinute then
		return false
	end
	s.sent += 1
	return true
end

local function send(s: Session, fn: () -> ())
	if allow(s) then
		pcall(fn)
	end
end

local function begin(player: Player, data: Data)
	local now = api.now()
	local s: Session = {
		funnel = {},
		blaster = number(data, "BlasterLevel"),
		discovered = discoveredCount(data),
		earned = {},
		spent = {},
		window = now,
		sent = 0,
		lastFlush = now,
	}
	sessions[player] = s
	local new = AnalyticsService.isNew(data)
	for step, entry in AnalyticsService.Funnel do
		local ok, done = pcall(entry.Done, data)
		if ok and done then
			s.funnel[step] = true
			if new and step == 1 then
				send(s, function()
					api.funnel(player, step, entry.Name)
				end)
			end
		end
	end
end

-- Logs what changed since the last look at the player's data.
function AnalyticsService.observe(player: Player)
	local s = sessions[player]
	local data = DataService.get(player)
	if not s or not data then
		return
	end
	for step, entry in AnalyticsService.Funnel do
		if not s.funnel[step] then
			local ok, done = pcall(entry.Done, data)
			if ok and done then
				s.funnel[step] = true
				send(s, function()
					api.funnel(player, step, entry.Name)
				end)
			end
		end
	end
	local level = number(data, "BlasterLevel")
	if level > s.blaster then
		for l = s.blaster + 1, level do
			send(s, function()
				api.progression(player, "Blaster", l)
			end)
		end
		s.blaster = level
	end
	local found = discoveredCount(data)
	if found > s.discovered then
		s.discovered = found
		send(s, function()
			api.custom(player, "OresDiscovered", found)
		end)
	end
end

-- Sends the summed coin flow of `player` (transaction types are the
-- Enum.AnalyticsEconomyTransactionType names: Gameplay for earnings, Shop for spending).
function AnalyticsService.flush(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	s.lastFlush = api.now()
	local balance = EconomyService.balance(player)
	for source, amount in s.earned do
		send(s, function()
			api.economy(player, true, amount, balance, "Gameplay", source)
		end)
	end
	for reason, amount in s.spent do
		send(s, function()
			api.economy(player, false, amount, balance, "Shop", reason)
		end)
	end
	table.clear(s.earned)
	table.clear(s.spent)
end

local function add(bucket: { [string]: number }, key: string, amount: number)
	if type(amount) == "number" and amount == amount and amount > 0 and amount < math.huge then
		bucket[key] = (bucket[key] or 0) + amount
	end
end

function AnalyticsService.init()
	DataService.onLoaded(function(player: Player, data: Data)
		begin(player, data)
	end)
	DataService.onChanged(function(player: Player)
		AnalyticsService.observe(player)
	end)
	EconomyService.onEarned(function(player: Player, amount: number, source: string)
		local s = sessions[player]
		if s then
			add(s.earned, AnalyticsService.label(source), amount)
		end
	end)
	EconomyService.onSpent(function(player: Player, amount: number, reason: string)
		local s = sessions[player]
		if s then
			add(s.spent, AnalyticsService.label(reason), amount)
		end
	end)
	DataService.beforeRelease(function(player: Player)
		AnalyticsService.flush(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		AnalyticsService.flush(player)
		sessions[player] = nil
	end)
end

function AnalyticsService.start()
	while true do
		task.wait(5)
		local now = api.now()
		for player, s in sessions do
			if now - s.lastFlush >= AnalyticsService.FlushEvery then
				AnalyticsService.flush(player)
			end
		end
	end
end

AnalyticsService._test = {
	setApi = function(fake: Api)
		api = fake
	end,
	reset = function()
		table.clear(sessions)
	end,
	begin = begin,
	session = function(player: Player): any
		return sessions[player]
	end,
	add = add,
}

return AnalyticsService
