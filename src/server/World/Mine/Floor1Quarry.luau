--[[
	Floor 1, GREYSTONE QUARRY (blaster 1+): the first mine floor players see.
	An open-pit quarry under the warm sunset sky (no ceiling): terraced
	blue-grey slate walls with pale strata stripes like the rocks, a grass
	rim with colorful trees, a sandy floor with dusty patches and a worn path,
	a wooden scaffold with ladders and a plank walkway on the first terrace, a
	mine cart on rails, a tool shed, lanterns on posts and copper and quartz
	crystal clusters sprouting from the walls.

	Contract: MineKit header (Floor.Index, Floor.Size, Floor.build). Local
	frame: origin = ground center (world: MineFloors.Placement[1] at
	0, -12, -180; local = world - origin), +Z = front (the town), -Z = back.

	In the game (docs/plans/MINE_STEP_PLAN.md) the quarry shares its box with
	other packages, so the floor leaves these spaces free:
	  front   Land builds the town-side cliff (z +56..) and the ramp from
	          0, +12, +68 down to 0, 0, +40: no front wall, x -10..10 clear
	  train   z +18..+39 stays clear (track at z +24, Mine Station x 12..40);
	          from z +14 to +39 the side walls step back to |x| 71.5 behind
	          Railway's tunnel portals (x +-66); no ore lift of our own
	  grotto  the east wall opens at z -8..+4 (floor to +11) into Land's
	          tunnel to the VIP Grotto (a rock lintel above it)
	  back    the lobby's DEPTHS portal (x -22..22, z -60..-45) frames the way
	          down; the opening x -9..9, y 0..16 is open; the falls pools
	          at x +-36..52 and the ForgeWorks chute at x 22..26 stay free; the
	          back wall rises to +34 under the ForgeMountain massif (no grass)
	opts.Cutaway (preview pictures, no town around): a simple glowing tunnel
	headland stands where the DEPTHS portal is in the game.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Geo = require(Shared:WaitForChild("Builders"):WaitForChild("Geo"))
local Rng = require(Shared:WaitForChild("Util"):WaitForChild("Rng"))
local MineFloors = require(Shared:WaitForChild("Config"):WaitForChild("MineFloors"))
local World = ServerScriptService:WaitForChild("Server"):WaitForChild("World")
local Style = require(World:WaitForChild("Lobby"):WaitForChild("Style"))
local MineKit = require(World:WaitForChild("Mine"):WaitForChild("MineKit"))

local Floor = {}

Floor.Index = 1
Floor.Size = Vector3.new(154, 44, 118)

local C = Style.C
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local WHITE = Color3.new(1, 1, 1)
local UP = Vector3.new(0, 1, 0)

local SOLID = { CanTouch = false, CanQuery = true, CanCollide = true }
local DECOR = { CanTouch = false, CanQuery = false, CanCollide = true }
local TINY = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false }
local GHOST = { CanTouch = false, CanQuery = false, CanCollide = false }

-- pit layout (local studs)
local PIT_X = 56 -- the side walls' first terrace faces
local BAND_Z0, BAND_Z1 = 14, 39 -- the train band: side walls stand back at |x| 71.5 here
local BAND_X = 72 -- the quarry edge (town ground and tunnel portals)
local OUTER_X = 77 -- the side walls' back (in the town ground)
local BACK_Z = -48 -- the back wall's first terrace face
local END_Z = -60 -- the back of the floor box (floor 2 starts here)
local FRONT_Z = 58 -- under Land's town-side cliff
local DOOR_Z0, DOOR_Z1 = -8, 4 -- the VIP Grotto door in the east wall
local DOOR_H = 11
local GIANT = Vector3.new(11, 0, -6) -- Giant Crystal plaza (beside the main path, the DEPTHS portal stays in view)
-- the preview tunnel (Cutaway only; in the game the lobby's DEPTHS portal stands here)
local MOUTH_Z = -46
local TUNNEL_W = 7
local TUNNEL_H = 14
local TUNNEL_END = -60
local TUNNEL_DROP = 4
local HEAD_X = 22

type Top = { cf: CFrame, w: number, d: number, step: number, wall: string, rim: boolean }

type Ctx = {
	m: Model,
	o: CFrame,
	rng: Rng.Rng,
	pal: MineFloors.Palette,
	tops: { Top },
	lights: number,
}

type Step = { Face: number, Top: number, Color: Color3 }

type TerraceOpts = {
	TrimStart: { number }?, -- per step, studs cut from the start
	TrimEnd: { number }?,
	Veins: number?, -- chance of a glowing crack on a first-step column
	Bare: boolean?, -- no topsoil and grass on the top step (under the massif)
}

---------------------------------------------------------------- small helpers

local function at(c: Ctx, x: number, y: number, z: number): CFrame
	return c.o * CFrame.new(x, y, z)
end

local function pt(c: Ctx, x: number, y: number, z: number): Vector3
	return c.o * Vector3.new(x, y, z)
end

local function block(c: Ctx, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	return Geo.block(c.m, cf, size, color, material, props or DECOR)
end

local function light(c: Ctx, part: BasePart, color: Color3, range: number, brightness: number)
	if c.lights >= 20 then
		return
	end
	c.lights += 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

-- A wall frame: `start` on the pit edge (ground), X runs along `along`, local +Z goes into the cliff.
local function wallFrame(c: Ctx, start: Vector3, along: Vector3): CFrame
	local back = along:Cross(UP)
	return c.o * CFrame.fromMatrix(start, along, UP, back)
end

-- A CFrame at `pos` whose UpVector leans `tilt` radians from straight up toward `out` (horizontal).
local function leaning(pos: Vector3, out: Vector3, tilt: number): CFrame
	local dir = (UP * math.cos(tilt) + out * math.sin(tilt)).Unit
	local right = out:Cross(UP)
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, dir, right:Cross(dir))
end

-- A zigzag glowing crack on a face: `face` = a frame on the face (X/Y in the face plane),
-- starting at (x, y) heading `angle` (radians from +X), `segments` pieces of about `len`.
local function crack(c: Ctx, face: CFrame, x: number, y: number, angle: number, segments: number, len: number)
	local rng = c.rng
	local px, py = x, y
	for i = 1, segments do
		local l = len * rng:range(0.7, 1.1)
		local a = angle + (if i % 2 == 0 then 0.5 else -0.5) * rng:range(0.6, 1.2)
		local dx, dy = math.cos(a) * l, math.sin(a) * l
		block(c, face * CFrame.new(px + dx / 2, py + dy / 2, 0) * CFrame.Angles(0, 0, a), Vector3.new(l + 0.2, 0.2, 0.2), Color3.fromRGB(255, 84, 30), NEON, TINY)
		px, py = px + dx, py + dy
	end
end

---------------------------------------------------------------- terraced walls

local STAGGER = { 0.8, 0.4, 0 } -- end trims so the steps' end faces never share a plane

--[[
	A terraced slate wall: voxel columns (~8 studs) per step, each with pale
	strata stripes on its face (shared heights along the wall, so the layers
	read as continuous), a pale slate ledge (sometimes a grass lip) on the lower
	steps and a dirt band + grass cap on the top step (opts.Bare: a pale slate
	cap). `frame` = wallFrame, the steps' Face = distance from the pit edge into
	the cliff, `outer` = the wall's back.
]]
local function terrace(c: Ctx, wall: string, frame: CFrame, length: number, steps: { Step }, outer: number, opts: TerraceOpts?)
	local o: TerraceOpts = opts or {}
	local rng, pal = c.rng, c.pal
	local n = math.max(1, math.floor(length / 8 + 0.5))
	local colW = length / n
	local strata: { { number } } = {}
	for k, s in steps do
		local below = if k == 1 then 0 else steps[k - 1].Top
		local span = s.Top - below
		local count = math.clamp(math.floor(span / 5.5), 1, 3)
		local levels = {}
		for j = 1, count do
			table.insert(levels, below + span * (j - 0.45 + rng:range(-0.08, 0.08)) / (count + 0.2))
		end
		strata[k] = levels
	end
	for i = 0, n - 1 do
		local x0, x1 = i * colW, (i + 1) * colW
		for k, s in steps do
			local a = math.max(x0, if o.TrimStart then o.TrimStart[k] or 0 else 0)
			local b = math.min(x1, length - (if o.TrimEnd then o.TrimEnd[k] or 0 else 0))
			if b - a >= 1 then
				local last = k == #steps
				local below = if k == 1 then 0 else steps[k - 1].Top
				local zFace = s.Face + rng:range(-0.3, 0.3)
				local zBack = if last then outer else steps[k + 1].Face + 2
				local jitter = if last and not o.Bare then math.min(1.4, s.Top * 0.2) else 0.5
				local h = s.Top + rng:range(-jitter, jitter)
				local w = b - a + 0.06
				local x = (a + b) / 2
				local depth = zBack - zFace
				Geo.block(c.m, frame * CFrame.new(x, h / 2, zFace + depth / 2), Vector3.new(w, h, depth), Geo.vary(s.Color, rng, 0.035), nil, SOLID)
				-- strata: pale layers like the rocks
				for j, y in strata[k] do
					if y < h - 0.8 and rng:chance(0.9) then
						local t = rng:range(0.55, 0.9)
						local color = if j % 2 == 1 then pal.Light:Lerp(WHITE, 0.2) else pal.Light:Lerp(WHITE, 0.45)
						block(c, frame * CFrame.new(x, y + rng:range(-0.18, 0.18), zFace - 0.15), Vector3.new(w + 0.12, t, 0.7), Geo.vary(color, rng, 0.03), nil, TINY)
					end
				end
				-- a broken chunk sticking out of the face
				if rng:chance(0.25) and h - below > 4 then
					local sw, sh = rng:range(1.6, 3), rng:range(1.2, 2.2)
					local y = rng:range(below + sh, math.max(below + sh + 0.1, h - sh))
					local color = if rng:chance(0.5) then pal.Dark else s.Color:Lerp(pal.Light, 0.45)
					block(c, frame * CFrame.new(x + rng:range(-w * 0.3, w * 0.3), y, zFace - 0.4), Vector3.new(sw, sh, 1.2), Geo.vary(color, rng, 0.04), nil, TINY)
				end
				-- a thin glowing crack (lowest step only)
				if k == 1 and o.Veins and rng:chance(o.Veins) and h > 5 then
					local dir = if rng:chance(0.5) then 0 else math.pi
					crack(c, frame * CFrame.new(0, 0, zFace - 0.05), x + rng:range(-w * 0.3, 0), rng:range(1.8, h - 3), dir + rng:range(-0.5, 0.5), 2, 1.4)
				end
				if last and o.Bare then
					block(c, frame * CFrame.new(x, h + 0.2, zFace + depth / 2), Vector3.new(w + 0.1, 0.5, depth + 0.2), Geo.vary(pal.Light, rng, 0.04), nil, SOLID)
				elseif last then
					-- topsoil band and grass cap (the rim)
					block(c, frame * CFrame.new(x, h - 0.7, zFace + depth / 2), Vector3.new(w + 0.24, 1.4, depth + 0.24), Geo.vary(C.DirtDark, rng, 0.04), nil, TINY)
					block(c, frame * CFrame.new(x, h + 0.4, zFace + depth / 2), Vector3.new(w + 0.5, 0.8, depth + 0.5), Geo.vary(C.Grass, rng, 0.05), nil, SOLID)
					table.insert(c.tops, { cf = frame * CFrame.new(x, h + 0.8, zFace + depth / 2), w = w, d = depth, step = k, wall = wall, rim = true })
				else
					-- the ledge: pale slate (like the rock tops) or a grass lip
					local nextFace = steps[k + 1].Face
					local ledge = nextFace + 0.5 - (zFace - 0.2)
					local color = if rng:chance(0.3) then C.Grass else pal.Light
					block(c, frame * CFrame.new(x, h + 0.2, zFace - 0.2 + ledge / 2), Vector3.new(w + 0.1, 0.5, ledge), Geo.vary(color, rng, 0.04), nil, SOLID)
					table.insert(c.tops, { cf = frame * CFrame.new(x, h + 0.45, zFace - 0.2 + ledge / 2), w = w, d = ledge, step = k, wall = wall, rim = false })
				end
			end
		end
	end
end

-- Rubble at the foot of a wall: tilted slate chunks a little in front of the face.
local function talus(c: Ctx, frame: CFrame, length: number, every: number)
	local rng, pal = c.rng, c.pal
	local n = math.floor(length / every)
	for i = 0, n - 1 do
		local s = rng:range(1.4, 2.8)
		local x = (i + rng:range(0.2, 0.8)) * every
		local z = -rng:range(0.4, 1.8)
		local color = if rng:chance(0.55) then pal.Dark else pal.Mid
		block(c, frame * CFrame.new(x, s * 0.3, z) * Geo.randomTilt(rng, 0.35), Vector3.new(s * 1.2, s * 0.8, s), Geo.vary(color, rng, 0.05))
	end
end

---------------------------------------------------------------- crystals

-- A copper/quartz cluster growing out of a wall: `pos` sits inside the rock, leaning `tilt` toward `out`.
local function wallCrystal(c: Ctx, pos: Vector3, out: Vector3, tilt: number, count: number, height: number, quartz: boolean, seed: number)
	local pal = c.pal
	local colors = if quartz then { pal.Crystal2, pal.Crystal } else { pal.Crystal, pal.Crystal:Lerp(pal.Crystal2, 0.35), pal.Crystal2 }
	local root = c.o * leaning(pos, out, tilt)
	return MineKit.crystals(c.m, root, count, height, "Tipped", colors, "Floor1Crystal" .. seed)
end

---------------------------------------------------------------- wooden pieces

local function beam(c: Ctx, a: Vector3, b: Vector3, thick: number, color: Color3, props: { [string]: any }?): Part
	local d = b - a
	local cf = CFrame.lookAt((a + b) / 2, b)
	return block(c, c.o * cf, Vector3.new(thick, thick, d.Magnitude), color, nil, props or DECOR)
end

-- A ladder from `foot` (local ground point) up `height` studs, rungs facing `out`.
local function ladder(c: Ctx, foot: Vector3, out: Vector3, height: number)
	local side = out:Cross(UP).Unit
	for _, s in { -0.8, 0.8 } do
		local p = foot + side * s
		beam(c, p, p + Vector3.new(0, height, 0), 0.32, C.WoodDark, GHOST)
	end
	local n = math.floor(height / 1.4)
	for i = 1, n do
		local p = foot + Vector3.new(0, i * 1.4 - 0.4, 0)
		beam(c, p - side * 0.8, p + side * 0.8, 0.22, C.Wood, TINY)
	end
end

-- A plank deck on short legs; `center` = top center (local), X across, Z along.
local function deck(c: Ctx, center: Vector3, size: Vector3, legDown: number)
	local cf = at(c, center.X, center.Y, center.Z)
	Style.planks(c.m, cf, size, c.rng, { PlankWidth = 1.7 })
	local n = math.max(1, math.floor(size.Z / 8))
	for i = 0, n do
		local z = -size.Z / 2 + 0.4 + (size.Z - 0.8) * i / n
		for _, sx in { -1, 1 } do
			block(c, cf * CFrame.new(sx * (size.X / 2 - 0.35), -legDown / 2, z), Vector3.new(0.5, legDown, 0.5), C.WoodDark, nil, GHOST)
		end
	end
end

---------------------------------------------------------------- the preview tunnel (Cutaway only)

-- The glowing tunnel headland of the preview pictures: in the game the lobby's DEPTHS portal
-- (src/server/World/Lobby/Backdrop/Depths.luau) frames the way down at this spot.
local function tunnel(c: Ctx, slate2: Color3, slate3: Color3, slate1: Color3)
	local rng, pal, m = c.rng, c.pal, c.m
	local depth = MOUTH_Z - TUNNEL_END
	local zMid = (MOUTH_Z + TUNNEL_END) / 2
	local headH = 23
	local face = MOUTH_Z + 0.15
	local flip = CFrame.Angles(0, math.pi, 0) -- signs face the pit (+Z)
	local jambW = HEAD_X - TUNNEL_W
	for _, sx in { -1, 1 } do
		block(c, at(c, sx * (TUNNEL_W + HEAD_X) / 2, headH / 2, zMid), Vector3.new(jambW, headH, depth), Geo.vary(slate2, rng, 0.03), nil, SOLID)
	end
	block(c, at(c, 0, (TUNNEL_H + headH) / 2, zMid), Vector3.new(TUNNEL_W * 2 + 0.1, headH - TUNNEL_H, depth), Geo.vary(slate2, rng, 0.03), nil, SOLID)
	block(c, at(c, 0, headH + 2.5, zMid - 2), Vector3.new(HEAD_X * 1.5, 5, depth - 4), Geo.vary(slate3, rng, 0.03), nil, SOLID)
	block(c, at(c, 0, headH - 0.7, zMid), Vector3.new(HEAD_X * 2 + 0.3, 1.4, depth + 0.3), C.DirtDark, nil, TINY)
	block(c, at(c, 0, headH + 0.4, zMid), Vector3.new(HEAD_X * 2 + 0.6, 0.8, depth + 0.6), C.Grass, nil, SOLID)
	block(c, at(c, 0, headH + 5.4, zMid - 2), Vector3.new(HEAD_X * 1.5 + 0.5, 0.8, depth - 3.5), C.Grass, nil, SOLID)
	for i, y in { 3.4, 7.4, 11.8 } do
		for _, sx in { -1, 1 } do
			local color = if i == 2 then pal.Light:Lerp(WHITE, 0.3) else pal.Light
			block(c, at(c, sx * (HEAD_X + 10.2) / 2, y + sx * 0.15, face), Vector3.new(HEAD_X - 10.2, 0.8, 0.7), color, nil, TINY)
		end
	end
	-- the stone arch around the portal: chunky slate blocks with glow seeping through the seams
	local seam = pal.Crystal:Lerp(C.Ember, 0.4)
	for _, sx in { -1, 1 } do
		block(c, at(c, sx * 8.7, 7.5, MOUTH_Z + 0.08), Vector3.new(3.1, 15, 0.16), seam, NEON, TINY)
	end
	block(c, at(c, 0, 16.6, MOUTH_Z + 0.08), Vector3.new(20.4, 3.6, 0.16), seam, NEON, TINY)
	local stones = {
		{ -8.7, 2.3, 2.7, 4.3 }, { -8.6, 6.9, 2.5, 4.4 }, { -8.8, 11.6, 2.8, 4.5 },
		{ 8.7, 2.1, 2.6, 3.9 }, { 8.8, 6.6, 2.8, 4.6 }, { 8.6, 11.4, 2.5, 4.4 },
		{ -8.3, 16.4, 3.4, 3 }, { -4.4, 16.6, 3.8, 3.2 }, { 4.4, 16.6, 3.8, 3.2 }, { 8.3, 16.4, 3.4, 3 },
	}
	for i, b in stones do
		local color = if i % 2 == 0 then pal.Dark else slate2:Lerp(pal.Dark, 0.3)
		block(c, at(c, b[1], b[2], MOUTH_Z + 0.45) * CFrame.Angles(0, 0, (i % 3 - 1) * 0.04), Vector3.new(b[3], b[4], 1.7), Geo.vary(color, rng, 0.04), nil, SOLID)
	end
	block(c, at(c, 0, 16.9, MOUTH_Z + 0.65), Vector3.new(3.6, 4, 1.9), pal.Light, nil, SOLID).Name = "Keystone"
	block(c, at(c, 0, 16.9, MOUTH_Z + 1.62), Vector3.new(1.2, 1.2, 0.1), pal.Crystal, NEON, TINY)
	-- dark lining inside, so the glow at the end reads as depth
	for _, sx in { -1, 1 } do
		block(c, at(c, sx * (TUNNEL_W - 0.15), (TUNNEL_H - TUNNEL_DROP) / 2, zMid - 0.5), Vector3.new(0.3, TUNNEL_H + TUNNEL_DROP, depth - 1), C.StoneDeep, nil, GHOST)
	end
	block(c, at(c, 0, TUNNEL_H - 0.15, zMid - 0.5), Vector3.new(TUNNEL_W * 2, 0.3, depth - 1), C.StoneDeep, nil, GHOST)
	-- the floor slopes down toward the glow
	local angle = math.atan2(TUNNEL_DROP, depth)
	local len = math.sqrt(depth * depth + TUNNEL_DROP * TUNNEL_DROP)
	block(c, at(c, 0, -TUNNEL_DROP / 2, zMid) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -0.6, 0), Vector3.new(TUNNEL_W * 2, 1.2, len + 0.4), C.DirtDark, nil, SOLID)
	local function floorY(z: number): number
		return -TUNNEL_DROP * (MOUTH_Z - z) / depth
	end
	-- the glowing end: layered panels, brightest low down (the light comes up from below)
	local glowLayers = {
		{ w = TUNNEL_W * 2, h = TUNNEL_H + TUNNEL_DROP, color = C.Ember, z = 0 },
		{ w = 10.4, h = 13.5, color = C.Fire, z = 0.3 },
		{ w = 6.8, h = 9.5, color = C.FireCore, z = 0.6 },
		{ w = 3.4, h = 6, color = Color3.fromRGB(255, 220, 150), z = 0.9 },
	}
	local endGlow: Part? = nil
	for _, g in glowLayers do
		local bottom = -TUNNEL_DROP - 0.2
		local p = block(c, at(c, 0, bottom + g.h / 2, TUNNEL_END + 0.1 + g.z), Vector3.new(g.w, g.h, 0.2), g.color, NEON, TINY)
		if endGlow == nil then
			endGlow = p
			p.Name = "TunnelGlow"
		end
	end
	-- receding timber frames (silhouettes against the glow) and the big portal frame
	local frameColor = Color3.fromRGB(52, 36, 30)
	for i, z in { -49.5, -53, -56.5 } do
		local y0 = floorY(z)
		local top = TUNNEL_H - 1.2 - i * 0.5
		local half = TUNNEL_W - 1 - i * 0.35
		for _, sx in { -1, 1 } do
			block(c, at(c, sx * half, (y0 + top) / 2, z), Vector3.new(1.1, top - y0, 1.1), frameColor, nil, GHOST)
		end
		block(c, at(c, 0, top + 0.55, z), Vector3.new(half * 2 + 1.1, 1.1, 1.2), frameColor, nil, GHOST)
	end
	local pz = MOUTH_Z + 0.4
	for _, sx in { -1, 1 } do
		block(c, at(c, sx * (TUNNEL_W - 0.5), 6.7, pz), Vector3.new(1.8, 13.4, 1.8), C.WoodDark)
		block(c, at(c, sx * (TUNNEL_W - 0.5), 0.4, pz), Vector3.new(2.4, 0.8, 2.4), C.StoneDark)
		beam(c, Vector3.new(sx * (TUNNEL_W - 1.2), 10.6, pz + 0.2), Vector3.new(sx * (TUNNEL_W - 4), 13.2, pz + 0.2), 0.7, C.Wood, GHOST)
	end
	block(c, at(c, 0, 14.2, pz), Vector3.new(TUNNEL_W * 2 + 2.6, 2, 2), C.Wood)
	-- signs: EMBER CAVES with arrows down, and the next floor's blaster level
	Style.sign(m, at(c, 0, 20.3, MOUTH_Z + 0.9) * flip, "EMBER CAVES", 12, 2.8, { Kind = "Wood" })
	for _, sx in { -1, 1 } do
		Style.icon(m, at(c, sx * 8.4, 20.3, MOUTH_Z + 0.3) * flip, "ArrowDown", 2.2, C.Fire, NEON)
	end
	Style.sign(m, at(c, 0, 14.2, pz + 1.15) * flip, "BLASTER LV 3+", 8, 1.4, { Kind = "Stone", Depth = 0.3, TextColor = C.FireCore })
	for _, sx in { -1, 1 } do
		Style.lantern(m, at(c, sx * (TUNNEL_W - 2.2), 13.2, pz + 0.6), { Kind = "Hanging", Color = C.FireCore })
	end
	local faceF = at(c, 0, 0, MOUTH_Z + 0.08)
	for _, v in { { -10.2, 4.6, math.pi + 0.3 }, { -10.2, 13.6, math.pi - 0.5 }, { 10.2, 9.4, 0.25 }, { 10.2, 14.6, 0.6 } } do
		crack(c, faceF, v[1], v[2], v[3], 2, 1.3)
	end
	-- rails up out of the tunnel with a cart on the slope and one at the mouth
	Style.rails(m, pt(c, 2.5, floorY(-59), -59), pt(c, 2.5, 0, MOUTH_Z))
	Style.rails(m, pt(c, 2.5, 0, MOUTH_Z), pt(c, 2.5, 0, -30))
	Style.mineCart(m, CFrame.lookAt(pt(c, 2.5, floorY(-53), -53), pt(c, 2.5, floorY(-51), -51)), rng, { Load = "Ore" })
	Style.mineCart(m, at(c, 2.5, 0, -38), rng, { Load = "Ore" })
	-- light spilling out, embers and a warm haze
	if endGlow then
		light(c, endGlow, C.Fire, 26, 2.2)
		local embers = Style.emitter(endGlow, "Embers", C.FireCore, 10)
		embers.EmissionDirection = Enum.NormalId.Back
		embers.Speed = NumberRange.new(2, 5)
		embers.Lifetime = NumberRange.new(2.5, 4)
	end
	local hidden = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
	light(c, block(c, at(c, 0, 3, -41), Vector3.new(0.2, 0.2, 0.2), C.Fire, nil, hidden), C.Fire, 26, 1.4)
	Style.emitter(block(c, at(c, 0, floorY(-56), -56), Vector3.new(8, 0.2, 2), C.Fire, nil, hidden), "Mist", C.Fire, 3)
	-- crystals at the feet and on top of the headland
	wallCrystal(c, Vector3.new(-12, -0.3, MOUTH_Z + 1.6), Vector3.new(0, 0, 1), 0.3, 9, 7.5, false, 1)
	wallCrystal(c, Vector3.new(12.4, -0.3, MOUTH_Z + 1.6), Vector3.new(0, 0, 1), 0.35, 8, 6.5, true, 2)
	wallCrystal(c, Vector3.new(-12, headH - 0.2, MOUTH_Z - 3), Vector3.new(0, 0, 1), 0.15, 8, 7, false, 4)
	wallCrystal(c, Vector3.new(11.5, headH - 0.2, MOUTH_Z - 5), Vector3.new(0, 0, 1), 0.2, 7, 6, true, 5)
	for _, p in { { 18, MOUTH_Z + 1.4 }, { -18.5, MOUTH_Z + 1.6 } } do
		Style.boulder(m, pt(c, p[1], 0, p[2]), rng:range(2, 2.8), rng, { Color = slate1 })
	end
end

---------------------------------------------------------------- the build

function Floor.build(parent: Instance, origin: CFrame, opts: { Cutaway: boolean? }?): Model
	local cutaway = opts ~= nil and opts.Cutaway == true
	local model = Instance.new("Model")
	model.Name = "MineFloor" .. Floor.Index
	model:SetAttribute("Floor", Floor.Index)
	local floor = MineFloors.get(Floor.Index)
	local c: Ctx = {
		m = model,
		o = origin,
		rng = Rng.new("Floor1Quarry"),
		pal = floor.Palette,
		tops = {},
		lights = 0,
	}
	local pal = c.pal
	local rng = c.rng
	local SLATE1 = pal.Mid:Lerp(pal.Light, 0.14)
	local SLATE2 = pal.Mid:Lerp(pal.Light, 0.27)
	local SLATE3 = pal.Mid:Lerp(pal.Light, 0.4)
	local SAND = pal.Ground
	local SAND_DARK = pal.Ground:Lerp(C.Dirt, 0.45)
	local SAND_LIGHT = pal.Ground:Lerp(WHITE, 0.18)

	------------------------------------------------------------ ground
	-- (east of x 70 the grotto tunnel's own floor runs in at z -20..16; the preview cuts
	-- the floor back under its tunnel, which slopes down)
	local back = if cutaway then MOUTH_Z else END_Z
	block(c, at(c, -1, -0.75, (back + FRONT_Z) / 2), Vector3.new(142, 1.5, FRONT_Z - back), SAND, nil, SOLID).Name = "Ground"
	if cutaway then
		for _, sx in { -1, 1 } do
			block(c, at(c, sx * (TUNNEL_W + 70) / 2, -0.75, (END_Z + MOUTH_Z) / 2), Vector3.new(70 - TUNNEL_W, 1.5, MOUTH_Z - END_Z), SAND, nil, SOLID)
		end
	end
	for _, z in { { END_Z, -20.5 }, { 16.5, FRONT_Z } } do
		block(c, at(c, 71, -0.75, (z[1] + z[2]) / 2), Vector3.new(2, 1.5, z[2] - z[1]), SAND, nil, SOLID)
	end
	-- dusty patches on a jittered grid (darker worn sand and pale blast dust), pebbles
	local patch = 0
	for _, gx in { -38, -19, 0, 19, 38 } do
		for _, gz in { -36, -18, 0, 46 } do
			patch += 1
			if rng:chance(0.7) then
				local color = if patch % 3 == 0 then SAND_LIGHT else SAND_DARK
				local base = at(c, gx + rng:range(-3, 3), 0, gz + rng:range(-3, 3)) * CFrame.Angles(0, rng:range(0, math.pi), 0)
				block(c, base * CFrame.new(0, -0.02, 0), Vector3.new(rng:range(6, 10), 0.2, rng:range(3.5, 5.5)), Geo.vary(color, rng, 0.03), nil, TINY)
			end
		end
	end
	for _ = 1, 16 do
		local s = rng:range(0.4, 0.9)
		local x, z = rng:range(-50, 50), rng:range(-44, 12)
		block(c, at(c, x, s * 0.25, z) * Geo.randomTilt(rng, 0.4), Vector3.new(s * 1.3, s * 0.6, s), Geo.vary(rng:pick({ pal.Dark, pal.Mid, pal.Light }), rng, 0.05), nil, TINY)
	end
	-- worn paths: entrance gate to the DEPTHS rails, side paths to the elevator, the shed, the grotto
	Style.path(model, pt(c, 0, 0, 8.5), pt(c, 0, 0, -19.5), 9, rng, { Kind = "Dirt" })
	Style.path(model, pt(c, -13, 0, 46), pt(c, -30, 0, 46), 6, rng, { Kind = "Dirt", TileEvery = 5 })
	Style.path(model, pt(c, 13, 0, 46), pt(c, 28, 0, 46), 6, rng, { Kind = "Dirt", TileEvery = 5 })
	Style.path(model, pt(c, 28, 0, -3), pt(c, 54, 0, -2), 6, rng, { Kind = "Dirt", TileEvery = 5 })
	-- the Giant Crystal plaza: a ring of dark flag tiles with copper studs
	local tiles = 20
	for i = 0, tiles - 1 do
		local a = (i + 0.5) / tiles * math.pi * 2
		local p = GIANT + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14)
		local onPath = math.abs(p.X) < 5.2 or (p.X > 22 and p.Z > -7 and p.Z < 2)
		if not onPath then
			local cf = at(c, p.X, 0.05, p.Z) * CFrame.Angles(0, -a, 0)
			block(c, cf, Vector3.new(2.2, 0.25, 3.6), Geo.vary(C.StoneDark, rng, 0.05), nil, TINY)
			if i % 3 == 0 then
				block(c, cf * CFrame.new(0, 0.2, 0), Vector3.new(0.7, 0.2, 0.7), pal.Crystal, NEON, TINY)
			end
		end
	end

	------------------------------------------------------------ walls
	local sideSteps: { Step } = {
		{ Face = 0, Top = 7, Color = SLATE1 },
		{ Face = 6.5, Top = 13, Color = SLATE2 },
		{ Face = 11, Top = 18, Color = SLATE3 },
	}
	-- by the grotto door the top step rises over Land's grotto roof (up to +25)
	local grottoSteps: { Step } = {
		{ Face = 0, Top = 7, Color = SLATE1 },
		{ Face = 6.5, Top = 13, Color = SLATE2 },
		{ Face = 11, Top = 26, Color = SLATE3 },
	}
	local bandSteps: { Step } = { { Face = -0.5, Top = 17, Color = SLATE2 } }
	local outer = OUTER_X - PIT_X
	local north, south = Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)
	-- west: back corner to the band, the band behind the portal, the band to the town cliff
	terrace(c, "west", wallFrame(c, Vector3.new(-PIT_X, 0, END_Z), north), BAND_Z0 - END_Z, sideSteps, outer, { TrimEnd = STAGGER, Veins = 0.15 })
	terrace(c, "westBand", wallFrame(c, Vector3.new(-BAND_X, 0, BAND_Z0), north), BAND_Z1 - BAND_Z0, bandSteps, OUTER_X - BAND_X)
	terrace(c, "westFront", wallFrame(c, Vector3.new(-PIT_X, 0, BAND_Z1), north), FRONT_Z - BAND_Z1, sideSteps, outer, { TrimStart = STAGGER })
	-- east: the same, with the grotto door (a slot through the terraces and a rock lintel)
	terrace(c, "eastFront", wallFrame(c, Vector3.new(PIT_X, 0, FRONT_Z), south), FRONT_Z - BAND_Z1, sideSteps, outer, { TrimEnd = STAGGER })
	terrace(c, "eastBand", wallFrame(c, Vector3.new(BAND_X, 0, BAND_Z1), south), BAND_Z1 - BAND_Z0, bandSteps, OUTER_X - BAND_X)
	local doorN, doorS = DOOR_Z1 + 0.5, DOOR_Z0 - 0.5
	terrace(c, "eastGrotto", wallFrame(c, Vector3.new(PIT_X, 0, BAND_Z0), south), BAND_Z0 - doorN, grottoSteps, outer, { TrimStart = STAGGER, TrimEnd = STAGGER })
	terrace(c, "eastGrotto", wallFrame(c, Vector3.new(PIT_X, 0, doorS), south), doorS + 21, grottoSteps, outer, { TrimStart = STAGGER })
	terrace(c, "east", wallFrame(c, Vector3.new(PIT_X, 0, -21), south), -21 - END_Z, sideSteps, outer, { Veins = 0.15 })
	do
		-- the lintel over the grotto door (its underside a little above Land's tunnel roof at +11)
		local x0, x1 = 60, OUTER_X
		local y0, y1 = DOOR_H + 0.2, 26
		local zc, d = (doorN + doorS) / 2, doorN - doorS + 0.2
		block(c, at(c, (x0 + x1) / 2, (y0 + y1) / 2, zc), Vector3.new(x1 - x0, y1 - y0, d), Geo.vary(SLATE2, rng, 0.03), nil, SOLID)
		block(c, at(c, (x0 + x1) / 2, y1 - 0.7, zc), Vector3.new(x1 - x0 + 0.24, 1.4, d + 0.24), C.DirtDark, nil, TINY)
		block(c, at(c, (x0 + x1) / 2, y1 + 0.4, zc), Vector3.new(x1 - x0 + 0.5, 0.8, d + 0.5), C.Grass, nil, SOLID)
		for _, y in { 15, 20.5 } do
			block(c, at(c, x0 - 0.15, y, zc), Vector3.new(0.7, 0.8, d + 0.1), pal.Light:Lerp(WHITE, 0.25), nil, TINY)
		end
		-- copper studs framing the way in
		for _, z in { DOOR_Z0 - 0.4, DOOR_Z1 + 0.4 } do
			block(c, at(c, x0 - 0.2, y0 - 0.4, z), Vector3.new(0.5, 0.8, 0.8), pal.Crystal, NEON, TINY)
		end
	end
	-- back: terraces either side of the DEPTHS portal, a single tall step behind the falls
	-- pools and beside the ForgeWorks chute; bare slate up to the massif
	local backSteps: { Step } = {
		{ Face = 0, Top = 7, Color = SLATE1 },
		{ Face = 4, Top = 16, Color = SLATE2 },
		{ Face = 8, Top = 34, Color = SLATE3 },
	}
	local fallsStep: { Step } = { { Face = 7, Top = 34, Color = SLATE3 } }
	local chuteStep: { Step } = { { Face = 8, Top = 34, Color = SLATE3 } }
	local westward = Vector3.new(-1, 0, 0)
	local backOuter = BACK_Z - END_Z
	terrace(c, "back", wallFrame(c, Vector3.new(OUTER_X, 0, BACK_Z), westward), OUTER_X - 35, fallsStep, backOuter, { Bare = true })
	terrace(c, "back", wallFrame(c, Vector3.new(35, 0, BACK_Z), westward), 8, backSteps, backOuter, { Bare = true, TrimStart = STAGGER, TrimEnd = STAGGER, Veins = 0.3 })
	terrace(c, "back", wallFrame(c, Vector3.new(27, 0, BACK_Z), westward), 27 - HEAD_X, chuteStep, backOuter, { Bare = true })
	terrace(c, "back", wallFrame(c, Vector3.new(-HEAD_X, 0, BACK_Z), westward), 35 - HEAD_X, backSteps, backOuter, { Bare = true, TrimStart = STAGGER, TrimEnd = STAGGER, Veins = 0.3 })
	terrace(c, "back", wallFrame(c, Vector3.new(-35, 0, BACK_Z), westward), OUTER_X - 35, fallsStep, backOuter, { Bare = true })
	-- rubble at the wall feet (clear of the scaffold, the band and the door)
	talus(c, wallFrame(c, Vector3.new(-PIT_X, 0, -46), north), 42, 6.5)
	talus(c, wallFrame(c, Vector3.new(-PIT_X, 0, 41), north), 13, 6.5)
	talus(c, wallFrame(c, Vector3.new(PIT_X, 0, 54), south), 13, 6.5)
	talus(c, wallFrame(c, Vector3.new(PIT_X, 0, -12), south), 34, 6.5)
	talus(c, wallFrame(c, Vector3.new(34.5, 0, BACK_Z), westward), 7, 3.5)
	talus(c, wallFrame(c, Vector3.new(-22.5, 0, BACK_Z), westward), 12, 4)

	if cutaway then
		tunnel(c, SLATE2, SLATE3, SLATE1)
		-- stand-in for Railway's quarry line (the track the ore trains take at z +24)
		Style.rails(model, pt(c, -66, 0, 24), pt(c, 66, 0, 24), { SleeperEvery = 3 })
	end

	------------------------------------------------------------ wall crystals (copper and quartz)
	local east, west = Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0)
	wallCrystal(c, Vector3.new(-PIT_X - 0.6, 3.5, -30), west, 0.95, 6, 5, false, 11)
	wallCrystal(c, Vector3.new(-PIT_X - 0.6, 3.2, -14), west, 1.0, 5, 4, true, 12)
	wallCrystal(c, Vector3.new(-PIT_X - 7.1, 9.5, -40), west, 0.9, 6, 5.5, false, 13)
	wallCrystal(c, Vector3.new(-PIT_X - 3.5, 6.8, -45), UP, 0, 6, 5, true, 14)
	wallCrystal(c, Vector3.new(-PIT_X - 0.6, 3.2, 49), west, 1.0, 5, 4, true, 15)
	wallCrystal(c, Vector3.new(PIT_X + 0.6, 3.5, -32), east, 0.95, 6, 5, false, 16)
	wallCrystal(c, Vector3.new(PIT_X + 0.6, 4, -16), east, 1.0, 5, 4.5, true, 17)
	wallCrystal(c, Vector3.new(PIT_X + 7.1, 9.5, -42), east, 0.9, 6, 5, false, 18)
	wallCrystal(c, Vector3.new(PIT_X + 3.5, 6.8, -45), UP, 0, 6, 5, true, 19)
	wallCrystal(c, Vector3.new(PIT_X + 0.6, 3.5, 47), east, 0.95, 6, 5, false, 20)
	wallCrystal(c, Vector3.new(31, 4, BACK_Z - 0.6), north, 0.6, 6, 5, false, 21)
	wallCrystal(c, Vector3.new(-28.5, 4, BACK_Z - 0.6), north, 0.6, 6, 5, false, 22)
	wallCrystal(c, Vector3.new(31, 10.5, BACK_Z - 4.6), north, 0.85, 5, 4, true, 23)
	wallCrystal(c, Vector3.new(-30, 10.5, BACK_Z - 4.6), north, 0.85, 5, 4, true, 24)
	wallCrystal(c, Vector3.new(54, 22, BACK_Z - 7.6), north, 0.9, 6, 5, false, 25)
	wallCrystal(c, Vector3.new(-54, 24, BACK_Z - 7.6), north, 0.9, 6, 5, true, 26)

	------------------------------------------------------------ spawns and markers
	local spawns = MineKit.spawns(model)
	local deep = {
		{ -43, -40 }, { -34, -40 }, { -25, -39 }, { -39, -31 }, { -30, -31 }, { -21, -30 }, { -12, -30 },
		{ 45, -40 }, { 36, -40 }, { 40, -31 }, { 31, -31 }, { 22, -30 }, { 13, -30 },
	}
	local shallow = {
		{ -44, -17 }, { -35, -17 }, { -26, -17 }, { -17, -16 }, { -40, -8 }, { -31, -8 }, { -22, -7 }, { -36, 1 }, { -27, 1 }, { -18, 2 },
		{ 29, -18 }, { 38, -18 }, { 47, -18 }, { 33, -11 }, { 30, 6 }, { 39, 7 },
	}
	for _, p in deep do
		spawns.add(at(c, p[1], 0, p[2]), true)
	end
	for _, p in shallow do
		spawns.add(at(c, p[1], 0, p[2]), false)
	end
	MineKit.marker(model, "GiantSpawn", at(c, GIANT.X, 0, GIANT.Z))
	MineKit.marker(model, "Entrance", at(c, 0, 0, 8))

	------------------------------------------------------------ entrance: gate, elevator, name sign
	-- (players come down Land's ramp, cross the track and walk in under the gate)
	MineKit.gate(model, CFrame.lookAt(pt(c, 0, 0, 12), pt(c, 0, 0, 13)), 12, Floor.Index, { pal.Mid, pal.Light, pal.Dark })
	MineKit.elevator(model, CFrame.lookAt(pt(c, -36, 0, 46), pt(c, -35, 0, 46)), Floor.Index)
	do
		local s = at(c, -17, 0, 45)
		for _, sx in { -1, 1 } do
			block(c, s * CFrame.new(sx * 5.6, 3.2, 0), Vector3.new(0.8, 6.4, 0.8), C.WoodDark)
		end
		Style.sign(model, s * CFrame.new(0, 5.4, 0) * CFrame.Angles(0, math.pi, 0), "GREYSTONE", 11.6, 2.3, { DoubleSided = true })
		for _, sx in { -1, 1 } do
			block(c, s * CFrame.new(sx * 2.6, 3.65, 0), Vector3.new(0.14, 1.2, 0.14), C.Iron, nil, TINY)
		end
		Style.sign(model, s * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.pi, 0), "QUARRY", 7, 1.5, { DoubleSided = true, Depth = 0.4 })
	end
	-- in the preview only: the Mine Lift is Railway's in the game (floor 1 loads at the Mine Station)

	------------------------------------------------------------ the scaffold, walkway and rails on the west wall
	do
		local x0, x1 = -PIT_X + 0.6, -PIT_X + 5
		local z0, z1 = -2, 12
		local zc = (z0 + z1) / 2
		local cx = (x0 + x1) / 2
		local top = sideSteps[1].Top + 1.25
		for _, x in { x0, x1 } do
			for _, z in { z0 + 0.5, zc, z1 - 0.5 } do
				block(c, at(c, x, top / 2, z), Vector3.new(0.6, top, 0.6), C.WoodDark)
			end
		end
		Style.planks(model, at(c, cx, 4, zc), Vector3.new(x1 - x0 + 1, 0.4, z1 - z0), rng, { PlankWidth = 1.7 })
		Style.planks(model, at(c, cx, top, zc), Vector3.new(x1 - x0 + 1, 0.4, z1 - z0), rng, { PlankWidth = 1.7 })
		for _, zz in { { z0 + 0.5, zc }, { zc, z1 - 0.5 } } do
			beam(c, Vector3.new(x1 + 0.35, 0.4, zz[1]), Vector3.new(x1 + 0.35, 3.6, zz[2]), 0.35, C.Wood, GHOST)
		end
		ladder(c, Vector3.new(x1 + 0.6, 0, zc - 3), Vector3.new(1, 0, 0), 4.2)
		ladder(c, Vector3.new(x1 + 0.6, 4, z1 - 3), Vector3.new(1, 0, 0), top - 4)
		Style.fence(model, pt(c, x1 + 0.2, top, z0 + 0.4), pt(c, x1 + 0.2, top, z1 - 0.4), { Height = 2.4, PostEvery = 7 })
		-- a bridge to the walkway on the first terrace, a ladder up to the second
		Style.planks(model, at(c, -PIT_X - 0.6, top, 0), Vector3.new(4.2, 0.4, 3), rng, { PlankWidth = 1.7 })
		deck(c, Vector3.new(-PIT_X - 3.25, top, -20.5), Vector3.new(3.2, 0.4, 39), 2)
		Style.fence(model, pt(c, -PIT_X - 1.9, top, -39.5), pt(c, -PIT_X - 1.9, top, -2), { Height = 2.4, PostEvery = 9 })
		ladder(c, Vector3.new(-PIT_X - 5.9, top - 0.2, -22), Vector3.new(1, 0, 0), sideSteps[2].Top - top + 1)
		Style.crate(model, at(c, cx - 0.6, top, z1 - 2.4), rng, 2)
		Style.barrel(model, pt(c, cx, top, z0 + 2.4), rng)
		block(c, at(c, x1 - 0.6, top + 1.8, zc), Vector3.new(0.5, 3.6, 0.5), C.WoodDark)
		block(c, at(c, x1 + 0.1, top + 3.5, zc), Vector3.new(1.9, 0.4, 0.4), C.WoodDark, nil, TINY)
		local lamp = Style.lantern(model, at(c, x1 + 0.6, top + 3.3, zc), { Kind = "Hanging" })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 16, 1.2)
		end
		local walkLamp = Style.lantern(model, at(c, -PIT_X - 4.6, top, -30) * CFrame.Angles(0, -math.pi / 2, 0), { Height = 5 })
		if walkLamp.PrimaryPart then
			light(c, walkLamp.PrimaryPart, C.Lamp, 16, 1.2)
		end
		-- a short spur of rails with a cart of ore beside the scaffold
		Style.rails(model, pt(c, -46.5, 0, -4), pt(c, -46.5, 0, 12))
		Style.mineCart(model, at(c, -46.5, 0, 4), rng, { Load = "Ore" })
		block(c, at(c, -46.5, 1, 12.4), Vector3.new(4, 0.8, 0.8), C.WoodDark)
		block(c, at(c, -46.5, 1, 12.85), Vector3.new(2.4, 0.5, 0.12), C.Roof, nil, TINY)
		Style.crate(model, at(c, -49.5, 0, -7), rng)
	end

	------------------------------------------------------------ the tool shed (front right, door toward the ramp)
	do
		local s = at(c, 36, 0, 47.5)
		local w, d, h = 10, 8, 6
		block(c, s * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.8, 0.6, d + 0.8), C.StoneDark, nil, SOLID)
		block(c, s * CFrame.new(0, 0.6 + h / 2, d / 2 - 0.3), Vector3.new(w, h, 0.6), C.WoodLight)
		block(c, s * CFrame.new(0, 0.6 + h / 2, -d / 2 + 0.3), Vector3.new(w, h, 0.6), C.WoodLight)
		block(c, s * CFrame.new(w / 2 - 0.3, 0.6 + h / 2, 0), Vector3.new(0.6, h, d - 1.2), C.Wood)
		block(c, s * CFrame.new(-w / 2 + 0.3, 0.6 + h / 2, 0), Vector3.new(0.6, h, d - 1.2), C.Wood)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				block(c, s * CFrame.new(sx * (w / 2 - 0.2), 0.6 + h / 2, sz * (d / 2 - 0.2)), Vector3.new(0.8, h, 0.8), C.WoodDark, nil, TINY)
			end
		end
		for _, sz in { -1, 1 } do
			local gz = sz * (d / 2 - 0.3)
			Geo.wedge(model, s * CFrame.new(w / 4, 0.6 + h + 1.5, gz) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(0.6, 3, w / 2), C.WoodLight, nil, TINY)
			Geo.wedge(model, s * CFrame.new(-w / 4, 0.6 + h + 1.5, gz) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.6, 3, w / 2), C.WoodLight, nil, TINY)
		end
		Style.gableRoof(model, s * CFrame.new(0, 0.6 + h, 0) * CFrame.Angles(0, math.pi / 2, 0), d + 1.6, w + 2, 3.2)
		-- door toward the ramp, a lit window and the sign toward the pit, a lantern by the door
		block(c, s * CFrame.new(-w / 2 - 0.05, 0.6 + 2.3, 1), Vector3.new(0.3, 4.6, 2.8), C.WoodDark, nil, TINY)
		Style.window(model, s * CFrame.new(0, 0.6 + 3.2, -d / 2 - 0.05), 2.4, 1.8)
		Style.sign(model, s * CFrame.new(0, 0.6 + 5.1, -d / 2 - 0.2), "TOOLS", 4, 1.1, { Depth = 0.3 })
		block(c, s * CFrame.new(-w / 2 - 0.4, 0.6 + 5.5, -1.4), Vector3.new(0.9, 0.25, 0.25), C.Iron, nil, TINY)
		local lamp = Style.lantern(model, s * CFrame.new(-w / 2 - 0.75, 0.6 + 5.4, -1.4), { Kind = "Hanging" })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 16, 1.3)
		end
		-- tool rack on the wall: two pickaxes and a shovel
		local rack = s * CFrame.new(-w / 2 - 0.5, 0, -2.4)
		block(c, rack * CFrame.new(0, 3.6, 0), Vector3.new(0.35, 0.35, 3.2), C.WoodDark, nil, TINY)
		for i, z in { -1, 0, 1 } do
			local t = rack * CFrame.new(-0.1, 2.3, z) * CFrame.Angles(if i == 2 then 0 else 0.12 * z, 0, 0)
			block(c, t, Vector3.new(0.22, 2.8, 0.22), C.Wood, nil, TINY)
			if i == 2 then
				block(c, t * CFrame.new(0, -1.5, 0), Vector3.new(0.12, 0.9, 0.7), C.IronLight, METAL, TINY)
			else
				block(c, t * CFrame.new(0, 1.3, 0), Vector3.new(0.3, 0.3, 1.6), C.IronLight, METAL, TINY)
			end
		end
		Style.crate(model, at(c, 28.6, 0, 51.5), rng)
		Style.crate(model, at(c, 43.6, 0, 44.6), rng, 2.4)
		Style.crate(model, at(c, 43.7, 2.4, 44.6), rng, 1.8)
		Style.barrel(model, pt(c, 44, 0, 50.5), rng, C.Copper)
	end

	------------------------------------------------------------ lanterns, props by the grotto door and the elevator
	local postLamps = { -- x, z, lamp direction (x, z)
		{ -7.5, 4, 1, 0 },
		{ -7.5, -18, 1, 0 },
		{ 7.5, -24, -1, 0 },
		{ -12, 42.2, 0, -1 },
	}
	for _, l in postLamps do
		local p = pt(c, l[1], 0, l[2])
		local dir = c.o:VectorToWorldSpace(Vector3.new(l[3], 0, l[4]))
		local lamp = Style.lantern(model, CFrame.lookAt(p, p + dir), { Height = 6.5 })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 18, 1.3)
		end
	end
	for _, a in { 110, 250 } do
		local r = math.rad(a)
		Style.lantern(model, at(c, GIANT.X + math.cos(r) * 15.5, 0, GIANT.Z + math.sin(r) * 15.5), { Kind = "Ground" })
	end
	Style.lantern(model, at(c, 52, 0, DOOR_Z0 - 2.5), { Kind = "Pillar", Height = 4 })
	Style.lantern(model, at(c, 52, 0, DOOR_Z1 + 2.5), { Kind = "Pillar", Height = 4 })
	Style.crate(model, at(c, 50, 0, 9), rng)
	Style.barrel(model, pt(c, -44.5, 0, 50.5), rng)
	Style.crate(model, at(c, -44.5, 0, 46.5), rng)

	------------------------------------------------------------ trees, bushes and flowers on the rim
	local kinds = { "Green", "Orange", "Green", "Pink", "Green", "Yellow" }
	local perWall: { [string]: number } = {}
	local trees = 0
	for _, top in c.tops do
		local n = perWall[top.wall] or 0
		if top.rim then
			n += 1
			perWall[top.wall] = n
			local p = top.cf.Position
			if n % 3 == 2 and trees < 10 then
				trees += 1
				Style.tree(model, CFrame.new(p) * CFrame.new(rng:range(-1, 1), -0.3, rng:range(-1, 1)), kinds[trees % #kinds + 1], rng, rng:range(0.95, 1.12))
			elseif n % 3 == 0 then
				Style.bush(model, (top.cf * CFrame.new(rng:range(-1.5, 1.5), 0, -top.d * 0.32)).Position, if rng:chance(0.5) then C.LeafGreen else C.LeafGreenDark, rng, rng:range(2.4, 3.2))
			elseif rng:chance(0.5) then
				Style.flowers(model, (top.cf * CFrame.new(0, 0, -top.d * 0.3)).Position, rng:pick({ C.FlowerYellow, C.FlowerWhite, C.FlowerPink }), rng, 4, 1.6)
			end
		elseif top.wall ~= "back" and rng:chance(0.08) then
			Style.bush(model, (top.cf * CFrame.new(0, -0.1, top.d * 0.2)).Position, C.LeafGreen, rng, rng:range(1.8, 2.4))
		end
	end

	model.Parent = parent
	return model
end

return Floor
