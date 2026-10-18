--[[
	HoverboardService: buying, equipping and riding hoverboards
	(HoverboardData; owner: mine floors point 3).

	Save: data.Hoverboards = { Owned = { [boardId] = true }, Equipped = id or "" }
	(DataTemplate; junk is repaired in place when read: unknown ids and
	non-true values leave Owned, an Equipped board you don't own becomes "").

	HoverboardAction (Net, rate limited), from anywhere (the Boards panel opens
	from the left side menu); every request read gets a HoverboardResult
	{ Action, Board?, Ok, Reason?, Riding? }:
	  { Action = "Buy", Board }    a coin board you don't own: EconomyService.spend
	                               and Owned[board] = true in one step with no
	                               yield (a double tap buys once). The new board
	                               is equipped when it is faster than the one you
	                               had (or you had none). Robux boards: "Robux"
	                               (the client prompts the developer product).
	  { Action = "Equip", Board }  an owned board ("" = none, also gets you off).
	                               While riding, the new board replaces the old.
	  { Action = "Ride", On }      On = true / false (nil = toggle). Getting on
	                               needs: a loaded save, an equipped owned board,
	                               a living character, not seated, not in a
	                               cleaning session (CleaningService, loaded on
	                               first use), not riding the elevator, and
	                               ToggleCooldown since the last ride change.
	Riding: the character gets the attribute HoverboardData.Attribute = board
	id and the Humanoid's HipHeight rises by HoverboardBuilder.DeckHeight (the
	old value is kept in HoverboardData.HipAttribute and put back); the walk
	speed comes from CarryService.updateWalkSpeed (HoverboardData.walkSpeed:
	the board's speed, Robux boards ignore the carry slowdown). Nothing visible
	is made here: every client builds the board under each rider
	(HoverboardController). Off again on: death, a new character, sitting down,
	a cleaning session starting, an elevator ride departing, unequipping.
	The blaster keeps working while riding.

	Robux boards: MonetizationService grants them (Kind "Hoverboard"):
	Owned[board] = true, equipped like a bought board; already owned = granted
	with nothing new.
	State: snapshot.Hoverboards = { Owned = { boardId... }, Equipped }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HoverboardData = require(Shared.Config.HoverboardData)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local HoverboardBuilder = require(Shared.Builders.HoverboardBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Guard = require(script.Parent.Parent.Guard)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local EconomyService = require(script.Parent.EconomyService)
local CarryService = require(script.Parent.CarryService)
local ElevatorService = require(script.Parent.ElevatorService)
local MonetizationService = require(script.Parent.MonetizationService)

local HoverboardService = {}

export type Reason =
	"Ok"
	| "NoData"
	| "BadAction"
	| "BadBoard"
	| "Owned"
	| "NotOwned"
	| "Robux"
	| "NoCoins"
	| "NoBoard"
	| "Dead"
	| "Seated"
	| "Cleaning"
	| "Elevator"
	| "Cooldown"

export type Record = { Owned: { [string]: boolean }, Equipped: string }

HoverboardService.ToggleCooldown = 0.5 -- seconds between two ride changes of one player
HoverboardService.Reasons = {
	"NoData",
	"BadAction",
	"BadBoard",
	"Owned",
	"NotOwned",
	"Robux",
	"NoCoins",
	"NoBoard",
	"Dead",
	"Seated",
	"Cleaning",
	"Elevator",
	"Cooldown",
}

local MAX_PAYLOAD = 4

local riding: { [Player]: string } = {}
local lastToggle: { [Player]: number } = {}
local clock: () -> number = os.clock

---------------------------------------------------------------- the save

-- data.Hoverboards, repaired in place (made when missing).
function HoverboardService.record(data: { [string]: any }): Record
	local record = data.Hoverboards
	if type(record) ~= "table" then
		record = { Owned = {}, Equipped = "" }
		data.Hoverboards = record
	end
	local owned = record.Owned
	if type(owned) ~= "table" then
		owned = {}
		record.Owned = owned
	end
	local junk = {}
	for id, value in owned do
		if value ~= true or HoverboardData.get(id) == nil then
			table.insert(junk, id)
		end
	end
	for _, id in junk do
		owned[id] = nil
	end
	local equipped = record.Equipped
	if type(equipped) ~= "string" or (equipped ~= "" and owned[equipped] ~= true) then
		record.Equipped = ""
	end
	return record :: Record
end

function HoverboardService.owns(data: { [string]: any }, boardId: string): boolean
	return HoverboardService.record(data).Owned[boardId] == true
end

-- The equipped board's id (owned and known), or nil.
function HoverboardService.equipped(data: { [string]: any }): string?
	local id = HoverboardService.record(data).Equipped
	return if id ~= "" then id else nil
end

-- Gives a board (bought or granted) and equips it when it beats the equipped one.
local function give(record: Record, board: HoverboardData.Board)
	record.Owned[board.Id] = true
	local current = HoverboardData.get(record.Equipped)
	if not current or board.Speed > current.Speed then
		record.Equipped = board.Id
	end
end

---------------------------------------------------------------- riding

-- The board the player rides right now, or nil.
function HoverboardService.ridingBoard(player: Player): string?
	return riding[player]
end

function HoverboardService.isRiding(player: Player): boolean
	return riding[player] ~= nil
end

local function humanoidOf(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character, humanoid
end

-- Puts the player on `boardId` (or off with nil): the character attribute, the
-- HipHeight, the walk speed. True when the change was made.
local function setRide(player: Player, boardId: string?): boolean
	local character, humanoid = humanoidOf(player)
	if boardId then
		if not character or not humanoid then
			return false
		end
		if character:GetAttribute(HoverboardData.HipAttribute) == nil then
			character:SetAttribute(HoverboardData.HipAttribute, humanoid.HipHeight)
			humanoid.HipHeight += HoverboardBuilder.DeckHeight
		end
		character:SetAttribute(HoverboardData.Attribute, boardId)
		riding[player] = boardId
	else
		riding[player] = nil
		if character then
			local hip = character:GetAttribute(HoverboardData.HipAttribute)
			if humanoid and type(hip) == "number" and hip == hip then
				humanoid.HipHeight = hip
			end
			character:SetAttribute(HoverboardData.HipAttribute, nil)
			character:SetAttribute(HoverboardData.Attribute, nil)
		end
	end
	CarryService.updateWalkSpeed(player)
	return true
end

-- Gets the player off the board (no-op when not riding).
function HoverboardService.dismount(player: Player)
	if riding[player] then
		setRide(player, nil)
	end
end

-- Is the player in the middle of the cleaning minigame? (CleaningService is loaded
-- on first use, like ElevatorService does: it needs the whole game around it)
function HoverboardService.isCleaning(player: Player): boolean
	local ok, CleaningService = pcall(function(): any
		return require(script.Parent.CleaningService) :: any
	end)
	return ok and CleaningService.inSession(player) == true
end

---------------------------------------------------------------- requests

local DENY_TEXT: { [string]: string } = {
	NoBoard = "Get a hoverboard first: open Boards on the left.",
	Cleaning = "Finish cleaning first.",
	Elevator = "Wait until the elevator stops.",
	Seated = "Stand up first.",
	Robux = "This board is bought with Robux.",
	Owned = "You already own this board.",
	NotOwned = "You don't own this board yet.",
}

local function answer(player: Player, action: string, board: string?, ok: boolean, reason: Reason)
	Net.fire("HoverboardResult", player, {
		Action = action,
		Board = board,
		Ok = ok,
		Reason = if ok then nil else reason,
		Riding = riding[player] ~= nil,
	})
end

local function deny(player: Player, reason: Reason, text: string?)
	local message = text or DENY_TEXT[reason]
	if message then
		Net.fire("Notify", player, { Text = message, Kind = "Deny" })
	end
	-- the panel may be out of date: send a fresh snapshot
	StateService.push(player)
end

local function buy(player: Player, data: { [string]: any }, boardId: any): (boolean, Reason)
	local board = HoverboardData.get(boardId)
	if not board then
		return false, "BadBoard"
	end
	local record = HoverboardService.record(data)
	if record.Owned[board.Id] then
		deny(player, "Owned")
		return false, "Owned"
	end
	if board.Kind ~= "Coins" then
		deny(player, "Robux")
		return false, "Robux"
	end
	local price = board.Price :: number
	-- no yield from the coin check to the board: a double tap buys once
	if not EconomyService.spend(player, price, "Hoverboard") then
		local missing = math.max(1, price - EconomyService.balance(player))
		deny(player, "NoCoins", `The {board.Name} costs {Format.money(price)}. You need {Format.money(missing)} more.`)
		return false, "NoCoins"
	end
	give(record, board)
	DataService.changed(player)
	if riding[player] and riding[player] ~= record.Equipped and record.Equipped ~= "" then
		setRide(player, record.Equipped)
	end
	Net.fire("Notify", player, { Text = `{board.Name} bought! Press RIDE to hover.`, Kind = "Reward" })
	return true, "Ok"
end

local function equip(player: Player, data: { [string]: any }, boardId: any): (boolean, Reason)
	local record = HoverboardService.record(data)
	if boardId == "" then
		record.Equipped = ""
		DataService.changed(player)
		HoverboardService.dismount(player)
		return true, "Ok"
	end
	local board = HoverboardData.get(boardId)
	if not board then
		return false, "BadBoard"
	end
	if not record.Owned[board.Id] then
		deny(player, "NotOwned")
		return false, "NotOwned"
	end
	record.Equipped = board.Id
	DataService.changed(player)
	if riding[player] then
		setRide(player, board.Id)
	end
	return true, "Ok"
end

local function ride(player: Player, data: { [string]: any }, on: any): (boolean, Reason)
	local want: boolean = if type(on) == "boolean" then on else riding[player] == nil
	if not want then
		HoverboardService.dismount(player)
		return true, "Ok"
	end
	local boardId = HoverboardService.equipped(data)
	if not boardId then
		deny(player, "NoBoard")
		return false, "NoBoard"
	end
	if riding[player] == boardId then
		return true, "Ok"
	end
	local root = Guard.rootPart(player)
	local _, humanoid = humanoidOf(player)
	if not root or not humanoid then
		return false, "Dead"
	end
	local now = clock()
	local last = lastToggle[player]
	if last and now - last < HoverboardService.ToggleCooldown then
		return false, "Cooldown"
	end
	if humanoid.Sit then
		deny(player, "Seated")
		return false, "Seated"
	end
	if HoverboardService.isCleaning(player) then
		deny(player, "Cleaning")
		return false, "Cleaning"
	end
	if ElevatorService.isRiding(player) then
		deny(player, "Elevator")
		return false, "Elevator"
	end
	lastToggle[player] = now
	if not setRide(player, boardId) then
		return false, "Dead"
	end
	return true, "Ok"
end

local function onAction(player: Player, arg: any): (boolean, Reason)
	local args = Guard.table(arg, MAX_PAYLOAD)
	local action = if args and type(args.Action) == "string" then args.Action else "?"
	local board = if args and type(args.Board) == "string" and #args.Board <= 40 then args.Board else nil
	local ok: boolean = false
	local reason: Reason = "BadAction"
	local data = DataService.get(player)
	if not data then
		reason = "NoData"
	elseif args then
		if action == "Buy" then
			ok, reason = buy(player, data, args.Board)
		elseif action == "Equip" then
			ok, reason = equip(player, data, args.Board)
		elseif action == "Ride" then
			ok, reason = ride(player, data, args.On)
		end
	end
	if action == "Buy" or action == "Equip" or action == "Ride" then
		answer(player, action, board, ok, reason)
	end
	return ok, reason
end

---------------------------------------------------------------- Robux boards

-- MonetizationService grant handler (Kind "Hoverboard"): owns the product's board.
local function grantBoard(player: Player, data: { [string]: any }, product: MonetizationConfig.Product): boolean
	local board = HoverboardData.get(product.BoardId)
	if not board then
		return false
	end
	local record = HoverboardService.record(data)
	if record.Owned[board.Id] then
		Net.fire("Notify", player, { Text = `You already own the {board.Name}.`, Kind = "Info" })
		return true
	end
	give(record, board)
	if riding[player] and record.Equipped ~= "" and riding[player] ~= record.Equipped then
		setRide(player, record.Equipped)
	end
	Net.fire("Notify", player, { Text = `{board.Name} unlocked! Thank you! Press RIDE to hover.`, Kind = "Reward" })
	return true
end

---------------------------------------------------------------- lifecycle

local function hookCharacter(player: Player, character: Model)
	-- a new character never starts on a board
	if riding[player] then
		riding[player] = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		HoverboardService.dismount(player)
	end)
	humanoid.Seated:Connect(function(active: boolean)
		if active then
			HoverboardService.dismount(player)
		end
	end)
end

-- Internals for the Lune tests only (tests/HoverboardService.spec.luau).
HoverboardService._test = {
	action = onAction,
	grant = grantBoard,
	setRide = setRide,
	hookCharacter = hookCharacter,
	setClock = function(fn: () -> number)
		clock = fn
	end,
	reset = function()
		table.clear(riding)
		table.clear(lastToggle)
		clock = os.clock
	end,
}

function HoverboardService.init()
	Net.on("HoverboardAction", onAction)
	MonetizationService.register("Hoverboard", grantBoard)
	StateService.addProvider(function(_player: Player, data: { [string]: any }, snapshot: { [string]: any })
		local record = HoverboardService.record(data)
		local owned = {}
		for _, board in HoverboardData.List do
			if record.Owned[board.Id] then
				table.insert(owned, board.Id)
			end
		end
		snapshot.Hoverboards = { Owned = owned, Equipped = record.Equipped }
	end)
	ElevatorService.onDepart(HoverboardService.dismount)
	local ok, CleaningService = pcall(function(): any
		return require(script.Parent.CleaningService) :: any
	end)
	if ok and CleaningService.onSessionStart then
		CleaningService.onSessionStart(HoverboardService.dismount)
	end
	local function setupPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			hookCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			riding[player] = nil
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		riding[player] = nil
		lastToggle[player] = nil
	end)
end

return HoverboardService
