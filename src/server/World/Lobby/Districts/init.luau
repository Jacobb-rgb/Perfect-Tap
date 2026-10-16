--[[
	Lobby package "Districts" (docs/plans/LOBBY_PLAN.md 6.4 + design v2,
	section 0): the market stalls and attractions around the plaza.

	  Shop           SHOP = the Gear shop (hook ShopCounter)            Stalls
	  ShopFront      Tobin's Sell stall: SellBin (+ Intake), SellCounter,
	                 Tobin the Miner                                    Fronts
	  Upgrades       UPGRADES = the Tech shop (hook UpgradeCounter)     Stalls
	  UpgradesFront  glowing laser blaster on a pedestal (Spin)          Fronts
	  SpinWheel      SPIN & WIN wheel (Wheel: Spin) + EmberChest        Wheel
	  CapsuleStall   golem capsule stall (tag CapsuleStall)             Capsules
	  EnchantShop    rune table (EnchantCounter), floating crystals     Enchant
	  HallOfFame     Board1..Board4 (tag Leaderboard, attribute Board)  Hall
	  GuildBoard     Forgekeepers' notice board (tag GuildBoard)        here
	  FossilDig      dig site with a dinosaur skeleton (tag FossilDig)  Dig
	  RockScanner    Ore Codex terminal (tag OreCodex)                  Scanner

	Every piece is a Model named after its LobbyLayout piece id, built
	inside the piece's footprint and height budget. Pure builder:
	Instance creation only, deterministic from `rng`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Style)
local Kit = require(script.Kit)
local Stalls = require(script.Stalls)
local Fronts = require(script.Fronts)
local Wheel = require(script.Wheel)
local Capsules = require(script.Capsules)
local Enchant = require(script.Enchant)
local Hall = require(script.Hall)
local Dig = require(script.Dig)
local Scanner = require(script.Scanner)

local Districts = {}

-- Legacy TownLegacy pieces this package takes over (with their hooks).
Districts.Replaces = { "tradingPost", "toolSmithy", "emberChest", "guildBoard" }

local C = Kit.C

-- The Forgekeepers' notice board beside the forge porch (tag GuildBoard, PrimaryPart "Board").
local function guildBoard(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("GuildBoard")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	for _, x in { -3.9, 3.9 } do
		Style.block(m, at(x, 4.0, 0.2), Vector3.new(0.8, 8.0, 0.8), C.WoodDark)
	end
	local board = Style.block(m, at(0, 4.2, 0.1), Vector3.new(7.2, 3.6, 0.4), C.WoodLight, nil, Style.solid())
	board.Name = "Board"
	-- pinned notes (quests, story pages of the Kingdom of Kaldrum)
	local notes = {
		{ X = -2.4, Y = 4.7, Color = C.FlowerWhite },
		{ X = -0.6, Y = 3.6, Color = C.Sand },
		{ X = 1.2, Y = 4.9, Color = C.LeafYellowLight },
		{ X = 2.6, Y = 3.7, Color = C.FlowerWhite },
		{ X = -2.3, Y = 3.2, Color = C.Sand },
	}
	for i, n in notes do
		local x, y, color = n.X, n.Y, n.Color
		local note = at(x, y, -0.15) * CFrame.Angles(0, 0, rng:range(-0.12, 0.12))
		Kit.bit(m, note, Vector3.new(1.3, 1.5, 0.06), color)
		if i % 2 == 1 then
			Kit.bit(m, note * CFrame.new(0, 0.6, -0.05), Vector3.new(0.18, 0.18, 0.08), C.AwningRed)
		end
		Kit.bit(m, note * CFrame.new(0, -0.1, -0.04), Vector3.new(0.9, 0.12, 0.03), C.SignBoard)
	end
	Style.sign(m, at(0, 6.65, 0.05), "FORGEKEEPERS' GUILD", 7.8, 1.2, { Kind = "Wood", Depth = 0.4 })
	-- little red roof cap
	local roof = at(0, 7.85, 0.15)
	Geo.wedge(m, roof * CFrame.new(0, 0.45, -0.45), Vector3.new(9.0, 0.9, 0.9), C.Roof, Kit.SMOOTH, Style.decor())
	Geo.wedge(
		m,
		roof * CFrame.new(0, 0.45, 0.45) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(9.0, 0.9, 0.9),
		C.Roof,
		Kit.SMOOTH,
		Style.decor()
	)
	Kit.bit(m, roof * CFrame.new(0, 0.95, 0), Vector3.new(9.0, 0.3, 0.4), C.RoofTrim)
	Kit.bit(m, roof * CFrame.new(0, -0.05, 0), Vector3.new(9.0, 0.25, 1.9), C.RoofTrim)
	m.PrimaryPart = board
	Kit.tag(m, "GuildBoard")
end

function Districts.build(parent: Model, rng: Rng.Rng)
	Stalls.build(parent, rng)
	Fronts.build(parent, rng)
	Wheel.build(parent, rng)
	Capsules.build(parent, rng)
	Enchant.build(parent, rng)
	Hall.build(parent, rng)
	guildBoard(parent, rng)
	Dig.build(parent, rng)
	Scanner.build(parent, rng)
end

return Districts
