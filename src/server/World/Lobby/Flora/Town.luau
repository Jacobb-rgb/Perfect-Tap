--[[
	Flora town buildings: 14 houses, workshops and towers on the free ground
	between the stalls and the plot roads, so both sides of the hero view
	read as a dense town (docs/art/lobby_concept.webp) in the concept v2
	building language (docs/art/lobby_concept_v2.webp: two-tone blocks with
	a dark gunmetal frame around light steel panels, blue neon along the
	frame, lit display cases, big dark navy signs with light letters,
	orange accents) mixed with the cozy stone-and-timber houses of concept
	v1. Shapes after Kenney's City Kit commercial and Space Station Kit
	(docs/art/kenney_refs/*.jpg), built from parts by Flora/Buildings.luau.

	Where they stand (each site checked against the lobby cameras):
	  west strip    a street wall along the west plot road, the hero's left
	                side: two narrow three-storey row houses (the Lodge and
	                the mine cottage) either side of TOOLS (two storeys and a
	                setback third storey with the TOOLS blade sign over the
	                mine hill), and the two-storey CARTS shop facing the west
	                spur behind the SPIN & WIN wheel (the mirror of WORKS on
	                the east spur)
	  behind SHOP   the MAP lookout tower by the west plot road (its lookout
	                deck and MAP blade sign rise over the SHOP roof in the
	                hero view; the wide SPIN & WIN wheel took its old spot),
	                the Smithy and the GEMS workshop along the forge west path
	  behind UPGR.  the INN (a blade sign on its cafe wing turned to the
	                spawn and the hero, a street parasol), front to the forge
	                east path, and the three-storey ORE workshop east of the
	                pink grove (its top rises over the UPGRADES roof in the
	                hero view; the wide UPGRADES module took its old spot)
	  east strip    the WORKS workshop on the east spur (a rooftop crane), the
	                narrow EastRow house, the LAB with a street parasol by the
	                ROCK SCANNER path, the Depot in the hero's right corner
	  south lane    the garden cottage by the south road, with a fence,
	                flower beds, a stepping-stone path, a shed and barrels

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
local NEON = Enum.Material.Neon

local Town = {}

export type Site = {
	Id: string,
	Min: Vector2, -- world x, z
	Max: Vector2,
	Facing: string, -- front direction: "N" (-Z), "S" (+Z), "E" (+X), "W" (-X)
	Recipe: string,
	Sign: string?,
	Blade: boolean?, -- a double-sided blade sign turned to the street and the hero
}

-- Rail line of the plots' train stops (BaseLayout.RailZ = 62 plot-local).
Town.RailMinX = 160

-- Clear ground in front of every facade (studs).
Town.FrontClearance = 6

Town.Sites = {
	-- the west strip along the west plot road (the hero's left side), north to south
	{ Id = "CartShop", Min = Vector2.new(-63, 8), Max = Vector2.new(-55.5, 13), Facing = "N", Recipe = "CartShop", Sign = "CARTS" },
	{ Id = "Lodge", Min = Vector2.new(-63, 54), Max = Vector2.new(-58, 63), Facing = "W", Recipe = "Lodge" },
	{
		Id = "ToolShop",
		Min = Vector2.new(-63, 64),
		Max = Vector2.new(-56, 72.5),
		Facing = "E",
		Recipe = "ToolShop",
		Sign = "TOOLS",
		Blade = true,
	},
	{ Id = "MineCottage", Min = Vector2.new(-63, 74), Max = Vector2.new(-58.5, 88), Facing = "W", Recipe = "MineCottage" },
	-- behind the SHOP: the MAP tower by the west plot road, then beside the forge west path
	{
		Id = "MapTower",
		Min = Vector2.new(-62, -74),
		Max = Vector2.new(-53, -64),
		Facing = "E",
		Recipe = "MapTower",
		Sign = "MAP",
		Blade = true,
	},
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
	-- behind UPGRADES, beside the forge east path (the pink grove behind it), and ORE east of the grove
	{ Id = "Inn", Min = Vector2.new(33, -54), Max = Vector2.new(44, -43), Facing = "W", Recipe = "Inn", Sign = "INN", Blade = true },
	{ Id = "OreWorks", Min = Vector2.new(55.5, -71), Max = Vector2.new(63, -66), Facing = "S", Recipe = "OreWorks", Sign = "ORE" },
	-- the east strip and the east spur
	{ Id = "SpurWorkshop", Min = Vector2.new(46, 8), Max = Vector2.new(61, 12.5), Facing = "N", Recipe = "SpurWorkshop", Sign = "WORKS" },
	{ Id = "EastRow", Min = Vector2.new(58, 54), Max = Vector2.new(63, 65), Facing = "S", Recipe = "EastRow" },
	{ Id = "CityBlock", Min = Vector2.new(40, 66), Max = Vector2.new(49, 74.5), Facing = "S", Recipe = "CityBlock", Sign = "LAB" },
	{ Id = "Depot", Min = Vector2.new(55.5, 90.5), Max = Vector2.new(63, 102.5), Facing = "W", Recipe = "Depot" },
	-- the south lane, beside the south road
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

-- Flat stepping stones from `a` to `b` (ground points), `n` stones. n parts.
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

-- An emblem on a wall: a dark navy plate with a glowing Style.icon (or a plain plate with an icon kind). 1 + icon parts.
local function emblem(m: Instance, wall: CFrame, x: number, y: number, size: number, icon: string, color: Color3, out: number)
	trim(m, wall * CFrame.new(x, y, -out + 0.25), Vector3.new(size, size, 0.5), K.SignBoard)
	Style.icon(m, wall * CFrame.new(x, y, -out - 0.12), icon, size * 0.78, color, NEON)
end

---------------------------------------------------------------- recipes

local Recipes: { [string]: (m: Model, fp: Buildings.Body, site: Site, rng: Rng.Rng) -> () } = {}

--[[
	MAP: the cartographer's lookout, the town's landmark tower: three
	two-tone storeys (gunmetal frame, light steel panels, blue neon on the
	town and hero sides), a door with a glowing map screen, the big MAP
	sign across the top storey, window rows on every side, and a lookout
	deck with Space Station balcony rails, a lantern room under a stepped
	slate cap, and the double-sided MAP blade sign on its south half (it
	reads over the SHOP roof in the hero view). Facing east: local +X is
	south.
]]
Recipes.MapTower = function(m, fp, site, rng)
	local tower = part(fp, -3.7, 3.7, -2.75, 3.2)
	local _, deck = Buildings.techShell(m, tower, { Floors = 3, NeonFaces = { "Front", "Right" } }, rng)
	local front, fw = face(tower, "Front")
	Buildings.shopfront(m, front, -1.0, 3.7, { Glass = false, DoorSide = -1 })
	Buildings.displayWall(m, front, 2.05, 4.4, 1.0, 2.6)
	Buildings.windowRow(m, front, floorY(2), 2, fw - 2.2, 1.8)
	-- the big MAP sign across the top storey (to the GEMS lane and the forge west path)
	Buildings.wallSign(m, front, 0, 16.4, site.Sign or "MAP", 5.5, 3.6, "Compass", K.Amber, 1.0)
	local south, sw = face(tower, "Right")
	Buildings.windowRow(m, south, floorY(1), 2, sw - 2.2, 2.4)
	Buildings.windowRow(m, south, floorY(2), 2, sw - 2.2, 1.8)
	Buildings.windowRow(m, south, floorY(3), 2, sw - 2.2, 1.8)
	local north = face(tower, "Left")
	Buildings.windowRow(m, north, floorY(2), 2, sw - 2.2, 1.8, { Dark = 2 })
	Buildings.windowRow(m, north, floorY(3), 2, sw - 2.2, 1.8)
	-- the lookout deck: balcony rails on the town and hero sides
	local rim = Buildings.sub(tower, 0, 0, tower.w + 2.2, tower.d + 2.2)
	for _, side in { "Front", "Right" } do
		local wall, ww = face(rim, side)
		Buildings.balconyRail(m, wall * CFrame.new(0, deck - 0.35, 0.25), ww - 0.4)
	end
	-- the lantern room on the north half (panes to the town and the north), a stepped cap, a dome, a small beacon
	local room = tower.cf * CFrame.new(-1.5, deck, 0.4)
	Style.block(m, room * CFrame.new(0, 1.3, 0), Vector3.new(3.2, 2.6, 3.6), K.Gun, nil, Style.decor())
	local p1 = glow(m, room * CFrame.new(0, 1.3, -1.83), Vector3.new(2.2, 1.4, 0.1), K.Window)
	p1.Name = "WindowGlow"
	local p2 = glow(m, room * CFrame.new(-1.63, 1.3, 0), Vector3.new(0.1, 1.4, 2.4), K.Window)
	p2.Name = "WindowGlow"
	local cap = Buildings.steppedRoof(m, Buildings.sub(tower, -1.5, 0.4, 3.0, 3.4), deck + 2.6, 2, { K.Slate, K.SlateLight }, 0.6)
	Buildings.dome(m, tower.cf * CFrame.new(-1.5, cap, 0.4), 1.3, K.PanelLight)
	glow(m, tower.cf * CFrame.new(-1.5, cap + 0.72, 0.4), Vector3.new(0.3, 0.3, 0.3), C.AwningRed)
	-- the MAP blade sign on the south half of the deck, facing south (the hero, over the SHOP roof) and north
	local at = tower.cf * CFrame.new(2.3, deck, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	Buildings.bladeSign(m, at, site.Sign or "MAP", 7.0, 3.4)
end

--[[
	TOOLS: City Kit building-d by the mine. Two two-tone storeys with a
	door under an orange awning-wide bar, the big TOOLS sign across the
	first storey, a lit display case with a pickaxe and a glowing crossed
	hammers emblem on the south side (the hero), and a setback third storey
	on the north half of the roof that carries the TOOLS blade sign, so the
	building and its sign rise clearly above the mine hill in the hero
	view. Facing east: local +X is south.
]]
Recipes.ToolShop = function(m, fp, site, rng)
	local b = part(fp, -2.95, 2.95, -1.75, 2.2)
	local _, deck = Buildings.techShell(m, b, { Floors = 2, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 0, 4.4, { Glass = false })
	Buildings.awningWide(m, front, 0, 8.3, 4.8, 1.2, C.Hazard)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "TOOLS", 7.6, 3.4, nil, nil, 1.3)
	-- south side (the hero): a display case with a pickaxe, the crossed hammers emblem
	local south = face(b, "Right")
	local case = Buildings.shopfront(m, south, 0, 3.0, { Door = false })
	Buildings.goods(m, case.Sill, "Pickaxe")
	emblem(m, south, 0, 11.6, 2.8, "CrossedHammers", K.Amber, 0.5)
	Buildings.window(m, face(b, "Left"), 0, floorY(2), 1.6, 1.8)
	-- the setback third storey on the north half
	local up = Buildings.sub(fp, -0.9, 0, 3.4, 4.0)
	local top = Buildings.setback(m, up, deck, 5, rng, { "Front", "Right" })
	local raised = Buildings.raise(up, deck)
	Buildings.window(m, face(raised, "Front"), 0, 2.7, 1.6, 1.6)
	Buildings.window(m, face(raised, "Right"), 0, 2.7, 1.8, 1.6)
	Buildings.vent(m, b.cf * CFrame.new(1.8, deck, 0.4), rng)
	-- the blade sign on the setback roof, turned south (the hero sees it over the mine hill) and north
	local at = up.cf * CFrame.new(0, top, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	Buildings.bladeSign(m, at, site.Sign or "TOOLS", 6.6, 3.2)
end

--[[
	A narrow three-storey row house on the west plot road (concept v1):
	warm cobble ground floor with chunky stone blocks and big quoins, a
	jettied plaster upper part with half-timbering, a red gable roof with
	its gables to the north and the south (the hero sees the south gable
	and the long east side over the lawn), window boxes and a caged
	lantern. Facing west (the plot road): local +X is north.
]]
Recipes.Lodge = function(m, fp, _site, rng)
	local b = part(fp, -3.7, 3.7, -1.7, 1.7)
	local H = Buildings.cozyShell(
		m,
		b,
		{ Floors = 3, Plaster = K.PlasterWarm, Timbering = 3, StoneFaces = { "Front", "Back", "Left" } },
		rng
	)
	local front = face(b, "Front")
	Buildings.door(m, front, 1.0, 0.7, 3, 6.2, C.WoodDark, C.Wood)
	Buildings.window(m, front, -1.9, floorY(1), 1.3, 2.2, { Frame = C.WoodDark })
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(2), 2, uw - 2.6, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.windowRow(m, upper, floorY(3), 2, uw - 2.6, 1.8, { Frame = C.WoodDark, Sill = false })
	-- the east side (the hero camera, the mine)
	local back, bw = face(jetty, "Back")
	Buildings.windowRow(m, back, floorY(2), 3, bw - 2.2, 1.8, { Frame = C.WoodDark })
	Buildings.windowRow(m, back, floorY(3), 3, bw - 2.2, 1.8, { Frame = C.WoodDark, Mullion = false })
	Buildings.window(m, face(b, "Back"), 0.6, floorY(1), 1.8, 2.2, { Frame = C.WoodDark })
	-- the south gable end (the hero, the plaza)
	local south = face(jetty, "Left")
	Buildings.window(m, south, 0, floorY(2), 1.3, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.window(m, south, 0, floorY(3), 1.3, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.window(m, south, 0, H + 1.0, 0.9, 0.9, { Frame = C.WoodDark, Sill = false })
	Buildings.gableRoof(m, jetty, H + 0.25, 4.2, K.PlasterWarm, C.Roof, C.RoofTrim, true)
	Buildings.chimney(m, b.cf * CFrame.new(-2.2, H + 0.6, 0.65), 4.6, rng)
end

--[[
	The mine cottage: a long three-storey row house on the west plot road
	south of TOOLS (concept v1), the bottom-left corner of the hero view:
	cobble ground floor with stone blocks and quoins, a jettied plaster
	upper part with half-timbering, rows of lit windows on the long east
	side (the hero, the mine), window boxes, a caged lantern by the door, a
	brown shingle roof with its gables to the north and the south and two
	chimneys. Facing west (the plot road): local +X is north.
]]
Recipes.MineCottage = function(m, fp, _site, rng)
	local b = part(fp, -6.2, 6.2, -1.5, 1.5)
	local H = Buildings.cozyShell(
		m,
		b,
		{ Floors = 3, Plaster = K.Plaster, Timbering = 4, StoneFaces = { "Front", "Back", "Left" } },
		rng
	)
	local front = face(b, "Front")
	Buildings.door(m, front, -2.4, 0.7, 3, 6.2, C.WoodDark, C.Wood)
	Buildings.window(m, front, 1.2, floorY(1), 1.6, 2.4, { Frame = C.WoodDark })
	Buildings.window(m, front, 3.9, floorY(1), 1.6, 2.4, { Frame = C.WoodDark })
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(2), 3, uw - 4.4, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.windowRow(m, upper, floorY(3), 3, uw - 4.4, 1.8, { Frame = C.WoodDark, Sill = false, Mullion = false })
	-- the long east side (the hero camera, the mine)
	local back, bw = face(jetty, "Back")
	Buildings.windowRow(m, back, floorY(2), 4, bw - 3.0, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.windowRow(m, back, floorY(3), 4, bw - 3.0, 1.8, { Frame = C.WoodDark, Mullion = false, Dark = 3 })
	Buildings.windowRow(m, face(b, "Back"), floorY(1), 2, 6.0, 2.2, { Frame = C.WoodDark })
	-- the south gable end
	local south = face(jetty, "Left")
	Buildings.window(m, south, 0, floorY(2), 1.3, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.window(m, south, 0, H + 1.0, 0.9, 0.9, { Frame = C.WoodDark, Sill = false })
	Buildings.gableRoof(m, jetty, H + 0.25, 4.2, K.Plaster, K.Shingle, C.Roof, true)
	Buildings.chimney(m, b.cf * CFrame.new(-3.6, H + 0.6, 0.65), 4.6, rng)
	Buildings.chimney(m, b.cf * CFrame.new(4.2, H + 0.6, -0.4), 3.4, rng)
end

--[[
	CARTS: a City Kit two-storey cart garage on the west spur, behind the
	SPIN & WIN wheel (the mirror of WORKS across the plaza): an orange
	roll-up garage door in a neon frame under a blue awning-wide bar to the
	spur road, the CARTS sign across the first storey, lit windows on both
	floors on the east side (the wheel, lobby_west) and the west side, a
	little ore cart on the roof as the shop's mascot. Facing north: local
	+X is east.
]]
Recipes.CartShop = function(m, fp, site, rng)
	local b = part(fp, -2.75, 2.75, -1.05, 1.5)
	local _, deck = Buildings.techShell(m, b, { Floors = 2, Out = 0.7, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 0, 4.6, { Bay = true })
	Buildings.awningWide(m, front, 0, 8.3, 5.0, 1.0, C.CrystalBlue)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "CARTS", 6.2, 3.3, nil, nil, 1.0)
	local east = face(b, "Right")
	Buildings.window(m, east, 0, floorY(1), 1.0, 2.4)
	Buildings.window(m, east, 0, floorY(2), 1.0, 1.8)
	Buildings.window(m, face(b, "Left"), 0, floorY(2), 1.0, 1.8)
	-- the mascot: a little ore cart full of gold on the roof
	Buildings.cart(m, b.cf * CFrame.new(0.6, deck, 0.2) * CFrame.Angles(0, math.pi / 2, 0), C.Gold)
end

--[[
	Smithy: a cozy two-storey house (warm cobble ground floor with stone
	blocks and quoins, jettied plaster with half-timbering, a red roof like
	the Great Forge, window boxes) and a stone forge wing at the south end
	under a light slate lean-to roof, with a glowing forge mouth to the
	forge west path and another to the south, and a tall stone chimney with
	a dark cap and an ember glow. Facing east: local +X is south.
]]
Recipes.Smithy = function(m, fp, _site, rng)
	local house = part(fp, -6.2, 0.4, -3.2, 3.2)
	local H = Buildings.cozyShell(m, house, { Floors = 2, StoneFaces = { "Front", "Left" } }, rng)
	local front = face(house, "Front")
	Buildings.door(m, front, 1.0, 0.7, 3, 6.2, C.WoodDark, C.Wood)
	Buildings.window(m, front, -1.9, floorY(1), 1.3, 2.4, { Frame = C.WoodDark })
	local jetty = Buildings.sub(house, 0, 0, house.w + 0.5, house.d + 0.5)
	local upper = face(jetty, "Front")
	for _, x in { -1.8, 1.8 } do
		Buildings.window(m, upper, x, floorY(2), 1.6, 1.8, { Frame = C.WoodDark, Sill = false })
		Buildings.windowBox(m, upper, x, floorY(2) - 1.75, 2.4, if x < 0 then C.FlowerRed else C.FlowerYellow)
	end
	local north, nw = face(jetty, "Left")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 2.6, 1.8, { Frame = C.WoodDark })
	Buildings.gableRoof(
		m,
		{ cf = house.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w },
		H + 0.25,
		3.8,
		K.Plaster,
		C.Roof,
		C.RoofTrim,
		true
	)
	Buildings.chimney(m, house.cf * CFrame.new(-house.w / 2 + 1.4, H + 0.4, 1.6), 4.4, rng)
	-- the forge wing: warm stone, a light slate lean-to roof sloping south
	local wing = part(fp, 1.2, 6.4, -2.8, 3.4)
	Style.block(m, wing.cf * CFrame.new(0, 0.32, 0), Vector3.new(wing.w + 0.6, 0.64, wing.d + 0.6), K.StonePlinth, nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 4.1, 0), Vector3.new(wing.w, 8.2, wing.d), Style.vary(K.StoneWarm, rng, 0.03), nil, Style.solid())
	local wf = face(wing, "Front")
	trim(m, wf * CFrame.new(-1.6, 7.3, -0.1), Vector3.new(1.6, 0.9, 0.2), K.StoneCourse)
	trim(m, wf * CFrame.new(1.7, 1.4, -0.1), Vector3.new(1.4, 1.0, 0.2), K.StoneCourse)
	local drop = 1.6
	local a = math.atan2(drop, wing.w)
	Style.block(
		m,
		wing.cf * CFrame.new(0, 8.2 + 0.25, 0) * CFrame.Angles(0, 0, -a) * CFrame.new(0, 0, 0),
		Vector3.new(math.sqrt(wing.w * wing.w + drop * drop) + 0.4, 0.5, wing.d + 0.6),
		K.SlateLight,
		nil,
		Style.ghost()
	)
	-- the forge mouth to the path: a dark stone arch with a molten glow and a timber lintel
	trim(m, wf * CFrame.new(0, 2.6, -0.23), Vector3.new(3.6, 4.4, 0.4), C.StoneDeep)
	local mouth = glow(m, wf * CFrame.new(0, 2.3, -0.47), Vector3.new(2.4, 2.6, 0.1), C.Molten)
	mouth.Name = "ForgeGlow"
	trim(m, wf * CFrame.new(0, 5.1, -0.45), Vector3.new(4.4, 0.7, 0.7), C.WoodDark)
	-- a second forge mouth on the south side (the plaza, the hero)
	local ws = face(wing, "Right")
	trim(m, ws * CFrame.new(-0.4, 2.4, -0.2), Vector3.new(2.8, 3.4, 0.4), C.StoneDeep)
	glow(m, ws * CFrame.new(-0.4, 2.2, -0.44), Vector3.new(1.8, 2.2, 0.1), C.Ember)
	-- the stone chimney (light stone, dark cap) with an ember glow at the top
	local stack = wing.cf * CFrame.new(-0.8, 7.6, wing.d / 2 - 1.2)
	Buildings.chimney(m, stack, 8, rng)
	glow(m, stack * CFrame.new(0, 8.45, 0), Vector3.new(1.1, 0.25, 1.1), C.Ember)
	-- an anvil on a stump by the forge mouth
	local anvil = wf * CFrame.new(-2.4, 0, -1.2)
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
		Enum.Material.SmoothPlastic,
		Style.tiny()
	)
	glow(m, body * CFrame.new(0, bh * 0.5, -wd / 2 + 0.02), Vector3.new(0.14, bh * 0.8, 0.08), core)
end

--[[
	GEMS: a wide two-storey City Kit block (building-k) along the forge
	west path: round gunmetal front pillars with orange bands, purple neon
	along the frame, a long lit display case (a Space Station
	table-display-planet and two gems on stands) under a purple
	awning-wide bar, the big GEMS sign with a faceted gem, two tilted
	crystals on the roof and the GEMS blade sign at the front roof corner,
	turned south. Facing east: local +X is south.
]]
Recipes.GemCutter = function(m, fp, site, rng)
	local b = part(fp, -7.45, 7.45, -2.25, 2.7)
	local neon = C.CrystalPurple
	local _, deck =
		Buildings.techShell(m, b, { Floors = 2, Corners = "Round", Neon = neon, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	local shop = Buildings.shopfront(m, front, 0, 11.6, { DoorSide = 1, Neon = neon })
	Buildings.goods(m, shop.Sill * CFrame.new(-2.0, 0, 0), "Planet")
	Buildings.goods(m, shop.Sill * CFrame.new(0, 0, 0), "Gem", C.CrystalPink)
	Buildings.goods(m, shop.Sill * CFrame.new(2.0, 0, 0), "Gem", C.CrystalCyan)
	Buildings.awningWide(m, front, 0, 8.3, 12.2, 1.2, C.AwningPurple)
	Buildings.wallSign(m, front, 0, 11.4, site.Sign or "GEMS", 11.1, 3.6, "Gem", C.CrystalPink, 1.1)
	-- south side (the plaza, the hero): windows on both floors
	local south, sw = face(b, "Right")
	Buildings.windowRow(m, south, floorY(1), 2, sw - 1.8, 2.4)
	Buildings.windowRow(m, south, floorY(2), 2, sw - 1.8, 1.8)
	Buildings.window(m, face(b, "Left"), 0, floorY(2), 1.8, 1.8)
	-- the roof crystals on a steel pedestal
	local base = b.cf * CFrame.new(-3.6, deck, 0.6)
	Style.block(m, base * CFrame.new(0, 0.3, 0), Vector3.new(2.4, 0.6, 2.2), K.Gun, nil, Style.tiny({ CastShadow = true }))
	crystal(m, base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0.08, 0, -0.1), 3.4, 0.95, C.CrystalPurple, C.CrystalPink)
	crystal(m, base * CFrame.new(0.65, 0.5, 0.35) * CFrame.Angles(0, 0, -0.42), 2.2, 0.7, C.CrystalPink, C.FlowerWhite)
	Buildings.vent(m, b.cf * CFrame.new(-6.2, deck, 1.4), rng)
	-- the blade sign at the front roof corner (the south end), facing south
	local at = fp.cf * CFrame.new(5.6, deck, -0.2) * CFrame.Angles(0, -math.pi / 2, 0)
	Buildings.bladeSign(m, at, site.Sign or "GEMS", 6.8, 3.4)
end

--[[
	INN: a gable-front cozy inn (warm cobble with stone blocks and quoins,
	jettied plaster with half-timbering, window boxes, the INN sign with a
	mug across the gable front, a warm brown shingle roof with a red ridge)
	and a one-storey stone cafe wing to the south: a street cafe in front
	of it (a parasol over a round table, stools) and the double-sided INN
	blade sign on its roof, turned south to the spawn and the hero camera.
	Facing west (the forge east path): local +X is north.
]]
Recipes.Inn = function(m, fp, site, rng)
	local b = part(fp, -2.0, 4.5, -4.0, 3.6)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm, StoneFaces = { "Front", "Left" } }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0.6, 0.7, 3, 6.2, C.WoodDark, C.Wood)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper = face(jetty, "Front")
	Buildings.wallSign(m, upper, 0, 11.4, site.Sign or "INN", 4.2, 3.4, "Mug", K.Amber, 0.5)
	Buildings.window(m, upper, 0, H + 1.5, 1.2, 1.2, { Frame = C.WoodDark, Sill = false })
	-- south side (toward the plaza and the hero)
	local south, sw = face(jetty, "Left")
	Buildings.windowRow(m, south, floorY(2), 3, sw - 2.4, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.windowBox(m, south, -2.0, floorY(2) - 1.75, 2.2, C.FlowerPink)
	Buildings.windowBox(m, south, 2.0, floorY(2) - 1.75, 2.2, C.FlowerYellow)
	local north, nw = face(jetty, "Right")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 3, 1.8, { Frame = C.WoodDark, Dark = 2 })
	Buildings.gableRoof(
		m,
		{ cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w },
		H + 0.25,
		4.0,
		K.PlasterWarm,
		K.Shingle,
		C.Roof,
		true
	)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.3, H + 1, 2.4), 4.2, rng)
	-- the cafe wing (south)
	local wing = part(fp, -5.0, -2.1, -0.8, 4.5)
	Style.block(m, wing.cf * CFrame.new(0, 0.32, 0), Vector3.new(wing.w + 0.6, 0.64, wing.d + 0.6), K.StonePlinth, nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 3.25, 0), Vector3.new(wing.w, 6.5, wing.d), Style.vary(K.StoneWarm, rng, 0.03), nil, Style.solid())
	local wf = face(wing, "Front")
	Buildings.window(m, wf, 0, 3.4, 1.7, 2.6, { Frame = C.WoodDark })
	local ws, wsw = face(wing, "Left")
	Buildings.windowRow(m, ws, 3.4, 2, wsw - 1.4, 2.4, { Frame = C.WoodDark })
	local top = Buildings.flatRoof(m, wing, 6.5, C.WoodDark)
	-- the INN blade sign on the wing roof: perpendicular to the facade, facing south (spawn, hero) and north
	local at = wing.cf * CFrame.new(0, top, 0.05) * CFrame.Angles(0, math.pi / 2, 0)
	Buildings.bladeSign(m, at, site.Sign or "INN", 6.6, 3.4)
	-- the street cafe in front of the wing: a parasol over a round table, two stools
	Buildings.parasol(m, fp.cf * CFrame.new(-4.0, 0, -2.2), C.AwningPink, 2.6)
	Buildings.stool(m, (fp.cf * CFrame.new(-5.0, 0, -2.2)).Position)
	Buildings.stool(m, (fp.cf * CFrame.new(-4.0, 0, -3.8)).Position)
end

--[[
	ORE: a three-storey two-tone workshop east of the pink grove (a narrow
	tower on a 7.5 x 5 site): a neon-framed door, the big ORE sign across
	the first storey, a glowing pickaxe emblem and a lit window on the
	third storey, windows on the west side (the grove), and a Space
	Station container-tall tank and a dish antenna on the roof.
	Facing south: local +X is west.
]]
Recipes.OreWorks = function(m, fp, site, rng)
	local b = part(fp, -2.75, 2.75, -1.05, 1.5)
	local _, deck = Buildings.techShell(m, b, { Floors = 3, Out = 0.7, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 0, 4.4, { Glass = false })
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "ORE", 6.2, 3.3, nil, nil, 1.0)
	emblem(m, front, -1.2, floorY(3), 2.4, "Pickaxe", K.Amber, 0.5)
	Buildings.window(m, front, 1.3, floorY(3), 1.5, 1.8)
	local west = face(b, "Right")
	Buildings.window(m, west, 0, floorY(1), 1.2, 2.4)
	Buildings.window(m, west, 0, floorY(2), 1.2, 1.8)
	Buildings.container(m, (b.cf * CFrame.new(1.0, deck, 0)).Position, 3.6, C.Hazard, 1.7)
	Buildings.antenna(m, b.cf * CFrame.new(-1.7, deck, 0.2), 3.2, C.AwningRed)
end

--[[
	WORKS: a long three-storey City Kit building-k workshop on the east
	spur: a lit display case and a door under a City Kit
	overhang-wide tray, the big WORKS sign, window rows on both long sides
	(the north to the spur road, the south to the fossil dig and the hero),
	and on the roof a jib crane lifting a crate and two Space Station
	container-tall tanks. Facing north (the spur road): local +X is east.
]]
Recipes.SpurWorkshop = function(m, fp, site, rng)
	local b = part(fp, -6.6, 6.6, -0.8, 1.35)
	local _, deck = Buildings.techShell(m, b, { Floors = 3, Out = 0.6, NeonFaces = { "Front", "Back" } }, rng)
	local front, fw = face(b, "Front")
	local shop = Buildings.shopfront(m, front, -2.4, 6.6, { DoorSide = 1 })
	Buildings.goods(m, shop.Sill, "Ingot")
	Buildings.overhang(m, front, -2.4, 8.25, 7.2, 0.9, K.PanelLight)
	Buildings.window(m, front, 3.6, floorY(1), 2.0, 2.4)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "WORKS", 9.8, 3.4, "Hammer", K.Amber, 0.86)
	Buildings.windowRow(m, front, floorY(3), 4, fw - 2.0, 1.8)
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(1), 2, 6.0, 2.4)
	Buildings.windowRow(m, back, floorY(2), 3, bw - 3.2, 1.8, { Dark = 3 })
	Buildings.windowRow(m, back, floorY(3), 3, bw - 3.2, 1.8)
	-- the rooftop crane (boom along the roof toward the east) and two tanks
	Buildings.crane(m, b.cf * CFrame.new(-4.6, deck, 0) * CFrame.Angles(0, -math.pi / 2, 0), 4, 7)
	Buildings.container(m, (b.cf * CFrame.new(3.6, deck, 0)).Position, 3.0, C.CrystalBlue, 1.6)
	Buildings.container(m, (b.cf * CFrame.new(5.5, deck, 0)).Position, 2.4, C.Hazard, 1.6)
end

--[[
	A narrow three-storey row house on the east plot road (the hero's right
	side, between the spur and the LAB): a column of lit windows on the
	south end (the hero), and on the long west side (the koi pond and the
	plaza) a door and a lit display case under a red awning-wide bar, two
	window rows and a hanging blue banner; a water tank on the roof.
	Facing south: local +X is west.
]]
Recipes.EastRow = function(m, fp, _site, rng)
	local b = part(fp, -1.5, 1.3, -4.5, 4.5)
	local _, deck = Buildings.techShell(m, b, { Floors = 3, Out = 0.6, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.window(m, front, 0, floorY(1), 1.2, 2.6)
	Buildings.window(m, front, 0, floorY(2), 1.2, 1.8)
	Buildings.window(m, front, 0, floorY(3), 1.2, 1.8)
	local west = face(b, "Right")
	local shop = Buildings.shopfront(m, west, 0.4, 7.0, { DoorSide = -1 })
	Buildings.goods(m, shop.Sill * CFrame.new(-0.5, 0, 0), "Ingot")
	Buildings.goods(m, shop.Sill * CFrame.new(0.7, 0, 0), "Flask", C.CrystalPink)
	Buildings.awningWide(m, west, 0.4, 8.3, 7.6, 1.0, C.AwningRed)
	Buildings.windowRow(m, west, floorY(2), 3, 6.0, 1.8, { X = 0.9 })
	Buildings.windowRow(m, west, floorY(3), 3, 6.0, 1.8, { X = 0.9, Dark = 2 })
	Buildings.banner(m, west, -3.2, 16.4, 1.4, 5.6, C.CrystalBlue, 0.6)
	Buildings.waterTank(m, b.cf * CFrame.new(0, deck, 1.8), 2.4)
end

--[[
	LAB: a two-storey City Kit block by the ROCK SCANNER path with a
	shopfront to the south (the hero): a door and a lit display case with a
	flask under a red awning-wide bar, the LAB sign with a flask across the
	first storey, a second display case with a table-display-planet on the
	west side, window rows, a Space Station tank and a dish antenna on the
	roof, and a street cafe parasol in front. Facing south: local +X is west.
]]
Recipes.CityBlock = function(m, fp, site, rng)
	local b = part(fp, -3.4, 3.4, -0.4, 3.15)
	local _, deck = Buildings.techShell(m, b, { Floors = 2, Out = 0.8, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	local shop = Buildings.shopfront(m, front, 0, 5.8, { DoorSide = 1 })
	Buildings.goods(m, shop.Sill, "Flask", C.CrystalCyan)
	Buildings.awningWide(m, front, 0, 8.3, 6.6, 1.1, C.AwningRed)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "LAB", 4.9, 3.6, "Flask", C.CrystalCyan, 1.15)
	local west = face(b, "Right")
	local case = Buildings.shopfront(m, west, 0, 2.6, { Door = false })
	Buildings.goods(m, case.Sill, "Planet")
	Buildings.windowRow(m, west, floorY(2), 2, 2.6, 1.8)
	Buildings.windowRow(m, face(b, "Back"), floorY(2), 3, 5.8, 1.8)
	Buildings.window(m, face(b, "Left"), 0, floorY(2), 1.4, 1.8)
	-- roof: a Space Station tank and a dish antenna
	Buildings.container(m, (b.cf * CFrame.new(1.8, deck, 0.4)).Position, 3.0, C.CrystalCyan, 1.7)
	Buildings.antenna(m, b.cf * CFrame.new(-2.0, deck, 0.6), 2.6, C.AwningRed)
	-- the street cafe in front of the display case
	Buildings.parasol(m, fp.cf * CFrame.new(-2.2, 0, -2.9), C.AwningRed, 2.6)
	Buildings.stool(m, (fp.cf * CFrame.new(-3.6, 0, -2.9)).Position)
end

--[[
	Depot in the hero's right corner: a three-storey two-tone block with
	round gunmetal front pillars (orange bands), an orange roll-up loading
	bay in a neon frame, window rows to the street and to the hero, a water
	tank and a container-tall on the roof. Facing west: local +X is north.
]]
Recipes.Depot = function(m, fp, _site, rng)
	local b = part(fp, -4.7, 4.7, -2.45, 2.45)
	local _, deck = Buildings.techShell(m, b, { Floors = 3, Corners = "Round", NeonFaces = { "Front", "Left" } }, rng)
	local front, fw = face(b, "Front")
	Buildings.shopfront(m, front, 1.2, 4.4, { Bay = true })
	Buildings.window(m, front, -2.3, floorY(1), 1.1, 2.6)
	Buildings.windowRow(m, front, floorY(2), 4, fw - 2.8, 1.8, { Dark = 3 })
	Buildings.windowRow(m, front, floorY(3), 4, fw - 2.8, 1.8)
	local south = face(b, "Left")
	Buildings.windowRow(m, south, floorY(1), 2, 3.6, 2.4)
	Buildings.windowRow(m, south, floorY(2), 2, 3.6, 1.8, { Frame = C.Hazard })
	Buildings.windowRow(m, south, floorY(3), 2, 3.6, 1.8)
	Buildings.waterTank(m, b.cf * CFrame.new(-2.0, deck, 0.4), 2.6)
	Buildings.container(m, (b.cf * CFrame.new(2.4, deck, 0.6)).Position, 3.0, C.Hazard)
end

--[[
	A cozy garden cottage beside the south road (concept v1): warm cobble
	with stone blocks and quoins, jettied plaster upper floor with
	half-timbering, window boxes, a caged lantern, a terracotta roof with
	the ridge along the front; a garden fence and flower beds in front, a
	stepping-stone path to the road, a small shed and barrels.
	Facing north (the town): local +X is east.
]]
Recipes.GardenCottage = function(m, fp, _site, rng)
	local b = part(fp, -2.1, 5.9, 1.8, 7.0)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.Plaster, StoneFaces = { "Front", "Left" } }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 1.4, 0.7, 3, 6.2, C.WoodDark, C.Wood)
	Buildings.window(m, front, -1.8, floorY(1), 1.8, 2.4, { Frame = C.WoodDark })
	Buildings.hangingLantern(m, front, -0.1, 7.6)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(2), 2, uw - 3, 1.8, { Frame = C.WoodDark, Sill = false })
	Buildings.windowBox(m, upper, -1.6, floorY(2) - 1.75, 2.2, C.FlowerPink)
	Buildings.windowBox(m, upper, 1.6, floorY(2) - 1.75, 2.2, C.FlowerPurple)
	local back, bw = face(jetty, "Back")
	Buildings.windowRow(m, back, floorY(2), 2, bw - 3, 1.8, { Frame = C.WoodDark })
	Buildings.window(m, face(jetty, "Left"), 0, floorY(2), 1.4, 1.8, { Frame = C.WoodDark })
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
