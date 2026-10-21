--[[
	3D banknotes for the UI (owner 2026-10-20: "the banknotes, then the
	amount", his egg-game photo): small part models shown in ViewportFrames,
	so they need no uploaded pictures.

	  bundle(cf)  one bundle: a stack of green notes, a lighter top note with a
	              dark-green oval, a gold paper band round the middle
	  pile()      the HUD's money: two bundles side by side, one on top, turned
	  stack(n)    n bundles in a little pyramid (the coin packs)
	  sack()      a cloth money sack, tied, notes sticking out
	  safe()      an open steel safe full of bundles (the biggest pack)

	Pure: only creates Instances (the previews run it too).
]]

local Geo = require(script.Parent.Geo)

local CashBuilder = {}

local rgb = Color3.fromRGB

CashBuilder.Note = rgb(98, 196, 74)
CashBuilder.NoteDark = rgb(52, 140, 50)
CashBuilder.NoteLight = rgb(160, 232, 120)
CashBuilder.Band = rgb(255, 204, 56)
CashBuilder.Size = Vector3.new(2.6, 0.62, 1.25) -- one bundle

local function decor(): { [string]: any }
	return { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
end

-- One bundle at `cf` (its center) in `parent`.
function CashBuilder.bundle(parent: Instance, cf: CFrame)
	local s = CashBuilder.Size
	Geo.block(parent, cf, s, CashBuilder.Note, nil, decor())
	-- the paper edges: a lighter line along each long side
	Geo.block(parent, cf * CFrame.new(0, 0.05, s.Z / 2), Vector3.new(s.X - 0.08, s.Y * 0.36, 0.04), CashBuilder.NoteLight, nil, decor())
	Geo.block(parent, cf * CFrame.new(0, 0.05, -s.Z / 2), Vector3.new(s.X - 0.08, s.Y * 0.36, 0.04), CashBuilder.NoteLight, nil, decor())
	-- the top note's oval (a flat dark-green disc)
	local oval = Geo.make("Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = cf * CFrame.new(-0.62, s.Y / 2 + 0.01, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Size = Vector3.new(0.04, 0.62, 0.62),
		Color = CashBuilder.NoteDark,
		Material = Enum.Material.SmoothPlastic,
	}, parent)
	for key, value in decor() do
		(oval :: any)[key] = value
	end
	-- the gold band round the middle
	Geo.block(parent, cf * CFrame.new(0.3, 0, 0), Vector3.new(0.5, s.Y + 0.06, s.Z + 0.06), CashBuilder.Band, nil, decor())
end

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- The HUD's money: two bundles side by side and one on top, turned a little.
function CashBuilder.pile(): Model
	local m = model("CashPile")
	local h = CashBuilder.Size.Y
	CashBuilder.bundle(m, CFrame.new(0, 0, -0.66) * CFrame.Angles(0, math.rad(4), 0))
	CashBuilder.bundle(m, CFrame.new(0.1, 0, 0.66) * CFrame.Angles(0, math.rad(-3), 0))
	CashBuilder.bundle(m, CFrame.new(0.05, h, 0.05) * CFrame.Angles(0, math.rad(24), 0))
	return m
end

-- `count` bundles in a pyramid (rows of 3, 2, 1...), turned this way and that.
function CashBuilder.stack(count: number): Model
	local m = model("CashStack")
	local h = CashBuilder.Size.Y
	local placed = 0
	local level = 0
	local perRow = if count >= 6 then 3 elseif count >= 3 then 2 else 1
	while placed < count do
		local inRow = math.min(perRow, count - placed)
		for i = 1, inRow do
			local z = (i - (inRow + 1) / 2) * 1.32
			local turn = math.rad(((placed * 37) % 17) - 8)
			CashBuilder.bundle(m, CFrame.new(0, level * h, z) * CFrame.Angles(0, turn, 0))
			placed += 1
		end
		level += 1
		perRow = math.max(1, perRow - 1)
	end
	return m
end

-- A tied cloth money sack with notes sticking out of the top.
function CashBuilder.sack(): Model
	local m = model("CashSack")
	local cloth = rgb(222, 196, 140)
	local body = Geo.ball(m, Vector3.new(0, 1.5, 0), 3, cloth, Enum.Material.Fabric, decor())
	body.Name = "Sack"
	Geo.cylinder(m, Vector3.new(0, 3.05, 0), 0.5, 1.2, cloth:Lerp(rgb(0, 0, 0), 0.08), Enum.Material.Fabric, decor())
	Geo.cylinder(m, Vector3.new(0, 3.0, 0), 0.22, 1.3, rgb(176, 110, 54), nil, decor()) -- the rope
	-- the dollar mark: a dark-green disc on the front
	local mark = Geo.make("Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(0, 1.55, -1.45) * CFrame.Angles(0, math.pi / 2, 0),
		Size = Vector3.new(0.08, 1.2, 1.2),
		Color = CashBuilder.NoteDark,
		Material = Enum.Material.SmoothPlastic,
	}, m)
	for key, value in decor() do
		(mark :: any)[key] = value
	end
	-- notes standing up out of the neck, fanned
	CashBuilder.bundle(m, CFrame.new(-0.35, 3.75, 0.1) * CFrame.Angles(0, math.rad(90), math.rad(72)))
	CashBuilder.bundle(m, CFrame.new(0.4, 3.7, -0.1) * CFrame.Angles(0, math.rad(90), math.rad(108)))
	-- bundles at its feet
	CashBuilder.bundle(m, CFrame.new(1.6, 0.31, -0.9) * CFrame.Angles(0, math.rad(30), 0))
	CashBuilder.bundle(m, CFrame.new(-1.5, 0.31, -1.0) * CFrame.Angles(0, math.rad(-20), 0))
	return m
end

-- An open steel safe full of bundles, more stacked in front.
function CashBuilder.safe(): Model
	local m = model("CashSafe")
	local steel = rgb(70, 76, 90)
	local dark = rgb(40, 44, 54)
	local gold = rgb(255, 200, 60)
	-- the box: back, sides, top, floor (open at the front)
	Geo.block(m, CFrame.new(0, 2, 1.6), Vector3.new(3.6, 4, 0.3), steel, Enum.Material.Metal, decor())
	Geo.block(m, CFrame.new(-1.75, 2, 0), Vector3.new(0.3, 4, 3.5), steel, Enum.Material.Metal, decor())
	Geo.block(m, CFrame.new(1.75, 2, 0), Vector3.new(0.3, 4, 3.5), steel, Enum.Material.Metal, decor())
	Geo.block(m, CFrame.new(0, 3.95, 0), Vector3.new(3.8, 0.3, 3.5), steel, Enum.Material.Metal, decor())
	Geo.block(m, CFrame.new(0, 0.1, 0), Vector3.new(3.8, 0.3, 3.5), dark, Enum.Material.Metal, decor())
	Geo.block(m, CFrame.new(0, 2, 0.05), Vector3.new(3.2, 0.16, 3.1), dark, Enum.Material.Metal, decor()) -- the shelf
	-- the door swung open to the left, with its gold dial
	local door = CFrame.new(-2.9, 2, -2.2) * CFrame.Angles(0, math.rad(-62), 0)
	Geo.block(m, door, Vector3.new(3.6, 4, 0.36), steel:Lerp(rgb(255, 255, 255), 0.08), Enum.Material.Metal, decor())
	local dial = Geo.make("Part", {
		Shape = Enum.PartType.Cylinder,
		CFrame = door * CFrame.new(0, 0.3, -0.26) * CFrame.Angles(0, math.pi / 2, 0),
		Size = Vector3.new(0.2, 1.3, 1.3),
		Color = gold,
		Material = Enum.Material.Metal,
	}, m)
	for key, value in decor() do
		(dial :: any)[key] = value
	end
	-- bundles inside (two shelves) and in front
	for shelf = 0, 1 do
		for i = -1, 1 do
			CashBuilder.bundle(m, CFrame.new(i * 1.02, 0.6 + shelf * 1.9, 0.4) * CFrame.Angles(0, math.rad(90), 0))
		end
	end
	CashBuilder.bundle(m, CFrame.new(0.4, 0.31, -2.4) * CFrame.Angles(0, math.rad(14), 0))
	CashBuilder.bundle(m, CFrame.new(1.9, 0.31, -2.0) * CFrame.Angles(0, math.rad(-30), 0))
	CashBuilder.bundle(m, CFrame.new(1.1, 0.93, -2.2) * CFrame.Angles(0, math.rad(5), 0))
	return m
end

-- The model for a picture name (the shop's coin packs, the HUD).
CashBuilder.Pictures = {
	cash_bundle = function(): Model
		return CashBuilder.stack(1)
	end,
	cash_pile = CashBuilder.pile,
	cash_stack = function(): Model
		return CashBuilder.stack(6)
	end,
	cash_sack = CashBuilder.sack,
	cash_safe = CashBuilder.safe,
} :: { [string]: () -> Model }

function CashBuilder.picture(name: string): Model?
	local make = CashBuilder.Pictures[name]
	return if make then make() else nil
end

return CashBuilder
