--[[
	The blaster crate (owner 2026-11-06: his "futuristic mining crates" script
	and the void crate picture): a black armoured box with a metal lid, corner
	posts, neon strips and a glowing diamond core on its front, in the colour of
	its rarity (Tiers, his four colours): the crate the Blaster Vault sells and
	the one the crate-opening cinematic bursts open.

	Built at the origin: bottom center, the long side along Z, the front (the
	core) facing +X. Models, so the cinematic can take it apart:
	  Base    bottom armour, floor, corner posts with their caps and strips, the
	          glowing inside ("Inside") and the glowing seam ("Seam")
	  Panels  the four walls, each hinged at the floor (Hinge, Fold: they fold
	          outward when the crate opens)
	  Lid     two halves (LidA at -Z, LidB at +Z) that fly apart; from level 4
	          the lid's corners glow, from level 7 a diamond on top
	Sizes scale with `size` (1 = a 7 stud long crate). About 60-75 parts.
	Pure: only Instance creation (Lune previews and the client both build it).
]]

local Geo = require(script.Parent.Geo)
local OreData = require(script.Parent.Parent.Config.OreData)

local CaseBuilder = {}

export type Panel = {
	Model: Model,
	Hinge: CFrame, -- the hinge's middle, in the crate's frame
	Fold: Vector3, -- CFrame.Angles(Fold.X * a, 0, Fold.Z * a) folds it outward by a
}

export type Case = {
	Base: Model,
	Lid: Model,
	LidA: Model,
	LidB: Model,
	Panels: { Panel },
	Seam: BasePart,
	Inside: BasePart,
	Core: BasePart, -- the diamond core on the front
	Lights: { BasePart }, -- the neon strips (they pulse in the cinematic)
	Height: number, -- the closed crate's height
	BaseHeight: number,
	Width: number,
	Length: number,
	Glow: Color3,
	Body: Color3,
}

local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic

local BLACK = Color3.fromRGB(30, 28, 42)
local PLATE = Color3.fromRGB(72, 68, 92)
local STEEL = Color3.fromRGB(108, 104, 130)
local WHITE = Color3.new(1, 1, 1)

local TINY = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

-- The hot ores (the guns' Magma skin in KenneyBlaster; the crates have one look).
CaseBuilder.HotOres = {
	[""] = true,
	Coal = true,
	Copper = true,
	Emberite = true,
	Gold = true,
	RoyalAurum = true,
	Bronze = true,
	Sunstone = true,
	VolcanicCore = true,
	PhoenixFeather = true,
}

-- The owner's four crates: { Name, Color (his main colour), Glow }.
CaseBuilder.Tiers = {
	Common = { Name = "COMMON", Color = Color3.fromRGB(220, 230, 240), Glow = Color3.fromRGB(180, 200, 220) },
	Rare = { Name = "RARE", Color = Color3.fromRGB(0, 140, 255), Glow = Color3.fromRGB(0, 190, 255) },
	Epic = { Name = "EPIC", Color = Color3.fromRGB(155, 40, 255), Glow = Color3.fromRGB(210, 50, 255) },
	Mythic = { Name = "MYTHIC", Color = Color3.fromRGB(255, 0, 200), Glow = Color3.fromRGB(255, 50, 230) },
}

-- The game's six rarities in his four crates.
CaseBuilder.TierOfRarity = {
	Common = "Common",
	Uncommon = "Rare",
	Rare = "Rare",
	Epic = "Epic",
	Legendary = "Mythic",
	Mythic = "Mythic",
	Secret = "Mythic",
}

-- The crate tier of an ore (its rarity; "" and unknown ores are Common).
function CaseBuilder.tier(oreId: string?): { Name: string, Color: Color3, Glow: Color3 }
	local ore = OreData.ById[oreId or ""]
	local id = if ore then CaseBuilder.TierOfRarity[ore.Rarity] else nil
	return CaseBuilder.Tiers[id or "Common"]
end

-- The look of a crate: (body, plate, glow, hot). (hot: always false, the lava look went with the old cases.)
function CaseBuilder.look(oreId: string?): (Color3, Color3, Color3, boolean)
	return BLACK, PLATE, CaseBuilder.tier(oreId).Glow, false
end

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return Geo.block(parent, cf, size, color, material or SMOOTH, table.clone(TINY))
end

--[[
	Builds a crate for blaster `level` in the look of `oreId` ("" = Common),
	`size` x a 7 stud long crate, at `cf` (its bottom center). Returns Case.
]]
function CaseBuilder.build(parent: Instance, cf: CFrame, level: number, oreId: string?, size: number?): Case
	local s = size or 1
	local L, W = 7 * s, 5 * s
	local foot = 0.3 * s -- the bottom armour
	local bodyTop = foot + 2.5 * s
	local lidH = 0.8 * s
	local _, _, glowColor = CaseBuilder.look(oreId)
	local hot = WHITE:Lerp(glowColor, 0.45)
	local lights: { BasePart } = {}
	local function model(name: string, into: Instance): Model
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = into
		return m
	end
	local base = model("Base", parent)
	local lid = model("Lid", parent)
	local lidA = model("LidA", lid)
	local lidB = model("LidB", lid)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function strip(into: Instance, c: CFrame, sz: Vector3): Part
		local p = block(into, c, sz, glowColor, NEON)
		table.insert(lights, p)
		return p
	end

	-- the base: armour, floor, the inside's glow and the seam
	block(base, at(0, foot / 2, 0), Vector3.new(W + 0.3 * s, foot, L + 0.3 * s), PLATE, METAL)
	block(base, at(0, foot + 0.05 * s, 0), Vector3.new(W - 0.2 * s, 0.1 * s, L - 0.2 * s), BLACK)
	local inside = block(base, at(0, foot + 0.95 * s, 0), Vector3.new(W - 0.9 * s, 0.06 * s, L - 0.9 * s), hot, NEON)
	inside.Name = "Inside"
	local seam = block(base, at(0, bodyTop + 0.02 * s, 0), Vector3.new(W + 0.06 * s, 0.08 * s, L + 0.06 * s), glowColor, NEON)
	seam.Name = "Seam"
	-- the corner posts with their caps and a strip on the long sides
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - 0.1 * s), sz * (L / 2 - 0.1 * s)
			block(base, at(x, foot + 1.25 * s, z), Vector3.new(0.62 * s, 2.5 * s, 0.62 * s), PLATE, METAL)
			block(base, at(x, foot + 0.22 * s, z), Vector3.new(0.84 * s, 0.5 * s, 0.84 * s), STEEL, METAL)
			block(base, at(x, bodyTop - 0.2 * s, z), Vector3.new(0.84 * s, 0.4 * s, 0.84 * s), STEEL, METAL)
			strip(base, at(sx * (W / 2 + 0.22 * s), foot + 1.25 * s, z), Vector3.new(0.1 * s, 1.5 * s, 0.2 * s))
		end
	end

	-- the walls: each its own model, hinged at the floor
	local panels: { Panel } = {}
	local function panel(name: string, hinge: CFrame, fold: Vector3): Model
		local m = model(name, parent)
		table.insert(panels, { Model = m, Hinge = hinge, Fold = fold })
		return m
	end
	local T = 0.24 * s
	local mid = foot + 1.25 * s
	local height = 2.3 * s
	local front = panel("Front", CFrame.new(W / 2 - T / 2, foot, 0), Vector3.new(0, 0, -1))
	block(front, at(W / 2 - T / 2, mid, 0), Vector3.new(T, height, L - 1.2 * s), BLACK)
	-- the frame and the core: a metal diamond, the neon diamond, its white-hot middle
	local face = at(W / 2 + 0.02 * s, mid, 0) * CFrame.Angles(math.pi / 4, 0, 0)
	block(front, face, Vector3.new(0.14 * s, 1.75 * s, 1.75 * s), STEEL, METAL)
	local core = block(front, face * CFrame.new(0.08 * s, 0, 0), Vector3.new(0.1 * s, 1.25 * s, 1.25 * s), glowColor, NEON)
	core.Name = "EnergyCore"
	block(front, face * CFrame.new(0.14 * s, 0, 0), Vector3.new(0.06 * s, 0.6 * s, 0.6 * s), WHITE:Lerp(glowColor, 0.15), NEON)
	for _, sz in { -1, 1 } do
		block(front, at(W / 2 + 0.03 * s, mid, sz * 1.42 * s), Vector3.new(0.16 * s, 1.7 * s, 0.16 * s), PLATE, METAL)
		strip(front, at(W / 2 + 0.03 * s, mid, sz * 2.2 * s), Vector3.new(0.1 * s, 0.14 * s, 0.9 * s))
	end
	local back = panel("Back", CFrame.new(-W / 2 + T / 2, foot, 0), Vector3.new(0, 0, 1))
	block(back, at(-W / 2 + T / 2, mid, 0), Vector3.new(T, height, L - 1.2 * s), BLACK)
	strip(back, at(-W / 2 - 0.03 * s, mid, 0), Vector3.new(0.1 * s, 0.14 * s, L * 0.6))
	local sideA = panel("EndA", CFrame.new(0, foot, -L / 2 + T / 2), Vector3.new(-1, 0, 0))
	block(sideA, at(0, mid, -L / 2 + T / 2), Vector3.new(W - 1.2 * s, height, T), BLACK)
	strip(sideA, at(0, mid, -L / 2 - 0.03 * s), Vector3.new(W * 0.5, 0.14 * s, 0.1 * s))
	local sideB = panel("EndB", CFrame.new(0, foot, L / 2 - T / 2), Vector3.new(1, 0, 0))
	block(sideB, at(0, mid, L / 2 - T / 2), Vector3.new(W - 1.2 * s, height, T), BLACK)
	strip(sideB, at(0, mid, L / 2 + 0.03 * s), Vector3.new(W * 0.5, 0.14 * s, 0.1 * s))

	-- the lid: two halves, each with its plate, top panel, strips and corner caps
	local y0 = bodyTop + 0.06 * s
	local halfL = (L + 0.3 * s) / 2
	for i, half in { lidA, lidB } do
		local sz = if i == 1 then -1 else 1
		local zc = sz * halfL / 2
		block(half, at(0, y0 + lidH / 2, zc), Vector3.new(W + 0.3 * s, lidH, halfL - 0.02 * s), PLATE, METAL)
		block(half, at(0, y0 + lidH + 0.07 * s, zc - sz * 0.15 * s), Vector3.new(W - 1.3 * s, 0.14 * s, halfL - 1 * s), BLACK)
		for _, sx in { -1, 1 } do
			strip(
				half,
				at(sx * (W / 2 - 0.25 * s), y0 + lidH + 0.05 * s, zc - sz * 0.1 * s),
				Vector3.new(0.12 * s, 0.12 * s, halfL - 1.3 * s)
			)
			block(
				half,
				at(sx * (W / 2 - 0.1 * s), y0 + lidH / 2, sz * (L / 2 - 0.1 * s)),
				Vector3.new(0.86 * s, lidH + 0.1 * s, 0.86 * s),
				STEEL,
				METAL
			)
			if level >= 4 then
				strip(
					half,
					at(sx * (W / 2 - 0.1 * s), y0 + lidH + 0.08 * s, sz * (L / 2 - 0.1 * s)),
					Vector3.new(0.9 * s, 0.06 * s, 0.9 * s)
				)
			end
		end
		strip(half, at(W / 2 + 0.18 * s, y0 + lidH / 2, zc - sz * 0.1 * s), Vector3.new(0.08 * s, 0.14 * s, halfL - 1.3 * s))
		if level >= 7 then
			-- half of the diamond on top
			for _, sx in { -1, 1 } do
				local c = at(0, y0 + lidH + 0.16 * s, sz * 0.42 * s) * CFrame.Angles(0, sx * sz * math.pi / 4, 0)
				strip(half, c * CFrame.new(sx * 0.3 * s, 0, 0), Vector3.new(0.72 * s, 0.05 * s, 0.1 * s))
			end
		end
	end
	return {
		Base = base,
		Lid = lid,
		LidA = lidA,
		LidB = lidB,
		Panels = panels,
		Seam = seam,
		Inside = inside,
		Core = core,
		Lights = lights,
		Height = y0 + lidH + 0.2 * s,
		BaseHeight = bodyTop,
		Width = W,
		Length = L,
		Glow = glowColor,
		Body = BLACK,
	}
end

return CaseBuilder
