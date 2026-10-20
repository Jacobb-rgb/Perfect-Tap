--[[
	RebirthService: rebirth "STAR FORGE" (RebirthConfig has the rules).

	RebirthAction (Net, rate limited, anywhere: the side menu's REBIRTH):
	  { Action = "Rebirth" }   RebirthConfig.canRebirth ("Locked" below
	                           MinBlaster, "Busy" while one runs), then in one
	                           go, with no yield: PlotService.reload takes the
	                           plot down (the machines unload, the vise ore,
	                           the pen's intents, the Foundry session), every
	                           item the player owns leaves the world (loose,
	                           carried, on belts), RebirthConfig.reset rewrites
	                           the save (coins, blaster, upgrades, train,
	                           backpack, every ore; the factory stays) and pays
	                           the stars, and the plot comes back up from the
	                           save (the machines spawn with empty queues).
	                           Then the train starts over (TrainService.
	                           resetRun), the podiums redraw, DataService.
	                           changed + saveNow, and after MomentSeconds the
	                           character goes home (the client's moment plays
	                           meanwhile).
	  { Action = "Buy", Perk } a Star Shop level (RebirthConfig.quote / buy:
	                           "BadPerk" | "Max" | "NoStars").
	Every request read gets a RebirthResult { Action, Ok, Reason?, Perk?,
	Level?, Stars?, Rebirths? }.

	The perks act through Bonuses (the built-in "Rebirth" provider: income,
	sell value, ore luck, carry capacity, train trips), the reset (Head
	Start, Podium Keeper). The player attribute ForgeStars (every star ever
	earned, Stats.StarsEarned) puts the gold star over the name
	(RebirthController). State: snapshot.Rebirth { Count, Stars, Earned,
	Perks, Ready, StarsNow, MinBlaster }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared.Config.RebirthConfig)
local BlasterData = require(Shared.Config.BlasterData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local PlotService = require(script.Parent.PlotService)
local PodiumService = require(script.Parent.PodiumService)
local TrainService = require(script.Parent.TrainService)
local ElevatorService = require(script.Parent.ElevatorService)

local RebirthService = {}

RebirthService.StarsAttribute = "ForgeStars"
RebirthService.MomentSeconds = 3.2 -- the client's flash + banner, then the character goes home

local MAX_PAYLOAD = 4

local busy: { [Player]: boolean } = {}

-- Every star the player ever earned (the gold star over the name).
local function earnedOf(data: { [string]: any }): number
	local stats = data.Stats
	local v = if type(stats) == "table" then stats.StarsEarned else nil
	return if type(v) == "number" and v == v and v > 0 and v < math.huge then math.floor(v) else 0
end

local function showStars(player: Player, data: { [string]: any })
	local earned = earnedOf(data)
	local value = if earned > 0 then earned else nil
	if player:GetAttribute(RebirthService.StarsAttribute) ~= value then
		player:SetAttribute(RebirthService.StarsAttribute, value)
	end
end

local function answer(player: Player, result: { [string]: any })
	Net.fire("RebirthResult", player, result)
end

-- The rebirth on the save and in the world (after canRebirth), in one step:
-- the plot comes down, the waiting welcome-back payout is settled (so it can't
-- land in the new run), the player's items leave the world, the save resets,
-- the plot comes back up. Returns the stars paid and the new count.
local function doRebirth(player: Player, data: { [string]: any }): (number, number)
	local stars, count = 0, 0
	PlotService.reload(player, function()
		PodiumService.settleOffline(player)
		-- every item the player owns leaves the world (the unload above already
		-- stashed the vise ore: the reset empties the pen with it); a dusty
		-- relic is an artifact: stashed (the relic keeper adds it to the collection)
		for _, record in ItemService.ownedBy(player.UserId) do
			if record.State ~= "Consumed" then
				if record.Kind == "Relic" then
					ItemService.stash(record, nil)
				else
					ItemService.destroy(record)
				end
			end
		end
		stars, count = RebirthConfig.reset(data)
		-- the relics the reset kept in the pen (from queues, the train, the pen) go to the keeper
		local storage = data.Storage
		for i = #storage, 1, -1 do
			local item = storage[i]
			if type(item) == "table" and item.K == "Relic" and ItemService.keepRelic(player, item.O) then
				table.remove(storage, i)
			end
		end
	end)
	return stars, count
end

-- The steps after the save changed: each on its own, so one failing never
-- hides the rebirth that already happened.
local function afterRebirth(player: Player, data: { [string]: any })
	local steps: { () -> () } = {
		function()
			TrainService.resetRun(player)
		end,
		function()
			local plotId = PlotService.plotOf(player)
			if plotId then
				PodiumService.refreshPlot(plotId)
			end
		end,
		function()
			showStars(player, data)
		end,
	}
	for _, step in steps do
		local ok, err = pcall(step :: any)
		if not ok then
			warn(`[RebirthService] after the rebirth of {player.Name}: {err}`)
		end
	end
	DataService.changed(player)
	task.spawn(function()
		DataService.saveNow(player)
	end)
	task.delay(RebirthService.MomentSeconds, function()
		if player.Parent then
			PlotService.sendHome(player)
		end
	end)
end

--[[
	Rebirths the player now (the RebirthAction "Rebirth" handler, and the
	tests). Returns (true, stars, rebirths) or (false, reason): "Locked",
	"NoData", "Busy" (one is running, or the elevator is taking you to a
	floor: it would land after the trip home), "Failed" (taking the plot down
	or the reset broke: nothing was paid).
]]
function RebirthService.rebirth(player: Player): (boolean, any, number?)
	local data = DataService.get(player)
	local ok, reason = RebirthConfig.canRebirth(data)
	if not ok or not data then
		return false, reason
	end
	if busy[player] or ElevatorService.isRiding(player) then
		return false, "Busy"
	end
	busy[player] = true
	local done, stars, count = pcall(doRebirth, player, data)
	busy[player] = nil
	if not done then
		warn(`[RebirthService] rebirth of {player.Name} failed: {stars}`)
		return false, "Failed"
	end
	afterRebirth(player, data)
	return true, stars, count
end

-- Buys the next level of a Star Shop perk. Returns (true, level) or (false, reason).
function RebirthService.buy(player: Player, perkId: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	local _, reason = RebirthConfig.quote(data, perkId)
	if reason then
		return false, reason
	end
	-- no yield between the quote and the purchase
	local level = RebirthConfig.buy(data, perkId)
	DataService.changed(player)
	return true, level
end

local function onAction(player: Player, raw: any)
	local args = Guard.table(raw, MAX_PAYLOAD)
	local action = if args then Guard.string(args.Action, 16) else nil
	if action == "Rebirth" then
		local ok, stars, count = RebirthService.rebirth(player)
		if ok then
			answer(player, { Action = "Rebirth", Ok = true, Stars = stars, Rebirths = count })
		else
			answer(player, { Action = "Rebirth", Ok = false, Reason = stars })
		end
	elseif action == "Buy" then
		local perk = if args then Guard.string(args.Perk, 32) else nil
		local ok, result = RebirthService.buy(player, perk)
		if ok then
			answer(player, { Action = "Buy", Ok = true, Perk = perk, Level = result })
		else
			answer(player, { Action = "Buy", Ok = false, Perk = perk, Reason = result })
		end
	end
end

-- The State snapshot's Rebirth field.
function RebirthService.snapshot(data: { [string]: any }): { [string]: any }
	local ready = RebirthConfig.canRebirth(data)
	local perks = if type(data.StarPerks) == "table" then data.StarPerks else {}
	return {
		Count = RebirthConfig.countOf(data),
		Stars = RebirthConfig.starsOf(data),
		Earned = earnedOf(data),
		Perks = perks,
		Ready = ready,
		StarsNow = RebirthConfig.starsFor(RebirthConfig.reachedOf(data)),
		Reached = RebirthConfig.reachedOf(data),
		MinBlaster = RebirthConfig.MinBlaster,
	}
end

-- Internals for the Lune tests only (tests/Rebirth.spec.luau).
RebirthService._test = {
	action = onAction,
	reset = function()
		table.clear(busy)
	end,
}

function RebirthService.init()
	Net.on("RebirthAction", onAction)
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		snapshot.Rebirth = RebirthService.snapshot(data)
		-- coin prices that grow with the blaster follow the best level ever (CapsuleView, BoostView)
		snapshot.PriceLevel = BlasterData.priceLevel(data)
	end)
	DataService.onLoaded(function(player: Player, data: { [string]: any })
		showStars(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
	end)
end

function RebirthService.start() end

return RebirthService
