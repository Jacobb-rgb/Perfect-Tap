--[[
	Flora town buildings: houses, workshops and towers on the free ground
	the lobby cameras see, so the hero view reads as a dense town
	(docs/art/lobby_concept.webp) in the concept v2 building language
	(docs/art/lobby_concept_v2.webp: dark charcoal metal, blue neon
	outlines, warm lit windows, dark navy neon signs with icons) mixed with
	the cozy stone-and-timber houses of concept v1. Shapes after Kenney's
	City Kit commercial and Space Station Kit (docs/art/kenney_refs/*.jpg),
	built from parts by Flora/Buildings.luau.

	Where they stand (each site checked against the gameplay signs from the
	lobby_hero / spawn / west / east / south cameras):
	  west strip    TOOLS tower (tall end north of the CAPSULES line of
	                sight), the MAP lookout tower at the hero's left edge
	  behind SHOP   the Smithy, forge mouth toward the forge west path; the
	                GEMS workshop behind it along the path
	  behind UPGR.  the INN, front to the forge east path, the pink grove
	                behind it
	  east          the ORE tower by the east spur, a small workshop across
	                the spur, a City Kit block by the ROCK SCANNER path, the
	                depot in the hero's right foreground
	  south         the mine cottage and a garden cottage by the south road

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
}

-- Rail line of the plots' train stops (BaseLayout.RailZ = 62 plot-local).
Town.RailMinX = 160

-- Clear ground in front of every facade (studs).
Town.FrontClearance = 6

Town.Sites = {
	-- west strip along the west plot road (the hero's left side)
	{ Id = "ToolShop", Min = Vector2.new(-63, 28), Max = Vector2.new(-55, 38), Facing = "E", Recipe = "ToolShop", Sign = "TOOLS" },
	{ Id = "MapTower", Min = Vector2.new(-63, 54), Max = Vector2.new(-58, 65), Facing = "E", Recipe = "MapTower", Sign = "MAP" },
	-- behind the SHOP, beside the forge west path
	{ Id = "Smithy", Min = Vector2.new(-44, -58), Max = Vector2.new(-35, -44), Facing = "E", Recipe = "Smithy" },
	{ Id = "GemCutter", Min = Vector2.new(-41, -81.5), Max = Vector2.new(-33, -64), Facing = "E", Recipe = "GemCutter", Sign = "GEMS" },
	-- behind UPGRADES, beside the forge east path (the pink grove behind it)
	{ Id = "Inn", Min = Vector2.new(33, -54), Max = Vector2.new(44, -43), Facing = "W", Recipe = "Inn", Sign = "INN" },
	-- east strip and the east spur
	{ Id = "OreTower", Min = Vector2.new(57, -13), Max = Vector2.new(63, -8), Facing = "S", Recipe = "OreTower", Sign = "ORE" },
	{ Id = "SpurWorkshop", Min = Vector2.new(50, 8), Max = Vector2.new(58, 12.5), Facing = "N", Recipe = "SpurWorkshop" },
	{ Id = "CityBlock", Min = Vector2.new(41, 66), Max = Vector2.new(52.5, 71), Facing = "N", Recipe = "CityBlock" },
	{ Id = "Depot", Min = Vector2.new(56, 96), Max = Vector2.new(63, 108), Facing = "W", Recipe = "Depot" },
	-- south meadow
	{ Id = "MineCottage", Min = Vector2.new(-30, 100), Max = Vector2.new(-13, 113), Facing = "N", Recipe = "MineCottage" },
	{ Id = "GardenCottage", Min = Vector2.new(14, 102), Max = Vector2.new(26, 112), Facing = "N", Recipe = "GardenCottage" },
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
local G, U = Buildings.Ground, Buildings.Upper

-- A crate on the ground (`at` = ground point in the frame). 3 parts.
local function crate(m: Instance, at: CFrame, s: number, rng: Rng.Rng)
	local cf = at * CFrame.Angles(0, rng:range(-0.2, 0.2), 0)
	local props = if s < 1.2 then Style.tiny() else Style.decor()
	Style.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), Style.vary(C.WoodLight, rng, 0.05), nil, props)
	Style.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s + 0.1, s * 0.2, s + 0.1), C.WoodDark, nil, Style.tiny())
	Style.block(m, cf * CFrame.new(0, s / 2, 0), Vector3.new(s * 0.2, s + 0.1, s + 0.1), C.WoodDark, nil, Style.tiny())
end

-- A small lamp post without a light (dark post, glowing box, cap). 3 parts.
local function lampPost(m: Instance, at: CFrame, h: number)
	Style.block(m, at * CFrame.new(0, h / 2, 0), Vector3.new(0.5, h, 0.5), K.Metal, nil, Style.decor())
	local g = glow(m, at * CFrame.new(0, h + 0.45, 0), Vector3.new(0.7, 0.9, 0.7), C.Lamp)
	g.Name = "LanternGlow"
	Style.block(m, at * CFrame.new(0, h + 1.05, 0), Vector3.new(1.1, 0.3, 1.1), K.Metal, nil, Style.tiny())
end

---------------------------------------------------------------- recipes

local Recipes: { [string]: (m: Model, fp: Buildings.Body, site: Site, rng: Rng.Rng) -> () } = {}

--[[
	TOOLS: a three-storey tech block with a two-storey setback box on the
	back of its roof (City Kit building-d) at the north end of the site,
	the TOOLS sign with crossed hammers on the front roof deck; the south
	end is the shop's yard (a container-tall, crates), kept low so the
	CAPSULES stall in front keeps a clear backdrop from the plaza.
	Facing east: local +X is south.
]]
Recipes.ToolShop = function(m, fp, site, rng)
	local b = part(fp, -4.4, 0.1, -2.7, 3.3)
	local H = Buildings.techShell(m, b, { Floors = 3, Accent = C.Hazard, Lines = true }, rng)
	local front, fw = face(b, "Front")
	-- wall-door-wide-banner: an orange framed shop door, a banner window beside it
	Buildings.door(m, front, 0.6, 0.6, 1.6, 4.2, C.Hazard, K.DoorLeaf, K.EdgeNeon)
	Buildings.window(m, front, -1.3, floorY(1), 0.8, 2.2, C.Hazard, true)
	for f = 2, 3 do
		Buildings.windowRow(m, front, floorY(f), 2, fw - 1.6, 1.6, K.Metal)
	end
	-- north side (seen from the plaza / lobby_west) and south side (seen from the hero)
	local left, lw = face(b, "Left")
	local right, rw = face(b, "Right")
	for f = 2, 3 do
		Buildings.windowRow(m, right, floorY(f), 2, rw - 1.8, 1.6, K.Metal)
		Buildings.windowRow(m, left, floorY(f), 2, lw - 1.8, 1.6, K.Metal)
	end
	Buildings.banner(m, right, 0, G - 2.2, 2, 4.2, C.AwningRed)
	local deck = Buildings.flatRoof(m, b, H, K.EdgeNeon)
	-- the setback box on the back of the roof
	local up = Buildings.sub(b, -0.4, 1, b.w - 1.6, b.d - 2.4)
	local top = Buildings.setback(m, up, deck, 2, K.Panel, rng)
	for i = 0, 1 do
		local y = deck + U * (i + 0.5)
		Buildings.windowRow(m, face(up, "Front"), y, 2, up.w - 1, 1.5, K.Metal)
		Buildings.window(m, face(up, "Right"), 0, y, 1.3, 1.5, K.Metal)
	end
	local roof = Buildings.flatRoof(m, up, top, K.EdgeNeon)
	Buildings.antenna(m, up.cf * CFrame.new(1, roof, 0), 3.6, K.EdgeNeon)
	Buildings.vent(m, up.cf * CFrame.new(-0.8, roof, 0.2), rng)
	Buildings.roofSign(m, b.cf * CFrame.new(0.75, deck, -b.d / 2 + 0.6), site.Sign or "TOOLS", 4.2, 2.3, "CrossedHammers", K.Amber)
	-- the yard: a Space Station container-tall and crates
	local yard = fp.cf * CFrame.new(3.4, 0, -1.2)
	Buildings.container(m, yard.Position, 4, C.Hazard)
	crate(m, fp.cf * CFrame.new(3.6, 0, 1.6), 1.6, rng)
	crate(m, fp.cf * CFrame.new(3.4, 1.6, 1.5), 1.1, rng)
end

--[[
	MAP: the cartographer's lookout at the hero's left edge, a five-storey
	tower with orange banner window frames (Space Station), the MAP sign
	with a compass high on its front, a lantern room on the roof (a metal
	frame, four warm panes around a dark core), a stepped cap and a beacon
	mast; a two-storey block with a shop window and a water tank at the
	south end. Both volumes ~cubic (4.9 x 3.8). Facing east (the corridor):
	local +X is south.
]]
Recipes.MapTower = function(m, fp, site, rng)
	local tower = part(fp, -4.75, 0.15, -1.45, 1.95)
	local H = Buildings.techShell(m, tower, { Floors = 5, Accent = C.Hazard, Lines = true }, rng)
	local front = face(tower, "Front")
	Buildings.door(m, front, 0, 0.6, 1.8, 4.2, K.Metal, K.DoorLeaf, K.EdgeNeon)
	for f = 2, 4 do
		Buildings.window(m, front, 0, floorY(f), 1.8, 1.8, C.Hazard)
	end
	Buildings.wallSign(m, front, 0, floorY(5), site.Sign or "MAP", 2.4, 1.8, "Compass", K.Amber, 0.3)
	local left, lw = face(tower, "Left")
	for f = 3, 5 do
		Buildings.windowRow(m, left, floorY(f), 2, lw - 1.6, 1.7, K.Metal)
	end
	local right = face(tower, "Right")
	for f = 4, 5 do
		Buildings.window(m, right, 0.3, floorY(f), 1.4, 1.7, K.Metal)
	end
	Buildings.pipe(m, right, -1.2, G + U, H - 0.6)
	local deck = Buildings.flatRoof(m, tower, H, K.EdgeNeon)
	-- lantern room: a dark core, four warm panes, corner posts, a stepped cap
	local s = tower.d - 0.2
	local look = tower.cf * CFrame.new(0, deck, 0)
	Style.block(m, look * CFrame.new(0, 1.1, 0), Vector3.new(s - 0.5, 2.2, s - 0.5), K.Metal, nil, Style.tiny())
	for i = 0, 3 do
		local side = look * CFrame.Angles(0, i * math.pi / 2, 0)
		local pane = glow(m, side * CFrame.new(0, 1.1, -(s - 0.5) / 2 - 0.05), Vector3.new(s - 1.4, 1.4, 0.1), K.Window)
		pane.Name = "WindowGlow"
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Style.block(m, look * CFrame.new(sx * s / 2, 1.2, sz * s / 2), Vector3.new(0.45, 2.4, 0.45), K.Metal, nil, Style.tiny())
		end
	end
	local cap = Buildings.steppedRoof(m, Buildings.sub(tower, 0, 0, s, s), deck + 2.4, 2, { K.Metal, K.SlateLight })
	Buildings.antenna(m, tower.cf * CFrame.new(0, cap, 0), 4, C.AwningRed)
	-- the low south block
	local low = part(fp, 0.6, 4.9, -1.25, 1.95)
	local h2 = Buildings.techShell(m, low, { Floors = 2, Accent = C.Hazard, Corners = "None" }, rng)
	local lf, lfw = face(low, "Front")
	Buildings.display(m, lf, 0, floorY(1), lfw - 1.6, 2.4, C.CrystalBlue)
	Buildings.overhang(m, lf, 0, G - 2, lfw - 0.4, 0.8, K.Metal, false, K.EdgeNeon)
	Buildings.windowRow(m, lf, floorY(2), 2, lfw - 1.2, 1.7, K.Metal)
	Buildings.window(m, face(low, "Right"), 0, floorY(2), 1.6, 1.7, K.Metal)
	local top = Buildings.flatRoof(m, low, h2)
	Buildings.waterTank(m, low.cf * CFrame.new(0.4, top, 0.2), 2.4)
end

--[[
	Smithy: a cozy two-storey house (stone ground floor, jettied plaster
	upper floor with half-timbering, slate roof, window boxes, a hanging
	lantern) and a stone forge wing at the south end whose glowing forge
	mouth faces the forge west path; a second opening glows toward the
	plaza. Facing east: local +X is south.
]]
Recipes.Smithy = function(m, fp, _site, rng)
	local house = part(fp, -5.7, 0.9, -3, 3.4)
	local H = Buildings.cozyShell(m, house, { Floors = 2 }, rng)
	local front = face(house, "Front")
	Buildings.door(m, front, -1.6, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, 1.9, floorY(1), 1.8, 2.2, C.WoodDark)
	Buildings.hangingLantern(m, front, -3.3, 5.3)
	local jetty = Buildings.sub(house, 0, 0, house.w + 0.5, house.d + 0.5)
	local upper = face(jetty, "Front")
	for _, x in { -1.9, 1.9 } do
		Buildings.window(m, upper, x, floorY(2), 1.6, 1.7, C.WoodDark)
		Buildings.windowBox(m, upper, x, floorY(2) - 1.55, 2.4, if x < 0 then C.FlowerRed else C.FlowerYellow)
	end
	local north, nw = face(jetty, "Left")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 2.6, 1.7, C.WoodDark)
	local south = face(jetty, "Right")
	Buildings.window(m, south, 0, floorY(2), 1.6, 1.7, C.WoodDark)
	Buildings.gableRoof(m, { cf = house.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w }, H + 0.25, 3.8, K.Plaster)
	Buildings.chimney(m, house.cf * CFrame.new(-house.w / 2 + 1.6, H + 0.4, 1.6), 4.6, rng)
	-- forge wing: stone, flat iron roof, a glowing forge mouth to the path, a tall chimney
	local wing = part(fp, 1.6, 6.1, -2.6, 3.4)
	Style.block(m, wing.cf * CFrame.new(0, 0.35, 0), Vector3.new(wing.w + 0.8, 0.7, wing.d + 0.8), C.StoneDark, nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 3.8, 0), Vector3.new(wing.w, 7.6, wing.d), Style.vary(C.Stone, rng, 0.04), nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 7.85, 0), Vector3.new(wing.w + 0.8, 0.5, wing.d + 0.8), C.Iron, nil, Style.decor())
	local wf = face(wing, "Front")
	Style.block(m, wf * CFrame.new(0, 2.5, -0.2), Vector3.new(3.6, 4, 0.4), C.StoneDeep, nil, Style.tiny())
	local mouth = glow(m, wf * CFrame.new(0, 2.2, -0.42), Vector3.new(2.4, 2.4, 0.1), C.Molten)
	mouth.Name = "ForgeGlow"
	Style.block(m, wf * CFrame.new(0, 4.8, -0.35), Vector3.new(4.4, 0.7, 0.7), C.WoodDark, nil, Style.tiny())
	local ws = face(wing, "Right")
	Style.block(m, ws * CFrame.new(0, 2.6, -0.15), Vector3.new(2.6, 2.6, 0.3), C.StoneDeep, nil, Style.tiny())
	glow(m, ws * CFrame.new(0, 2.5, -0.34), Vector3.new(1.6, 1.6, 0.1), C.Ember)
	local stack = wing.cf * CFrame.new(-0.4, 8.1, wing.d / 2 - 1.3)
	Buildings.chimney(m, stack, 7.5, rng)
	glow(m, stack * CFrame.new(0, 8, 0), Vector3.new(1.1, 0.3, 1.1), C.Ember)
	-- an anvil on a stump by the forge mouth
	local anvil = wf * CFrame.new(1.4, 0, -1)
	Style.block(m, anvil * CFrame.new(0, 0.5, 0), Vector3.new(0.9, 1, 0.9), C.Trunk, nil, Style.tiny())
	Style.block(m, anvil * CFrame.new(0, 1.25, 0), Vector3.new(1.4, 0.5, 0.7), C.Iron, nil, Style.tiny())
end

--[[
	GEMS: a wide low two-storey City Kit block (building-k) along the forge
	west path: round front pillars with orange bands, display windows
	(SmoothPlastic glass, no bloom), a long window row, the GEMS roof sign
	with a gem icon facing the path, a small roof crystal (solid body, a
	thin neon core line). Facing east: local +X is south.
]]
Recipes.GemCutter = function(m, fp, site, rng)
	local b = part(fp, -7.6, 7.6, -2.85, 3.3)
	local H = Buildings.techShell(m, b, { Floors = 2, Accent = C.AwningPurple, Corners = "Round", Neon = C.CrystalPurple }, rng)
	local front, fw = face(b, "Front")
	Buildings.display(m, front, -4.6, floorY(1), 3.8, 2.4, C.CrystalPink)
	Buildings.display(m, front, 4.4, floorY(1), 3.6, 2.4, C.CrystalCyan)
	Buildings.door(m, front, 0, 0.6, 2.2, 4.2, K.Metal, K.DoorLeaf, C.CrystalPurple)
	Buildings.windowRow(m, front, floorY(2), 6, fw - 2.6, 1.7, K.Metal)
	for _, side in { "Left", "Right" } do
		local wall, ww = face(b, side)
		Buildings.windowRow(m, wall, floorY(2), 2, ww - 2.2, 1.7, K.Metal)
	end
	local deck = Buildings.flatRoof(m, b, H, C.CrystalPurple)
	Buildings.roofSign(m, b.cf * CFrame.new(-1, deck, -b.d / 2 + 0.7), site.Sign or "GEMS", 5, 2.6, "Gem", C.AwningPink)
	-- the roof crystal on a pedestal: solid facets, a thin neon core line
	local base = b.cf * CFrame.new(5.2, deck, 1)
	Style.block(m, base * CFrame.new(0, 0.4, 0), Vector3.new(1.8, 0.8, 1.8), K.Metal, nil, Style.tiny({ CastShadow = true }))
	local body = base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.pi / 4, 0)
	Style.block(m, body * CFrame.new(0, 1, 0), Vector3.new(0.95, 2, 0.95), C.CrystalViolet, nil, Style.tiny({ CastShadow = true }))
	Geo.wedge(m, body * CFrame.new(0, 2.4, -0.2375), Vector3.new(0.95, 0.8, 0.475), C.CrystalPurple, SMOOTH, Style.tiny())
	Geo.wedge(
		m,
		body * CFrame.new(0, 2.4, 0.2375) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(0.95, 0.8, 0.475),
		C.CrystalViolet,
		SMOOTH,
		Style.tiny()
	)
	glow(m, body * CFrame.new(0, 1, -0.5), Vector3.new(0.14, 1.6, 0.06), C.CrystalPink)
	glow(m, body * CFrame.new(-0.5, 1, 0), Vector3.new(0.06, 1.6, 0.14), C.CrystalPink)
	Buildings.vent(m, b.cf * CFrame.new(-5.2, deck, 1.2), rng)
end

--[[
	INN: a gable-front cozy inn (stone, jettied plaster with half-timbering,
	window boxes, a hanging lantern, the INN sign with a mug) and a one-
	storey cafe wing with a striped awning and a roof terrace parasol. The
	front faces the forge east path, the pink grove stands behind it.
	Facing west: local +X is north.
]]
Recipes.Inn = function(m, fp, site, rng)
	local b = part(fp, -1.6, 4.4, -3.7, 4.4)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm, Timbering = 2 }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.hangingLantern(m, front, -2, 5.2)
	Buildings.window(m, front, 2.1, floorY(1), 1.3, 2.2, C.WoodDark)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper = face(jetty, "Front")
	Buildings.wallSign(m, upper, 0, floorY(2) + 0.2, site.Sign or "INN", 3.4, 2.2, "Mug", K.Amber)
	-- the attic window in the gable
	Buildings.window(m, upper, 0, H + 1.6, 1.2, 1.2, C.WoodDark)
	-- south side (toward the plaza and the hero)
	local south, sw = face(jetty, "Left")
	Buildings.windowRow(m, south, floorY(2), 3, sw - 2.4, 1.7, C.WoodDark)
	Buildings.windowBox(m, south, -2.2, floorY(2) - 1.55, 2.2, C.FlowerPink)
	Buildings.windowBox(m, south, 2.2, floorY(2) - 1.55, 2.2, C.FlowerYellow)
	Buildings.window(m, face(b, "Left"), 1.6, floorY(1), 1.8, 2, C.WoodDark)
	local north, nw = face(jetty, "Right")
	Buildings.windowRow(m, north, floorY(2), 2, nw - 3, 1.7, C.WoodDark)
	Buildings.gableRoof(m, { cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w }, H + 0.25, 4.4, K.PlasterWarm)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.3, H + 1, 2.2), 4.2, rng)
	-- the cafe wing
	local wing = part(fp, -5.1, -2.3, -2.4, 4.6)
	Style.block(m, wing.cf * CFrame.new(0, 0.35, 0), Vector3.new(wing.w + 0.6, 0.7, wing.d + 0.6), C.StoneDark, nil, Style.solid())
	Style.block(m, wing.cf * CFrame.new(0, 3, 0), Vector3.new(wing.w, 6, wing.d), Style.vary(C.Stone, rng, 0.04), nil, Style.solid())
	local wf, ww = face(wing, "Front")
	Buildings.window(m, wf, 0, 2.9, ww - 1.2, 2.2, C.WoodDark)
	Buildings.awning(m, wf, 0, 5.2, ww + 0.2, 1.6, C.AwningPink, C.AwningWhite, 3)
	local top = Buildings.flatRoof(m, wing, 6, nil, C.WoodDark)
	Buildings.parasol(m, wing.cf * CFrame.new(0, top, 1), C.AwningPink)
	Buildings.window(m, face(wing, "Left"), 0, 2.9, 2.6, 2, C.WoodDark)
end

--[[
	ORE: a tech tower by the east spur, its front and the ORE sign with a
	pickaxe toward the spur road, the plaza and the hero camera: four
	storeys, a stepped slate cap with a beacon mast, orange banner window
	frames (Space Station), neon outlines. Facing south: local +X is west.
]]
Recipes.OreTower = function(m, fp, site, rng)
	local b = part(fp, -2.3, 2.3, -1.45, 1.95)
	local H = Buildings.techShell(m, b, { Floors = 4, Accent = C.Hazard, Lines = true }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 0.6, 0.6, 1.8, 4.2, C.Hazard, K.DoorLeaf, K.EdgeNeon)
	Buildings.window(m, front, -1.3, floorY(1), 0.9, 2, K.Metal)
	Buildings.windowRow(m, front, floorY(2), 2, b.w - 1.6, 1.8, K.Metal)
	Buildings.wallSign(m, front, 0, floorY(3) + 0.2, site.Sign or "ORE", 2.6, 1.9, "Pickaxe", K.Amber, 0.4)
	Buildings.window(m, front, -1, floorY(4), 1.3, 1.8, C.Hazard)
	Buildings.window(m, front, 1, floorY(4), 1.3, 1.8, C.Hazard)
	-- west side: toward the plaza and lobby_east
	local west, ww = face(b, "Right")
	for f = 2, 4 do
		Buildings.windowRow(m, west, floorY(f), 2, ww - 1.6, 1.8, K.Metal)
	end
	local east, ew = face(b, "Left")
	for f = 3, 4 do
		Buildings.windowRow(m, east, floorY(f), 2, ew - 1.6, 1.8, K.Metal)
	end
	local deck = Buildings.flatRoof(m, b, H, K.EdgeNeon)
	-- a stepped slate cap with a beacon mast (the TOOLS block has the setback box)
	local cap = Buildings.steppedRoof(m, Buildings.sub(b, 0, 0.2, b.w - 0.4, b.d - 0.6), deck, 3, { K.Metal, K.Slate, K.SlateLight })
	glow(m, b.cf * CFrame.new(0, deck + 0.45, -(b.d - 0.6 + 0.8) / 2 + 0.2 - 0.06), Vector3.new(b.w + 0.2, 0.14, 0.08), C.Hazard)
	Buildings.antenna(m, b.cf * CFrame.new(0, cap, 0.2), 4.5, C.AwningRed)
end

--[[
	A small two-storey tech workshop across the east spur from the ORE
	tower (City Kit building-a): banner band, an overhang over the shop
	front, a rooftop vent and dome; the back toward the fossil dig has a
	window row too. Facing north (the spur road): local +X is east.
]]
Recipes.SpurWorkshop = function(m, fp, _site, rng)
	local b = part(fp, -3.3, 3.3, -1.3, 1.65)
	local H = Buildings.techShell(m, b, { Floors = 2, Accent = C.Hazard, Wall = K.PanelLight }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, 1.6, 0.6, 1.8, 4.2, K.Metal, K.DoorLeaf, K.EdgeNeon)
	Buildings.display(m, front, -1.4, floorY(1), 2.6, 2.2, C.Hazard)
	Buildings.overhang(m, front, 0, G - 1.9, fw - 0.4, 0.8, K.Metal, false, K.EdgeNeon)
	Buildings.windowRow(m, front, floorY(2), 3, fw - 1.4, 1.7, K.Metal)
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(2), 3, bw - 1.4, 1.7, K.Metal)
	Buildings.windowRow(m, back, floorY(1), 2, bw - 2.4, 1.8, K.Metal)
	local west = face(b, "Left")
	Buildings.window(m, west, 0, floorY(2), 1.4, 1.7, K.Metal)
	local top = Buildings.flatRoof(m, b, H, K.EdgeNeon)
	Buildings.vent(m, b.cf * CFrame.new(-1.6, top, 0.2), rng)
	Buildings.dome(m, b.cf * CFrame.new(1.8, top, 0.2), 1.6)
end

--[[
	City Kit building-k by the ROCK SCANNER path: a wide low two-storey block
	with long window rows on both long sides, a light accent band, a door
	and a display toward the koi pond and the plaza, rooftop boxes and a
	dome. Facing north: local +X is east.
]]
Recipes.CityBlock = function(m, fp, _site, rng)
	local b = part(fp, -5.05, 5.05, -1.7, 1.9)
	local H = Buildings.techShell(m, b, { Floors = 2, Accent = C.Hazard }, rng)
	local front, fw = face(b, "Front")
	Buildings.door(m, front, -3.6, 0.6, 2, 4.2, C.Hazard, K.DoorLeaf, K.EdgeNeon)
	Buildings.display(m, front, 0.4, floorY(1), 3.4, 2.2, C.CrystalCyan)
	Buildings.window(m, front, 4, floorY(1), 1.6, 2.2, K.Metal)
	Buildings.windowRow(m, front, floorY(2), 5, fw - 1.6, 1.7, K.Metal)
	local back, bw = face(b, "Back")
	Buildings.windowRow(m, back, floorY(2), 5, bw - 1.6, 1.7, K.Metal)
	Buildings.windowRow(m, back, floorY(1), 3, bw - 3, 2, K.Metal)
	-- light accent band under the parapet (the City Kit's light trim)
	Style.block(m, b.cf * CFrame.new(0, H - 0.5, 0), Vector3.new(b.w + 0.3, 0.4, b.d + 0.3), K.PanelLight, nil, Style.tiny())
	local top = Buildings.flatRoof(m, b, H, K.EdgeNeon)
	Buildings.vent(m, b.cf * CFrame.new(-3.4, top, 0), rng)
	Buildings.vent(m, b.cf * CFrame.new(-0.6, top, 0.3), rng)
	Buildings.dome(m, b.cf * CFrame.new(3.4, top, 0), 1.8)
end

--[[
	Depot in the hero's right foreground: a four-storey tech block with
	round front pillars (orange bands), an orange framed loading bay
	(wall-door-wide-banner), window rows, a water tank; its yard has a pair
	of container-talls, crates, a bench and a lamp post (no light).
	Facing west: local +X is north.
]]
Recipes.Depot = function(m, fp, _site, rng)
	local b = part(fp, -4.8, 2.6, -2.35, 2.85)
	local H = Buildings.techShell(m, b, { Floors = 4, Accent = C.Hazard, Corners = "Round", Lines = true }, rng)
	local front, fw = face(b, "Front")
	-- the loading bay: an orange frame, a dark shutter with slats
	Buildings.door(m, front, -0.6, 0.6, 3.6, 4.1, C.Hazard, C.HazardDark, K.EdgeNeon)
	for i = 1, 3 do
		Style.block(m, front * CFrame.new(-0.6, 0.6 + i * 1.05, -0.27), Vector3.new(3.5, 0.15, 0.08), K.MetalEdge, nil, Style.tiny())
	end
	Buildings.window(m, front, 2.6, floorY(1), 1.2, 2, K.Metal)
	for f = 2, 4 do
		Buildings.windowRow(m, front, floorY(f), 3, fw - 1.8, 1.7, K.Metal)
	end
	-- south side (the hero's view): orange banner window frames
	local south, sw = face(b, "Left")
	for f = 2, 4 do
		Buildings.windowRow(m, south, floorY(f), 2, sw - 1.8, 1.7, C.Hazard)
	end
	local top = Buildings.flatRoof(m, b, H, K.EdgeNeon)
	Buildings.waterTank(m, b.cf * CFrame.new(-1.4, top, 0.6), 2.8)
	Buildings.vent(m, b.cf * CFrame.new(1.6, top, 0.4), rng)
	-- the yard at the south end
	Buildings.container(m, (fp.cf * CFrame.new(-4.9, 0, -2)).Position, 4.2, C.Hazard)
	Buildings.container(m, (fp.cf * CFrame.new(-4.9, 0, 0.6)).Position, 3.4, C.CrystalBlue)
	crate(m, fp.cf * CFrame.new(-4.7, 0, 2.6), 1.5, rng)
	Buildings.bench(m, fp.cf * CFrame.new(4.1, 0, -2.6))
	lampPost(m, fp.cf * CFrame.new(5.2, 0, -2.9), 3.6)
end

--[[
	Gable-front cottage beside the mine with half-timbering, window boxes,
	a hanging lantern and a woodshed: a back wall, side boards, a roof
	sloping to the back and a stack of log ends. Facing north: local +X is
	east (toward the south road).
]]
Recipes.MineCottage = function(m, fp, _site, rng)
	local b = part(fp, -fp.w / 2 + 1.2, 2.4, -fp.d / 2 + 1.3, fp.d / 2 - 1.3)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.PlasterWarm }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, -1.4, 0.7, 2.2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, 2.2, floorY(1), 1.8, 2.2, C.WoodDark)
	Buildings.hangingLantern(m, front, 0.4, 5.3)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	for _, side in { "Front", "Right", "Left" } do
		local wall, ww = face(jetty, side)
		Buildings.windowRow(m, wall, floorY(2), 2, ww - 2.2, 1.7, C.WoodDark)
		if side == "Front" then
			Buildings.windowBox(m, wall, 0, floorY(2) - 1.55, ww - 2.6, C.FlowerRed)
		end
	end
	Buildings.gableRoof(m, { cf = b.cf * CFrame.Angles(0, math.pi / 2, 0), w = jetty.d, d = jetty.w }, H + 0.25, 4.4, K.PlasterWarm)
	Buildings.chimney(m, b.cf * CFrame.new(-b.w / 2 + 1.4, H, 1.4), 5, rng)
	-- woodshed: back wall, side boards, posts, a roof sloping to the back, stacked logs
	local shed = part(fp, 3.6, fp.w / 2 - 0.8, -fp.d / 2 + 2.8, fp.d / 2 - 2.6)
	local sw, sd = shed.w, shed.d
	Style.block(m, shed.cf * CFrame.new(0, 2, sd / 2 - 0.2), Vector3.new(sw, 4, 0.4), C.Plank, nil, Style.decor())
	for _, sx in { -1, 1 } do
		Style.block(m, shed.cf * CFrame.new(sx * (sw / 2 - 0.2), 1.9, 0.6), Vector3.new(0.4, 3.8, sd - 1.2), C.Wood, nil, Style.decor())
		Style.block(
			m,
			shed.cf * CFrame.new(sx * (sw / 2 - 0.2), 2.4, -sd / 2 + 0.3),
			Vector3.new(0.6, 4.8, 0.6),
			C.WoodDark,
			nil,
			Style.tiny()
		)
	end
	-- roof: high at the open front, low at the back
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
	-- log stack: rows of horizontal cylinders with their ends to the front
	local rows = { { -1.1, 0.55 }, { 0, 0.55 }, { 1.1, 0.55 }, { -0.55, 1.5 }, { 0.55, 1.5 }, { 0, 2.45 } }
	for _, r in rows do
		Geo.make(
			"Part",
			Style.tiny({
				Shape = Enum.PartType.Cylinder,
				CFrame = shed.cf * CFrame.new(r[1], r[2], 0.2) * CFrame.Angles(0, math.pi / 2, 0),
				Size = Vector3.new(sd - 1.4, 1, 1),
				Color = Style.vary(C.WoodLight, rng, 0.06),
				Material = SMOOTH,
			}),
			m
		)
	end
end

--[[
	A cozy garden cottage by the south road: stone ground floor, jettied
	plaster upper floor with half-timbering, window boxes, a hanging
	lantern, a slate roof with the ridge along the front; a garden fence and
	flower beds in front. Facing north (the town): local +X is east.
]]
Recipes.GardenCottage = function(m, fp, _site, rng)
	local b = part(fp, -4.6, 3.4, -1.2, 4)
	local H = Buildings.cozyShell(m, b, { Floors = 2, Plaster = K.Plaster }, rng)
	local front = face(b, "Front")
	Buildings.door(m, front, 1.6, 0.7, 2, 4.4, C.WoodDark, C.Wood)
	Buildings.window(m, front, -1.8, floorY(1), 2, 2.2, C.WoodDark)
	Buildings.hangingLantern(m, front, 3.2, 5.3)
	local jetty = Buildings.sub(b, 0, 0, b.w + 0.5, b.d + 0.5)
	local upper, uw = face(jetty, "Front")
	Buildings.windowRow(m, upper, floorY(2), 2, uw - 3, 1.7, C.WoodDark)
	Buildings.windowBox(m, upper, -1.6, floorY(2) - 1.55, 2.2, C.FlowerPink)
	Buildings.windowBox(m, upper, 1.6, floorY(2) - 1.55, 2.2, C.FlowerPurple)
	local back, bw = face(jetty, "Back")
	Buildings.windowRow(m, back, floorY(2), 2, bw - 3, 1.7, C.WoodDark)
	Buildings.window(m, face(jetty, "Left"), 0, floorY(2), 1.4, 1.7, C.WoodDark)
	Buildings.gableRoof(m, jetty, H + 0.25, 3.6, K.Plaster)
	Buildings.chimney(m, b.cf * CFrame.new(b.w / 2 - 1.4, H + 0.6, 1.2), 4.4, rng)
	-- garden: a low fence along the front with a gate gap, flower beds
	local fy = -fp.d / 2 + 0.6
	local p0 = (fp.cf * CFrame.new(-fp.w / 2 + 0.6, 0, fy)).Position
	local p1 = (fp.cf * CFrame.new(0.2, 0, fy)).Position
	local p2 = (fp.cf * CFrame.new(3, 0, fy)).Position
	local p3 = (fp.cf * CFrame.new(fp.w / 2 - 0.6, 0, fy)).Position
	Style.fence(m, p0, p1, { Height = 1.8, PostEvery = 3 })
	Style.fence(m, p2, p3, { Height = 1.8, PostEvery = 3 })
	Kit.flowerPatch(m, (fp.cf * CFrame.new(-3.4, 0, -fp.d / 2 + 2.2)).Position, C.FlowerYellow, rng, 3)
	Kit.flowerPatch(m, (fp.cf * CFrame.new(4.4, 0, -fp.d / 2 + 2.2)).Position, C.FlowerRed, rng, 3)
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
