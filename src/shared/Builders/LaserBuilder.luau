--[[
	The 2X MONEY LASER (owner 2026-10-21, a Sandbox Tycoon upgrader in the
	block look; BlockKit): a block tunnel over a conveyor with green windows
	and a pixel "2X" on its roof. Ores ride through the green laser curtain
	and come out worth double: one bill goes in, two bills and a coin come out.

	build(cf, scale?) -> Model (anchored; origin = the middle of the base's bottom;
	the conveyor runs along +X through the gate, the 2X sign faces +Z).
]]

local Geo = require(script.Parent.Geo)
local BlockKit = require(script.Parent.BlockKit)

local LaserBuilder = {}

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

LaserBuilder.Face = rgb(54, 120, 220) -- blue blocks with a white top, like the tycoon's upgraders
LaserBuilder.Rim = rgb(28, 64, 150)
LaserBuilder.Top = rgb(238, 242, 250)
LaserBuilder.TopRim = rgb(176, 186, 206)
LaserBuilder.Beam = rgb(90, 255, 110)
LaserBuilder.Length = 7.2 -- along the belt
LaserBuilder.Width = 6.4 -- across the belt

local function decor(): { [string]: any }
	return { CanTouch = false, CanQuery = false, CastShadow = false }
end

-- a green bill with a darker middle (lying on the belt)
local function bill(parent: Instance, cf: CFrame)
	Geo.block(parent, cf, Vector3.new(1.3, 0.08, 0.66), rgb(86, 196, 70), Enum.Material.SmoothPlastic, decor())
	Geo.block(parent, cf * CFrame.new(0, 0.03, 0), Vector3.new(0.5, 0.06, 0.4), rgb(40, 130, 44), Enum.Material.SmoothPlastic, decor())
end

local function coin(parent: Instance, position: Vector3)
	local c = Geo.cylinder(parent, position, 0.2, 0.9, rgb(255, 204, 40), Enum.Material.SmoothPlastic, decor())
	c.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(0.4, 0, 0)
end

function LaserBuilder.build(cf: CFrame, scale: number?): Model
	local model = Instance.new("Model")
	model.Name = "MoneyLaser2X"
	local L, W = LaserBuilder.Length, LaserBuilder.Width
	local face, rim = LaserBuilder.Face, LaserBuilder.Rim
	local baseH = 0.6
	BlockKit.cube(model, cf * CFrame.new(0, baseH / 2, 0), Vector3.new(L, baseH, W), rgb(56, 60, 76), rgb(32, 34, 46))
	BlockKit.belt(model, cf * CFrame.new(0, baseH, 0), L, 2.4)

	-- the tunnel over the belt: two side walls with a green window each, the
	-- roof with its white slab, a big pixel "2X" standing on the roof
	local T = 4.4 -- tunnel length along the belt
	local wallH, inner = 4.2, 3.4 -- wall height, the gap between the walls
	local window = LaserBuilder.Beam:Lerp(Color3.new(1, 1, 1), 0.35)
	for _, side in { -1, 1 } do
		local z = side * (inner / 2 + 0.5)
		for _, px in { -1, 1 } do
			BlockKit.cube(model, cf * CFrame.new(px * (T / 2 - 0.5), baseH + wallH / 2, z), Vector3.new(1.0, wallH, 1.0), face, rim, "side")
		end
		BlockKit.cube(model, cf * CFrame.new(0, baseH + 0.45, z), Vector3.new(T - 2.0, 0.9, 1.0), face, rim, "side")
		BlockKit.cube(model, cf * CFrame.new(0, baseH + wallH - 0.45, z), Vector3.new(T - 2.0, 0.9, 1.0), face, rim, "side")
		Geo.block(model, cf * CFrame.new(0, baseH + wallH / 2, z), Vector3.new(T - 2.0, wallH - 1.8, 0.2), window, Enum.Material.Glass, {
			Transparency = 0.45,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		})
		BlockKit.pixels(model, cf * CFrame.new(side * 0, baseH + wallH / 2, z), Vector3.new(T, wallH, 1.0), LaserBuilder.Beam, 2)
	end
	local roofY = baseH + wallH + 0.4
	BlockKit.cube(model, cf * CFrame.new(0, roofY, 0), Vector3.new(T + 0.4, 0.8, inner + 2.4), face, rim)
	BlockKit.cube(model, cf * CFrame.new(0, roofY + 0.65, 0), Vector3.new(T + 0.8, 0.5, inner + 2.8), LaserBuilder.Top, LaserBuilder.TopRim)
	BlockKit.pixelArt(model, cf * CFrame.new(0, roofY + 2.3, 0), {
		"###..#...#",
		"...#..#.#.",
		".##....#..",
		"#.....#.#.",
		"####.#...#",
	}, 0.48, { ["#"] = rgb(80, 230, 90) }, 0.48)

	-- the laser: three bright beams across the belt, a faint curtain, lenses in the walls
	for _, y in { 1.3, 2.2, 3.1 } do
		Geo.block(model, cf * CFrame.new(0, baseH + y, 0), Vector3.new(0.12, 0.12, inner), LaserBuilder.Beam, NEON, decor())
		for _, side in { -1, 1 } do
			Geo.block(
				model,
				cf * CFrame.new(0, baseH + y, side * (inner / 2 - 0.02)),
				Vector3.new(0.5, 0.36, 0.1),
				LaserBuilder.Beam,
				NEON,
				decor()
			)
		end
	end
	Geo.block(
		model,
		cf * CFrame.new(0, baseH + 2.2, 0),
		Vector3.new(0.06, 3.0, inner),
		LaserBuilder.Beam,
		NEON,
		{ Transparency = 0.72, CanTouch = false, CanQuery = false, CastShadow = false }
	)
	BlockKit.text(
		model,
		cf * CFrame.new(0, roofY, (inner + 2.4) / 2 + 0.06),
		Vector3.new(3.6, 0.62, 0.06),
		"MONEY LASER",
		rgb(255, 250, 236),
		rgb(20, 24, 36),
		nil
	)

	-- before the gate one bill, after it two bills and a coin
	bill(model, cf * CFrame.new(-2.6, baseH + 0.68, 0) * CFrame.Angles(0, 0.2, 0))
	bill(model, cf * CFrame.new(2.3, baseH + 0.68, -0.25) * CFrame.Angles(0, -0.15, 0))
	bill(model, cf * CFrame.new(2.6, baseH + 0.78, 0.2) * CFrame.Angles(0, 0.3, 0))
	coin(model, (cf * CFrame.new(3.1, baseH + 1.05, -0.1)).Position)
	if scale and scale ~= 1 then
		BlockKit.scale(model, cf, scale)
	end
	return model
end

return LaserBuilder
