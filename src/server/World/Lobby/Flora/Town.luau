--[[
	Flora town buildings: small 2-4 storey houses, workshops and towers that
	fill the strips between the town corridor and the plot roads, the back
	rows behind the stalls and the island's south corners, so the hero view
	reads as a dense town (docs/art/lobby_concept.webp) in the concept v2
	building language (docs/art/lobby_concept_v2.webp: dark metal frames,
	blue neon trims, warm lit windows, big neon signs) mixed with the cozy
	stone-and-timber houses of concept v1. Shapes after Kenney's City Kit
	commercial and Space Station Kit (docs/art/kenney_refs/*.jpg), built
	from parts by Flora/Buildings.luau.

	Every building stays inside its site rectangle (`Town.Sites`, world XZ,
	axis-aligned), and every point of a site is LobbyLayout.isFree(p, 1):
	off roads, paths, plots, the bases' yards, outcrops, keep-outs and every
	lobby piece. Sites also stay off the coastal rail line (world |x|
	160..172). No lights: windows and signs glow with Neon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Buildings = require(script.Parent.Buildings)

local C = Style.C
local K = Buildings.Colors
local NEON = Enum.Material.Neon

local Town = {}

export type Site = {
	Id: string,
	Min: Vector2, -- world x, z
	Max: Vector2,
	Facing: string, -- front direction: "N" (-Z), "S" (+Z), "E" (+X), "W" (-X)
	Recipe: string,
	Sign: string?,
}

-- Rail line of the plots' train stops (BaseLayout.RailZ = 62 plot-local).
Town.RailMinX = 160

Town.Sites = {
	-- west strip along the west plot road (hero view: left of the town)
	{ Id = "ToolShop", Min = Vector2.new(-63, 29), Max = Vector2.new(-53, 38), Facing = "E", Recipe = "ToolShop", Sign = "TOOLS" },
	{ Id = "WestHouse", Min = Vector2.new(-63, 8), Max = Vector2.new(-54, 13), Facing = "N", Recipe = "WestHouse" },
	{ Id = "MapTower", Min = Vector2.new(-63, -32), Max = Vector2.new(-57, -21), Facing = "S", Recipe = "MapTower", Sign = "MAP" },
	{ Id = "Inn", Min = Vector2.new(-63, 66), Max = Vector2.new(-42, 73), Facing = "S", Recipe = "Inn", Sign = "INN" },
	-- back row behind the SHOP, left of the Great Forge
	{ Id = "Smithy", Min = Vector2.new(-63, -82), Max = Vector2.new(-50, -63), Facing = "E", Recipe = "Smithy" },
	{ Id = "GemCutter", Min = Vector2.new(-41, -82), Max = Vector2.new(-33, -64), Facing = "S", Recipe = "GemCutter", Sign = "GEMS" },
	-- east strip along the east plot road (hero view: right of the town)
	{ Id = "SpurHouse", Min = Vector2.new(55, -13), Max = Vector2.new(63, -8), Facing = "S", Recipe = "SpurHouse" },
	{ Id = "EastTower", Min = Vector2.new(56, -31), Max = Vector2.new(63, -22), Facing = "W", Recipe = "EastTower" },
	{ Id = "EastHall", Min = Vector2.new(56, -72), Max = Vector2.new(63, -60), Facing = "W", Recipe = "EastHall" },
	{ Id = "ScannerTower", Min = Vector2.new(58, 54), Max = Vector2.new(63, 66), Facing = "W", Recipe = "ScannerTower" },
	-- back row along the quarry rim road, behind the Enchant shop
	{ Id = "NorthRow", Min = Vector2.new(34, -104), Max = Vector2.new(62, -96), Facing = "S", Recipe = "NorthRow" },
	-- south: beside the mine and the island's south corners past the plots
	{ Id = "MineCottage", Min = Vector2.new(-30, 100), Max = Vector2.new(-13, 113), Facing = "N", Recipe = "MineCottage" },
	{ Id = "SouthWestBlock", Min = Vector2.new(-130, 122), Max = Vector2.new(-110, 140), Facing = "N", Recipe = "CityBlock" },
	{ Id = "SouthEastDepot", Min = Vector2.new(110, 122), Max = Vector2.new(130, 140), Facing = "N", Recipe = "Depot" },
} :: { Site }

local DIRS: { [string]: Vector3 } = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

--[[
	The site as a body: frame at the rectangle's ground center with
	LookVector = Facing; w = the front's width, d = the depth.
]]
function Town.footprint(site: Site): Buildings.Body
	local center = Vector3.new((site.Min.X + site.Max.X) / 2, 0, (site.Min.Y + site.Max.Y) / 2)
	local look = DIRS[site.Facing]
	local sx, sz = site.Max.X - site.Min.X, site.Max.Y - site.Min.Y
	local turned = look.X ~= 0
	return {
		cf = CFrame.lookAt(center, center + look),
		w = if turned then sz else sx,
		d = if turned then sx else sz,
	}
end

-- A body inside the footprint from local extents (x: -w/2..w/2, z: front -d/2 .. back d/2).
local function part(fp: Buildings.Body, x0: number, x1: number, z0: number, z1: number): Buildings.Body
	return Buildings.sub(fp, (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0)
end

-- Keep-out boxes for the scatter (sites grown by `margin`).
function Town.keepOut(margin: number?): { Kit.Box }
	local m = margin or 0
	local out: { Kit.Box } = {}
	for _, site in Town.Sites do
		table.insert(out, { Min = site.Min - Vector2.new(m, m), Max = site.Max + Vector2.new(m, m) })
	end
	return out
end

local face = Buildings.face
local G, U = Buildings.Ground, Buildings.Upper

local function glow(parent: Instance, cf: CFrame, size: Vector3, color: Color3): Part
	return Style.block(parent, cf, size, color, NEON, Style.tiny())
end

-- y of the window centers of upper floor f (2 = first upper floor).
local function floorY(f: number): number
	return G + (f - 2) * U + U * 0.52
end

---------------------------------------------------------------- recipes

local Recipes: { [string]: (m: Model, fp: Buildings.Body, site: Site, rng: Rng.Rng) -> () } = {}

-- TOOLS: three-storey tech workshop (Space Station walls, City Kit overhang), front to the corridor.
Recipes.ToolShop = function(m, fp, site, rng)
	local b = part(fp, -fp.w / 2 + 0.9, fp.w / 2 - 0.9, -fp.d / 2 + 2.3, fp.d / 2 - 0.8)
	local H = Buildings.techShell(m, b, { Floors = 3, Accent = C.Hazard }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, -1.5, 0.6, 1.8, 4.4, C.GlowEdge, K.DoorLeaf, true)
	Buildings.window(m, front, 1.6, 2.9, 1.8, 2.4, K.Metal, K.Display)
	Buildings.overhang(m, front, 0, 5.5, fw - 0.4, 2.1, K.Metal, true, C.GlowEdge)
	for f = 2, 3 do
		Buildings.windowRow(m, front, floorY(f), 3, fw - 1.6, 1.8, K.Metal)
		for _, side in { "Right", "Left", "Back" } do
			local wall, ww = face(b, side)
			if f == 2 or side == "Right" then
				Buildings.windowRow(m, wall, floorY(f), 2, ww - 1.6, 1.8, K.Metal)
			end
		end
	end
	local right = face(b, "Right")
	Buildings.window(m, right, 0, 3, 2.4, 1.8, K.Metal)
	local top = Buildings.flatRoof(m, b, H, C.GlowEdge)
	Buildings.roofSign(m, b.cf * CFrame.new(0, top, -b.d / 2 + 0.9), site.Sign or "TOOLS", fw + 1.2, 2.8)
	Buildings.vent(m, b.cf * CFrame.new(-1.6, top, 1.6), rng)
	Buildings.antenna(m, b.cf * CFrame.new(2.4, top, 2.2), 4, C.GlowEdge)
end

-- MAP: a slim four-storey cartographer's tower with a lit lookout, a low annex behind.
Recipes.MapTower = function(m, fp, site, rng)
	local x0, x1 = -fp.w / 2 + 0.75, fp.w / 2 - 0.75
	local tower = part(fp, x0, x1, -fp.d / 2 + 1.6, -fp.d / 2 + 1.6 + (x1 - x0))
	local H = Buildings.techShell(m, tower, { Floors = 4, Accent = C.AwningRed, Wall = K.Panel }, rng)
	local front, fw = face(tower, "Front")
	Buildings.door(m, front, 0, 0.6, 2, 4.2, C.GlowEdge, K.DoorLeaf, true)
	for f = 2, 3 do
		Buildings.window(m, front, 0, floorY(f), 1.6, 1.8, K.Metal)
	end
	Buildings.wallSign(m, front, 0, floorY(4), site.Sign or "MAP", fw + 1.1, 2.5, 0.8)
	for _, side in { "Left", "Right" } do
		local wall = face(tower, side)
		for f = 2, 4 do
			Buildings.window(m, wall, 0, floorY(f), 1.4, 1.8, K.Metal)
		end
	end
	-- lookout: floor slab, low wall, glowing lantern room, corner posts, stepped cap
	local s = tower.w
	local look = tower.cf * CFrame.new(0, H, 0)
	Style.block(m, look * CFrame.new(0, 0.3, 0), Vector3.new(s + 1, 0.6, s + 1), K.Metal, nil, Style.decor())
	Style.block(m, look * CFrame.new(0, 1.1, 0), Vector3.new(s + 0.6, 1, s + 0.6), C.Wood, nil, Style.decor())
	local lamp = Style.block(m, look * CFrame.new(0, 2.3, 0), Vector3.new(s - 1.2, 2.2, s - 1.2), C.Lamp, NEON, Style.tiny())
	lamp.Name = "WindowGlow"
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.block(m, look * CFrame.new(sx * s / 2, 2.3, sz * s / 2), Vector3.new(0.5, 3.4, 0.5), K.Metal, nil, Style.tiny())
		end
	end
	local cap = Buildings.steppedRoof(m, Buildings.sub(tower, 0, 0, s - 0.4, s - 0.4), H + 4, 2)
	Buildings.antenna(m, tower.cf * CFrame.new(0, cap, 0), 3.4, C.AwningRed)
	-- annex
	local annex = part(fp, x0 + 0.2, x1 - 0.2, -fp.d / 2 + 1.6 + (x1 - x0), fp.d / 2 - 0.6)
	local h2 = Buildings.techShell(m, annex, { Floors = 2, Accent = C.AwningRed, Wall = K.PanelLight, Corners = false }, rng)
	local left, lw = face(annex, "Left")
	Buildings.windowRow(m, left, floorY(2), 2, lw - 1.2, 1.8, K.Metal)
	Buildings.flatRoof(m, annex, h2)
end

-- INN: three-storey gable-front inn (peeks over the MINE hill) with a two-storey cafe wing and a roof terrace.
Recipes.Inn = function(m, fp, site, rng)
	-- facing south: local +X is west; the inn stands west, the wing east
	local b = part(fp, -2.6, fp.w / 2 - 1.3, -fp.d / 2 + 1.2, fp.d / 2 - 1.15)
	local H = Buildings.cozyShell(m, b, { Floors = 3, Plaster = K.PlasterWarm }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0, 0.7, 2.4, 4.4, C.WoodDark, C.Wood)
	for _, sx in { -1, 1 } do
		Buildings.window(m, front, sx * 3.4, 3.4, 1.8, 2.2, C.WoodDark)
	end
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper = face(jetty, "Front")
	Buildings.wallSign(m, upper, 0, floorY(2), site.Sign or "INN", 5.6, 2.4)
	for _, sx in { -1, 1 } do
		Buildings.window(m, upper, sx * 4.4, floorY(2), 1.4, 1.8, C.WoodDark)
	end
	local _, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(3), 3, uw - 2, 1.8, C.WoodDark)
	-- the back faces the town (lily pond, signpost): windows and a lamp there too
	local back, bw = face(jetty, "Back")
	for f = 2, 3 do
		Buildings.windowRow(m, back, floorY(f), 3, bw - 2, 1.7, C.WoodDark)
	end
	Buildings.window(m, face(b, "Back"), 0, 3.4, 2, 1.8, C.WoodDark)
	-- gable-front roof (ridge front to back) with an attic window
	Buildings.gableRoof(m, { cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w }, H + 0.25, 4.8, K.PlasterWarm)
	Buildings.window(m, upper, 0, H + 1.8, 1.4, 1.4, C.WoodDark)
	Buildings.chimney(m, b.cf * CFrame.new(-b.w / 2 + 1.6, H + 1, 0.4), 4.6, rng)
	-- the cafe wing: stone ground floor, plaster upper floor, striped awning, roof terrace parasol
	local wing = part(fp, -fp.w / 2 + 1.1, -3.8, -fp.d / 2 + 2, fp.d / 2 - 0.8)
	local h2 = Buildings.cozyShell(m, wing, { Floors = 2, Quoins = false }, rng)
	local wf, ww = face(wing, "Front")
	Buildings.window(m, wf, 0.8, 3, 2.8, 2.4, C.WoodDark)
	Buildings.awning(m, wf, 0, 5.9, ww, 1.8, C.AwningPink, C.AwningWhite, 4)
	local wu = face(Buildings.sub(wing, 0, 0, wing.w + 0.5, wing.d + 0.5), "Front")
	Buildings.windowRow(m, wu, floorY(2), 2, ww - 1.4, 1.7, C.WoodDark)
	local top = Buildings.flatRoof(m, Buildings.sub(wing, 0, 0, wing.w + 0.2, wing.d + 0.2), h2 + 0.25, nil, C.WoodDark)
	Buildings.parasol(m, wing.cf * CFrame.new(0, top, 0), C.AwningPink)
end

-- Narrow City Kit shop house beside the SPIN & WIN wheel: plaster upper floor, a shop window, a water tank.
Recipes.WestHouse = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 0.7, fp.w / 2 - 0.7, -fp.d / 2 + 1.1, fp.d / 2 - 0.6)
	local H = Buildings.techShell(m, b, { Floors = 2, Accent = C.AwningPurple, Wall = K.Plaster, Corners = false }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, 2.3, 0.6, 1.8, 4.2, C.GlowEdge, K.DoorLeaf, true)
	Buildings.window(m, front, -1.4, 3, 3.2, 2.4, K.Metal, K.Display)
	Buildings.overhang(m, front, -1.4, 5.6, 4.6, 1, K.Metal, false, C.GlowEdge)
	Buildings.windowRow(m, front, floorY(2), 3, fw - 1.4, 1.7, K.Metal)
	for _, side in { "Left", "Right" } do
		Buildings.window(m, face(b, side), 0, floorY(2), 1.2, 1.7, K.Metal)
	end
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(2), 2, bw - 2.4, 1.7, K.Metal)
	local top = Buildings.flatRoof(m, b, H, C.GlowEdge)
	Buildings.waterTank(m, b.cf * CFrame.new(-1.8, top, 0.2), 2.4)
	Buildings.vent(m, b.cf * CFrame.new(1.8, top, 0.2), rng)
end

-- Narrow three-storey tech house by the east spur: neon edges, a hazard band, rooftop antenna.
Recipes.SpurHouse = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 0.7, fp.w / 2 - 0.7, -fp.d / 2 + 1.05, fp.d / 2 - 0.75)
	local H = Buildings.techShell(m, b, { Floors = 3, Accent = C.Hazard, Wall = K.Panel }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, -1.6, 0.6, 1.8, 4.2, C.GlowEdge, K.DoorLeaf, true)
	Buildings.window(m, front, 1.5, 3, 1.6, 2.4, K.Metal, K.Display)
	for f = 2, 3 do
		Buildings.windowRow(m, front, floorY(f), 2, fw - 1.6, 1.7, K.Metal)
		for _, side in { "Left", "Right" } do
			Buildings.window(m, face(b, side), 0, floorY(f), 1, 1.7, K.Metal)
		end
	end
	local top = Buildings.flatRoof(m, b, H, C.GlowEdge)
	Buildings.antenna(m, b.cf * CFrame.new(1.6, top, 0), 3.6, C.AwningRed)
	Buildings.vent(m, b.cf * CFrame.new(-1.4, top, 0), rng)
end

-- Smithy: cozy two-storey house with a slate roof and a stone forge wing with a tall chimney.
Recipes.Smithy = function(m, fp, _site, rng)
	-- facing east: local +X is south (the hero side), the wing sits north
	local house = part(fp, -1.2, fp.w / 2 - 1.2, -fp.d / 2 + 1.3, fp.d / 2 - 1.2)
	local H = Buildings.cozyShell(m, house, { Floors = 2 }, rng)
	local front, fw = face(house, "Front")
	Buildings.door(m, front, -1.6, 0.7, 2.4, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, 2.2, 3.4, 2.2, 2.2, C.WoodDark)
	local upperFront = face(Buildings.sub(house, 0, 0, house.w + 0.5, house.d + 0.5), "Front")
	Buildings.windowRow(m, upperFront, floorY(2), 3, fw - 1.4, 1.7, C.WoodDark)
	for _, side in { "Right", "Back" } do
		local wall, ww = face(Buildings.sub(house, 0, 0, house.w + 0.5, house.d + 0.5), side)
		Buildings.windowRow(m, wall, floorY(2), 2, ww - 2, 1.7, C.WoodDark)
	end
	local right = face(house, "Right")
	Buildings.window(m, right, 0, 3.4, 2, 1.8, C.WoodDark)
	Buildings.gableRoof(m, { cf = house.cf, w = house.w + 0.5, d = house.d + 0.5 }, H + 0.25, 4.4, K.Plaster)
	Buildings.wallLamp(m, front, -3.4, 4.8)
	-- forge wing: stone, flat iron roof, glowing forge mouth, tall chimney with an ember top
	local wing = part(fp, -fp.w / 2 + 0.8, -1.8, -fp.d / 2 + 2.2, fp.d / 2 - 2)
	Style.block(m, wing.cf * CFrame.new(0, 0.35, 0), Vector3.new(wing.w + 0.8, 0.7, wing.d + 0.8), C.StoneDark, nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 3.6, 0), Vector3.new(wing.w, 7.2, wing.d), Style.vary(C.Stone, rng, 0.04), nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 7.45, 0), Vector3.new(wing.w + 0.8, 0.5, wing.d + 0.8), C.Iron, nil, Style.decor())
	local wf = face(wing, "Front")
	Style.block(m, wf * CFrame.new(0, 2.6, -0.2), Vector3.new(4.2, 4.2, 0.4), C.StoneDeep, nil, Style.tiny())
	local mouth = Style.block(m, wf * CFrame.new(0, 2.3, -0.42), Vector3.new(3, 2.8, 0.12), C.Molten, NEON, Style.tiny())
	mouth.Name = "ForgeGlow"
	Style.block(m, wf * CFrame.new(0, 4.9, -0.3), Vector3.new(4.8, 0.7, 0.6), C.WoodDark, nil, Style.tiny())
	local stack = wing.cf * CFrame.new(-wing.w / 2 + 1.4, 7.7, wing.d / 2 - 1.6)
	Buildings.chimney(m, stack, 7, rng)
	Style.block(m, stack * CFrame.new(0, 7.5, 0), Vector3.new(1.1, 0.3, 1.1), C.Ember, NEON, Style.tiny())
	Buildings.waterTank(m, wing.cf * CFrame.new(0.6, 7.7, -0.6), 2.6)
end

-- GEMS: long two-storey gem cutter's workshop with display windows and a glowing crystal on the roof.
Recipes.GemCutter = function(m, fp, site, rng)
	local b = part(fp, -fp.w / 2 + 0.8, fp.w / 2 - 0.8, -fp.d / 2 + 2, fp.d / 2 - 0.7)
	local H = Buildings.techShell(m, b, { Floors = 2, Accent = C.AwningPurple }, rng)
	local front, fw = face(b, "Front")
	Buildings.window(m, front, 0, 3, fw - 2.2, 2.8, K.Metal, K.Display)
	Buildings.overhang(m, front, 0, 5.6, fw + 0.4, 1.9, K.Metal, true, C.CrystalPurple)
	Buildings.wallSign(m, front, 0, floorY(2), site.Sign or "GEMS", fw - 0.4, 2.2, 0.75)
	-- the long east wall faces the forge path: door, display windows, a window row
	local left, lw = face(b, "Left")
	Buildings.door(m, left, -3.2, 0.6, 2.2, 4.4, C.CrystalPurple, K.DoorLeaf, true)
	Buildings.window(m, left, 1, 3, 2.6, 2.4, K.Metal, K.Display)
	Buildings.window(m, left, 4.6, 3, 2.6, 2.4, K.Metal, K.Display)
	Buildings.windowRow(m, left, floorY(2), 4, lw - 2, 1.8, K.Metal)
	local right, rw = face(b, "Right")
	Buildings.windowRow(m, right, floorY(2), 3, rw - 3, 1.8, K.Metal)
	local top = Buildings.flatRoof(m, b, H, C.CrystalPurple)
	-- the roof crystal on a metal pedestal
	local base = b.cf * CFrame.new(0, top, -b.d / 2 + 3.2)
	Style.block(m, base * CFrame.new(0, 0.5, 0), Vector3.new(2.6, 1, 2.6), K.Metal, nil, Style.tiny({ CastShadow = true }))
	Style.crystal(m, base * CFrame.new(0, 1, 0), 5.2, 1.5, C.CrystalPurple)
	Style.crystal(m, base * CFrame.new(0.7, 1, 0.3) * CFrame.Angles(0, 0, -0.45), 3, 1, C.CrystalPink)
	Style.crystal(m, base * CFrame.new(-0.7, 1, -0.2) * CFrame.Angles(0.1, 0, 0.5), 2.6, 0.9, C.CrystalViolet)
	Buildings.vent(m, b.cf * CFrame.new(0.6, top, b.d / 2 - 2.4), rng)
end

-- Three-storey tech tower beside the UPGRADES stall, stepped cap and antenna.
Recipes.EastTower = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 0.8, fp.w / 2 - 0.8, -fp.d / 2 + 1, fp.d / 2 - 0.7)
	local H = Buildings.techShell(m, b, { Floors = 3, Accent = C.Hazard, Wall = K.Panel }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, -1.6, 0.6, 2, 4.3, C.GlowEdge, K.DoorLeaf, true)
	Buildings.window(m, front, 1.9, 3.1, 1.8, 2.2, K.Metal, K.Display)
	Buildings.banner(m, front, 0, G + U * 2 - 0.6, 2.2, 5.6, C.AwningRed)
	for f = 2, 3 do
		for _, sx in { -1, 1 } do
			Buildings.window(m, front, sx * (fw / 2 - 1.6), floorY(f), 1.1, 1.7, K.Metal)
		end
	end
	for _, side in { "Left", "Back" } do
		local wall, ww = face(b, side)
		for f = 2, 3 do
			Buildings.windowRow(m, wall, floorY(f), 2, ww - 1.6, 1.7, K.Metal)
		end
	end
	local right = face(b, "Right")
	for f = 2, 3 do
		Buildings.window(m, right, 0, floorY(f), 1.6, 1.7, K.Metal)
	end
	local cap = Buildings.steppedRoof(m, b, H, 3, { K.Metal, K.Slate, K.SlateLight })
	glow(m, b.cf * CFrame.new(0, H + 0.45, -(b.d + 0.8) / 2 - 0.06), Vector3.new(b.w + 0.8, 0.22, 0.12), C.GlowEdge)
	Buildings.antenna(m, b.cf * CFrame.new(0, cap, 0), 4.5, C.GlowEdge)
end

-- Three-storey gable house by the pink grove (gable end to the south, the hero side).
Recipes.EastHall = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 1.2, fp.w / 2 - 1.2, -fp.d / 2 + 1.2, fp.d / 2 - 1.2)
	local H = Buildings.cozyShell(m, b, { Floors = 3, Plaster = K.Plaster }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	for _, sx in { -1, 1 } do
		Buildings.window(m, front, sx * 2.7, 3.4, 1.6, 2.2, C.WoodDark)
	end
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	for _, side in { "Front", "Left", "Back" } do
		local wall, ww = face(jetty, side)
		for f = 2, 3 do
			Buildings.windowRow(m, wall, floorY(f), if side == "Left" then 1 else 3, ww - 1.6, 1.7, C.WoodDark)
		end
	end
	Buildings.gableRoof(m, jetty, H + 0.25, 3.6, K.Plaster)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.5, H + 1, 0.8), 4.4, rng)
	Buildings.wallLamp(m, front, -1.9, 4.8)
end

-- Slim radio tower with a blue beacon and a small shed, by the ROCK SCANNER.
Recipes.ScannerTower = function(m, fp, _site, rng)
	-- facing west: local -X is south (toward the camera), the shed sits north
	local tower = part(fp, -fp.w / 2 + 0.7, -fp.w / 2 + 0.7 + 4.2, -fp.d / 2 + 0.75, fp.d / 2 - 0.75)
	local H = Buildings.techShell(m, tower, { Floors = 3, Accent = C.CrystalBlue, Wall = K.PanelLight }, rng)
	local front = face(tower, "Front")
	Buildings.door(m, front, 0, 0.6, 1.8, 4.2, C.GlowEdge, K.DoorLeaf, true)
	for _, side in { "Front", "Left", "Back" } do
		local wall = face(tower, side)
		for f = 2, 3 do
			Buildings.window(m, wall, 0, floorY(f), 1.3, 1.7, K.Metal)
		end
	end
	local top = Buildings.flatRoof(m, tower, H, C.GlowEdge)
	Buildings.antenna(m, tower.cf * CFrame.new(0, top, 0), 6, C.CrystalCyan)
	local shed = part(fp, tower.w - fp.w / 2 + 1.6, fp.w / 2 - 0.6, -fp.d / 2 + 0.8, fp.d / 2 - 0.8)
	Style.block(m, shed.cf * CFrame.new(0, 0.3, 0), Vector3.new(shed.w + 0.8, 0.6, shed.d + 0.8), K.Metal, nil, Style.solid())
	Style.block(
		m,
		shed.cf * CFrame.new(0, 2.9, 0),
		Vector3.new(shed.w, 5.2, shed.d),
		Style.vary(K.PanelDark, rng, 0.03),
		nil,
		Style.solid()
	)
	Style.block(m, shed.cf * CFrame.new(0, 4.6, 0), Vector3.new(shed.w + 0.24, 0.7, shed.d + 0.24), C.CrystalBlue, nil, Style.tiny())
	Buildings.flatRoof(m, shed, 5.5)
	local sf = face(shed, "Front")
	Buildings.window(m, sf, 0, 2.8, 2.2, 1.6, K.Metal, K.Display)
end

-- Back row by the quarry rim: a three-storey tech block and a two-storey cozy shop with an awning.
Recipes.NorthRow = function(m, fp, _site, rng)
	-- facing south: local +X is west
	local west = part(fp, 1.6, fp.w / 2 - 0.8, -fp.d / 2 + 1.4, fp.d / 2 - 0.7)
	local H = Buildings.techShell(m, west, { Floors = 3, Accent = C.AwningPurple }, rng)
	local front, fw = face(west, "Front")
	Buildings.door(m, front, -3, 0.6, 2.2, 4.4, C.GlowEdge, K.DoorLeaf, true)
	Buildings.window(m, front, 1.6, 3, 5.6, 2.6, K.Metal, K.Display)
	for f = 2, 3 do
		Buildings.windowRow(m, front, floorY(f), 4, fw - 1.6, 1.7, K.Metal)
	end
	local right, rw = face(west, "Right")
	for f = 2, 3 do
		Buildings.windowRow(m, right, floorY(f), 2, rw - 1.8, 1.7, K.Metal)
	end
	local top = Buildings.flatRoof(m, west, H, C.GlowEdge)
	Buildings.vent(m, west.cf * CFrame.new(-2.4, top, 0.6), rng)
	Buildings.dome(m, west.cf * CFrame.new(2.6, top, 1), 2)
	local east = part(fp, -fp.w / 2 + 1.3, 0, -fp.d / 2 + 1.9, fp.d / 2 - 1.2)
	local H2 = Buildings.cozyShell(m, east, { Floors = 2, Plaster = K.Plaster }, rng)
	local ef, ew = face(east, "Front")
	Buildings.door(m, ef, 3.4, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, ef, -2.2, 3.1, 6, 2.4, C.WoodDark)
	Buildings.awning(m, ef, -1, 5.9, ew - 1, 1.6, C.AwningRed, C.AwningWhite, 6)
	local eu = face(Buildings.sub(east, 0, 0, east.w + 0.5, east.d + 0.5), "Front")
	Buildings.windowRow(m, eu, floorY(2), 4, ew - 1.6, 1.7, C.WoodDark)
	Buildings.gableRoof(m, Buildings.sub(east, 0, 0, east.w + 0.5, east.d + 0.5), H2 + 0.25, 3, K.Plaster)
	Buildings.chimney(m, east.cf * CFrame.new(-east.w / 2 + 1.8, H2 + 0.8, 0.6), 4, rng)
end

-- Gable-front cottage with a lean-to woodshed beside the mine.
Recipes.MineCottage = function(m, fp, _site, rng)
	-- facing north: local +X is east (toward the south road)
	local b = part(fp, -fp.w / 2 + 1.2, 2.4, -fp.d / 2 + 1.3, fp.d / 2 - 1.3)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, -1.4, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, 2.2, 3.4, 1.8, 2.2, C.WoodDark)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	for _, side in { "Front", "Right", "Left" } do
		local wall, ww = face(jetty, side)
		Buildings.windowRow(m, wall, floorY(2), 2, ww - 2.2, 1.7, C.WoodDark)
	end
	Buildings.gableRoof(m, { cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w }, H + 0.25, 4.4, K.PlasterWarm)
	Buildings.chimney(m, b.cf * CFrame.new(-b.w / 2 + 1.4, H, 1.4), 5, rng)
	Buildings.wallLamp(m, front, 0.6, 4.8)
	-- woodshed: timber posts, a plank roof, a log pile
	local shed = part(fp, 3.6, fp.w / 2 - 0.8, -fp.d / 2 + 2.8, fp.d / 2 - 2.6)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.block(
				m,
				shed.cf * CFrame.new(sx * shed.w / 2, 2.2, sz * shed.d / 2),
				Vector3.new(0.6, 4.4, 0.6),
				C.WoodDark,
				nil,
				Style.decor()
			)
		end
	end
	Style.block(
		m,
		shed.cf * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.rad(-8)),
		Vector3.new(shed.w + 0.8, 0.4, shed.d + 0.8),
		C.Plank,
		nil,
		Style.ghost()
	)
	for i = 0, 2 do
		Style.block(
			m,
			shed.cf * CFrame.new(0, 0.6 + i * 1.05, 0.4),
			Vector3.new(shed.w - 1.4, 1, shed.d - 1.8),
			Style.vary(C.Wood, rng, 0.06),
			nil,
			if i == 0 then Style.decor() else Style.tiny()
		)
	end
end

-- City Kit block (building-i / building-l): three storeys of light walls and dark bands, a water tank.
Recipes.CityBlock = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 3, fp.w / 2 - 3, -fp.d / 2 + 2.6, fp.d / 2 - 3)
	local H = Buildings.techShell(m, b, { Floors = 3, Accent = C.AwningRed, Wall = K.Plaster, Ground = K.PanelDark, Corners = false }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, 0, 0.6, 2.4, 4.4, K.Metal, K.DoorLeaf)
	for _, sx in { -1, 1 } do
		Buildings.window(m, front, sx * 4, 3, 3.4, 2.4, K.Metal)
	end
	Buildings.overhang(m, front, 0, 5.6, fw - 2, 2.2, K.Metal, true)
	for f = 2, 3 do
		for _, x in { -4.6, -1.6, 1.6, 4.6 } do
			Buildings.window(m, front, x, floorY(f), 1.4, 1.5, K.Metal)
		end
	end
	for _, side in { "Left", "Right" } do
		local wall = face(b, side)
		for f = 2, 3 do
			Buildings.windowRow(m, wall, floorY(f), 2, 6, 1.5, K.Metal)
		end
	end
	local top = Buildings.flatRoof(m, b, H)
	Buildings.waterTank(m, b.cf * CFrame.new(-3, top, 1.5), 3.4)
	Buildings.vent(m, b.cf * CFrame.new(3, top, 2), rng)
	Buildings.dome(m, b.cf * CFrame.new(2.6, top, -2.2), 1.8)
end

-- Two-storey tech depot with a loading bay overhang and tall containers.
Recipes.Depot = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 2.5, fp.w / 2 - 2.5, -fp.d / 2 + 3.2, fp.d / 2 - 2.4)
	local H = Buildings.techShell(m, b, { Floors = 2, Accent = C.Hazard }, rng)
	local front, fw = face(b, "Front")
	Style.block(m, front * CFrame.new(-2.6, 2.9, -0.15), Vector3.new(6, 4.6, 0.3), K.Metal, nil, Style.tiny())
	Style.block(m, front * CFrame.new(-2.6, 2.9, -0.32), Vector3.new(5.2, 3.8, 0.1), C.HazardDark, nil, Style.tiny())
	Buildings.door(m, front, 3.6, 0.6, 2, 4.2, C.GlowEdge, K.DoorLeaf, true)
	Buildings.overhang(m, front, -1, 5.7, fw - 2, 2.8, K.Metal, true, C.GlowEdge)
	Buildings.windowRow(m, front, floorY(2), 4, fw - 1.6, 1.8, K.Metal)
	for _, side in { "Left", "Right" } do
		local wall, ww = face(b, side)
		Buildings.windowRow(m, wall, floorY(2), 3, ww - 1.6, 1.8, K.Metal)
	end
	local top = Buildings.flatRoof(m, b, H, C.GlowEdge)
	Buildings.vent(m, b.cf * CFrame.new(-3, top, 1), rng)
	Buildings.vent(m, b.cf * CFrame.new(1, top, 1.6), rng)
	-- Space Station container-tall pair beside the bay
	for i, x in { -fp.w / 2 + 1.4, fp.w / 2 - 1.4 } do
		local p = (fp.cf * CFrame.new(x, 0, -fp.d / 2 + 1.5)).Position
		local color = if i == 1 then C.Hazard else C.CrystalBlue
		Style.block(m, CFrame.new(p + Vector3.new(0, 0.3, 0)), Vector3.new(2.2, 0.6, 2.2), K.Metal, nil, Style.decor())
		local body = Style.block(m, CFrame.new(p + Vector3.new(0, 2.4, 0)), Vector3.new(1.9, 3.6, 1.9), color, nil, Style.decor())
		body.Name = "Container"
		Style.block(m, CFrame.new(p + Vector3.new(0, 2.4, 0)), Vector3.new(2.1, 0.6, 2.1), K.MetalEdge, nil, Style.tiny())
	end
end

---------------------------------------------------------------- build

function Town.build(parent: Instance, rng: Rng.Rng)
	for _, site in Town.Sites do
		local recipe = Recipes[site.Recipe]
		assert(recipe, "unknown town recipe " .. site.Recipe)
		local m = Style.model(site.Id, parent)
		m:SetAttribute("TownBuilding", true)
		m:SetAttribute("SiteMin", Vector3.new(site.Min.X, 0, site.Min.Y))
		m:SetAttribute("SiteMax", Vector3.new(site.Max.X, 0, site.Max.Y))
		recipe(m, Town.footprint(site), site, Kit.sub(rng))
	end
end

return Town
