--[[
	Flora town buildings: 14 houses, workshops and one lookout tower on the
	free ground between the stalls and the plot roads, so both sides of the
	hero view read as a dense town (docs/art/lobby_concept.webp) in the
	concept v2 building language (docs/art/lobby_concept_v2.webp: steel-grey
	blocks with lighter bevels, thick blue neon contours, neon-framed
	shopfronts, big dark navy signs with light text, orange accents) mixed
	with the cozy cobble-and-timber houses of concept v1. Shapes after
	Kenney's City Kit commercial and Space Station Kit
	(docs/art/kenney_refs/*.jpg), built from parts by Flora/Buildings.luau.

	Where they stand (each site checked against the lobby cameras):
	  west strip    MAP lookout (the one landmark tower, the first building
	                on the hero's left), TOOLS by the mine (building-d: two
	                storeys and a setback box whose blade sign shows over the
	                mine hill), a cozy lodge west of the wheel, a low cart
	                garage by the west spur (the gap between the wheel and the
	                SHOP in lobby_west / lobby_spawn)
	  behind SHOP   the Smithy and the GEMS workshop along the forge west path
	  behind UPGR.  the INN, front to the forge east path
	  east strip    the ORE workshop by the east spur, a long building-k
	                workshop across the spur, a narrow row house and the
	                LAB (City Kit block with a shopfront to the hero) by the
	                ROCK SCANNER path, the depot in the hero's right corner
	  south lane    the mine cottage and the garden cottage either side of
	                the south road, with path stubs, fences, barrels, a cart
	                and sheds

	Every building stays inside its site rectangle (`Town.Sites`, world XZ,
	axis-aligned), every point of a site is LobbyLayout.isFree(p, 1) (off
	roads, paths, plots, the bases' yards, outcrops, keep-outs and every
	lobby piece), off the coastal rail line (world |x| 160..172), and the
	ground for 6 studs in front of each site's Facing side is clear of the
	other packages. No lights: windows, signs and lanterns glow with Neon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Buildings = require(script.Parent.Buildings)

local C = Style.C
local K = Buildings.Colors
local SMOOTH = Enum.Material.SmoothPlastic

local Town = {}

export type Site = {
	Id: string,
	Min: Vector2, -- world x, z
	Max: Vector2,
	Facing: string, -- front direction: "N" (-Z), "S" (+Z), "E" (+X), "W" (-X)
	Recipe: string,
	Sign: string?,
	Blade: boolean?, -- a double-sided rooftop blade sign turned to the street and the hero
}

-- Rail line of the plots' train stops (BaseLayout.RailZ = 62 plot-local).
Town.RailMinX = 160

-- Clear ground in front of every facade (studs).
Town.FrontClearance = 6

Town.Sites = {
	-- west strip along the west plot road (the hero's left side)
	{
		Id = "MapTower",
		Min = Vector2.new(-63, 28),
		Max = Vector2.new(-54, 38),
		Facing = "E",
		Recipe = "MapTower",
		Sign = "MAP",
		Blade = true,
	},
	{
		Id = "ToolShop",
		Min = Vector2.new(-63, 64),
		Max = Vector2.new(-56, 72.5),
		Facing = "E",
		Recipe = "ToolShop",
		Sign = "TOOLS",
		Blade = true,
	},
	{ Id = "Lodge", Min = Vector2.new(-63, 8), Max = Vector2.new(-56.4, 16.6), Facing = "S", Recipe = "Lodge" },
	{ Id = "CartShop", Min = Vector2.new(-63, -13), Max = Vector2.new(-56.2, -8), Facing = "S", Recipe = "CartShop", Sign = "CARTS" },
	-- behind the SHOP, beside the forge west path
	{ Id = "Smithy", Min = Vector2.new(-44, -58), Max = Vector2.new(-35, -44), Facing = "E", Recipe = "Smithy" },
	{
		Id = "GemCutter",
		Min = Vector2.new(-41, -81.5),
		Max = Vector2.new(-33, -64),
		Facing = "E",
		Recipe = "GemCutter",
		Sign = "GEMS",
		Blade = true,
	},
	-- behind UPGRADES, beside the forge east path (the pink grove behind it)
	{ Id = "Inn", Min = Vector2.new(33, -54), Max = Vector2.new(44, -43), Facing = "W", Recipe = "Inn", Sign = "INN" },
	-- east strip and the east spur
	{ Id = "OreWorks", Min = Vector2.new(56.2, -13), Max = Vector2.new(63, -8), Facing = "S", Recipe = "OreWorks", Sign = "ORE" },
	{ Id = "SpurWorkshop", Min = Vector2.new(46, 8), Max = Vector2.new(60, 12.5), Facing = "N", Recipe = "SpurWorkshop" },
	{ Id = "EastRow", Min = Vector2.new(58, 54), Max = Vector2.new(63, 65), Facing = "S", Recipe = "EastRow" },
	{ Id = "CityBlock", Min = Vector2.new(41, 66), Max = Vector2.new(50.8, 73), Facing = "S", Recipe = "CityBlock", Sign = "LAB" },
	{ Id = "Depot", Min = Vector2.new(56, 96), Max = Vector2.new(63, 108), Facing = "W", Recipe = "Depot" },
	-- the south lane, either side of the south road
	{ Id = "MineCottage", Min = Vector2.new(-30, 96.5), Max = Vector2.new(-13, 113), Facing = "N", Recipe = "MineCottage" },
	{ Id = "GardenCottage", Min = Vector2.new(9, 96), Max = Vector2.new(26, 112), Facing = "N", Recipe = "GardenCottage" },
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

-- The strip of ground in front of a site's facade (world XZ box), `depth` deep.
function Town.frontStrip(site: Site, depth: number): Kit.Box
	local lo, hi = site.Min, site.Max
	if site.Facing == "E" then
		return { Min = Vector2.new(hi.X, lo.Y), Max = Vector2.new(hi.X + depth, hi.Y) }
	elseif site.Facing == "W" then
		return { Min = Vector2.new(lo.X - depth, lo.Y), Max = Vector2.new(lo.X, hi.Y) }
	elseif site.Facing == "N" then
		return { Min = Vector2.new(lo.X, lo.Y - depth), Max = Vector2.new(hi.X, lo.Y) }
	end
	return { Min = Vector2.new(lo.X, hi.Y), Max = Vector2.new(hi.X, hi.Y + depth) }
end

-- A body inside the footprint from local extents (x: -w/2..w/2, z: front -d/2 .. back d/2).
local function part(fp: Buildings.Body, x0: number, x1: number, z0: number, z1: number): Buildings.Body
	return Buildings.sub(fp, (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0)
end

--[[
	Keep-out boxes for the scatter: every site grown by `margin`, plus the
	clear ground in front of each facade.
]]
function Town.keepOut(margin: number?): { Kit.Box }
	local m = margin or 0
	local out: { Kit.Box } = {}
	for _, site in Town.Sites do
		table.insert(out, { Min = site.Min - Vector2.new(m, m), Max = site.Max + Vector2.new(m, m) })
		table.insert(out, Town.frontStrip(site, Town.FrontClearance))
	end
	return out
end

local face = Buildings.face
local floorY = Buildings.floorY
local glow = Buildings.glow
local trim = Buildings.trim

-- A lamp post without a light: a steel post and a caged amber lamp. 5 parts.
local function lampPost(m: Instance, at: CFrame, h: number)
	Style.block(m, at * CFrame.new(0, h / 2, 0), Vector3.new(0.45, h, 0.45), K.Frame, nil, Style.decor())
	Buildings.cagedLamp(m, at * CFrame.new(0, h + 0.4, 0), 1.1)
end

-- Flat stepping stones from `a` to `b` (ground points in a frame), `n` stones. n parts.
local function stones(m: Instance, a: Vector3, b: Vector3, n: number, rng: Rng.Rng)
	for i = 0, n - 1 do
		local p = a:Lerp(b, (i + 0.5) / n)
		local s = rng:range(1.3, 1.7)
		local h = 0.14 + (i % 2) * 0.05
		trim(
			m,
			CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:range(-0.3, 0.3), 0),
			Vector3.new(s, h, s * 0.8),
			Style.vary(C.Cobble, rng, 0.05)
		)
	end
end

-- A flower bed: a leafy box with three flower cubes spaced along it (`at` = ground center). 4 parts.
local function flowerBed(m: Instance, at: CFrame, color: Color3)
	trim(m, at * CFrame.new(0, 0.25, 0), Vector3.new(2.6, 0.5, 1.1), C.LeafGreenDark)
	for i = -1, 1 do
		local s = 0.5 + 0.06 * (i + 1)
		trim(m, at * CFrame.new(i * 0.85, 0.5 + s / 2, 0), Vector3.new(s, s, s), color)
	end
end

-- A low fence corner: three posts and two rails along a -> corner -> b (ground points). 5 parts.
local function fenceCorner(m: Instance, a: Vector3, corner: Vector3, b: Vector3)
	for _, p in { a, corner, b } do
		Style.block(m, CFrame.new(p + Vector3.new(0, 0.9, 0)), Vector3.new(0.5, 1.8, 0.5), C.WoodDark, nil, Style.decor())
	end
	for _, seg in { { a, corner }, { corner, b } } do
		local p0, p1 = seg[1], seg[2]
		local mid = (p0 + p1) / 2 + Vector3.new(0, 1.2, 0)
		local len = (p1 - p0).Magnitude
		trim(m, CFrame.lookAt(mid, mid + (p1 - p0)), Vector3.new(0.25, 0.35, len - 0.5), C.Wood)
	end
end

---------------------------------------------------------------- recipes

local Recipes: { [string]: (m: Model, fp: Buildings.Body, site: Site, rng: Rng.Rng) -> () } = {}

--[[
	MAP: the cartographer's lookout, the town's one landmark tower (about
	22 studs): three chunky storeys on an 8 x 6.9 base, a neon-framed
	shopfront under a red awning-wide bar, the big MAP sign across the front
	(wider than the tower, like the v2 SHOP sign), a balcony on the south
	side whose rail carries the double-sided MAP blade sign for the hero and
	the south lawn, a lantern room with warm panes, a stepped slate cap and
	a small dome with a beacon. Facing east (the town): local +X is south.
]]
Recipes.MapTower = function(m, fp, site, rng)
	local tower = part(fp, -4.2, 3.8, -3.2, 3.7)
	local H = Buildings.techShell(m, tower, { Floors = 3, NeonFaces = { "Front", "Right" } }, rng)
	local front, fw = face(tower, "Front")
	Buildings.shopfront(m, front, 0, fw - 1.9, { DoorW = 2, DoorSide = -1, Goods = { C.Gold, C.CrystalCyan } })
	Buildings.awningWide(m, front, 0, 6.1, fw - 1.2, 1.0, C.AwningRed)
	Buildings.wallSign(m, front, 0.15, 9.6, site.Sign or "MAP", 6, 3, "Compass", K.Amber, 0.45)
	Buildings.windowRow(m, front, floorY(3), 2, fw - 2, 1.8)
	-- south side: windows under the balcony and above it
	local south, sw = face(tower, "Right")
	Buildings.windowRow(m, south, floorY(1), 2, sw - 2, 1.8, { X = 0.2 })
	Buildings.windowRow(m, south, floorY(3), 2, sw - 2, 1.8)
	-- the balcony on the first storey band: a steel slab and the blade sign as its rail
	local deckY = Buildings.Ground + 0.25
	Style.block(m, south * CFrame.new(0, deckY + 0.2, -0.6), Vector3.new(sw - 0.4, 0.4, 1.0), K.Frame, nil, Style.ghost())
	Buildings.bladeSign(m, south * CFrame.new(0, deckY + 0.4, -0.75), site.Sign or "MAP", sw - 1.2, 2.5, false)
	-- north and back
	Buildings.windowRow(m, face(tower, "Left"), floorY(3), 2, sw - 2, 1.8, { Dark = 2 })
	Buildings.windowRow(m, face(tower, "Back"), floorY(2), 2, fw - 2, 1.8)
	local deck = Buildings.flatRoof(m, tower, H, { "Front", "Right" })
	-- Space Station balcony-rail on the parapet of the lookout deck (town and hero sides)
	local rim = Buildings.sub(tower, 0, 0, tower.w + 0.5, tower.d + 0.5)
	for _, side in { "Front", "Right" } do
		local wall, ww = face(rim, side)
		Buildings.balconyRail(m, wall * CFrame.new(0, deck - 0.3, 0.1), ww - 0.6)
	end
	-- lantern room: a steel core with two warm panes (to the town and the hero), a stepped cap
	local room = tower.cf * CFrame.new(0, deck, 0)
	Style.block(m, room * CFrame.new(0, 1, 0), Vector3.new(4, 2, 4), K.Frame, nil, Style.decor())
	local p1 = glow(m, room * CFrame.new(0, 1, -2.03), Vector3.new(2.6, 1.2, 0.1), K.Window)
	p1.Name = "WindowGlow"
	local p2 = glow(m, room * CFrame.new(2.03, 1, 0), Vector3.new(0.1, 1.2, 2.6), K.Window)
	p2.Name = "WindowGlow"
	local cap = Buildings.steppedRoof(m, Buildings.sub(tower, 0, 0, 4.2, 4.2), deck + 2, 2, { K.Slate, K.SlateLight }, 0.7)
	Buildings.dome(m, tower.cf * CFrame.new(0, cap, 0), 1.4, K.PanelLight)
	glow(m, tower.cf * CFrame.new(0, cap + 0.75, 0), Vector3.new(0.45, 0.45, 0.45), C.AwningRed)
end

--[[
	TOOLS: City Kit building-d. A chunky two-storey block over the full
	depth of the strip with a neon-framed shopfront under an orange
	awning-wide bar, the big TOOLS sign on the first storey, a Space
	Station display-wall screen beside the door, and a one-storey setback
	box on the back of the roof; the TOOLS blade sign
	stands on the setback roof turned to the south (the hero, over the mine
	hill) and the north. Facing east: local +X is south.
]]
Recipes.ToolShop = function(m, fp, site, rng)
	local b = part(fp, -3.5, 3.5, -2.45, 2.9)
	local H = Buildings.techShell(m, b, { Floors = 2, NeonFaces = { "Front", "Right" } }, rng)
	local front, fw = face(b, "Front")
	Buildings.shopfront(m, front, 0, fw - 1.9, { DoorW = 2, DoorSide = 1, Goods = { C.Iron, C.Gold } })
	Buildings.awningWide(m, front, 0, 6.1, fw - 1.2, 0.95, C.Hazard)
	Buildings.wallSign(m, front, 0, 9.6, site.Sign or "TOOLS", 5, 2.8, "CrossedHammers", K.Amber, 0.45)
	-- south side (the hero): a display-wall screen by the front corner, two window rows
	local south, sw = face(b, "Right")
	Buildings.displayWall(m, south, -1.2, 3.3, 1.2, 1.0)
	Buildings.windowRow(m, south, floorY(1), 1, 1.6, 1.8, { X = 1.3 })
	Buildings.windowRow(m, south, floorY(2), 2, sw - 2, 1.8)
	Buildings.windowRow(m, face(b, "Left"), floorY(2), 2, sw - 2, 1.8, { Dark = 1 })
	local deck = Buildings.flatRoof(m, b, H, { "Front", "Right" })
	-- the setback box on the back of the roof
	local up = Buildings.sub(b, -0.4, 1.0, 5.4, 2.6)
	local top = Buildings.setback(m, up, deck, 4, K.Panel, rng)
	Buildings.windowRow(m, face(up, "Front"), deck + 2.2, 2, up.w - 1.4, 1.6)
	local roof = Buildings.flatRoof(m, up, top, { "Front" })
	-- the blade sign on the setback roof, turned south (the hero sees it over the mine hill)
	local at = up.cf * CFrame.new(0, roof, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	Buildings.bladeSign(m, at, site.Sign or "TOOLS", 4.0, 2.4)
	Buildings.vent(m, b.cf * CFrame.new(2.6, deck, -1.2), rng)
end

--[[
	A cozy two-storey lodge west of the wheel (concept v1): warm cobble
	ground floor with stone courses and quoins, jettied plaster upper floor
	with half-timbering, a red gable roof with its gable to the south (the
	hero sees it over the wheel), window boxes and a caged lantern.
	Facing south: local +X is west.
]]
Recipes.Lodge = function(m, fp, _site, rng)
	local b = part(fp, -2.2, 2.2, -2.7, 3.3)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0.25, 0.7, 1.6, 4.2, C.WoodDark, C.Wood)
	Buildings.hangingLantern(m, front, -1.45, 5.2)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(2), 2, uw - 1.6, 1.7, { Frame = C.WoodDark, Sill = false })
	Buildings.windowBox(m, upper, 0, floorY(2) - 1.5, uw - 1.9, C.FlowerRed)
	Buildings.window(m, face(jetty, "Left"), 0.6, floorY(2), 1.6, 1.6, { Frame = C.WoodDark })
	Buildings.window(m, face(b, "Left"), -1.2, floorY(1), 1.4, 1.8, { Frame = C.WoodDark })
	Buildings.gableRoof(
		m,
		{ cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w },
		H + 0.25,
		3.4,
		K.PlasterWarm,
		C.Roof,
		C.RoofTrim
	)
	Buildings.chimney(m, b.cf * CFrame.new(-1.2, H + 0.4, 2.2), 3.6, rng)
end

--[[
	CARTS: a low City Kit building-k garage by the west spur (seen in the
	gap between the wheel and the SHOP): one tall storey, an orange-slatted
	loading bay in a neon frame under a blue awning-wide bar, the CARTS
	sign standing on the parapet, lit windows on the east side (lobby_west /
	lobby_spawn) and the west side. Facing south: local +X is west.
]]
Recipes.CartShop = function(m, fp, site, rng)
	local b = part(fp, -2.75, 2.75, -1.75, 2.0)
	local H = Buildings.techShell(m, b, { Floors = 1, NeonFaces = { "Front", "Left" } }, rng)
	local front, fw = face(b, "Front")
	Buildings.shopfront(m, front, 0, fw - 1.9, { Bay = true })
	Buildings.awningWide(m, front, 0, 5.75, fw - 1.4, 0.7, C.CrystalBlue)
	Buildings.windowRow(m, face(b, "Left"), floorY(1), 2, 2.4, 1.8, { Sill = false })
	Buildings.window(m, face(b, "Right"), 0, floorY(1), 1.2, 1.8, { Sill = false })
	local deck = Buildings.flatRoof(m, b, H, { "Front", "Left" })
	-- the CARTS sign on two legs on the front of the deck
	local at = b.cf * CFrame.new(0, deck, -b.d / 2 + 0.5)
	for _, sx in { -1, 1 } do
		trim(m, at * CFrame.new(sx * 1.8, 0.5, 0.45), Vector3.new(0.35, 1, 0.35), K.Frame)
	end
	Buildings.sign(m, at * CFrame.new(0, 1.0 + 1.3, 0), site.Sign or "CARTS", 5.8, 2.6)
	Buildings.vent(m, b.cf * CFrame.new(2, deck, 0.6), rng)
end

--[[
	Smithy: a cozy two-storey house (warm cobble ground floor with stone
	courses and quoins, jettied plaster upper floor with half-timbering, a
	red roof like the Great Forge, window boxes, a caged lantern) and a
	stone forge wing at the south end whose glowing forge mouth faces the
	forge west path. Facing east: local +X is south.
]]
Recipes.Smithy = function(m, fp, _site, rng)
	local house = part(fp, -5.7, 0.9, -3, 3.4)
	local H = Buildings.cozyShell(m, house, { Floors = 2 }, rng)
	local front = face(house, "Front")
	Buildings.door(m, front, -0.9, 0.7, 2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, 1.85, floorY(1), 1.2, 2.2, { Frame = C.WoodDark })
	local jetty = Buildings.sub(house, 0, 0, house.w + 0.5, house.d + 0.5)
	local upper = face(jetty, "Front")
	for _, x in { -1.9, 1.9 } do
		Buildings.window(m, upper, x, floorY(2), 1.6, 1.7, { Frame = C.WoodDark, Sill = false })
		Buildings.windowBox(m, upper, x, floorY(2) - 1.5, 2.4, if x < 0 then C.FlowerRed else C.FlowerYellow)
	end
	local north, nw = face(jetty, "Left")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 2.6, 1.7, { Frame = C.WoodDark })
	Buildings.window(m, face(jetty, "Right"), 0, floorY(2), 1.6, 1.7, { Frame = C.WoodDark })
	Buildings.gableRoof(
		m,
		{ cf = house.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w },
		H + 0.25,
		3.8,
		K.Plaster,
		C.Roof,
		C.RoofTrim
	)
	Buildings.chimney(m, house.cf * CFrame.new(-house.w / 2 + 1.6, H + 0.4, 1.6), 4.6, rng)
	-- forge wing: warm stone, a flat iron roof, a glowing forge mouth to the path, a tall chimney
	local wing = part(fp, 1.6, 6.1, -2.6, 3.4)
	Style.block(m, wing.cf * CFrame.new(0, 0.32, 0), Vector3.new(wing.w + 0.6, 0.64, wing.d + 0.6), K.StonePlinth, nil, Style.solid())
	Style.block(
		m,
		wing.cf * CFrame.new(0, 3.8, 0),
		Vector3.new(wing.w, 7.6, wing.d),
		Style.vary(K.StoneWarm, rng, 0.03),
		nil,
		Style.solid()
	)
	trim(m, wing.cf * CFrame.new(0, 3.9, 0), Vector3.new(wing.w + 0.12, 0.38, wing.d + 0.12), K.StoneCourse)
	Style.block(m, wing.cf * CFrame.new(0, 7.85, 0), Vector3.new(wing.w + 0.8, 0.5, wing.d + 0.8), C.Iron, nil, Style.decor())
	local wf = face(wing, "Front")
	trim(m, wf * CFrame.new(0, 2.5, -0.23), Vector3.new(3.6, 4, 0.4), C.StoneDeep)
	local mouth = glow(m, wf * CFrame.new(0, 2.2, -0.47), Vector3.new(2.4, 2.4, 0.1), C.Molten)
	mouth.Name = "ForgeGlow"
	trim(m, wf * CFrame.new(0, 4.8, -0.4), Vector3.new(4.4, 0.7, 0.7), C.WoodDark)
	local ws = face(wing, "Right")
	trim(m, ws * CFrame.new(0, 2.6, -0.18), Vector3.new(2.6, 2.6, 0.3), C.StoneDeep)
	glow(m, ws * CFrame.new(0, 2.5, -0.37), Vector3.new(1.6, 1.6, 0.1), C.Ember)
	local stack = wing.cf * CFrame.new(-0.4, 8.1, wing.d / 2 - 1.3)
	Buildings.chimney(m, stack, 7.5, rng)
	glow(m, stack * CFrame.new(0, 8, 0), Vector3.new(1.1, 0.3, 1.1), C.Ember)
	-- an anvil on a stump by the forge mouth
	local anvil = wf * CFrame.new(1.4, 0, -1)
	trim(m, anvil * CFrame.new(0, 0.5, 0), Vector3.new(0.9, 1, 0.9), C.Trunk)
	trim(m, anvil * CFrame.new(0, 1.25, 0), Vector3.new(1.4, 0.5, 0.7), C.Iron)
end

-- A tilted crystal (solid facets, a neon core line inside the front face). 3 parts.
local function crystal(m: Instance, base: CFrame, h: number, wd: number, color: Color3, core: Color3)
	local body = base * CFrame.Angles(0, math.pi / 4, 0)
	local bh = h * 0.75
	Style.block(m, body * CFrame.new(0, bh / 2, 0), Vector3.new(wd, bh, wd), color, nil, Style.tiny({ CastShadow = true }))
	Geo.wedge(
		m,
		body * CFrame.new(0, bh + (h - bh) / 2, 0),
		Vector3.new(wd, h - bh, wd),
		color:Lerp(Color3.new(1, 1, 1), 0.2),
		SMOOTH,
		Style.tiny()
	)
	glow(m, body * CFrame.new(0, bh * 0.5, -wd / 2 + 0.02), Vector3.new(0.14, bh * 0.8, 0.08), core)
end

--[[
	GEMS: a wide two-storey City Kit block (building-k) along the forge
	west path: round front pillars with orange bands, purple neon contours,
	a long display window with a Space Station table-display-planet and
	gems under a purple awning-wide bar, the big GEMS sign, a cluster of
	three tilted pink and violet crystals on the roof, and the GEMS blade
	sign on the roof turned south. Facing east: local +X is south.
]]
Recipes.GemCutter = function(m, fp, site, rng)
	local b = part(fp, -7.6, 7.6, -2.9, 3.4)
	local neon = C.CrystalPurple
	local H = Buildings.techShell(m, b, { Floors = 2, Corners = "Round", Neon = neon, NeonFaces = { "Front", "Right" } }, rng)
	local front, fw = face(b, "Front")
	local sill = Buildings.shopfront(m, front, 0, fw - 3.4, { DoorW = 2.2, DoorSide = 1, Neon = neon })
	Buildings.planetTable(m, sill * CFrame.new(-2.2, 0.15, -0.17), 0.7)
	trim(m, sill * CFrame.new(1.4, 0.55, -0.13), Vector3.new(0.6, 0.8, 0.4), C.CrystalPink)
	trim(m, sill * CFrame.new(-0.4, 0.45, -0.13), Vector3.new(0.5, 0.6, 0.4), C.CrystalCyan)
	Buildings.awningWide(m, front, 0, 6.1, fw - 3, 1.0, C.AwningPurple)
	Buildings.wallSign(m, front, 0, 9.6, site.Sign or "GEMS", 6.4, 3, "Gem", C.AwningPink, 0.45)
	for _, x in { -5.85, 5.85 } do
		Buildings.window(m, front, x, floorY(2), 0.7, 1.8)
	end
	-- south side (the hero, the plaza): windows on both floors
	local south, sw = face(b, "Right")
	Buildings.window(m, south, 0.4, floorY(1), 1.6, 1.8)
	Buildings.windowRow(m, south, floorY(2), 2, sw - 2, 1.8)
	Buildings.windowRow(m, face(b, "Left"), floorY(2), 2, sw - 2, 1.8, { Dark = 2 })
	local deck = Buildings.flatRoof(m, b, H, { "Front", "Right" }, nil, neon)
	-- the roof crystal cluster on a steel pedestal: three tilted crystals of different heights
	local base = b.cf * CFrame.new(-3.6, deck, 1)
	Style.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(2.4, 0.6, 2.2), K.Frame, nil, Style.tiny({ CastShadow = true }))
	crystal(m, base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0.08, 0, -0.1), 3.4, 0.95, C.CrystalPurple, C.CrystalPink)
	crystal(m, base * CFrame.new(0.65, 0.5, 0.35) * CFrame.Angles(0, 0, -0.42), 2.2, 0.7, C.CrystalPink, C.FlowerWhite)
	crystal(m, base * CFrame.new(-0.6, 0.5, -0.3) * CFrame.Angles(-0.2, 0, 0.45), 1.8, 0.6, C.LeafPink, C.CrystalPink)
	Buildings.vent(m, b.cf * CFrame.new(-6.2, deck, 1.6), rng)
	-- the blade sign at the south end of the roof, facing south
	local at = b.cf * CFrame.new(6.2, deck, 0.1) * CFrame.Angles(0, -math.pi / 2, 0)
	Buildings.bladeSign(m, at, site.Sign or "GEMS", 4.8, 2.4)
end

--[[
	INN: a gable-front cozy inn (warm cobble with stone courses and quoins,
	jettied plaster with half-timbering, window boxes, a caged lantern, the
	INN sign with a mug, a dark shingle roof with a red ridge) and a one-storey
	cafe wing with a striped awning and a roof terrace parasol. The front
	faces the forge east path, the pink grove stands behind it.
	Facing west: local +X is north.
]]
Recipes.Inn = function(m, fp, site, rng)
	local b = part(fp, -1.6, 4.4, -3.7, 4.4)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.hangingLantern(m, front, -2, 5.4)
	Buildings.window(m, front, 2.1, floorY(1), 1.1, 2.2, { Frame = C.WoodDark })
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper = face(jetty, "Front")
	Buildings.wallSign(m, upper, 0, floorY(2) + 0.2, site.Sign or "INN", 3.4, 2.2, "Mug", K.Amber, 0.62)
	-- the attic window in the gable
	Buildings.window(m, upper, 0, H + 1.6, 1.2, 1.2, { Frame = C.WoodDark, Sill = false })
	-- south side (toward the plaza and the hero)
	local south, sw = face(jetty, "Left")
	Buildings.windowRow(m, south, floorY(2), 3, sw - 2.4, 1.7, { Frame = C.WoodDark, Sill = false })
	Buildings.windowBox(m, south, -2.2, floorY(2) - 1.5, 2.2, C.FlowerPink)
	Buildings.windowBox(m, south, 2.2, floorY(2) - 1.5, 2.2, C.FlowerYellow)
	Buildings.window(m, face(b, "Left"), 1.6, floorY(1), 1.8, 2, { Frame = C.WoodDark })
	local north, nw = face(jetty, "Right")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 3, 1.7, { Frame = C.WoodDark, Dark = 2 })
	Buildings.gableRoof(
		m,
		{ cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w },
		H + 0.25,
		4.4,
		K.PlasterWarm,
		K.ShingleDark,
		C.Roof
	)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.3, H + 1, 2.2), 4.2, rng)
	-- the cafe wing
	local wing = part(fp, -5.1, -2.3, -2.4, 4.6)
	Style.block(m, wing.cf * CFrame.new(0, 0.35, 0), Vector3.new(wing.w + 0.6, 0.7, wing.d + 0.6), K.StonePlinth, nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 3, 0), Vector3.new(wing.w, 6, wing.d), Style.vary(K.StoneWarm, rng, 0.03), nil, Style.solid())
	trim(m, wing.cf * CFrame.new(0, 4.9, 0), Vector3.new(wing.w + 0.12, 0.38, wing.d + 0.12), K.StoneCourse)
	local wf, ww = face(wing, "Front")
	Buildings.window(m, wf, 0, 2.6, ww - 1.4, 2, { Frame = C.WoodDark })
	Buildings.awning(m, wf, 0, 5.2, ww + 0.2, 1.6, C.AwningPink, C.AwningWhite, 3)
	local top = Buildings.flatRoof(m, wing, 6, nil, C.WoodDark)
	Buildings.parasol(m, wing.cf * CFrame.new(0, top, 1), C.AwningPink)
	Buildings.window(m, face(wing, "Left"), 0, 2.9, 2.6, 2, { Frame = C.WoodDark, Mullion = false, Sill = false })
end

--[[
	ORE: a chunky two-storey workshop by the east spur with a metal gable
	roof (its gable to the spur road, the plaza and the hero), a neon-framed
	door with a Space Station display-wall screen beside it, the big ORE
	sign, a glowing pickaxe in the gable and a dish antenna.
	The free ground here is only 5 deep, so the workshop is wide and low
	instead of a tower. Facing south: local +X is west.
]]
Recipes.OreWorks = function(m, fp, site, rng)
	local b = part(fp, -2.65, 2.65, -1.55, 2.0)
	local H = Buildings.techShell(m, b, { Floors = 2, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 0.75, 2.0, { DoorW = 1.4, DoorSide = 1, Glass = false })
	Buildings.displayWall(m, front, -1.45, 3.0, 0.9, 1.6)
	Buildings.wallSign(m, front, 0, 9.5, site.Sign or "ORE", 5.6, 2.8, nil, nil, 0.4)
	local west = face(b, "Right")
	Buildings.window(m, west, 0, floorY(1), 1.2, 1.8)
	Buildings.window(m, west, 0, floorY(2), 1.2, 1.8)
	Buildings.window(m, face(b, "Left"), 0, floorY(2), 1.2, 1.8)
	-- a steel cornice under the gable roof (the corner frames end inside it)
	Style.block(m, b.cf * CFrame.new(0, H + 0.3, 0), Vector3.new(b.w + 0.7, 0.6, b.d + 0.7), K.PanelLight, nil, Style.decor())
	glow(
		m,
		face(Buildings.sub(b, 0, 0, b.w + 0.7, b.d + 0.7), "Front") * CFrame.new(0, H + 0.3, -0.08),
		Vector3.new(b.w + 0.9, Buildings.Contour, 0.16),
		K.EdgeNeon
	)
	-- the gable to the south: ridge along the depth
	local eave = H + 0.6
	Buildings.gableRoof(
		m,
		{ cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = b.d - 0.4, d = b.w - 0.6 },
		eave,
		2.4,
		K.Panel,
		K.Slate,
		C.Hazard
	)
	-- a glowing pickaxe on a dark plate in the gable
	local g = face(Buildings.sub(b, 0, 0, b.w, b.d - 0.4), "Front")
	trim(m, g * CFrame.new(0, eave + 0.85, -0.12), Vector3.new(1.6, 1.3, 0.24), K.SignBoard)
	Style.icon(m, g * CFrame.new(0, eave + 0.85, -0.42), "Pickaxe", 1.1, K.Amber, Enum.Material.Neon)
	Buildings.antenna(m, b.cf * CFrame.new(-1.8, eave + 1.2, 1.0), 3, C.AwningRed)
end

--[[
	A long two-storey City Kit building-k workshop across the east spur from
	the ORE workshop: long window rows on both long sides (the north to the
	spur road, the south to the fossil dig and the hero), a neon-framed
	shopfront under a City Kit overhang-wide tray, rooftop boxes and a dome.
	Facing north (the spur road): local +X is east.
]]
Recipes.SpurWorkshop = function(m, fp, _site, rng)
	local b = part(fp, -6.4, 6.4, -1.4, 1.69)
	local H = Buildings.techShell(m, b, { Floors = 2, NeonFaces = { "Front", "Back" } }, rng)
	local front, fw = face(b, "Front")
	Buildings.shopfront(m, front, -1.6, 6.6, { DoorW = 2, DoorSide = 1, Goods = { C.Copper, C.CrystalBlue } })
	Buildings.overhang(m, front, -1.6, 5.9, 7.4, 0.6, K.PanelLight)
	Buildings.window(m, front, 3.9, floorY(1), 1.6, 1.8)
	Buildings.windowRow(m, front, floorY(2), 4, fw - 2, 1.7)
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(2), 4, bw - 2, 1.7, { Dark = 3 })
	Buildings.windowRow(m, back, floorY(1), 3, bw - 4.4, 1.8)
	local top = Buildings.flatRoof(m, b, H, { "Front", "Back" })
	Buildings.vent(m, b.cf * CFrame.new(-3.6, top, 0.2), rng)
	Buildings.vent(m, b.cf * CFrame.new(-0.8, top, 0.3), rng)
	Buildings.dome(m, b.cf * CFrame.new(3.4, top, 0.2), 1.6)
end

--[[
	A narrow two-storey row house along the east plot road (the hero's right
	side, between the spur and the LAB), gable to the south like the ORE
	workshop so it reads as a house and not a shaft: a neon-framed door, a
	steel cornice with a neon line, window rows along its long west side
	(the koi pond and the plaza) and a slate roof with an orange ridge.
	Facing south: local +X is west.
]]
Recipes.EastRow = function(m, fp, _site, rng)
	local b = part(fp, -1.7, 1.7, -4.5, 4.9)
	local H = Buildings.techShell(m, b, { Floors = 2, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 0, 1.6, { DoorW = 1.2, Glass = false })
	Buildings.window(m, front, 0, floorY(2), 1.0, 1.8)
	local west, ww = face(b, "Right")
	Buildings.windowRow(m, west, floorY(1), 3, ww - 2.4, 1.8)
	Buildings.windowRow(m, west, floorY(2), 3, ww - 2, 1.8, { Dark = 2 })
	Buildings.windowRow(m, face(b, "Left"), floorY(2), 3, ww - 2, 1.8)
	-- a steel cornice (the corner frames end inside it) and the gable roof to the south
	Style.block(m, b.cf * CFrame.new(0, H + 0.3, 0), Vector3.new(b.w + 0.7, 0.6, b.d + 0.7), K.PanelLight, nil, Style.decor())
	local wide = Buildings.sub(b, 0, 0, b.w + 0.7, b.d + 0.7)
	for _, side in { "Front", "Right" } do
		local wall, wl = face(wide, side)
		glow(m, wall * CFrame.new(0, H + 0.3, -0.08), Vector3.new(wl + 0.2, Buildings.Contour, 0.16), K.EdgeNeon)
	end
	local eave = H + 0.6
	Buildings.gableRoof(m, { cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = b.d - 0.4, d = b.w }, eave, 2.2, K.Panel, K.Slate, C.Hazard)
	local g = face(Buildings.sub(b, 0, 0, b.w, b.d - 0.4), "Front")
	trim(m, g * CFrame.new(0, eave + 0.75, -0.12), Vector3.new(1.0, 0.9, 0.24), K.PanelLight)
	local gp = glow(m, g * CFrame.new(0, eave + 0.75, -0.28), Vector3.new(0.6, 0.5, 0.08), K.Window)
	gp.Name = "WindowGlow"
	Buildings.chimney(m, b.cf * CFrame.new(0.6, eave + 0.6, 3.2), 2.2, rng)
end

--[[
	LAB: City Kit block by the ROCK SCANNER path with a real shopfront to
	the south (the hero): a neon-framed door and display under a red
	awning-wide bar, the LAB sign with a flask on the first storey, the
	light City Kit accent band under the parapet, window rows to the west
	and to the koi pond (north), a rooftop parasol, a box and a dome.
	Facing south: local +X is west.
]]
Recipes.CityBlock = function(m, fp, site, rng)
	local b = part(fp, -4.4, 4.4, -2.5, 3.0)
	local H = Buildings.techShell(m, b, { Floors = 2, NeonFaces = { "Front" } }, rng)
	local front, fw = face(b, "Front")
	Buildings.shopfront(m, front, 0, fw - 1.9, { DoorW = 2, DoorSide = -1, Goods = { C.CrystalCyan, C.Gold } })
	Buildings.awningWide(m, front, 0, 6.1, fw - 1.2, 0.85, C.AwningRed)
	Buildings.wallSign(m, front, 0, 9.5, site.Sign or "LAB", 5, 3, "Flask", C.CrystalCyan, 0.35)
	-- the light accent band under the parapet (City Kit trim)
	Style.block(m, b.cf * CFrame.new(0, H - 0.55, 0), Vector3.new(b.w + 0.3, 0.4, b.d + 0.3), K.PanelLight, nil, Style.tiny())
	local west, ww = face(b, "Right")
	Buildings.windowRow(m, west, floorY(1), 2, ww - 2, 1.8)
	Buildings.windowRow(m, west, floorY(2), 2, ww - 2, 1.8)
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(2), 3, bw - 2, 1.8)
	Buildings.windowRow(m, back, floorY(1), 2, bw - 4, 1.8, { X = 1 })
	local top = Buildings.flatRoof(m, b, H, { "Front" })
	Buildings.parasol(m, b.cf * CFrame.new(-1.8, top, -0.4), C.AwningRed)
	Buildings.vent(m, b.cf * CFrame.new(1.4, top, 1), rng)
	Buildings.dome(m, b.cf * CFrame.new(3, top, 1), 1.6)
end

--[[
	Depot in the hero's right corner: a chunky two-storey tech block with
	round front pillars (orange bands), an orange-slatted loading bay in a
	neon frame, window rows to the street and to the hero, a water tank; its
	yard (the south end) has a container-tall and a caged lamp post.
	Facing west: local +X is north.
]]
Recipes.Depot = function(m, fp, _site, rng)
	local b = part(fp, -3.2, 4.9, -2.35, 2.9)
	local H = Buildings.techShell(m, b, { Floors = 2, Corners = "Round", NeonFaces = { "Front", "Left" } }, rng)
	local front, fw = face(b, "Front")
	Buildings.shopfront(m, front, -1.2, 4.2, { Bay = true })
	Buildings.window(m, front, 2.3, floorY(1), 1.2, 1.8)
	Buildings.windowRow(m, front, floorY(2), 4, fw - 2.6, 1.7, { Dark = 3 })
	local south, sw = face(b, "Left")
	Buildings.windowRow(m, south, floorY(1), 1, 1.8, 1.8, { X = 0.6 })
	Buildings.windowRow(m, south, floorY(2), 2, sw - 2, 1.7, { Frame = C.Hazard })
	local top = Buildings.flatRoof(m, b, H, { "Front", "Left" })
	Buildings.waterTank(m, b.cf * CFrame.new(-1.8, top, 0.6), 2.6)
	Buildings.vent(m, b.cf * CFrame.new(1.8, top, 0.4), rng)
	-- the yard at the south end: a container-tall and a caged lamp post
	Buildings.container(m, (fp.cf * CFrame.new(-4.95, 0, 1.4)).Position, 3.6, C.Hazard)
	lampPost(m, fp.cf * CFrame.new(-5.3, 0, -2.9), 3.4)
end

--[[
	Gable-front cottage beside the mine (concept v1) with half-timbering,
	window boxes, a caged lantern, a brown shingle roof with a red ridge and
	a woodshed; its front yard is part of the south lane: a stepping-stone
	path to the mine path, a fence corner, barrels and an ore cart.
	Facing north: local +X is east (toward the south road).
]]
Recipes.MineCottage = function(m, fp, _site, rng)
	local b = part(fp, -7.3, 2.4, -3.2, 7.2)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, -1.4, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, 2.2, floorY(1), 1.8, 2.2, { Frame = C.WoodDark })
	Buildings.hangingLantern(m, front, 0.4, 5.4)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	for _, side in { "Front", "Right", "Left" } do
		local wall, ww = face(jetty, side)
		Buildings.windowRow(m, wall, floorY(2), 2, ww - 2.2, 1.7, { Frame = C.WoodDark, Sill = side ~= "Front" })
		if side == "Front" then
			Buildings.windowBox(m, wall, 0, floorY(2) - 1.5, ww - 2.6, C.FlowerRed)
		end
	end
	Buildings.gableRoof(
		m,
		{ cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w },
		H + 0.25,
		4.4,
		K.PlasterWarm,
		K.Shingle,
		C.Roof
	)
	Buildings.chimney(m, b.cf * CFrame.new(-b.w / 2 + 1.4, H, 1.4), 5, rng)
	-- woodshed: back wall, side boards (short of the back wall), posts, a roof sloping back, logs
	local shed = part(fp, 3.6, fp.w / 2 - 0.8, -0.8, 5.4)
	local sw, sd = shed.w, shed.d
	Style.block(m, shed.cf * CFrame.new(0, 2, sd / 2 - 0.2), Vector3.new(sw, 4, 0.4), C.Plank, nil, Style.decor())
	for _, sx in { -1, 1 } do
		Style.block(m, shed.cf * CFrame.new(sx * (sw / 2 - 0.2), 1.9, 0.4), Vector3.new(0.4, 3.8, sd - 1.6), C.Wood, nil, Style.decor())
		trim(m, shed.cf * CFrame.new(sx * (sw / 2 - 0.2), 2.4, -sd / 2 + 0.3), Vector3.new(0.6, 4.8, 0.6), C.WoodDark)
	end
	local drop = 1.2
	local a = math.atan2(drop, sd)
	Style.block(
		m,
		shed.cf * CFrame.new(0, 4.6 - drop / 2, 0) * CFrame.Angles(-a, 0, 0),
		Vector3.new(sw + 0.8, 0.35, math.sqrt(sd * sd + drop * drop) + 0.6),
		C.WoodDark,
		nil,
		Style.ghost()
	)
	for _, r in { { -0.6, 0.55 }, { 0.6, 0.55 }, { 0, 1.5 } } do
		Geo.make(
			"Part",
			Style.tiny({
				Shape = Enum.PartType.Cylinder,
				CFrame = shed.cf * CFrame.new(r[1], r[2], 0.2) * CFrame.Angles(0, math.pi / 2, 0),
				Size = Vector3.new(sd - 1.8, 1, 1),
				Color = Style.vary(C.WoodLight, rng, 0.06),
				Material = SMOOTH,
			}),
			m
		)
	end
	-- the lane: a stone path from the door to the mine path, a fence corner, barrels, an ore cart
	local door = (b.cf * CFrame.new(-1.4, 0, -b.d / 2)).Position
	stones(m, door + Vector3.new(0, 0, -1.2), Vector3.new(door.X, 0, fp.cf.Position.Z - fp.d / 2 + 0.6), 3, rng)
	local c0 = (fp.cf * CFrame.new(-fp.w / 2 + 0.6, 0, -fp.d / 2 + 0.6)).Position
	fenceCorner(m, c0 + Vector3.new(3.2, 0, 0), c0, c0 + Vector3.new(0, 0, 4.2))
	Buildings.barrel(m, (fp.cf * CFrame.new(-7.4, 0, -5.2)).Position, rng)
	Buildings.barrel(m, (fp.cf * CFrame.new(-5.8, 0, -6.4)).Position, rng, 1.7)
	Buildings.cart(m, fp.cf * CFrame.new(4.8, 0, -6.2) * CFrame.Angles(0, 0.3, 0), C.Copper)
end

--[[
	A cozy garden cottage on the other side of the south road (concept v1):
	warm cobble with courses and quoins, jettied plaster upper floor with
	half-timbering, window boxes, a caged lantern, a terracotta roof with
	the ridge along the front; a garden fence and flower beds in front, a
	stepping-stone path to the road, a small shed and barrels.
	Facing north (the town): local +X is east.
]]
Recipes.GardenCottage = function(m, fp, _site, rng)
	local b = part(fp, -2.1, 5.9, 1.8, 7.0)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.Plaster }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 1.6, 0.7, 2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, -1.8, floorY(1), 2, 2.2, { Frame = C.WoodDark })
	Buildings.hangingLantern(m, front, -0.1, 5.4)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(2), 2, uw - 3, 1.7, { Frame = C.WoodDark, Sill = false })
	Buildings.windowBox(m, upper, -1.6, floorY(2) - 1.5, 2.2, C.FlowerPink)
	Buildings.windowBox(m, upper, 1.6, floorY(2) - 1.5, 2.2, C.FlowerPurple)
	local back, bw = face(jetty, "Back")
	Buildings.windowRow(m, back, floorY(2), 2, bw - 3, 1.7, { Frame = C.WoodDark })
	Buildings.window(m, face(jetty, "Left"), 0, floorY(2), 1.4, 1.7, { Frame = C.WoodDark })
	Buildings.gableRoof(m, jetty, H + 0.25, 3.6, K.Plaster, K.Terracotta, C.RoofDark)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.4, H + 0.6, 1.2), 4.4, rng)
	-- garden: a low fence along the front with a gate gap, flower beds
	local fy = 1.8 - 2.6
	local p0 = (fp.cf * CFrame.new(-2.6, 0, fy)).Position
	local p1 = (fp.cf * CFrame.new(1.8, 0, fy)).Position
	local p2 = (fp.cf * CFrame.new(4.4, 0, fy)).Position
	local p3 = (fp.cf * CFrame.new(fp.w / 2 - 0.6, 0, fy)).Position
	Style.fence(m, p0, p1, { Height = 1.8, PostEvery = 4.5, Rails = 1 })
	Style.fence(m, p2, p3, { Height = 1.8, PostEvery = 4.5, Rails = 1 })
	flowerBed(m, fp.cf * CFrame.new(-0.6, 0, 0.5), C.FlowerYellow)
	flowerBed(m, fp.cf * CFrame.new(5.9, 0, 0.5), C.FlowerRed)
	-- the lane: a stepping-stone path from the gate to the south road
	local gate = (fp.cf * CFrame.new(3.1, 0, fy - 1)).Position
	stones(m, gate, (fp.cf * CFrame.new(-fp.w / 2 + 0.8, 0, -fp.d / 2 + 2.4)).Position, 4, rng)
	-- a small garden shed and barrels west of the house
	local shed = fp.cf * CFrame.new(-6, 0, 4.8)
	Style.block(m, shed * CFrame.new(0, 1.6, 0), Vector3.new(3, 3.2, 2.6), Style.vary(C.Plank, rng, 0.04), nil, Style.decor())
	trim(m, shed * CFrame.new(0, 1.3, -1.32), Vector3.new(1.2, 2.4, 0.1), C.WoodDark)
	Style.block(m, shed * CFrame.new(0, 3.4, 0) * CFrame.Angles(0.25, 0, 0), Vector3.new(3.6, 0.3, 3.4), K.Terracotta, nil, Style.ghost())
	Buildings.barrel(m, (fp.cf * CFrame.new(-6.4, 0, 1.4)).Position, rng)
	Buildings.barrel(m, (fp.cf * CFrame.new(-4.6, 0, 1.9)).Position, rng, 1.7)
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
		m:SetAttribute("Facing", site.Facing)
		recipe(m, Town.footprint(site), site, Kit.sub(rng))
	end
end

return Town
