--[[
	BACKPACKS: the backpack shop's stall (owner 2026-10-24: "Nový stánek v
	lobby", coins only) on the lawn north of the SHOP, beside the gear shop
	that sold the old Ore Backpack. A lean kiosk in the concept v2 metal and
	neon language, its neon teal like the shop window's header band:
	  - a gunmetal deck with a teal front edge over the orange band
	  - a back wall with a teal line and, in its middle, a raised display shelf
	  - two front posts with teal slots, a canopy with a teal front edge
	  - the BACKPACKS neon sign box on the canopy
	  - the counter in front: its warm top is the BasePart tagged
	    BackpackCounter, with an Attachment BackpackPromptPoint on the
	    customer side (BackpackService puts the "Backpacks" prompt there)
	  - two round plinths either side of the counter, a square plate on each
	The three display packs are NOT map parts: the shelf and the plinth plates
	carry the attribute BackpackId (the best three packs; no tag: Plaza Life
	keeps its miners off tagged parts as prompt spots) and every client finds
	them through the counter and builds those packs standing on them while it
	is near (BackpackWearController), so the stall costs the map ~27 parts.
	Local frame: 10 wide, 11 tall, 8 deep, front = -Z (toward the plaza);
	every part stays inside it (tests/LobbyDistricts.spec.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Tech = require(script.Parent.Tech)

local Backpacks = {}

Backpacks.CounterTag = "BackpackCounter"
Backpacks.PromptPoint = "BackpackPromptPoint"
Backpacks.DisplayAttribute = "BackpackId" -- (BackpackWearController: the stall's display markers)
-- what stands where: the shelf in the middle of the back wall, the plinths left and right
Backpacks.Displays = {
	Shelf = "StarforgePack",
	Left = "RuneboundPack",
	Right = "EmberforgePack",
}

local rgb = Color3.fromRGB
local TEAL = rgb(16, 176, 168) -- deep enough to stay teal under bloom
local WOOD = rgb(176, 120, 72)

local FLOOR = 0.5

local function display(part: BasePart, packId: string)
	part:SetAttribute(Backpacks.DisplayAttribute, packId)
end

function Backpacks.build(parent: Instance, rng: Rng.Rng)
	local piece, cf = Kit.piece("BackpackStall")
	local m = Style.model(piece.Id, parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- the deck: a teal front edge over the orange band
	Style.block(m, at(0, FLOOR / 2, 0), Vector3.new(9.8, FLOOR, 7.8), Style.vary(Tech.MetalDark, rng, 0.03), nil, Style.solid())
	Tech.glow(m, at(0, FLOOR - 0.12, -3.86), Vector3.new(9.4, 0.16, 0.12), TEAL)
	Kit.bit(m, at(0, 0.12, -3.87), Vector3.new(9.8, 0.2, 0.1), Tech.Band)

	-- the back wall with a teal line and the raised display shelf
	Style.block(m, at(0, FLOOR + 3.4, 3.5), Vector3.new(9.8, 6.8, 0.6), Tech.Metal, nil, Style.solid())
	Tech.glow(m, at(0, 6.9, 3.18), Vector3.new(9.4, 0.16, 0.1), TEAL)
	local shelf = Style.block(m, at(0, 3.6, 2.8), Vector3.new(3.2, 0.4, 1.6), Tech.MetalLight, nil, Style.decor())
	shelf.Name = "DisplayShelf"
	display(shelf, Backpacks.Displays.Shelf)
	Tech.glow(m, at(0, 3.6, 1.98), Vector3.new(3.2, 0.12, 0.1), TEAL)

	-- two front posts with teal slots, the canopy with a teal front edge
	for _, s in { -1, 1 } do
		Style.block(m, at(s * 4.5, FLOOR + 3.9, -3.35), Vector3.new(0.8, 7.8, 0.8), Tech.Metal, nil, Style.solid())
		Tech.glow(m, at(s * 4.5, 4.5, -3.77), Vector3.new(0.18, 5.0, 0.06), TEAL)
	end
	Style.block(m, at(0, 8.55, 0), Vector3.new(9.8, 0.5, 7.8), Tech.MetalDark, nil, Style.decor())
	Tech.glow(m, at(0, 8.55, -3.85), Vector3.new(9.8, 0.2, 0.12), TEAL)

	-- the BACKPACKS sign box on the canopy (its neon frame stays inside the footprint's front)
	Kit.neonSign(m, at(0, 9.9, -3.45), "BACKPACKS", 8.6, 2.0, Tech.Board, TEAL, { Depth = 0.5 })

	-- the counter: a light gunmetal body with a teal stripe, the warm top (the hook)
	Style.block(m, at(0, FLOOR + 1.4, -2.2), Vector3.new(6.0, 2.8, 1.4), Tech.MetalLight, nil, Style.solid())
	Tech.glow(m, at(0, 1.9, -2.92), Vector3.new(5.6, 0.16, 0.08), TEAL)
	local counter = Style.block(m, at(0, FLOOR + 2.95, -2.2), Vector3.new(6.4, 0.3, 1.7), WOOD, nil, Style.solid())
	counter.Name = Backpacks.CounterTag
	Kit.tag(counter, Backpacks.CounterTag)
	local point = Instance.new("Attachment")
	point.Name = Backpacks.PromptPoint
	point.CFrame = CFrame.new(0, 0.15, -0.85) -- the customer side of the top
	point.Parent = counter

	-- two round plinths either side of the counter, their tops hold display packs
	for _, spec in { { Side = -1, Pack = Backpacks.Displays.Left }, { Side = 1, Pack = Backpacks.Displays.Right } } do
		local s, packId = spec.Side, spec.Pack
		local base = at(s * 3.6, 0, -2.6)
		Kit.disc(m, (base * CFrame.new(0, FLOOR + 0.6, 0)).Position, 1.2, 1.9, Tech.Metal, nil, Style.solid())
		Kit.disc(m, (base * CFrame.new(0, FLOOR + 1.12, 0)).Position, 0.1, 2.0, TEAL, Kit.NEON, Style.tiny())
		-- a square plate on the round plinth: the marker (a block: its front is the stall's)
		local top = Style.block(m, base * CFrame.new(0, FLOOR + 1.27, 0), Vector3.new(1.6, 0.14, 1.6), Tech.MetalLight, nil, Style.decor())
		top.Name = "DisplayPlinth"
		display(top, packId)
	end
	m.PrimaryPart = counter
end

return Backpacks
