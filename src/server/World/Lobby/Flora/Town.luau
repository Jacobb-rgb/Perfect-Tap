--[[
	Flora town buildings: 10 houses and workshops on the free ground
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
	                mine hill; lit windows, timber framing and a blade sign
	                on its street side), and the wide two-storey CARTS shop
	                under a slate gable roof facing the west spur
	  behind SHOP   nothing: the SPIN & WIN wheel stands free there (the
	                Smithy is gone, its red roof hid the wheel's stairs)
	  behind UPGR.  the INN (a street parasol), front to the forge east
	                path, and the two-storey ORE workshop east of the pink
	                grove under a low module roof
	  east strip    the two-storey MAP house with a steep slate roof in the
	                east tree belt and the WORKS workshop south of it under a
	                shingle roof (a little street along the east plot road;
	                every ridge under SHOP's 20 studs: the stalls and the
	                forge lead the skyline)
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
	{ Id = "CartShop", Min = Vector2.new(-63, 8), Max = Vector2.new(-52, 14), Facing = "N", Recipe = "CartShop", Sign = "CARTS" },
	{ Id = "Lodge", Min = Vector2.new(-63, 54), Max = Vector2.new(-58, 63), Facing = "W", Recipe = "Lodge" },
	{
		Id = "ToolShop",
		Min = Vector2.new(-63, 64),
		Max = Vector2.new(-56, 72.5),
		Facing = "E",
		Recipe = "ToolShop",
		Sign = "TOOLS",
	},
	{ Id = "MineCottage", Min = Vector2.new(-63, 74), Max = Vector2.new(-58.5, 88), Facing = "W", Recipe = "MineCottage" },
	-- behind UPGRADES, beside the forge east path (the pink grove behind it), and ORE east of the grove
	{ Id = "Inn", Min = Vector2.new(33, -54), Max = Vector2.new(44, -43), Facing = "W", Recipe = "Inn", Sign = "INN" },
	{ Id = "OreWorks", Min = Vector2.new(55.5, -71), Max = Vector2.new(63, -66), Facing = "S", Recipe = "OreWorks", Sign = "ORE" },
	-- the east strip: the MAP house in the east tree belt, south of the red
	-- tree, and the WORKS workshop south of it (a little street; the FOSSIL
	-- DIG turned toward the hero camera took WORKS' old spot on the east spur)
	{ Id = "MapTower", Min = Vector2.new(54, 90), Max = Vector2.new(63, 100), Facing = "W", Recipe = "MapTower", Sign = "MAP" },
	{ Id = "SpurWorkshop", Min = Vector2.new(48.5, 103), Max = Vector2.new(63, 107.5), Facing = "S", Recipe = "SpurWorkshop", Sign = "WORKS" },
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
	MAP: the cartographer's house in the east tree belt: two two-tone
	storeys (gunmetal frame, light steel panels, a red band, blue neon on
	the street and hero sides), a door with a glowing map screen, the big
	MAP sign across the first storey, window rows on the long sides, and a
	steep dark slate gable roof (ridge under 20 studs, its gables to the
	north and to the south, a lit window in the south gable, a red beacon
	on the ridge). Facing west: local +X is north.
]]
Recipes.MapTower = function(m, fp, site, rng)
	local tower = part(fp, -3.7, 3.7, -2.75, 3.2)
	local out = Buildings.Out
	local H = Buildings.techShell(m, tower, { Floors = 2, Cornice = false, Accent = C.AwningRed, NeonFaces = { "Front", "Left" } }, rng)
	local front = face(tower, "Front")
	-- (round 3: a warm amber door frame, the full-height blue neon frame clashed)
	Buildings.shopfront(m, front, -1.0, 3.7, { Glass = false, DoorSide = -1, Neon = K.LampAmber })
	Buildings.displayWall(m, front, 2.05, 4.4, 1.0, 2.6)
	-- the big MAP sign across the first storey (to the street and the scanner path)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "MAP", 5.5, 3.6, "Compass", K.Amber, 1.0)
	local south, sw = face(tower, "Left")
	Buildings.windowRow(m, south, floorY(1), 2, sw - 2.2, 2.4)
	Buildings.windowRow(m, south, floorY(2), 2, sw - 2.2, 1.8)
	local north, nw = face(tower, "Right")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 2.2, 1.8, { Dark = 2 })
	Buildings.window(m, face(tower, "Back"), 0, floorY(2), 1.6, 1.8)
	-- the steep dark slate roof (ridge north-south), a lit window in the south gable
	local roof = Buildings.sub(tower, 0, 0, tower.w + 2 * out - 0.4, tower.d + 2 * out - 0.5)
	Buildings.gableRoof(m, roof, H + 0.2, 4.6, K.PanelLight, K.SlateDark, C.RoofTerracottaDark, true)
	local gable = face(roof, "Left")
	Buildings.window(m, gable, 0, H + 1.7, 1.1, 1.1, { Sill = false, Mullion = false })
	glow(m, tower.cf * CFrame.new(0, H + 5.25, 0), Vector3.new(0.3, 0.3, 0.3), C.AwningRed)
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
	-- the street side (west, the plot road): dark timber framing, two lit
	-- windows and a second TOOLS sign with the pickaxe (no blank back)
	local street, stw = face(b, "Back")
	Buildings.window(m, street, -1.35, floorY(1), 1.4, 2.4, { Frame = C.WoodDark })
	Buildings.window(m, street, 1.35, floorY(1), 1.4, 2.4, { Frame = C.WoodDark })
	for _, x in { -stw / 2 + 0.35, 0, stw / 2 - 0.35 } do
		trim(m, street * CFrame.new(x, 4.0, -0.2), Vector3.new(0.45, 7.6, 0.3), C.WoodDark)
	end
	trim(m, street * CFrame.new(0, 7.95, -0.2), Vector3.new(stw, 0.45, 0.3), C.WoodDark)
	Buildings.wallSign(m, street, 0, 11.0, site.Sign or "TOOLS", 4.2, 3.2, "Pickaxe", K.Amber, 0.72).Name = "StreetSign"
	-- the setback third storey on the north half
	local up = Buildings.sub(fp, -0.9, 0, 3.4, 4.0)
	local top = Buildings.setback(m, up, deck, 5, rng, { "Front", "Right" })
	local raised = Buildings.raise(up, deck)
	Buildings.window(m, face(raised, "Front"), 0, 2.7, 1.6, 1.6)
	Buildings.window(m, face(raised, "Right"), 0, 2.7, 1.8, 1.6)
	Buildings.vent(m, b.cf * CFrame.new(1.8, deck, 0.4), rng)
	local _ = top
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
	local H =
		Buildings.cozyShell(m, b, { Floors = 3, Plaster = K.PlasterWarm, Timbering = 3, StoneFaces = { "Front", "Back", "Left" } }, rng)
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
	Buildings.gableRoof(m, jetty, H + 0.25, 4.2, K.PlasterWarm, C.RoofTerracotta, C.RoofTerracottaDark, true)
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
	local H = Buildings.cozyShell(m, b, { Floors = 3, Plaster = K.Plaster, Timbering = 4, StoneFaces = { "Front", "Back", "Left" } }, rng)
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
	Buildings.gableRoof(m, jetty, H + 0.25, 4.2, K.Plaster, K.Shingle, C.RoofTerracottaDark, true)
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
	local b = part(fp, -4.6, 4.6, -1.3, 2.1)
	local out = 0.7
	local H = Buildings.techShell(m, b, { Floors = 2, Out = out, Cornice = false, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 1.6, 4.6, { Bay = true })
	Buildings.window(m, front, -2.9, floorY(1), 1.6, 2.4)
	Buildings.awningWide(m, front, 0, 8.3, 8.6, 1.0, C.CrystalBlue)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "CARTS", 6.6, 3.3, "Cart", K.Amber, 1.0)
	-- lit windows on both sides (the wheel, lobby_west; the plot road)
	local east, ew = face(b, "Right")
	Buildings.windowRow(m, east, floorY(1), 2, ew - 1.4, 2.2)
	Buildings.window(m, east, 0, floorY(2), 1.4, 1.8)
	local west, ww = face(b, "Left")
	Buildings.windowRow(m, west, floorY(2), 2, ww - 1.4, 1.8)
	-- a dark slate gable roof, ridge along the front
	local roof = Buildings.sub(b, 0, 0, b.w + 2 * out - 0.8, b.d + 2 * out - 1.0)
	Buildings.gableRoof(m, roof, H + 0.2, 2.8, K.PanelLight, K.SlateDark, C.RoofTerracottaDark, true)
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
	-- the INN sign on two gunmetal brackets off the wall (the big neon mug on it)
	for _, y in { 9.2, 13.62 } do
		trim(m, upper * CFrame.new(0, y, -0.34), Vector3.new(5.4, 0.3, 0.6), K.Gun)
	end
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
		C.RoofTerracottaDark,
		true
	)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.3, H + 1, 2.4), 4.2, rng)
	-- the cafe wing (south)
	local wing = part(fp, -5.0, -2.1, -0.8, 4.5)
	Style.block(m, wing.cf * CFrame.new(0, 0.32, 0), Vector3.new(wing.w + 0.6, 0.64, wing.d + 0.6), K.StonePlinth, nil, Style.solid())
	Style.block(
		m,
		wing.cf * CFrame.new(0, 3.25, 0),
		Vector3.new(wing.w, 6.5, wing.d),
		Style.vary(K.StoneWarm, rng, 0.03),
		nil,
		Style.solid()
	)
	local wf = face(wing, "Front")
	Buildings.window(m, wf, 0, 3.4, 1.7, 2.6, { Frame = C.WoodDark })
	local ws, wsw = face(wing, "Left")
	Buildings.windowRow(m, ws, 3.4, 2, wsw - 1.4, 2.4, { Frame = C.WoodDark })
	local top = Buildings.flatRoof(m, wing, 6.5, C.WoodDark)
	-- the INN blade sign on the wing roof: perpendicular to the facade, facing south (spawn, hero) and north
	if site.Blade then
		local at = wing.cf * CFrame.new(0, top, 0.05) * CFrame.Angles(0, math.pi / 2, 0)
		Buildings.bladeSign(m, at, site.Sign or "INN", 6.6, 3.4)
	end
	-- the street cafe in front of the wing: a parasol over a round table, two stools
	Buildings.parasol(m, fp.cf * CFrame.new(-3.6, 0, -3.4), C.AwningPink, 2.6)
	Buildings.stool(m, (fp.cf * CFrame.new(-4.7, 0, -3.4)).Position)
	Buildings.stool(m, (fp.cf * CFrame.new(-2.5, 0, -3.6)).Position)
end

--[[
	ORE: a two-storey two-tone workshop east of the pink grove (a narrow
	block on a 7.5 x 5 site) under a low concept v2 module roof: a
	neon-framed door, the big ORE sign across the first storey, a copper
	band, a glowing pickaxe emblem and lit windows on the sides, and a
	Space Station container-tall tank and a dish antenna on the roof deck
	(everything under 20 studs). Facing south: local +X is west.
]]
Recipes.OreWorks = function(m, fp, site, rng)
	local b = part(fp, -2.75, 2.75, -1.05, 1.5)
	local _, deck = Buildings.techShell(m, b, { Floors = 2, Out = 0.7, Accent = C.Copper, NeonFaces = { "Front", "Right" } }, rng)
	local front = face(b, "Front")
	Buildings.shopfront(m, front, 0, 4.4, { Glass = false })
	-- the sign sits low on the first storey: from the hero camera it stays under UPGRADES' roofline
	Buildings.wallSign(m, front, 0, 9.4, site.Sign or "ORE", 6.2, 3.3, nil, nil, 1.0)
	local west = face(b, "Right")
	Buildings.window(m, west, 0, floorY(1), 1.2, 2.4)
	emblem(m, west, 0, floorY(2), 2.2, "Pickaxe", K.Amber, 0.5)
	local east = face(b, "Left")
	Buildings.window(m, east, 0, floorY(1), 1.2, 2.4)
	Buildings.window(m, east, 0, floorY(2), 1.2, 1.8)
	Buildings.container(m, (b.cf * CFrame.new(1.0, deck, 0)).Position, 3.0, C.Hazard, 1.7)
	Buildings.antenna(m, b.cf * CFrame.new(-1.7, deck, 0.2), 2.4, C.AwningRed)
end

--[[
	WORKS: a long two-storey City Kit building-k workshop on the east
	spur under a warm brown shingle gable roof (gables to the east and the
	west, a stone chimney): a lit display case and a door under a City Kit
	overhang-wide tray, the big WORKS sign, a blue band, windows on both
	long sides (the north to the spur road, the south to the fossil dig
	and the hero). Facing north (the spur road): local +X is east.
]]
Recipes.SpurWorkshop = function(m, fp, site, rng)
	local b = part(fp, -6.4, 6.4, -0.8, 1.35)
	local out = 0.6
	local H =
		Buildings.techShell(m, b, { Floors = 2, Out = out, Cornice = false, Accent = C.CrystalBlue, NeonFaces = { "Front", "Back" } }, rng)
	local front = face(b, "Front")
	local shop = Buildings.shopfront(m, front, -2.0, 6.6, { DoorSide = 1 })
	Buildings.goods(m, shop.Sill, "Ingot")
	Buildings.overhang(m, front, -2.0, 8.25, 7.2, 0.9, K.PanelLight)
	Buildings.window(m, front, 3.6, floorY(1), 2.0, 2.4)
	Buildings.wallSign(m, front, 0, 11.35, site.Sign or "WORKS", 8.7, 3.4, "Hammer", K.Amber, 0.86)
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(1), 2, 6.0, 2.4)
	Buildings.windowRow(m, back, floorY(2), 3, bw - 3.2, 1.8, { Dark = 3 })
	-- the low shingle roof along the building and a stone chimney at its east end
	local roof = Buildings.sub(b, 0, 0, b.w + 2 * out - 0.4, b.d + 2 * out - 0.5)
	Buildings.gableRoof(m, roof, H + 0.2, 2.4, K.PanelLight, K.Shingle, C.RoofTerracottaDark, true)
	Buildings.chimney(m, b.cf * CFrame.new(4.4, H + 0.6, 0.3), 3.0, rng)
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
	Buildings.gableRoof(m, jetty, H + 0.25, 3.6, K.Plaster, C.RoofTerracotta, C.RoofTerracottaDark)
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

---------------------------------------------------------------- the west street

--[[
	The west street (round 2): the west plot road's town side dressed like a
	street: double-headed lamp posts every ~12 studs (amber Neon heads, no
	lights), a gold ore cart, barrels, crates and flower boxes by the house
	fronts. All of it 1.5+ studs off the road's edge (x -64.2, the road edge
	is x -65.5) and clear of the doors.
]]
Town.StreetX = -64.2
Town.StreetLampZ = { 18, 30, 42, 66, 90, 102 }
local function streetLamp(m: Instance, foot: Vector3)
	trim(m, CFrame.new(foot + Vector3.new(0, 2.6, 0)), Vector3.new(0.45, 5.2, 0.45), K.Gun).Name = "LampPost"
	trim(m, CFrame.new(foot + Vector3.new(0, 5.15, 0)), Vector3.new(0.3, 0.3, 2.6), K.Gun)
	for _, dz in { -1.15, 1.15 } do
		local head = glow(m, CFrame.new(foot + Vector3.new(0, 4.75, dz)), Vector3.new(0.5, 0.55, 0.5), K.LampAmber)
		head.Name = "LanternGlow"
		trim(m, CFrame.new(foot + Vector3.new(0, 5.15, dz)), Vector3.new(0.8, 0.2, 0.8), K.Metal)
	end
end

function Town.street(parent: Instance, rng: Rng.Rng)
	local m = Style.model("WestStreet", parent)
	local x = Town.StreetX
	for _, z in Town.StreetLampZ do
		streetLamp(m, Vector3.new(x, 0, z))
	end
	-- an ore cart heaped with gold, barrels and crates, flower boxes
	Buildings.cart(m, CFrame.new(x + 0.2, 0, 47.5), C.Gold)
	Buildings.barrel(m, Vector3.new(x + 0.1, 0, 52.4), rng)
	Buildings.barrel(m, Vector3.new(x + 0.3, 0, 54.0), rng, 1.6)
	Buildings.crate(m, CFrame.new(x + 0.2, 0, 76.2), 1.6, rng)
	Buildings.crate(m, CFrame.new(x + 0.4, 0, 77.9), 1.2, rng)
	flowerBed(m, CFrame.new(x + 0.3, 0, 36.5) * CFrame.Angles(0, math.pi / 2, 0), C.FlowerPink)
	flowerBed(m, CFrame.new(x + 0.3, 0, 96.5) * CFrame.Angles(0, math.pi / 2, 0), C.FlowerYellow)
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
	Town.street(parent, Kit.sub(rng))
end

return Town
