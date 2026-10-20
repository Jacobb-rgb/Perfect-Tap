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
	  { Action = "Glow", Color } the Plot Glow colour to show ("" = off;
	                           "Locked" for a colour the perk hasn't unlocked).
	The Plot Glow (World/PlotGlow) follows the save: built into the plot when
	it is assigned and whenever the pick changes, gone when the plot is
	freed. THE GREAT FORGE plaza's fire crystal gets a "Star Forge" prompt
	(CrystalPrompt, F / gamepad Y) that opens the window (OpenUI "Rebirth").
	  { Action = "Weapon", Id } buys a STAR blaster with Forge Stars
	                           (StarBlasterData.quote / buy: "BadWeapon" |
	                           "Owned" | "Locked" | "NoStars") and equips it.
	  { Action = "Equip", Id } the star blaster to fight with ("" = your
	                           forged blaster; "Locked" for one you don't
	                           own or that hasn't opened yet).
	Every request read gets a RebirthResult { Action, Ok, Reason?, Perk?,
	Level?, Stars?, Rebirths?, Id? }.

	STAR blasters by Robux: the game passes StarComet..StarSingularity
	(Grant "RebirthWeapon", MonetizationService.registerPass, checked on
	every load and on a purchase). Grant = RebirthWeapons[id] and
	RebirthWeaponPasses[id] (equipped when it is open and you hold none);
	a weapon already bought with stars stays a star one (a refund of the
	pass never takes it). Revoke (Roblox says the pass isn't owned, e.g. a
	refund) = only a pass-given weapon goes, unequipped. ToolService hands
	the equipped one out, MiningService multiplies the damage
	(StarBlasterData.equipped / mult).

	The perks act through Bonuses (the built-in "Rebirth" provider: income,
	sell value, ore luck, carry capacity, train trips), the reset (Head
	Start, Podium Keeper). The player attribute ForgeStars (every star ever
	earned, Stats.StarsEarned) puts the gold star over the name
	(RebirthController). State: snapshot.Rebirth { Count, Stars, Earned,
	Perks, Ready, StarsNow, MinBlaster, Weapons = { [id] = true },
	Weapon = the equipped id or "" }.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared.Config.RebirthConfig)
local StarBlasterData = require(Shared.Config.StarBlasterData)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local BlasterData = require(Shared.Config.BlasterData)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local ItemService = require(script.Parent.ItemService)
local PlotService = require(script.Parent.PlotService)
local PodiumService = require(script.Parent.PodiumService)
local TrainService = require(script.Parent.TrainService)
local PlotGlow = require(script.Parent.Parent.World.PlotGlow)
local LobbyLayout = require(Shared.Config.LobbyLayout)
local ElevatorService = require(script.Parent.ElevatorService)
local MonetizationService = require(script.Parent.MonetizationService)

local RebirthService = {}

RebirthService.StarsAttribute = "ForgeStars"
RebirthService.CrystalPrompt = "StarForgePrompt"
RebirthService.CrystalRange = 16 -- studs from the crystal's axis (the ring is 10.2 out, the walk-in base 12.4)
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

---------------------------------------------------------------- the plot glow

-- Builds, swaps or removes the owner's Plot Glow to match their save.
function RebirthService.refreshGlow(player: Player)
	local plotId = PlotService.plotOf(player)
	local plot = if plotId then PlotService.model(plotId) else nil
	if not plotId or not plot then
		return
	end
	local data = DataService.get(player)
	local want = if data then RebirthConfig.glowOf(data) else ""
	local shown = plot:FindFirstChild(PlotGlow.Name)
	if shown and shown:GetAttribute("Color") == want then
		return
	end
	if shown then
		shown:Destroy()
	end
	if want ~= "" then
		PlotGlow.build(plot, PlotService.plotCFrame(plotId), want)
	end
end

local function clearGlow(plotId: number)
	local plot = PlotService.model(plotId)
	local shown = plot and plot:FindFirstChild(PlotGlow.Name)
	if shown then
		shown:Destroy()
	end
end

-- Sets the Plot Glow colour to show. Returns (true) or (false, "NoData" | "Locked").
function RebirthService.setGlow(player: Player, colorId: any): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	if type(colorId) ~= "string" or not RebirthConfig.glowUnlocked(data.StarPerks, colorId) then
		return false, "Locked"
	end
	data.PlotGlow = colorId
	RebirthService.refreshGlow(player)
	DataService.changed(player)
	return true, nil
end

---------------------------------------------------------------- the crystal prompt

--[[
	The "Star Forge" prompt at THE GREAT FORGE plaza's fire crystal: an
	invisible anchored part on the crystal's axis at chest height (the
	crystal itself spins on the clients), under `parent`. Returns the prompt.
]]
function RebirthService.setupCrystal(parent: Instance, center: Vector3, floorY: number): ProximityPrompt
	local anchor = Instance.new("Part")
	anchor.Name = RebirthService.CrystalPrompt
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(center.X, floorY + 3, center.Z)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "Star Forge"
	prompt.ObjectText = "Rebirth"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = RebirthService.CrystalRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player: Player)
		Net.fire("OpenUI", player, "Rebirth")
	end)
	anchor.Parent = parent
	return prompt
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

---------------------------------------------------------------- star blasters

local function weaponSet(data: { [string]: any }, key: string): { [string]: any }
	local t = data[key]
	if type(t) ~= "table" then
		t = {}
		data[key] = t
	end
	return t
end

-- Buys a STAR blaster with Forge Stars and equips it. Returns (true) or (false, reason).
function RebirthService.buyWeapon(player: Player, id: any): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	local _, reason = StarBlasterData.quote(data, id)
	if reason then
		return false, reason
	end
	StarBlasterData.buy(data, id)
	DataService.changed(player)
	return true, nil
end

-- Equips a STAR blaster you own that is open ("" = your forged blaster). Returns (true) or (false, reason).
function RebirthService.equipWeapon(player: Player, id: any): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "NoData"
	end
	if id ~= "" and not (StarBlasterData.owns(data, id) and StarBlasterData.unlocked(data, id)) then
		return false, "Locked"
	end
	if data.StarBlaster ~= id then
		data.StarBlaster = id
		DataService.changed(player)
	end
	return true, nil
end

-- Pass handler "RebirthWeapon" grant (idempotent: runs on every load). True when the save changed.
local function grantWeapon(player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local star = StarBlasterData.get(entry.WeaponId)
	if not star then
		return false
	end
	local owned = weaponSet(data, "RebirthWeapons")
	if owned[star.Id] then
		-- bought with stars, or this pass gave it on an earlier load
		return false
	end
	owned[star.Id] = true
	weaponSet(data, "RebirthWeaponPasses")[star.Id] = true
	local open = StarBlasterData.unlocked(data, star.Id)
	if open and StarBlasterData.equipped(data) == nil then
		data.StarBlaster = star.Id
	end
	local line = if open
		then `{star.Name} unlocked! Thank you! Equip it in the Star Forge.`
		else `{star.Name} is yours! Thank you! It opens at rebirth {star.Unlock}.`
	Net.fire("Notify", player, { Text = line, Kind = "Reward" })
	return true
end

-- Pass handler "RebirthWeapon" revoke: only a weapon this pass gave goes (unequipped). True when the save changed.
local function revokeWeapon(_player: Player, data: { [string]: any }, entry: MonetizationConfig.Entry): boolean
	local star = StarBlasterData.get(entry.WeaponId)
	local passes = weaponSet(data, "RebirthWeaponPasses")
	if not star or not passes[star.Id] then
		return false
	end
	passes[star.Id] = nil
	weaponSet(data, "RebirthWeapons")[star.Id] = nil
	if data.StarBlaster == star.Id then
		data.StarBlaster = ""
	end
	return true
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
			if perk == "PlotGlow" then
				RebirthService.refreshGlow(player)
			end
			answer(player, { Action = "Buy", Ok = true, Perk = perk, Level = result })
		else
			answer(player, { Action = "Buy", Ok = false, Perk = perk, Reason = result })
		end
	elseif action == "Glow" then
		local color = if args then Guard.string(args.Color, 16) else nil
		local ok, reason = RebirthService.setGlow(player, color)
		answer(player, { Action = "Glow", Ok = ok, Color = color, Reason = reason })
	elseif action == "Weapon" or action == "Equip" then
		local id = if args then Guard.string(args.Id, 32) else nil
		local ok, reason
		if action == "Weapon" then
			ok, reason = RebirthService.buyWeapon(player, id)
		else
			ok, reason = RebirthService.equipWeapon(player, id)
		end
		answer(player, { Action = action, Ok = ok, Id = id, Reason = reason })
	end
end

-- The State snapshot's Rebirth field.
function RebirthService.snapshot(data: { [string]: any }): { [string]: any }
	local ready = RebirthConfig.canRebirth(data)
	local perks = if type(data.StarPerks) == "table" then data.StarPerks else {}
	local weapons = {}
	for _, star in StarBlasterData.List do
		if StarBlasterData.owns(data, star.Id) then
			weapons[star.Id] = true
		end
	end
	return {
		Count = RebirthConfig.countOf(data),
		Stars = RebirthConfig.starsOf(data),
		Earned = earnedOf(data),
		Perks = perks,
		Ready = ready,
		Glow = RebirthConfig.glowOf(data),
		StarsNow = RebirthConfig.starsFor(RebirthConfig.reachedOf(data)),
		Reached = RebirthConfig.reachedOf(data),
		MinBlaster = RebirthConfig.MinBlaster,
		Weapons = weapons,
		Weapon = if StarBlasterData.equipped(data) then data.StarBlaster else "",
	}
end

-- Internals for the Lune tests only (tests/Rebirth.spec.luau).
RebirthService._test = {
	action = onAction,
	grantWeapon = grantWeapon,
	revokeWeapon = revokeWeapon,
	reset = function()
		table.clear(busy)
	end,
}

function RebirthService.init()
	Net.on("RebirthAction", onAction)
	MonetizationService.registerPass("RebirthWeapon", { grant = grantWeapon, revoke = revokeWeapon })
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
	PlotService.onAssigned(function(player: Player)
		RebirthService.refreshGlow(player)
	end)
	PlotService.onReleased(function(_player: Player, plotId: number)
		clearGlow(plotId)
	end)
end

function RebirthService.start()
	-- the "Star Forge" prompt at the plaza's fire crystal (the lobby is built by now)
	local map = Workspace:FindFirstChild("Map")
	local ring = map and map:FindFirstChild("FireCrystalRing", true)
	local ok, piece = pcall(LobbyLayout.get, "FireCrystal")
	if ring and ok and piece then
		-- (the plaza's slate tiles top out 0.43 over the piece's centre: Plaza/Common.TileTop)
		RebirthService.setupCrystal(ring, piece.Center, piece.Center.Y + 0.43)
	else
		warn("[RebirthService] no FireCrystalRing in the map: no Star Forge prompt")
	end
end

return RebirthService
