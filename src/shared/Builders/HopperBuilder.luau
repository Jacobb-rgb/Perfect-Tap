--[[
	The hoppers (Config/HopperConfig) in the block-tycoon look (owner
	2026-10-21, after Sandbox Tycoon; BlockKit): a framed block bin full of ores
	on four block legs, a stepped block funnel under it and a spout that drops
	ores onto the conveyor running between the legs. Each hopper is made of
	its own "material" with bright pixels in the corners and a pixel-art crest
	on top:

	  EpicHopper       iron: navy blocks, purple pixels, bolts
	  LegendaryHopper  gold blocks, orange pixels, a block crown
	  MythicHopper     ruby: dark red blocks, block crystals on the corners
	  HeartHopper      rose quartz: pink blocks, a pixel heart over it
	  StarHopper       diamond: white + ice-blue blocks, a pixel star
	  RiftHopper       obsidian: black blocks, rainbow pixels, floating cubes
	  TerraCoreHopper  gold + lava: a lava core cube in a gold cage, magma pixels

	build(id, cf) -> Model (anchored; origin = the middle of the base's bottom;
	the conveyor runs along +X, the name sign faces +Z toward the player).
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)
local ItemBuilder = require(script.Parent.ItemBuilder)
local HopperConfig = require(Shared.Config.HopperConfig)
local OreData = require(Shared.Config.OreData)

local HopperBuilder = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass

export type Style = {
	Scale: number,
	Face: Color3, -- block faces
	Rim: Color3, -- block rims
	Dark: Color3, -- legs and base
	DarkRim: Color3,
	Pixel: { Color3 }, -- the bright corner pixels (take turns)
	Trim: { Color3 }, -- kept for the shop / previews: the hopper's main glow
	Deco: string,
}

HopperBuilder.Styles = {
	EpicHopper = {
		Scale = 1,
		Face = rgb(58, 66, 104),
		Rim = rgb(34, 38, 64),
		Dark = rgb(46, 50, 70),
		DarkRim = rgb(26, 28, 42),
		Pixel = { rgb(176, 110, 255) },
		Trim = { rgb(180, 92, 255) },
		Deco = "bolts",
	},
	LegendaryHopper = {
		Scale = 1.08,
		Face = rgb(250, 196, 64),
		Rim = rgb(196, 128, 26),
		Dark = rgb(96, 64, 36),
		DarkRim = rgb(62, 40, 22),
		Pixel = { rgb(255, 250, 200) },
		Trim = { rgb(255, 176, 32) },
		Deco = "crown",
	},
	MythicHopper = {
		Scale = 1.16,
		Face = rgb(186, 32, 62),
		Rim = rgb(110, 14, 36),
		Dark = rgb(52, 36, 44),
		DarkRim = rgb(30, 18, 24),
		Pixel = { rgb(255, 130, 170) },
		Trim = { rgb(255, 59, 122) },
		Deco = "crystals",
	},
	HeartHopper = {
		Scale = 1.24,
		Face = rgb(248, 156, 196),
		Rim = rgb(214, 92, 146),
		Dark = rgb(120, 56, 86),
		DarkRim = rgb(78, 30, 54),
		Pixel = { rgb(255, 240, 248) },
		Trim = { rgb(255, 120, 180) },
		Deco = "heart",
	},
	StarHopper = {
		Scale = 1.34,
		Face = rgb(226, 246, 255),
		Rim = rgb(110, 206, 240),
		Dark = rgb(70, 120, 160),
		DarkRim = rgb(40, 74, 108),
		Pixel = { rgb(90, 220, 255), rgb(255, 214, 80) },
		Trim = { rgb(120, 220, 255) },
		Deco = "star",
	},
	RiftHopper = {
		Scale = 1.44,
		Face = rgb(40, 30, 64),
		Rim = rgb(18, 12, 30),
		Dark = rgb(30, 24, 46),
		DarkRim = rgb(12, 8, 20),
		Pixel = { rgb(255, 96, 96), rgb(255, 196, 64), rgb(120, 230, 90), rgb(70, 190, 255), rgb(190, 110, 255) },
		Trim = { rgb(190, 110, 255) },
		Deco = "rift",
	},
	TerraCoreHopper = {
		Scale = 1.56,
		Face = rgb(255, 202, 70),
		Rim = rgb(176, 104, 20),
		Dark = rgb(64, 40, 34),
		DarkRim = rgb(36, 20, 18),
		Pixel = { rgb(255, 110, 30), rgb(255, 236, 140) },
		Trim = { rgb(255, 150, 30) },
		Deco = "core",
	},
} :: { [string]: Style }

-- Sizes at Scale 1 (studs).
HopperBuilder.Plate = 7.2 -- the base's side
HopperBuilder.LegHeight = 5.0
HopperBuilder.Bin = 6.4 -- the bin's side
HopperBuilder.BinHeight = 2.4

-- How tall a hopper is (studs, without its crest).
function HopperBuilder.height(id: string): number
	local s = HopperBuilder.Styles[id].Scale
	return (0.6 + HopperBuilder.LegHeight + 1.0 + HopperBuilder.BinHeight) * s
end

local function decor(): { [string]: any }
	return { CanTouch = false, CanQuery = false, CastShadow = false }
end

local function pixel(style: Style, i: number): Color3
	return style.Pixel[(i - 1) % #style.Pixel + 1]
end

local function ore(parent: Instance, id: string, grade: string, cf: CFrame, seed: number, full: boolean?)
	local info = { Kind = "Clean", OreId = id, Grade = grade }
	local model = if full then ItemBuilder.build(info, cf, seed) else ItemBuilder.buildLight(info, cf, seed)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model.Parent = parent
	return model
end

-- pixel art crests (a "#" is the main colour, "o" the light one, "x" the dark one)
local HEART = {
	".##...##.",
	"#oo#.####",
	"#o#######",
	"#########",
	".#######.",
	"..#####..",
	"...###...",
	"....#....",
}
local STAR = {
	"....#....",
	"...#o#...",
	"...#o#...",
	"#########",
	".##ooo##.",
	"..#ooo#..",
	".##.#.##.",
	"##.....##",
}

function HopperBuilder.build(id: string, cf: CFrame): Model
	local hopper = HopperConfig.ById[id]
	local style = HopperBuilder.Styles[id]
	assert(hopper and style, "Unknown hopper " .. tostring(id))
	local s = style.Scale
	local model = Instance.new("Model")
	model.Name = id
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x * s, y * s, z * s)
	end
	local function cube(x: number, y: number, z: number, size: Vector3, face: Color3, rim: Color3, mode: string?): Part
		return BlockKit.cube(model, at(x, y, z), size * s, face, rim, mode)
	end

	local plate = HopperBuilder.Plate
	local legH = HopperBuilder.LegHeight
	local bin, binH = HopperBuilder.Bin, HopperBuilder.BinHeight
	local baseH = 0.6
	local legTop = baseH + legH
	local binBottom = legTop + 1.0 -- (the top frame is 1 stud)
	local binTop = binBottom + binH
	local legX = bin / 2 - 0.6

	---------------------------------------------------------------- base and the conveyor between the legs
	cube(0, baseH / 2, 0, Vector3.new(plate, baseH, plate), style.Dark, style.DarkRim)
	BlockKit.belt(model, at(0, baseH, 0), plate * s, 2.4 * s)

	---------------------------------------------------------------- four legs and the top frame
	for i, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		local x, z = c.X * legX, c.Y * legX
		cube(x, baseH + legH / 2, z, Vector3.new(1.2, legH, 1.2), style.Dark, style.DarkRim, "side")
		cube(x, baseH + 0.35, z, Vector3.new(1.5, 0.7, 1.5), style.Face, style.Rim, "side")
		if c.Y > 0 then
			BlockKit.pixels(model, at(x, baseH + legH * 0.6, z), Vector3.new(1.2, legH * 0.4, 1.2) * s, pixel(style, i), 2)
		end
	end
	for i = 0, 3 do
		local turn = cf * CFrame.Angles(0, i * math.pi / 2, 0)
		BlockKit.cube(
			model,
			turn * CFrame.new(0, (legTop + 0.5) * s, legX * s),
			Vector3.new(bin, 1.0, 1.2) * s,
			style.Face,
			style.Rim,
			"all"
		)
	end

	---------------------------------------------------------------- the stepped funnel and the spout under the frame
	cube(0, legTop - 0.1, 0, Vector3.new(bin - 2.2, 0.9, bin - 2.2), style.Face, style.Rim)
	cube(0, legTop - 0.95, 0, Vector3.new(2.6, 0.8, 2.6), style.Face, style.Rim)
	cube(0, legTop - 1.7, 0, Vector3.new(1.6, 0.7, 1.6), style.Dark, style.DarkRim)
	local main = OreData.get(hopper.Ores[#hopper.Ores])
	Geo.block(model, at(0, legTop - 2.07, 0), Vector3.new(1.0, 0.06, 1.0) * s, main.Glow, NEON, decor())

	---------------------------------------------------------------- the bin with its ores and the name
	cube(0, binBottom + binH / 2, 0, Vector3.new(bin, binH, bin), style.Face, style.Rim)
	-- a dark rim band around the bin's top edge and the ore fill
	for i = 0, 3 do
		local turn = cf * CFrame.Angles(0, i * math.pi / 2, 0)
		BlockKit.cube(
			model,
			turn * CFrame.new(0, (binTop + 0.3) * s, (bin / 2 - 0.3) * s),
			Vector3.new(bin + 0.01, 0.6, 0.6) * s,
			style.Dark,
			style.DarkRim,
			"side"
		)
	end
	Geo.block(model, at(0, binTop + 0.15, 0), Vector3.new(bin - 1.2, 0.3, bin - 1.2) * s, main.Color, PLASTIC, decor())
	local heap = {
		Vector3.new(-1.2, 0, -1.0),
		Vector3.new(1.1, 0, -1.1),
		Vector3.new(0, 0.2, 0.1),
		Vector3.new(-1.0, 0, 1.1),
		Vector3.new(1.2, 0, 1.0),
	}
	for i, p in heap do
		local oreId = hopper.Ores[(i - 1) % #hopper.Ores + 1]
		ore(model, oreId, hopper.Grade, at(p.X, binTop + 0.6 + p.Y, p.Z) * CFrame.Angles(0.3 * i, i * 1.3, -0.2 * i), i, i == 3)
	end
	BlockKit.pixels(model, at(0, binBottom + binH / 2, 0), Vector3.new(bin, binH, bin) * s, pixel(style, 1), 4)
	BlockKit.text(
		model,
		at(0, binBottom + binH / 2, bin / 2 + 0.06),
		Vector3.new(bin - 1.6, binH - 0.9, 0.08) * s,
		string.upper(hopper.Name),
		rgb(255, 250, 236),
		rgb(20, 22, 30),
		style.Rim
	)

	---------------------------------------------------------------- ores falling onto the belt and riding it
	for i = 1, 2 do
		local oreId = hopper.Ores[(i * 2 - 1) % #hopper.Ores + 1]
		ore(model, oreId, hopper.Grade, at(0, legTop - 2.6 - (i - 1) * 1.3, 0) * CFrame.Angles(i, i * 2, 0.4), 10 + i)
	end
	for i, x in { -2.2, 0.4, 2.6 } do
		local oreId = hopper.Ores[(i + 1) % #hopper.Ores + 1]
		ore(model, oreId, hopper.Grade, at(x, baseH + 1.2, 0) * CFrame.Angles(0.2, i * 1.9, 0.3), 20 + i)
	end

	---------------------------------------------------------------- the crest of each hopper
	local deco = style.Deco
	local top = binTop + 0.6
	local corners = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	local cx = bin / 2 - 0.3
	if deco == "bolts" then
		for i, c in corners do
			cube(c.X * cx, top + 0.3, c.Y * cx, Vector3.new(0.8, 0.6, 0.8), style.Dark, style.DarkRim, "flat")
			Geo.block(model, at(c.X * cx, top + 0.65, c.Y * cx), Vector3.new(0.4, 0.1, 0.4) * s, pixel(style, i), NEON, decor())
		end
	elseif deco == "crown" then
		for i, c in corners do
			cube(c.X * cx, top + 0.6, c.Y * cx, Vector3.new(0.9, 1.2, 0.9), style.Face, style.Rim)
			Geo.block(model, at(c.X * cx, top + 1.35, c.Y * cx), Vector3.new(0.4, 0.3, 0.4) * s, rgb(255, 80, 60), NEON, decor())
		end
		for i = 0, 3 do
			local turn = cf * CFrame.Angles(0, i * math.pi / 2, 0)
			BlockKit.cube(
				model,
				turn * CFrame.new(0, (top + 0.4) * s, cx * s),
				Vector3.new(0.7, 0.8, 0.7) * s,
				style.Face,
				style.Rim,
				"flat"
			)
		end
	elseif deco == "crystals" then
		for i, c in corners do
			local base = at(c.X * cx, top + 0.7, c.Y * cx) * CFrame.Angles(-c.Y * 0.25, math.pi / 4, c.X * 0.25)
			Geo.block(model, base, Vector3.new(0.7, 1.6, 0.7) * s, rgb(230, 50, 90), GLASS, decor())
			Geo.block(model, base * CFrame.new(0, 1.0 * s, 0), Vector3.new(0.45, 0.5, 0.45) * s, pixel(style, i), NEON, decor())
		end
	elseif deco == "heart" then
		BlockKit.pixelArt(model, at(0, top + 2.6, 0), HEART, 0.42 * s, {
			["#"] = rgb(255, 70, 130),
			o = rgb(255, 214, 230),
		}, 0.42 * s)
	elseif deco == "star" then
		BlockKit.pixelArt(model, at(0, top + 2.6, 0), STAR, 0.42 * s, {
			["#"] = rgb(255, 200, 50),
			o = rgb(255, 246, 190),
		}, 0.42 * s)
		cube(0, top + 0.4, 0, Vector3.new(0.6, 0.8, 0.6), style.Rim, style.Dark, "flat")
	elseif deco == "rift" then
		for i, p in
			{
				Vector3.new(-2.4, 1.6, 0.6),
				Vector3.new(2.2, 2.3, -0.8),
				Vector3.new(0.2, 3.0, 0.2),
				Vector3.new(-0.8, 1.2, -2.0),
				Vector3.new(1.6, 1.0, 2.0),
			}
		do
			local size = 0.5 + (i % 3) * 0.2
			Geo.block(
				model,
				at(p.X, top + p.Y, p.Z) * CFrame.Angles(i * 0.6, i * 0.9, 0.4),
				Vector3.new(size, size, size) * s,
				pixel(style, i),
				NEON,
				decor()
			)
		end
		-- a ring of block "rift" pixels behind the bin
		for i = 1, 12 do
			local a = i / 12 * math.pi * 2
			Geo.block(
				model,
				at(math.cos(a) * 3.6, binTop - 0.6 + math.sin(a) * 3.6, -bin / 2 - 1.2),
				Vector3.new(0.8, 0.8, 0.5) * s,
				pixel(style, i),
				NEON,
				decor()
			)
		end
	elseif deco == "core" then
		-- the lava core in a gold cage
		local coreY = top + 2.0
		Geo.block(model, at(0, coreY, 0), Vector3.new(2.0, 2.0, 2.0) * s, rgb(236, 64, 18), NEON, decor())
		for _, c in corners do
			cube(c.X * 1.35, coreY, c.Y * 1.35, Vector3.new(0.45, 2.9, 0.45), style.Face, style.Rim, "flat")
		end
		for i = 0, 3 do
			local turn = cf * CFrame.Angles(0, i * math.pi / 2, 0)
			BlockKit.cube(
				model,
				turn * CFrame.new(0, (coreY + 1.45) * s, 1.35 * s),
				Vector3.new(3.15, 0.45, 0.45) * s,
				style.Face,
				style.Rim,
				"flat"
			)
		end
		cube(0, coreY - 1.45, 0, Vector3.new(3.15, 0.45, 3.15), style.Face, style.Rim, "flat")
		cube(0, coreY + 2.0, 0, Vector3.new(0.8, 0.8, 0.8), rgb(255, 236, 140), style.Rim, "flat")
		for i, c in corners do
			Geo.block(model, at(c.X * cx, top + 0.25, c.Y * cx), Vector3.new(0.6, 0.5, 0.6) * s, pixel(style, i), NEON, decor())
		end
	end
	return model
end

return HopperBuilder
