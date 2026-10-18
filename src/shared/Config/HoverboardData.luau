--[[
	Hoverboards (owner, docs/DESIGN_V2_NOTES.md "Mine floors" point 3,
	docs/plans/MINE_FLOORS_PLAN.md point 7): ride one anywhere to move faster
	(the mine floors are big, floors 1-3 are walked).

	- 3 boards for coins, each one faster than the one before.
	- 2 boards for Robux (49 R$ each): faster than every coin board and with
	  their own particle / trail effects (owner: "more benefits").
	- Speed is the Humanoid WalkSpeed while riding (CarryService walks at
	  BaseWalkSpeed = 18 without a board).
	- Bought once and kept forever (save: data.Hoverboards, PHASE 2).

	Coin prices sit between the other one-time goals, so a board is always the
	next nice thing to save for (BlasterData recipes, MineFloors.Elevator):
	  blaster 3   2,000     floor 2 opens
	  BOARD 1     5,000     (Timber Drifter) the first floor-1/2 treat
	  blaster 4   15,000
	  BOARD 2     80,000    (Cart Cruiser) just before blaster 5 / floor 3
	  blaster 5   100,000   floor 3 opens
	  elevator    500,000   ("about when players reach floor 3")
	  blaster 6   700,000
	  BOARD 3     1,500,000 (Emberglass Glider) 3x the elevator: the floor 3 -> 4 luxury
	  blaster 7   5,000,000 floor 4 opens
	The Robux boards are faster than all of them from the first minute.

	Developer products: ProductId 0 = not created yet. The owner creates the
	products on the Creator Dashboard and writes their ids here (TODO). A board
	whose ProductId is 0 is never prompted: the shop shows "Coming soon".

	Model look and effects: src/shared/Builders/HoverboardBuilder.luau and
	HoverboardFx.luau (Colors below are the board's palette there).
]]

local HoverboardData = {}

export type Kind = "Coins" | "Robux"
export type Effect = "None" | "Comet" | "Phoenix"

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
	ProductId: number?, -- developer product id (Kind = "Robux"); 0 = TODO, never prompted
	Speed: number, -- Humanoid.WalkSpeed while riding
	Effect: Effect,
	Colors: Colors,
	Description: string, -- one short line on the shop card
	Perks: { string }, -- short chips on the shop card
}

HoverboardData.BaseWalkSpeed = 18 -- CarryService BASE_WALK_SPEED (walking, no board)
HoverboardData.RobuxPrice = 49

local rgb = Color3.fromRGB

HoverboardData.List = {
	{
		Id = "TimberDrifter",
		Order = 1,
		Name = "Timber Drifter",
		Kind = "Coins",
		Price = 5000,
		Speed = 23,
		Effect = "None",
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
		Price = 80000,
		Speed = 27,
		Effect = "None",
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
		Price = 1500000,
		Speed = 31,
		Effect = "None",
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
		ProductId = 0, -- TODO(owner): developer product id for Neon Comet (49 R$)
		Speed = 35,
		Effect = "Comet",
		Colors = {
			Main = rgb(42, 54, 140), -- night indigo
			Trim = rgb(214, 232, 255), -- star white grip edges
			Accent = rgb(255, 70, 200), -- magenta fins
			Glow = rgb(40, 210, 255), -- cyan
			Glow2 = rgb(255, 80, 210), -- magenta
		},
		Description = "A comet with a glowing core. Leaves a trail of stars.",
		Perks = { "Faster than any coin board", "Star trail", "Glowing fins" },
	},
	{
		Id = "RoyalPhoenix",
		Order = 5,
		Name = "Royal Phoenix",
		Kind = "Robux",
		Robux = HoverboardData.RobuxPrice,
		ProductId = 0, -- TODO(owner): developer product id for Royal Phoenix (49 R$)
		Speed = 38,
		Effect = "Phoenix",
		Colors = {
			Main = rgb(104, 50, 186), -- royal violet
			Trim = rgb(246, 188, 62), -- gold
			Accent = rgb(255, 120, 50), -- flame feather tips
			Glow = rgb(176, 80, 255), -- violet glow
			Glow2 = rgb(255, 170, 40), -- gold flame
		},
		Description = "The fastest board. Golden wings, a crown crystal and a flame trail.",
		Perks = { "Fastest board", "Flame trail", "Wing sparkles" },
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

-- A Robux board can be prompted only once the owner has written its product id.
function HoverboardData.canPrompt(board: Board): boolean
	local id = board.ProductId
	return board.Kind == "Robux" and type(id) == "number" and id > 0
end

-- The board sold as this developer product, or nil (0 / unknown ids never match).
function HoverboardData.byProduct(productId: any): Board?
	if type(productId) ~= "number" or productId <= 0 then
		return nil
	end
	for _, board in HoverboardData.List do
		if board.ProductId == productId then
			return board
		end
	end
	return nil
end

-- How much faster than walking, in percent (23 -> 28), for the shop card ("+28% speed").
function HoverboardData.speedBonus(board: Board): number
	return math.floor((board.Speed / HoverboardData.BaseWalkSpeed - 1) * 100 + 0.5)
end

return HoverboardData
