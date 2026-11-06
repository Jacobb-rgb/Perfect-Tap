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
	  HallOfFame     Board1..Board5 (tag Leaderboard, attribute Board)  Hall
	  GuildBoard     Forgekeepers' notice board (tag GuildBoard)        here
	  FossilDig      dig site with a dinosaur skeleton (tag FossilDig)  Dig
	  DroppersHouse  the DROPPERS shop house (tag DropperCounter)      Droppers
	  BackpackStall  the BACKPACKS shop (tag BackpackCounter)           Backpacks
	  (the ROCK SCANNER went 2026-10-24, owner: the Ore Codex opens from the side menu)

	Every piece is a Model named after its LobbyLayout piece id, built
	inside the piece's footprint and height budget. Pure builder:
	Instance creation only, deterministic from `rng`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Style)
local Kit = require(script.Kit)
local Tech = require(script.Tech)
local Stalls = require(script.Stalls)
local Fronts = require(script.Fronts)
local Wheel = require(script.Wheel)
local Capsules = require(script.Capsules)
local Enchant = require(script.Enchant)
local Backpacks = require(script.Backpacks)
local Hall = require(script.Hall)
local Dig = require(script.Dig)
local Droppers = require(script.Droppers)

local Districts = {}

-- Legacy TownLegacy pieces this package takes over (with their hooks).
Districts.Replaces = { "tradingPost", "toolSmithy", "emberChest", "guildBoard" }

local C = Kit.C

-- The Forgekeepers' notice board beside the forge porch (tag GuildBoard,
-- PrimaryPart "Board"), in the concept v2 metal and neon language: a cork
-- board in a gunmetal display-wall bezel with a blue neon edge between two
-- round pillars, under a glowing FORGEKEEPERS' GUILD sign box with orange
-- corner studs and a blue neon top edge.
local function guildBoard(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("GuildBoard")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	for _, x in { -3.85, 3.85 } do
		Tech.roundPillar(m, at(x, 0, 0.2), 8.4, 0.9, { Neon = false })
	end
	-- bezel (top, bottom, sides), back plate, the board and its neon edge
	local by, bw, bh = 4.2, 7.0, 3.6
	Style.block(m, at(0, by + bh / 2 + 0.3, 0.25), Vector3.new(bw + 1.0, 0.6, 0.9), Tech.Metal)
	Style.block(m, at(0, by - bh / 2 - 0.3, 0.25), Vector3.new(bw + 1.0, 0.6, 0.9), Tech.Metal)
	for _, x in { -1, 1 } do
		Style.block(m, at(x * (bw / 2 + 0.25), by, 0.25), Vector3.new(0.5, bh, 0.9), Tech.Metal)
	end
	Kit.bit(m, at(0, by - bh / 2 - 0.3, -0.21), Vector3.new(bw + 1.0, 0.25, 0.06), Tech.Band)
	local board = Style.block(m, at(0, by, 0.3), Vector3.new(bw, bh, 0.4), C.WoodLight, nil, Style.solid())
	board.Name = "Board"
	Tech.outline(m, at(0, by, 0.3), bw / 2 - 0.08, bh / 2 - 0.08, 0.35, 0.14, -0.22, Tech.Neon)
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
		local note = at(x, y, 0.05) * CFrame.Angles(0, 0, rng:range(-0.12, 0.12))
		Kit.bit(m, note, Vector3.new(1.3, 1.5, 0.06), color)
		if i % 2 == 1 then
			Kit.bit(m, note * CFrame.new(0, 0.6, -0.05), Vector3.new(0.18, 0.18, 0.08), C.AwningRed)
		end
		Kit.bit(m, note * CFrame.new(0, -0.1, -0.04), Vector3.new(0.9, 0.12, 0.03), C.SignBoard)
	end
	-- the glowing sign box on top: the words at 80% of the board width (not
	-- edge to edge), orange studs in the casing corners, a thick blue neon
	-- line along the casing's top edge (the module's roof line)
	-- (round 2: a plate 1.5x taller, the title on two lines: bigger letters)
	local title = "FORGEKEEPERS'\nGUILD"
	Tech.sign(m, at(0, 8.75, -0.1), title, 7.6, 2.4, {
		Back = true,
		Words = { { Text = title, Width = 7.6 * 0.86 } },
		StudColor = Tech.Warm,
		Margin = 0.4,
		Lip = 0.25,
	})
	Tech.channel(m, at(0, 10.75, -0.5), 8.8, Tech.EDGE)
	m.PrimaryPart = board
	Kit.tag(m, "GuildBoard")
end

function Districts.build(parent: Model, rng: Rng.Rng)
	Stalls.build(parent, rng)
	Fronts.build(parent, rng)
	Wheel.build(parent, rng)
	Capsules.build(parent, rng)
	Enchant.build(parent, rng)
	Backpacks.build(parent, rng)
	Hall.build(parent, rng)
	guildBoard(parent, rng)
	Dig.build(parent, rng)
	Droppers.build(parent, rng)
end

return Districts
