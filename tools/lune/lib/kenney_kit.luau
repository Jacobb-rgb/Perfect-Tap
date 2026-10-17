--[[
	Builds pieces of the Space Station Kit, Mini Dungeon and City Kit
	Commercial (Kenney, CC0) from parts, from the data that
	tools/kenney/kit_shapes.py generates (kenney_kit_shapes.luau). The pieces
	keep Kenney's origin (bottom center) and orientation, in studs at `scale`
	per Kenney meter. Prototype for the blaster shop proposals.
]]

local roblox = require("@lune/roblox") :: any
local Concepts = require("./blaster_concepts")
local Shapes = require("./kenney_kit_shapes") :: any

local Kit = {}

local V3 = roblox.Vector3
local C3 = roblox.Color3
local Enum = roblox.Enum

local CF: any
local Geo: any

local function wedgeTurn(sz: number, sy: number): any
	if sz > 0 and sy < 0 then
		return CF.identity
	elseif sz < 0 and sy < 0 then
		return CF.Angles(0, math.pi, 0)
	elseif sz > 0 then
		return CF.Angles(0, 0, math.pi)
	end
	return CF.Angles(math.pi, 0, 0)
end

-- The rotation that turns a piece back from its projection frame (see ROTATE in kit_shapes.py).
local function unturn(axis: string): any
	if axis == "z" then
		return CF.Angles(0, -math.pi / 2, 0)
	elseif axis == "y" then
		return CF.Angles(0, 0, math.pi / 2)
	end
	return CF.identity
end

export type Paint = (region: any, color: any) -> (any, any?)

--[[
	Builds piece `key` ("space/wall", ...) into `parent` at `cf` (the piece's
	origin), `scale` studs per Kenney meter. paint(region, kenneyColor) may
	return another color and a material (Neon for glowing accents).
]]
function Kit.piece(Loader: any, parent: any, key: string, cf: any, scale: number, paint: Paint?)
	CF = Loader.CFrame
	Geo = Loader.requirePath("ReplicatedStorage.Shared.Builders.Geo")
	local data = Shapes[key]
	assert(data, "unknown kit piece " .. key)
	local model = roblox.Instance.new("Model")
	model.Name = key
	local K = Concepts.kit(model)
	local base = cf * unturn(data.axis)
	for _, region in data.regions do
		local kenney = C3.fromRGB(region.rgb[1], region.rgb[2], region.rgb[3])
		local color, material = kenney, nil
		if paint then
			local c, m = paint(region, kenney)
			color, material = c or kenney, m
		end
		local w = region.w * scale
		local x = region.c * scale
		for _, p in region.prims do
			local kind = p[1]
			if kind == "b" then
				local z0, z1, y0, y1 = p[2] * scale, p[3] * scale, p[4] * scale, p[5] * scale
				if z1 - z0 >= 0.003 and y1 - y0 >= 0.003 then
					K.boxCF(base * CF.new(x, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(w, y1 - y0, z1 - z0), color, material)
				end
			elseif kind == "t" then
				local pz, py, az, by = p[2] * scale, p[3] * scale, p[4] * scale, p[7] * scale
				if math.abs(by - py) >= 0.003 and math.abs(az - pz) >= 0.003 then
					local local_ = CF.new(x, (py + by) / 2, (pz + az) / 2) * wedgeTurn(pz - az, py - by)
					K.part("WedgePart", base * local_, V3.new(w, math.abs(by - py), math.abs(az - pz)), color, material)
				end
			else
				local a = base * V3.new(x, p[3] * scale, p[2] * scale)
				local b = base * V3.new(x, p[5] * scale, p[4] * scale)
				local c = base * V3.new(x, p[7] * scale, p[6] * scale)
				Geo.triangle(model, a, b, c, w, color, material, nil, { CanCollide = false, Anchored = true })
			end
		end
	end
	model.Parent = parent
	return model
end

-- Every converted piece in a row (to check them against the kits).
function Kit.buildCheck(Loader: any, parent: any)
	Concepts.init(Loader)
	CF = Loader.CFrame
	local root = roblox.Instance.new("Model")
	root.Name = "KitCheck"
	root.Parent = parent
	local keys = {}
	for key in Shapes do
		table.insert(keys, key)
	end
	table.sort(keys)
	for i, key in keys do
		local col = (i - 1) % 8
		local row = math.floor((i - 1) / 8)
		Kit.piece(Loader, root, key, CF.new(col * 16 - 56, 0, -row * 16), 10)
	end
	return root
end

return Kit
