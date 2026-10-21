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

local function decor(): { [string]: any }
	return { CanTouch = false, CanQuery = false, CastShadow = false }
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
			Vector3.new(-2.0, 3.5, 0.4),
			Vector3.new(2.0, 6.5, -0.2),
			Vector3.new(-1.8, 10.0, -0.4),
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

return LaserBuilder
