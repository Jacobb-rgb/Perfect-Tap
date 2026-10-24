--[[
	Live 3D pictures for the UI (the Shop's cards, the HUD's money): a model
	by picture name, shown in a ViewportFrame (Pop.model), so the pictures
	need no uploaded images. The same names are the preview pictures
	(tools/preview/icons: cash_*, capsule_*, golem_*, train, star_*).

	  cash_*            CashBuilder (bundle, pile, stack, sack, safe)
	  capsule_<Id>      GolemBuilder.capsule
	  golem_<Kind>      GolemBuilder.build
	  train             TrainBuilder.locomotive (the shop's Express Train pass)
	  board_<BoardId>   HoverboardBuilder.build
	  backpack_<Id>     BackpackBuilder.build for display (no shoulder straps), seen from behind
	  item_<Ore>        ItemBuilder.build: a pristine clean ore (luck, night, enchant cards)
	  blaster           BlasterBuilder.build (the Next Blaster card)
	  pass_crown        a gold crown with gems (the Forgemaster's Pass)
	  luck_server / clover   a four / three leaf clover (the luck cards)
	  podium            a podium with a gold ore on top

	`from` is the camera's direction for the picture (the models face -Z).
	Pure: only creates Instances (the previews run it too).
]]

local CashBuilder = require(script.Parent.CashBuilder)
local GolemBuilder = require(script.Parent.GolemBuilder)
local TrainBuilder = require(script.Parent.TrainBuilder)
local HoverboardBuilder = require(script.Parent.HoverboardBuilder)
local BackpackBuilder = require(script.Parent.BackpackBuilder)
local ItemBuilder = require(script.Parent.ItemBuilder)
local BlasterBuilder = require(script.Parent.BlasterBuilder)
local Geo = require(script.Parent.Geo)

local PictureModels = {}

local FRONT = Vector3.new(-0.55, 0.42, -1)

local rgb = Color3.fromRGB

local function decor(): { [string]: any }
	return { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
end

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- A gold crown: a ring, five spikes with balls on top, red and blue gems.
function PictureModels.crown(): Model
	local m = model("Crown")
	local gold = rgb(255, 196, 46)
	Geo.cylinder(m, Vector3.new(0, 0.6, 0), 1.2, 3.2, gold, Enum.Material.Metal, decor())
	Geo.cylinder(m, Vector3.new(0, 0.66, 0), 1.0, 2.7, rgb(150, 30, 50), nil, decor()) -- the velvet inside
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local at = Vector3.new(math.cos(a) * 1.45, 1.55, math.sin(a) * 1.45)
		Geo.block(m, CFrame.new(at) * CFrame.Angles(0, -a, 0), Vector3.new(0.35, 1.1, 0.7), gold, Enum.Material.Metal, decor())
		Geo.ball(m, at + Vector3.new(0, 0.7, 0), 0.5, gold, Enum.Material.Metal, decor())
		local gem = Vector3.new(math.cos(a + 0.63) * 1.62, 0.6, math.sin(a + 0.63) * 1.62)
		Geo.ball(m, gem, 0.42, if i % 2 == 0 then rgb(230, 40, 60) else rgb(60, 120, 255), Enum.Material.Glass, decor())
	end
	return m
end

-- A clover: `leaves` heart-ish leaves (two balls each) on a stem.
function PictureModels.clover(leaves: number, color: Color3): Model
	local m = model("Clover")
	for i = 0, leaves - 1 do
		local a = i / leaves * math.pi * 2 + math.pi / 4
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local side = Vector3.new(-dir.Y, dir.X, 0)
		Geo.ball(m, dir * 0.95 + side * 0.32, 1.1, color, nil, decor())
		Geo.ball(m, dir * 0.95 - side * 0.32, 1.1, color, nil, decor())
	end
	Geo.ball(m, Vector3.new(0, 0, -0.05), 0.55, color:Lerp(Color3.new(1, 1, 1), 0.3), nil, decor())
	Geo.block(
		m,
		CFrame.new(0.35, -1.55, 0) * CFrame.Angles(0, 0, math.rad(-14)),
		Vector3.new(0.22, 1.9, 0.22),
		color:Lerp(Color3.new(0, 0, 0), 0.3),
		nil,
		decor()
	)
	return m
end

-- A podium (a round base and plate) with a gold ore on top.
function PictureModels.podium(): Model
	local m = model("Podium")
	Geo.cylinder(m, Vector3.new(0, 0.4, 0), 0.8, 3.6, rgb(70, 76, 92), nil, decor())
	Geo.cylinder(m, Vector3.new(0, 0.9, 0), 0.25, 3.0, rgb(255, 196, 46), Enum.Material.Metal, decor())
	local ok, ore = pcall(ItemBuilder.build, { Kind = "Clean", OreId = "Gold", Grade = "Pristine" }, CFrame.new(0, 1.8, 0), "podium")
	if ok then
		for _, part in (ore :: Model):GetChildren() do
			part.Parent = m
		end
	end
	return m
end

-- The model for picture `name` and the camera direction (nil: no such model).
-- A red shopping cart (the Shop's header, the pixel reels' basket): a slatted basket, a frame, a handle, wheels.
function PictureModels.cart(): Model
	local m = model("Cart")
	local red = rgb(236, 48, 74)
	local deep = rgb(170, 24, 52)
	local steel = rgb(232, 236, 244)
	local dark = rgb(40, 42, 54)
	-- the basket: a floor, two sides, the front and back, slats across the long sides
	Geo.block(m, CFrame.new(0, 1.2, 0), Vector3.new(3.2, 0.2, 2), deep, nil, decor())
	for _, z in { -1, 1 } do
		Geo.block(m, CFrame.new(0, 2.05, z) * CFrame.Angles(math.rad(-8 * z), 0, 0), Vector3.new(3.4, 1.6, 0.16), red, nil, decor())
		for i = -3, 3 do
			Geo.block(
				m,
				CFrame.new(i * 0.45, 2.05, z * 1.06) * CFrame.Angles(math.rad(-8 * z), 0, 0),
				Vector3.new(0.12, 1.5, 0.06),
				deep,
				nil,
				decor()
			)
		end
		Geo.block(m, CFrame.new(0, 2.88, z * 1.12), Vector3.new(3.6, 0.18, 0.2), steel, Enum.Material.Metal, decor())
	end
	for _, x in { -1.65, 1.65 } do
		Geo.block(
			m,
			CFrame.new(x, 2.05, 0) * CFrame.Angles(0, 0, math.rad(if x < 0 then 10 else -10)),
			Vector3.new(0.16, 1.6, 2.2),
			red,
			nil,
			decor()
		)
	end
	-- the frame under it, the handle at the back, four wheels
	Geo.block(m, CFrame.new(0, 0.75, 0), Vector3.new(3, 0.14, 1.8), steel, Enum.Material.Metal, decor())
	for _, z in { -0.8, 0.8 } do
		Geo.block(m, CFrame.new(2.1, 2.6, z), Vector3.new(0.14, 1.2, 0.14), steel, Enum.Material.Metal, decor())
	end
	Geo.block(m, CFrame.new(2.1, 3.25, 0), Vector3.new(0.3, 0.3, 2), dark, nil, decor())
	for _, x in { -1.2, 1.2 } do
		for _, z in { -0.75, 0.75 } do
			Geo.ball(m, Vector3.new(x, 0.35, z), 0.62, dark, nil, decor())
		end
	end
	return m
end

function PictureModels.build(name: string): (Model?, Vector3)
	if string.sub(name, 1, 5) == "cash_" then
		return CashBuilder.picture(name), FRONT
	elseif string.sub(name, 1, 8) == "capsule_" then
		local ok, made = pcall(GolemBuilder.capsule, string.sub(name, 9))
		return if ok then made else nil, Vector3.new(-0.35, 0.3, -1)
	elseif string.sub(name, 1, 6) == "golem_" then
		local ok, made = pcall(GolemBuilder.build, string.sub(name, 7))
		return if ok then made else nil, Vector3.new(-0.3, 0.22, -1)
	elseif name == "train" then
		local ok, made = pcall(TrainBuilder.locomotive, Color3.fromRGB(226, 72, 60))
		return if ok then made else nil, Vector3.new(-1, 0.35, -0.55)
	elseif string.sub(name, 1, 6) == "board_" then
		local ok, made = pcall(HoverboardBuilder.build, string.sub(name, 7))
		return if ok then made else nil, Vector3.new(-1, 0.75, -0.7)
	elseif string.sub(name, 1, 9) == "backpack_" then
		local ok, made = pcall(BackpackBuilder.build, string.sub(name, 10), true)
		-- (the packs face +Z: the side the wearer's camera sees)
		return if ok then made else nil, Vector3.new(0.5, 0.35, 1)
	elseif string.sub(name, 1, 5) == "item_" then
		local ok, made = pcall(ItemBuilder.build, { Kind = "Clean", OreId = string.sub(name, 6), Grade = "Pristine" }, CFrame.new(), name)
		return if ok then made else nil, Vector3.new(-0.5, 0.5, -1)
	elseif name == "blaster" then
		local ok, tool = pcall(BlasterBuilder.build, 5)
		if not ok then
			return nil, FRONT
		end
		-- (a Tool: its parts move into a Model for the ViewportFrame)
		local made = model("Blaster")
		for _, child in (tool :: Instance):GetChildren() do
			child.Parent = made
		end
		return made, Vector3.new(-1, 0.3, 0.18)
	elseif name == "pass_crown" then
		return PictureModels.crown(), Vector3.new(-0.3, 0.75, -1)
	elseif name == "luck_server" then
		return PictureModels.clover(4, rgb(90, 220, 80)), Vector3.new(0, 0.1, -1)
	elseif name == "clover" then
		return PictureModels.clover(3, rgb(120, 236, 110)), Vector3.new(0, 0.1, -1)
	elseif name == "podium" then
		return PictureModels.podium(), Vector3.new(-0.4, 0.55, -1)
	elseif name == "cart" then
		return PictureModels.cart(), Vector3.new(-0.7, 0.45, -1)
	end
	return nil, FRONT
end

return PictureModels
