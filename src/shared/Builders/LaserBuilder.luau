--[[
	The MONEY LASER (owner's concept picture docs/art/hoppers_concept.webp,
	2026-10-21): the hopper cabinet (CabinetBuilder.buildCabinet) in green, a
	tall green laser beam out of its roof and glowing pixel dollar signs
	floating around the beam. It makes the ores that pass it worth double
	(DropperConfig.Laser).

	build(cf, scale?) -> Model (anchored; origin = the middle of the base's
	bottom; front = +Z).
]]

local Shared = script.Parent.Parent
local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)
local CabinetBuilder = require(script.Parent.CabinetBuilder)
local DropperConfig = require(Shared.Config.DropperConfig)
local Format = require(Shared.Util.Format)

local LaserBuilder = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

LaserBuilder.Color = rgb(0, 255, 105)
LaserBuilder.Length = CabinetBuilder.Plate -- (the row spacing in the previews)

local DOLLAR = {
	"..#..",
	".####",
	"#.#..",
	".###.",
	"..#.#",
	"####.",
	"..#..",
}

local function decor(extra: { [string]: any }?): { [string]: any }
	local props: { [string]: any } = { CanTouch = false, CanQuery = false, CastShadow = false, CanCollide = false }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return props
end

function LaserBuilder.build(cf: CFrame, scale: number?): Model
	local green = LaserBuilder.Color
	local laser = DropperConfig.Laser
	local model = CabinetBuilder.buildCabinet(cf, green, "MONEY LASER", Format.money(laser.Price), nil)
	model.Name = "MoneyLaser2X"
	local roofTop = 0.7 + CabinetBuilder.PillarH + 0.75
	-- the emitter on the roof and the beam: a bright core in a soft wide glow
	BlockKit.cube(model, cf * CFrame.new(0, roofTop + 0.4, 0), Vector3.new(1.8, 0.8, 1.8), rgb(10, 70, 45), rgb(4, 36, 22))
	Geo.block(model, cf * CFrame.new(0, roofTop + 7.5, 0), Vector3.new(0.5, 13.4, 0.5), rgb(200, 255, 210), NEON, decor())
	Geo.block(model, cf * CFrame.new(0, roofTop + 7.5, 0), Vector3.new(1.3, 13.4, 1.3), green, NEON, {
		Transparency = 0.6,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		CanCollide = false,
	})
	-- the "2X" on the emitter's front and the floating dollar signs
	BlockKit.text(
		model,
		cf * CFrame.new(0, roofTop + 0.4, 0.93),
		Vector3.new(1.4, 0.6, 0.06),
		"2X",
		rgb(160, 255, 170),
		rgb(10, 40, 24),
		nil,
		Enum.Font.LuckiestGuy
	)
	for i, p in
		{
			Vector3.new(-2.0, 4.0, 0.4),
			Vector3.new(2.0, 8.5, -0.2),
		}
	do
		local turn = CFrame.Angles(0, 0.3 * (i % 2 * 2 - 1), 0.15 * (i - 3))
		BlockKit.pixelArt(model, cf * CFrame.new(p.X, roofTop + p.Y, p.Z) * turn, DOLLAR, 0.22, { ["#"] = green }, 0.22, NEON)
	end
	if scale and scale ~= 1 then
		BlockKit.scale(model, cf, scale)
	end
	return model
end

--[[
	The Money Laser on the plot (owner 2026-10-24: "tiny, smaller than the
	machines and the Sell Box; it sits between the belts and the ore just
	rides through it"): a small green gate over one belt cell. A dark base
	plate with green neon rails, two green posts with dark caps, a lintel
	with the glowing "2X" on its front, and the laser itself: a thin bright
	sheet between the posts in a soft green glow, with an emitter under the
	lintel. Built at `cf` = the middle of the cell's floor, the ore runs
	along Z (front = +Z). About 14 parts, 3.2 studs high.
]]
function LaserBuilder.gate(cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = DropperConfig.Laser.Id
	local green, dark = LaserBuilder.Color, rgb(18, 40, 28)
	local post = rgb(40, 150, 70)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- the base plate and its neon rails along the belt
	Geo.block(model, at(0, 0.12, 0), Vector3.new(3.6, 0.24, 3.4), dark, nil, decor())
	for _, sx in { -1, 1 } do
		Geo.block(model, at(sx * 1.55, 0.26, 0), Vector3.new(0.14, 0.06, 3.2), green, NEON, decor())
	end
	-- the posts, their caps and glowing slots
	local h = 2.7
	for _, sx in { -1, 1 } do
		Geo.block(model, at(sx * 1.5, 0.24 + h / 2, 0), Vector3.new(0.5, h, 0.7), post, nil, decor())
		Geo.block(model, at(sx * 1.5, 0.24 + h + 0.12, 0), Vector3.new(0.66, 0.24, 0.86), dark, nil, decor())
		Geo.block(model, at(sx * 1.5, 0.24 + h * 0.5, 0.36), Vector3.new(0.18, h * 0.6, 0.04), rgb(200, 255, 210), NEON, decor())
	end
	-- the lintel with the "2X" on its front
	local top = 0.24 + h + 0.24
	Geo.block(model, at(0, top + 0.3, 0), Vector3.new(3.6, 0.6, 0.8), post, nil, decor())
	BlockKit.text(model, at(0, top + 0.3, 0.42), Vector3.new(1.4, 0.5, 0.06), "2X", rgb(160, 255, 170), dark, nil, Enum.Font.LuckiestGuy)
	-- the emitter under the lintel and the laser sheet between the posts
	Geo.block(model, at(0, top - 0.12, 0), Vector3.new(2.2, 0.24, 0.4), dark, nil, decor())
	Geo.block(model, at(0, 0.24 + h / 2, 0), Vector3.new(2.5, h - 0.2, 0.06), rgb(200, 255, 210), NEON, decor({ Transparency = 0.35 }))
	Geo.block(model, at(0, 0.24 + h / 2, 0), Vector3.new(2.5, h - 0.2, 0.4), green, NEON, decor({ Transparency = 0.75 }))
	return model
end

return LaserBuilder
