--[[
	Hoverboards (owner, docs/DESIGN_V2_NOTES.md "Mine floors" point 3,
	docs/plans/MINE_FLOORS_PLAN.md point 7): ride one anywhere to move faster
	(the mine floors are big, floors 1-3 are walked).

	- 3 boards for coins, each one faster than the one before.
	- 2 boards for Robux (49 R$ each): faster than every coin board and with
	  big particle effects and a light trail (owner: "more benefits"); the coin
	  boards get small thruster effects only, no trail (owner 2026-10-21:
	  "better effects").
	- Speed is the Humanoid WalkSpeed while riding (CarryService walks at
	  BaseWalkSpeed = 18 without a board). One formula for everything,
	  HoverboardData.walkSpeed (CarryService.updateWalkSpeed uses it): every
	  carried item slows you by SlowPerItem, at most MaxSlow in total, on foot
	  and on coin boards; Robux boards ignore the carry slowdown (owner:
	  "more benefits").
	- Bought once and kept forever: data.Hoverboards = { Owned = { [id] = true },
	  Equipped = id or "" } (HoverboardService). While riding, the character
	  has the attribute Attribute = the board id (the server sets it and raises
	  the Humanoid's HipHeight by HoverboardBuilder.DeckHeight; every client
	  builds the board under that character, HoverboardController).

	Coin prices sit between the other one-time goals, so a board is always the
	next nice thing to save for. They follow the blaster recipe prices
	(priceFrom; today's numbers, the balance sim in docs/BALANCE_SIM.md):
	  blaster 3   2,000     floor 2 opens
	  BOARD 1     5,000     (Timber Drifter) 2.5x blaster 3: the first floor-1/2 treat
	  blaster 4   15,000
	  BOARD 2     80,000    (Cart Cruiser) 0.8x blaster 5: just before floor 3
	  blaster 5   100,000   floor 3 opens
	  blaster 6   700,000
	  elevator    3,300,000 (MineFloors.Elevator) 2/3 of blaster 7: before floor 4
	  BOARD 3     5,000,000 (Emberglass Glider) = blaster 7: a goal past the first hour
	  blaster 7   5,000,000 floor 4 opens
	The Robux boards are faster than all of them from the first minute.

	Robux boards are game passes (bought once, owned forever; a refund takes
	the board back): each names its MonetizationConfig entry (PassKey), the
	ids live there. A pass whose id is still 0 is never prompted: the shop
	shows "Coming soon". MonetizationService checks pass ownership on every
	load and HoverboardService grants / revokes the board.

	Model look and effects: src/shared/Builders/HoverboardBuilder.luau and
	HoverboardFx.luau (Colors below are the board's palette there).
]]

local BlasterData = require(script.Parent.BlasterData)
local GearConfig = require(script.Parent.GearConfig)
local MonetizationConfig = require(script.Parent.MonetizationConfig)

local HoverboardData = {}

export type Kind = "Coins" | "Robux"
export type Effect = "None" | "Sparks" | "Vents" | "Lava" | "Comet" | "Phoenix"

export type Colors = {
	Main: Color3, -- the deck / body
	Trim: Color3, -- rims, bolts, frames
	Accent: Color3, -- the second body color (stripes, fins, feathers)
	Glow: Color3, -- the hover pad and the main glow (Neon)
	Glow2: Color3, -- the second glow (trails, tips)
}

export type Board = {
	Id: string,
	Order: number, -- 1..5, shop order (coin boards first)
	Name: string,
	Kind: Kind,
	Price: number?, -- coins (Kind = "Coins")
	Robux: number?, -- price shown on the button (Kind = "Robux")
	PassKey: string?, -- MonetizationConfig.Entries key of its game pass (Kind = "Robux")
	Speed: number, -- Humanoid.WalkSpeed while riding
	IgnoresCarrySlow: boolean, -- true: carried items don't slow you down on it
	Effect: Effect,
	Colors: Colors,
	Description: string, -- one short line on the shop card
	Perks: { string }, -- short chips on the shop card
}

-- walking without boots or bonuses, and the carry slowdown: GearConfig's numbers (steps 6-7)
HoverboardData.BaseWalkSpeed = GearConfig.value("Boots", 0)
HoverboardData.SlowPerItem = GearConfig.CarrySlowPerItem -- walk speed lost per carried item
HoverboardData.MaxSlow = GearConfig.CarrySlowMax -- at most this much in total
HoverboardData.MinWalkSpeed = GearConfig.MinWalkSpeed -- on foot, never slower
HoverboardData.MaxRideSpeed = 50 -- never faster (Bonuses.walkSpeed's cap too)
HoverboardData.RobuxPrice = 49
HoverboardData.Attribute = "Hoverboard" -- character attribute while riding: the board id
HoverboardData.HipAttribute = "HoverboardHip" -- character attribute: the HipHeight before riding

local rgb = Color3.fromRGB

-- Coin prices follow the blaster prices (BlasterData Recipe.Coins), so a blaster re-balance
-- moves the boards with it: `factor` x the coin price of blaster `level`, rounded to 2 digits.
function HoverboardData.priceFrom(level: number, factor: number): number
	local blaster = BlasterData.ByLevel[level]
	local coins = if blaster and blaster.Recipe then blaster.Recipe.Coins else 0
	local raw = coins * factor
	if raw <= 0 then
		return 0
	end
	local step = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	return math.floor(raw / step + 0.5) * step
end

HoverboardData.List = {
	{
		Id = "TimberDrifter",
		Order = 1,
		Name = "Timber Drifter",
		Kind = "Coins",
		Price = HoverboardData.priceFrom(3, 2.5), -- right after blaster 3 (floor 2)
		Speed = 23,
		IgnoresCarrySlow = false,
		Effect = "Sparks",
		Colors = {
			Main = rgb(170, 112, 66), -- planks
			Trim = rgb(206, 116, 60), -- copper bolts, caps, thruster pods
			Accent = rgb(58, 60, 72), -- iron straps and pads
			Glow = rgb(255, 136, 40), -- amber hover glow
			Glow2 = rgb(255, 170, 70),
		},
		Description = "Planks, copper bolts and two little thrusters. It floats!",
		Perks = { "Faster than walking" },
	},
	{
		Id = "CartCruiser",
		Order = 2,
		Name = "Cart Cruiser",
		Kind = "Coins",
		Price = HoverboardData.priceFrom(5, 0.8), -- just before blaster 5 (floor 3)
		Speed = 27,
		IgnoresCarrySlow = false,
		Effect = "Vents",
		Colors = {
			Main = rgb(118, 128, 156), -- riveted steel tub
			Trim = rgb(206, 116, 60), -- copper rim
			Accent = rgb(62, 64, 78), -- dark iron wheels, bumper
			Glow = rgb(40, 170, 255), -- blue vents and pads
			Glow2 = rgb(255, 196, 110), -- the warm headlamp
		},
		Description = "A mine cart that forgot its rails. Blue vents, big speed.",
		Perks = { "Faster than walking" },
	},
	{
		Id = "EmberglassGlider",
		Order = 3,
		Name = "Emberglass Glider",
		Kind = "Coins",
		Price = HoverboardData.priceFrom(7, 1), -- a goal past the first hour (balance sim)
		Speed = 31,
		IgnoresCarrySlow = false,
		Effect = "Lava",
		Colors = {
			Main = rgb(44, 38, 52), -- obsidian
			Trim = rgb(78, 64, 74), -- basalt under-layer
			Accent = rgb(255, 150, 70), -- amber crystal shards
			Glow = rgb(255, 92, 20), -- lava
			Glow2 = rgb(255, 170, 60),
		},
		Description = "Forged from obsidian with lava running through it.",
		Perks = { "Faster than walking", "Lava glow" },
	},
	{
		Id = "NeonComet",
		Order = 4,
		Name = "Neon Comet",
		Kind = "Robux",
		Robux = HoverboardData.RobuxPrice,
		PassKey = "HoverboardComet",
		Speed = 35,
		IgnoresCarrySlow = true,
		Effect = "Comet",
		Colors = {
			Main = rgb(42, 54, 140), -- night indigo
			Trim = rgb(214, 232, 255), -- star white grip edges
			Accent = rgb(255, 70, 200), -- magenta fins
			Glow = rgb(40, 210, 255), -- cyan
			Glow2 = rgb(255, 80, 210), -- magenta
		},
		Description = "A comet with a glowing core. Leaves a trail of stars.",
		Perks = { "Faster than any coin board", "No carry slowdown", "Star trail" },
	},
	{
		Id = "RoyalPhoenix",
		Order = 5,
		Name = "Royal Phoenix",
		Kind = "Robux",
		Robux = HoverboardData.RobuxPrice,
		PassKey = "HoverboardPhoenix",
		Speed = 38,
		IgnoresCarrySlow = true,
		Effect = "Phoenix",
		Colors = {
			Main = rgb(104, 50, 186), -- royal violet
			Trim = rgb(246, 188, 62), -- gold
			Accent = rgb(255, 120, 50), -- flame feather tips
			Glow = rgb(176, 80, 255), -- violet glow
			Glow2 = rgb(255, 170, 40), -- gold flame
		},
		Description = "The fastest board. Golden wings, a crown crystal and a flame trail.",
		Perks = { "Fastest board", "No carry slowdown", "Flame trail" },
	},
} :: { Board }

HoverboardData.ById = {} :: { [string]: Board }
for _, board in HoverboardData.List do
	HoverboardData.ById[board.Id] = board
end

-- The board for an id, or nil (anything that isn't a known id string).
function HoverboardData.get(id: any): Board?
	if type(id) ~= "string" or #id > 40 then
		return nil
	end
	return HoverboardData.ById[id]
end

function HoverboardData.isRobux(board: Board): boolean
	return board.Kind == "Robux"
end

-- The board's game pass id (0 = not created yet, or not a Robux board).
function HoverboardData.passId(board: Board): number
	local entry = MonetizationConfig.get(board.PassKey)
	return if entry and entry.Kind == "GamePass" then entry.Id else 0
end

-- A Robux board can be prompted only once the owner has written its pass id.
function HoverboardData.canPrompt(board: Board): boolean
	local entry = MonetizationConfig.get(board.PassKey)
	return board.Kind == "Robux" and entry ~= nil and entry.Kind == "GamePass" and MonetizationConfig.canPrompt(board.PassKey)
end

-- The board this game pass unlocks, or nil (0 / unknown ids never match).
function HoverboardData.byPass(passId: any): Board?
	local entry = MonetizationConfig.byId(passId, "GamePass")
	if not entry or entry.Grant ~= "Hoverboard" then
		return nil
	end
	return HoverboardData.get(entry.BoardId)
end

--[[
	The one walk speed formula (CarryService, the only WalkSpeed writer):
	`boardId` = the board being ridden (nil, "" or an unknown id = on foot),
	`carried` = items in your hands, `feet` = your own speed from boots and
	bonuses (Bonuses.walkSpeed; default BaseWalkSpeed), `pct` = your percent
	speed bonuses (Swift, golems: stats.WalkSpeedPct; default 0).
	  on foot   feet minus the carry slowdown (SlowPerItem per item, at most
	            MaxSlow), never below MinWalkSpeed (= Bonuses.carryWalkSpeed)
	  on board  the board's Speed with your percent bonuses, never slower than
	            your feet, minus the carry slowdown except on boards that
	            ignore it; at most MaxRideSpeed
]]
function HoverboardData.walkSpeed(boardId: any, carried: any, feet: number?, pct: number?): number
	local board = HoverboardData.get(boardId)
	local own = if type(feet) == "number" and feet == feet and feet > 0 then feet else HoverboardData.BaseWalkSpeed
	local count = if type(carried) == "number" and carried == carried and carried > 0 then math.floor(carried) else 0
	local slow = math.min(HoverboardData.MaxSlow, count * HoverboardData.SlowPerItem)
	if not board then
		return math.max(HoverboardData.MinWalkSpeed, own - slow)
	end
	local bonus = if type(pct) == "number" and pct == pct and pct > 0 then pct else 0
	local base = math.max(board.Speed * (1 + bonus), own)
	if not board.IgnoresCarrySlow then
		base -= slow
	end
	return math.min(HoverboardData.MaxRideSpeed, base)
end

-- How much faster than walking, in percent (23 -> 28), for the shop card ("+28% speed").
function HoverboardData.speedBonus(board: Board): number
	return math.floor((board.Speed / HoverboardData.BaseWalkSpeed - 1) * 100 + 0.5)
end

return HoverboardData
