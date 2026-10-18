--[[
	Kenney Hexagon Kit tiles (CC0, colours sampled from the kit's colormap)
	built from parts: a pointy-top hexagonal prism is the union of three
	boxes (flat-to-flat width x circumradius) turned 0, 60 and 120 degrees,
	so a tile is 3 body boxes in the salmon earth colour and 3 thin top
	boxes in the tile's colour. Islands are clusters of tiles on axial
	coordinates; Kenney's buildings (Blocks + Kenney/Hex*) stand on top.
]]

local Style = require(script.Parent.Parent.Parent.Style)
local Kit = require(script.Parent.Parent.Parent.Sky.Kit)

local Hex = {}

Hex.Colors = {
	Grass = Color3.fromHex("48c1a3"),
	Sand = Color3.fromHex("f2bf99"),
	Stone = Color3.fromHex("a0a8c9"),
	Water = Color3.fromHex("8fdbff"),
	Earth = Color3.fromHex("f1976c"),
	EarthDark = Color3.fromHex("d7815b"),
}

local ROOT3 = math.sqrt(3)

-- World offset of axial tile (q, r) for tiles `w` studs flat-to-flat
-- (pointy along Z like the kit).
function Hex.offset(q: number, r: number, w: number): Vector3
	return Vector3.new(w * (q + r / 2), 0, w * ROOT3 / 2 * r)
end

-- One hexagonal prism: `frame` = center of the top face, `w` flat-to-flat,
-- `h` tall (downward). 3 parts.
local function prism(parent: Instance, frame: CFrame, w: number, h: number, color: Color3)
	local size = Vector3.new(w, h, w / ROOT3)
	for i = 0, 2 do
		Style.block(parent, frame * CFrame.Angles(0, i * math.pi / 3, 0) * CFrame.new(0, -h / 2, 0), size, color, nil, Kit.far())
	end
end

--[[
	A tile: top face at `top` (world), body down to `bottom`, the top colour
	`kind` (Grass, Sand, Stone) in a thin cap over the salmon earth. 6 parts.
]]
function Hex.tile(parent: Instance, center: Vector3, top: number, bottom: number, w: number, kind: string)
	local frame = CFrame.new(center.X, top, center.Z)
	local cap = math.max(1, w * 0.04)
	prism(parent, frame, w * 1.002, cap, Hex.Colors[kind] or Hex.Colors.Grass)
	prism(parent, frame * CFrame.new(0, -cap, 0), w, top - cap - bottom, Hex.Colors.Earth)
end

return Hex
