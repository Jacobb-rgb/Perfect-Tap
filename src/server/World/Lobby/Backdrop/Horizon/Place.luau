--[[
	Horizon placement helpers and the Kenney Pirate Kit palette (shape and
	colour reference: https://kenney.nl/assets/pirate-kit, rebuilt from
	parts). Bearings are compass degrees from the plaza (0 = north (-Z),
	90 = east (+X)), like Sky/Clouds.
]]

local Place = {}

-- Sea surface top (Land.luau: the sea spans y -23..-21).
Place.Sea = -21

-- A point at `dist` studs from the plaza along compass bearing `az`.
function Place.at(az: number, dist: number, y: number): Vector3
	local r = math.rad(az)
	return Vector3.new(math.sin(r) * dist, y, -math.cos(r) * dist)
end

-- A frame at `p` whose LookVector points along compass bearing `az`.
function Place.heading(p: Vector3, az: number): CFrame
	local r = math.rad(az)
	return CFrame.lookAt(p, p + Vector3.new(math.sin(r), 0, -math.cos(r)))
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Kenney Pirate Kit colours
Place.K = {
	Sand = rgb(240, 196, 136),
	SandDark = rgb(214, 158, 102),
	RockOrange = rgb(208, 120, 76),
	RockOrangeDark = rgb(166, 86, 58),
	RockGrey = rgb(128, 128, 158),
	RockGreyDark = rgb(94, 94, 124),
	Tower = rgb(156, 158, 192),
	TowerDark = rgb(120, 122, 158),
	RoofBlue = rgb(72, 98, 208),
	RoofBlueDark = rgb(52, 72, 168),
	Hull = rgb(198, 112, 62),
	HullDark = rgb(132, 70, 42),
	HullTrim = rgb(96, 50, 34),
	SailBlack = rgb(44, 44, 58),
	SailWhite = rgb(236, 232, 246),
	Skull = rgb(232, 228, 236),
	Palm = rgb(150, 98, 60),
	Leaf = rgb(96, 186, 72),
	LeafLight = rgb(140, 210, 88),
	Wreck = rgb(96, 150, 104),
}

return Place
