--[[
	Floor 1, GREYSTONE QUARRY (blaster 1+): the first mine floor players see.
	An open-pit quarry under the warm sunset sky (no ceiling): terraced
	blue-grey slate walls with pale strata stripes like the rocks, a grass
	rim with trees, a sandy floor with dusty patches and a worn path from the
	entrance, wooden scaffolds, ladders and plank walkways on the terraces,
	mine carts on rails, a tool shed, lanterns on posts, copper and quartz
	crystal clusters sprouting from the walls, and in the back cliff the big
	glowing tunnel mouth down to the Ember Caves.

	Contract: MineKit header (Floor.Index, Floor.Size, Floor.build). Local
	frame: origin = ground center of the pit, +Z = front (entrance, gate,
	elevator), -Z = back ("deep" rocks, the tunnel). Pit floor: x -46..46,
	z -39..48 (the tunnel mouth at z -39); walls rise in three terraces.
	opts.Cutaway: the front wall is a low grass bank so a camera at +Z sees in.
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
Floor.Size = Vector3.new(140, 44, 120)

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
local WALL_X = 46 -- side wall faces at x = +-46
local BACK_Z = -42 -- back wall face
local MOUTH_Z = -39 -- front face of the tunnel headland
local FRONT_Z = 48 -- front edge of the pit
local TUNNEL_W = 7 -- tunnel half width
local TUNNEL_H = 14 -- tunnel opening height
local TUNNEL_END = -56 -- the glowing end of the tunnel
local TUNNEL_DROP = 4 -- the tunnel floor slopes down this much (the way down)
local GIANT = Vector3.new(11, 0, -6) -- Giant Crystal plaza (beside the main path, so the tunnel stays in view)
local LIFT = Vector3.new(38, 0, 6)

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

--[[
	A terraced slate wall: voxel columns (~7 studs) per step, each with pale
	strata stripes on its face (shared heights along the wall, so the layers
	read as continuous), a pale slate ledge (sometimes a grass lip) on the lower
	steps and a dirt band + grass cap on the top step. `frame` = wallFrame, the
	steps' Face = distance from the pit edge into the cliff. trimStart/trimEnd
	cut each step shorter at the ends (stagger so end faces never share a plane).
]]
local function terrace(c: Ctx, wall: string, frame: CFrame, length: number, steps: { Step }, outer: number, trimStart: { number }?, trimEnd: { number }?, veins: number?)
	local rng, pal = c.rng, c.pal
	local n = math.max(1, math.floor(length / 7 + 0.5))
	local colW = length / n
	local strata: { { number } } = {}
	for k, s in steps do
		local below = if k == 1 then 0 else steps[k - 1].Top
		local span = s.Top - below
		strata[k] = { below + span * rng:range(0.24, 0.34), below + span * rng:range(0.6, 0.7) }
	end
	for i = 0, n - 1 do
		local x0, x1 = i * colW, (i + 1) * colW
		for k, s in steps do
			local a = math.max(x0, if trimStart then trimStart[k] or 0 else 0)
			local b = math.min(x1, length - (if trimEnd then trimEnd[k] or 0 else 0))
			if b - a >= 1 then
				local last = k == #steps
				local below = if k == 1 then 0 else steps[k - 1].Top
				local zFace = s.Face + rng:range(-0.3, 0.3)
				local zBack = if last then outer else steps[k + 1].Face + 2
				local jitter = if last then math.min(1.6, s.Top * 0.2) else 0.5
				local h = s.Top + rng:range(-jitter, jitter)
				local w = b - a + 0.06
				local x = (a + b) / 2
				local depth = zBack - zFace
				Geo.block(c.m, frame * CFrame.new(x, h / 2, zFace + depth / 2), Vector3.new(w, h, depth), Geo.vary(s.Color, rng, 0.035), nil, SOLID)
				-- strata: pale layers like the rocks
				if h - below > 3 then
					for j, y in strata[k] do
						if rng:chance(0.88) and y < h - 0.8 then
							local t = rng:range(0.55, 0.9)
							local color = if j == 1 then pal.Light:Lerp(WHITE, 0.2) else pal.Light:Lerp(WHITE, 0.45)
							block(c, frame * CFrame.new(x, y + rng:range(-0.18, 0.18), zFace - 0.15), Vector3.new(w + 0.12, t, 0.7), Geo.vary(color, rng, 0.03), nil, TINY)
						end
					end
				end
				-- a broken chunk sticking out of the face
				if rng:chance(0.35) and h - below > 4 then
					local sw, sh = rng:range(1.6, 3), rng:range(1.2, 2.2)
					local y = rng:range(below + sh, math.max(below + sh + 0.1, h - sh))
					local color = if rng:chance(0.5) then pal.Dark else s.Color:Lerp(pal.Light, 0.45)
					block(c, frame * CFrame.new(x + rng:range(-w * 0.3, w * 0.3), y, zFace - 0.4), Vector3.new(sw, sh, 1.2), Geo.vary(color, rng, 0.04), nil, TINY)
				end
				-- a thin copper glow vein (lowest step only)
				if k == 1 and veins and rng:chance(veins) and h > 5 then
					local dir = if rng:chance(0.5) then 0 else math.pi
					crack(c, frame * CFrame.new(0, 0, zFace - 0.05), x + rng:range(-w * 0.3, 0), rng:range(1.8, h - 3), dir + rng:range(-0.5, 0.5), 3, 1.4)
				end
				if last then
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
		local s = rng:range(1.2, 2.8)
		local x = (i + rng:range(0.2, 0.8)) * every
		local z = -rng:range(0.2, 2.2)
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
	local n = math.floor(height / 1.1)
	for i = 1, n do
		local p = foot + Vector3.new(0, i * 1.1 - 0.3, 0)
		beam(c, p - side * 0.8, p + side * 0.8, 0.22, C.Wood, TINY)
	end
end

-- A plank deck on short legs; `center` = top center (local), X across, Z along.
local function deck(c: Ctx, center: Vector3, size: Vector3, legDown: number, yaw: number)
	local cf = at(c, center.X, center.Y, center.Z) * CFrame.Angles(0, yaw, 0)
	Style.planks(c.m, cf, size, c.rng)
	local n = math.max(1, math.floor(size.Z / 6))
	for i = 0, n do
		local z = -size.Z / 2 + 0.4 + (size.Z - 0.8) * i / n
		for _, sx in { -1, 1 } do
			block(c, cf * CFrame.new(sx * (size.X / 2 - 0.35), -legDown / 2, z), Vector3.new(0.5, legDown, 0.5), C.WoodDark, nil, GHOST)
		end
	end
end

---------------------------------------------------------------- the build

-- The tunnel headland in the back cliff: the big glowing way down to the Ember Caves.
local function tunnel(c: Ctx, slate2: Color3, slate3: Color3, slate1: Color3)
	local rng, pal, m = c.rng, c.pal, c.m
	local depth = MOUTH_Z - TUNNEL_END
	local zMid = (MOUTH_Z + TUNNEL_END) / 2
	local headH = 23
	local face = MOUTH_Z + 0.15 -- strata/veins sit just in front of the headland face (+Z)
	local flip = CFrame.Angles(0, math.pi, 0) -- signs face the pit (+Z)
	-- the headland: two jambs, the lintel, a rear tier, topsoil and grass
	for _, sx in { -1, 1 } do
		local x = sx * (TUNNEL_W + 16) / 2
		block(c, at(c, x, headH / 2, zMid), Vector3.new(16 - TUNNEL_W, headH, depth), Geo.vary(slate2, rng, 0.03), nil, SOLID)
	end
	block(c, at(c, 0, (TUNNEL_H + headH) / 2, zMid), Vector3.new(TUNNEL_W * 2 + 0.1, headH - TUNNEL_H, depth), Geo.vary(slate2, rng, 0.03), nil, SOLID)
	block(c, at(c, 0, headH + 2.5, -50.5), Vector3.new(24, 5, 11), Geo.vary(slate3, rng, 0.03), nil, SOLID)
	block(c, at(c, 0, headH - 0.7, zMid), Vector3.new(32.3, 1.4, depth + 0.3), C.DirtDark, nil, TINY)
	block(c, at(c, 0, headH + 0.4, zMid), Vector3.new(32.6, 0.8, depth + 0.6), C.Grass, nil, SOLID)
	block(c, at(c, 0, headH + 5.4, -50.5), Vector3.new(24.5, 0.8, 11.5), C.Grass, nil, SOLID)
	-- strata across the face (the upper bands run over the opening)
	for i, y in { 3.4, 7.4, 11.8 } do
		for _, sx in { -1, 1 } do
			local color = if i == 2 then pal.Light:Lerp(WHITE, 0.3) else pal.Light
			block(c, at(c, sx * 13.2, y + sx * 0.15, face), Vector3.new(5.7, 0.8, 0.7), color, nil, TINY)
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
	block(c, at(c, 0, (TUNNEL_H - TUNNEL_DROP) / 2, TUNNEL_END - 0.6), Vector3.new(TUNNEL_W * 2 + 2, TUNNEL_H + TUNNEL_DROP + 2, 1), C.StoneDeep, nil, GHOST)
	-- timber frames inside (silhouettes against the glow) and the big portal frame
	local frameColor = Color3.fromRGB(52, 36, 30)
	for i, z in { -43, -47, -51, -54.6 } do
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
	block(c, at(c, 0, 15.35, pz), Vector3.new(TUNNEL_W * 2 + 3, 0.3, 2.3), C.WoodDark, nil, TINY)
	-- signs: EMBER CAVES with arrows down, and the next floor's blaster level
	Style.sign(m, at(c, 0, 20.3, MOUTH_Z + 0.9) * flip, "EMBER CAVES", 12, 2.8, { Kind = "Wood" })
	for _, sx in { -1, 1 } do
		Style.icon(m, at(c, sx * 8.4, 20.3, MOUTH_Z + 0.3) * flip, "ArrowDown", 2.2, C.Fire, NEON)
	end
	Style.sign(m, at(c, 0, 14.2, pz + 1.15) * flip, "BLASTER LV 3+", 8, 1.4, { Kind = "Stone", Depth = 0.3, TextColor = C.FireCore })
	for _, sx in { -1, 1 } do
		Style.lantern(m, at(c, sx * (TUNNEL_W - 2.2), 13.2, pz + 0.6), { Kind = "Hanging", Color = C.FireCore })
	end
	-- glow veins radiating from the opening
	local faceF = at(c, 0, 0, MOUTH_Z + 0.08)
	for _, v in { { -10.2, 4.6, math.pi + 0.3 }, { -10.2, 13.6, math.pi - 0.5 }, { 10.2, 9.4, 0.25 }, { 10.2, 14.6, 0.6 }, { 10.2, 1.6, -0.1 } } do
		crack(c, faceF, v[1], v[2], v[3], 2, 1.3)
	end
	-- rails up out of the tunnel, a cart on the slope (silhouette) and one at the mouth
	Style.rails(m, pt(c, 2.5, floorY(-55), -55), pt(c, 2.5, 0, MOUTH_Z))
	Style.rails(m, pt(c, 2.5, 0, MOUTH_Z), pt(c, 2.5, 0, -28.5))
	Style.mineCart(m, CFrame.lookAt(pt(c, 2.5, floorY(-48), -48), pt(c, 2.5, floorY(-46), -46)), rng, { Load = "Ore" })
	Style.mineCart(m, at(c, 2.5, 0, -33.5), rng, { Load = "Ore" })
	block(c, at(c, 2.5, 1.05, -28.3), Vector3.new(4, 0.8, 0.8), C.WoodDark)
	block(c, at(c, 2.5, 1.05, -28.75), Vector3.new(2.4, 0.5, 0.12), C.Roof, nil, TINY)
	for _, sx in { -1, 1 } do
		block(c, at(c, 2.5 + sx * 1.5, 0.6, -28.3), Vector3.new(0.6, 1.2, 0.6), C.WoodDark)
	end
	-- light spilling out: the end, the middle, the mouth; embers and a warm haze
	if endGlow then
		light(c, endGlow, C.Fire, 26, 2.2)
		local embers = Style.emitter(endGlow, "Embers", C.FireCore, 10)
		embers.EmissionDirection = Enum.NormalId.Back
		embers.Speed = NumberRange.new(2, 5)
		embers.Lifetime = NumberRange.new(2.5, 4)
	end
	local hidden = { CanTouch = false, CanQuery = false, CanCollide = false, CastShadow = false, Transparency = 1 }
	light(c, block(c, at(c, 0, 3, -34), Vector3.new(0.2, 0.2, 0.2), C.Fire, nil, hidden), C.Fire, 26, 1.4)
	Style.emitter(block(c, at(c, 0, floorY(-52), -52), Vector3.new(8, 0.2, 2), C.Fire, nil, hidden), "Mist", C.Fire, 3)
	-- crystals: big copper and quartz clusters at the feet and on top of the headland
	local feet = wallCrystal(c, Vector3.new(-11.2, -0.3, MOUTH_Z + 1.6), Vector3.new(0, 0, 1), 0.3, 9, 7.5, false, 1)
	wallCrystal(c, Vector3.new(11.6, -0.3, MOUTH_Z + 1.6), Vector3.new(0, 0, 1), 0.35, 8, 6.5, true, 2)
	wallCrystal(c, Vector3.new(-14.6, -0.3, MOUTH_Z + 1), Vector3.new(-0.6, 0, 0.8).Unit, 0.5, 5, 4, true, 3)
	wallCrystal(c, Vector3.new(-10, headH - 0.2, -42), Vector3.new(0, 0, 1), 0.15, 8, 7, false, 4)
	wallCrystal(c, Vector3.new(9.5, headH - 0.2, -44), Vector3.new(0, 0, 1), 0.2, 7, 6, true, 5)
	wallCrystal(c, Vector3.new(-12.4, 18.4, MOUTH_Z - 0.6), Vector3.new(0, 0, 1), 0.95, 5, 3.6, false, 6)
	wallCrystal(c, Vector3.new(12.6, 11.5, MOUTH_Z - 0.6), Vector3.new(0, 0, 1), 1.0, 5, 3.6, false, 7)
	local copperGlow = feet:FindFirstChildWhichIsA("BasePart", true)
	if copperGlow then
		light(c, copperGlow, pal.Crystal, 14, 1)
	end
	for _, p in { { 15.8, -37.2 }, { -17.6, -37.6 } } do
		Style.boulder(m, pt(c, p[1], 0, p[2]), rng:range(2, 2.8), rng, { Color = slate1 })
	end
end

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
	block(c, at(c, 0, -0.75, (MOUTH_Z + 60) / 2), Vector3.new(96, 1.5, 60 - MOUTH_Z), SAND, nil, SOLID).Name = "Ground"
	for _, sx in { -1, 1 } do
		block(c, at(c, sx * (TUNNEL_W + 48) / 2, -0.75, -42.5), Vector3.new(48 - TUNNEL_W, 1.5, 7), SAND, nil, SOLID)
	end
	-- diorama skirt under the front edge (never seen in game)
	block(c, at(c, 0, -4.5, 59.5), Vector3.new(140, 6, 1), C.DirtDark, nil, GHOST)
	-- dusty patches on a jittered grid (no overlaps): darker worn sand and pale blast dust
	local patch = 0
	for _, gx in { -34, -17, 0, 17, 34 } do
		for _, gz in { -31, -13, 5, 23, 40 } do
			patch += 1
			if rng:chance(0.75) then
				local color = if patch % 3 == 0 then SAND_LIGHT else SAND_DARK
				local base = at(c, gx + rng:range(-3, 3), 0, gz + rng:range(-3, 3)) * CFrame.Angles(0, rng:range(0, math.pi), 0)
				block(c, base * CFrame.new(0, -0.02, 0), Vector3.new(rng:range(6, 10), 0.2, rng:range(3.5, 5.5)), Geo.vary(color, rng, 0.03), nil, TINY)
				block(c, base * CFrame.new(rng:range(-2, 2), 0.02, rng:range(-1.5, 1.5)) * CFrame.Angles(0, 0.6, 0), Vector3.new(rng:range(3.5, 5.5), 0.2, rng:range(2.5, 4)), Geo.vary(color, rng, 0.03), nil, TINY)
			end
		end
	end
	-- pebbles and slate chips
	for _ = 1, 40 do
		local s = rng:range(0.35, 0.9)
		local color = rng:pick({ pal.Dark, pal.Mid, pal.Light })
		block(c, at(c, rng:range(-43, 43), s * 0.25, rng:range(-37, 46)) * Geo.randomTilt(rng, 0.4), Vector3.new(s * 1.3, s * 0.6, s), Geo.vary(color, rng, 0.05), nil, TINY)
	end
	-- the worn path from the entrance to the plaza and on to the tunnel, side paths
	Style.path(model, pt(c, 0, 0, 55.5), pt(c, 0, 0, -34.5), 9, rng, { Kind = "Dirt" })
	Style.path(model, pt(c, 22, 0, 3), pt(c, 30, 0, 6), 7, rng, { Kind = "Dirt", TileEvery = 4 })
	Style.path(model, pt(c, -8, 0, 34), pt(c, -16, 0, 34), 6, rng, { Kind = "Dirt", TileEvery = 4 })
	-- the Giant Crystal plaza: a ring of dark flag tiles with copper studs
	local tiles = 28
	for i = 0, tiles - 1 do
		local a = (i + 0.5) / tiles * math.pi * 2
		local p = GIANT + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14)
		local onPath = math.abs(p.X) < 5.2 or (p.X > 18 and p.Z > -1 and p.Z < 6)
		if not onPath then
			local cf = at(c, p.X, 0.05, p.Z) * CFrame.Angles(0, -a, 0)
			block(c, cf, Vector3.new(1.8, 0.25, 3.1), Geo.vary(C.StoneDark, rng, 0.05), nil, TINY)
			if i % 3 == 0 then
				block(c, cf * CFrame.new(0, 0.2, 0), Vector3.new(0.6, 0.2, 0.6), pal.Crystal, NEON, TINY)
			end
		end
	end

	------------------------------------------------------------ walls
	local sideSteps: { Step } = {
		{ Face = 0, Top = 9, Color = SLATE1 },
		{ Face = 7, Top = 19, Color = SLATE2 },
		{ Face = 14, Top = 30, Color = SLATE3 },
	}
	local backSteps: { Step } = {
		{ Face = 0, Top = 10, Color = SLATE1 },
		{ Face = 6, Top = 20, Color = SLATE2 },
		{ Face = 12, Top = 31, Color = SLATE3 },
	}
	local stagger = { 0.8, 0.4, 0 }
	local leftF = wallFrame(c, Vector3.new(-WALL_X, 0, -60), Vector3.new(0, 0, 1))
	local rightF = wallFrame(c, Vector3.new(WALL_X, 0, 60), Vector3.new(0, 0, -1))
	terrace(c, "left", leftF, 120, sideSteps, 24, nil, stagger, 0.15)
	terrace(c, "right", rightF, 120, sideSteps, 24, stagger, nil, 0.15)
	local backR = wallFrame(c, Vector3.new(WALL_X + 1, 0, BACK_Z), Vector3.new(-1, 0, 0))
	local backL = wallFrame(c, Vector3.new(-16, 0, BACK_Z), Vector3.new(-1, 0, 0))
	terrace(c, "backR", backR, WALL_X + 1 - 16, backSteps, 18, nil, nil, 0.25)
	terrace(c, "backL", backL, WALL_X + 1 - 16, backSteps, 18, nil, nil, 0.25)
	terrace(c, "backMid", wallFrame(c, Vector3.new(16, 0, BACK_Z), Vector3.new(-1, 0, 0)), 32, { { Face = 14, Top = 32, Color = SLATE3 } }, 18)
	talus(c, wallFrame(c, Vector3.new(-WALL_X, 0, -41), Vector3.new(0, 0, 1)), 51, 4.6)
	talus(c, wallFrame(c, Vector3.new(-WALL_X, 0, 30), Vector3.new(0, 0, 1)), 14, 4.6)
	talus(c, wallFrame(c, Vector3.new(WALL_X, 0, 44), Vector3.new(0, 0, -1)), 84, 4.6)
	talus(c, wallFrame(c, Vector3.new(WALL_X - 1, 0, BACK_Z), Vector3.new(-1, 0, 0)), 27, 4.2)
	talus(c, wallFrame(c, Vector3.new(-18, 0, BACK_Z), Vector3.new(-1, 0, 0)), 27, 4.2)

	-- the front wall: a low grass bank for the preview, else terraces with the arrival tunnel
	if cutaway then
		local bank: { Step } = { { Face = 1.5, Top = 1.8, Color = SLATE1 } }
		terrace(c, "frontL", wallFrame(c, Vector3.new(-WALL_X, 0, FRONT_Z), Vector3.new(1, 0, 0)), WALL_X - 9, bank, 6)
		terrace(c, "frontR", wallFrame(c, Vector3.new(9, 0, FRONT_Z), Vector3.new(1, 0, 0)), WALL_X - 9, bank, 6)
	else
		local frontSteps: { Step } = {
			{ Face = 0, Top = 7, Color = SLATE1 },
			{ Face = 4, Top = 15, Color = SLATE2 },
			{ Face = 8, Top = 24, Color = SLATE3 },
		}
		terrace(c, "frontL", wallFrame(c, Vector3.new(-WALL_X, 0, FRONT_Z), Vector3.new(1, 0, 0)), WALL_X - TUNNEL_W, frontSteps, 12, nil, stagger)
		terrace(c, "frontR", wallFrame(c, Vector3.new(TUNNEL_W, 0, FRONT_Z), Vector3.new(1, 0, 0)), WALL_X - TUNNEL_W, frontSteps, 12, stagger, nil)
		-- the arrival tunnel from the town through the front cliff
		block(c, at(c, 0, 14.2, 54), Vector3.new(TUNNEL_W * 2 + 0.2, 2.4, 4), SLATE2, nil, SOLID)
		block(c, at(c, 0, 18.5, 58), Vector3.new(TUNNEL_W * 2 + 0.2, 11, 4), SLATE3, nil, SOLID)
		block(c, at(c, 0, 24.4, 58), Vector3.new(TUNNEL_W * 2 + 0.6, 0.8, 4.4), C.Grass, nil, SOLID)
		block(c, at(c, 0, 6.5, 59.6), Vector3.new(TUNNEL_W * 2, 13, 0.8), C.StoneDeep, nil, SOLID)
		for _, sx in { -1, 1 } do
			block(c, at(c, sx * (TUNNEL_W - 0.6), 6.5, 51.6), Vector3.new(1.4, 13, 1.4), C.WoodDark)
		end
		block(c, at(c, 0, 13.6, 51.6), Vector3.new(TUNNEL_W * 2 + 1.6, 1.6, 1.6), C.Wood)
		Style.lantern(model, at(c, 0, 12.8, 51.2), { Kind = "Hanging" })
	end
	talus(c, wallFrame(c, Vector3.new(-WALL_X + 4, 0, FRONT_Z + 1), Vector3.new(1, 0, 0)), WALL_X - 24, 5.5)
	talus(c, wallFrame(c, Vector3.new(20, 0, FRONT_Z + 1), Vector3.new(1, 0, 0)), WALL_X - 24, 5.5)

	tunnel(c, SLATE2, SLATE3, SLATE1)

	------------------------------------------------------------ wall crystals (copper and quartz)
	wallCrystal(c, Vector3.new(-WALL_X - 0.6, 4.5, -18), Vector3.new(1, 0, 0), 0.95, 6, 5, false, 11)
	wallCrystal(c, Vector3.new(-WALL_X - 0.6, 3.2, 6), Vector3.new(1, 0, 0), 1.0, 5, 4, true, 12)
	wallCrystal(c, Vector3.new(-WALL_X - 7.6, 13.5, -30), Vector3.new(1, 0, 0), 0.9, 6, 5.5, false, 13)
	wallCrystal(c, Vector3.new(-WALL_X - 3.5, 8.8, -38), UP, 0, 7, 6, false, 14)
	wallCrystal(c, Vector3.new(WALL_X + 0.6, 4, -20), Vector3.new(-1, 0, 0), 0.95, 6, 5, true, 15)
	wallCrystal(c, Vector3.new(WALL_X + 0.6, 5, 32), Vector3.new(-1, 0, 0), 1.0, 5, 4.5, false, 16)
	wallCrystal(c, Vector3.new(WALL_X + 7.6, 14, -10), Vector3.new(-1, 0, 0), 0.9, 6, 5, false, 17)
	wallCrystal(c, Vector3.new(WALL_X + 3.5, 8.8, -34), UP, 0, 6, 5, true, 18)
	wallCrystal(c, Vector3.new(-34.5, 7, BACK_Z - 0.6), Vector3.new(0, 0, 1), 0.6, 6, 5, false, 19)
	wallCrystal(c, Vector3.new(34.5, 7, BACK_Z - 0.6), Vector3.new(0, 0, 1), 0.6, 6, 5, true, 20)
	wallCrystal(c, Vector3.new(-38, 14, BACK_Z - 6.6), Vector3.new(0, 0, 1), 0.85, 7, 6, false, 21)
	wallCrystal(c, Vector3.new(27, 14, BACK_Z - 6.6), Vector3.new(0, 0, 1), 0.9, 6, 5, false, 22)

	------------------------------------------------------------ spawns and markers
	local spawns = MineKit.spawns(model)
	local deep = {
		{ -39, -36 }, { -30, -36 }, { -22, -35 }, { -36, -27 }, { -27, -27 }, { -19, -27 },
		{ 39, -35 }, { 30, -36 }, { 22, -36 }, { 36, -27 }, { 27, -27 }, { 19, -28 },
	}
	local shallow = {
		{ -38, -14 }, { -29, -14 }, { -20, -15 }, { -37, -5 }, { -28, -5 }, { -19, -6 }, { -35, 4 }, { -26, 4 },
		{ 38, -14 }, { 29, -15 }, { 36, -5 }, { 28, -6 },
		{ -30, 18 }, { -22, 19 }, { -14, 18 },
		{ 18, 19 }, { 26, 20 }, { 34, 18 },
	}
	for _, p in deep do
		spawns.add(at(c, p[1], 0, p[2]), true)
	end
	for _, p in shallow do
		spawns.add(at(c, p[1], 0, p[2]), false)
	end
	MineKit.marker(model, "GiantSpawn", at(c, GIANT.X, 0, GIANT.Z))
	MineKit.marker(model, "Entrance", at(c, 0, 0, 41))

	------------------------------------------------------------ entrance: gate, elevator, name sign
	MineKit.gate(model, CFrame.lookAt(pt(c, 0, 0, 45), pt(c, 0, 0, 46)), 12, Floor.Index, { pal.Mid, pal.Light, pal.Dark })
	MineKit.elevator(model, CFrame.lookAt(pt(c, -24, 0, 34), pt(c, -23, 0, 34)), Floor.Index)
	do
		local s = at(c, -15, 0, 44)
		for _, sx in { -1, 1 } do
			block(c, s * CFrame.new(sx * 5.6, 3.2, 0), Vector3.new(0.8, 6.4, 0.8), C.WoodDark)
		end
		Style.sign(model, s * CFrame.new(0, 5.4, 0) * CFrame.Angles(0, math.pi, 0), "GREYSTONE", 11.6, 2.3, { DoubleSided = true })
		for _, sx in { -1, 1 } do
			block(c, s * CFrame.new(sx * 2.6, 3.65, 0), Vector3.new(0.14, 1.2, 0.14), C.Iron, nil, TINY)
		end
		Style.sign(model, s * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.pi, 0), "QUARRY", 7, 1.5, { DoubleSided = true, Depth = 0.4 })
	end

	------------------------------------------------------------ ore lift with its crane on the right ledge
	MineKit.oreLift(model, pt(c, LIFT.X, LIFT.Y, LIFT.Z), "Floor1Quarry")
	do
		local mx = WALL_X + 4
		block(c, at(c, mx, 21, LIFT.Z), Vector3.new(1.4, 25, 1.4), C.WoodDark)
		block(c, at(c, mx, 9.2, LIFT.Z), Vector3.new(2.6, 1.6, 2.6), C.StoneDark)
		block(c, at(c, (LIFT.X - 2.5 + mx + 1) / 2, 30.6, LIFT.Z), Vector3.new(mx + 1 - (LIFT.X - 2.5), 1.2, 1.2), C.Wood)
		beam(c, Vector3.new(mx - 0.4, 24, LIFT.Z), Vector3.new(LIFT.X + 5, 30.1, LIFT.Z), 0.7, C.WoodDark)
		beam(c, Vector3.new(mx + 0.4, 33, LIFT.Z), Vector3.new(WALL_X + 11, 19.4, LIFT.Z), 0.18, C.Iron, TINY)
		block(c, at(c, mx, 33.6, LIFT.Z), Vector3.new(1.8, 0.6, 1.8), C.Iron, METAL)
		Geo.make("Part", {
			Shape = Enum.PartType.Cylinder,
			CFrame = at(c, LIFT.X - 1.6, 30.6, LIFT.Z),
			Size = Vector3.new(0.6, 2, 2),
			Color = C.Hazard,
			Material = METAL,
			CanTouch = false,
			CanQuery = false,
			CanCollide = false,
		}, model)
		Style.lantern(model, at(c, LIFT.X + 4, 30, LIFT.Z), { Kind = "Hanging" })
		ladder(c, Vector3.new(WALL_X - 0.6, 0, LIFT.Z + 8), Vector3.new(-1, 0, 0), 10)
	end
	-- rails along the right wall with a cart of ore, buffer at the front
	Style.rails(model, pt(c, 41, 0, 12), pt(c, 41, 0, 45))
	Style.mineCart(model, CFrame.lookAt(pt(c, 41, 0, 23), pt(c, 41, 0, 22)), rng, { Load = "Ore" })
	block(c, at(c, 41, 1.1, 45.4), Vector3.new(4.6, 0.9, 0.9), C.Roof)

	------------------------------------------------------------ the scaffold and walkway on the left wall
	do
		local x0, x1 = -WALL_X + 1.2, -WALL_X + 5.6
		local z0, z1 = 12, 26
		local zc = (z0 + z1) / 2
		local cx = (x0 + x1) / 2
		local top = sideSteps[1].Top + 1.25
		for _, x in { x0, x1 } do
			for _, z in { z0 + 0.5, zc, z1 - 0.5 } do
				block(c, at(c, x, top / 2, z), Vector3.new(0.6, top, 0.6), C.WoodDark)
			end
		end
		Style.planks(model, at(c, cx, 4.8, zc), Vector3.new(x1 - x0 + 1, 0.4, z1 - z0), rng)
		Style.planks(model, at(c, cx, top, zc), Vector3.new(x1 - x0 + 1, 0.4, z1 - z0), rng)
		for _, zz in { { z0 + 0.5, zc }, { zc, z1 - 0.5 } } do
			beam(c, Vector3.new(x1 + 0.35, 0.4, zz[1]), Vector3.new(x1 + 0.35, 4.4, zz[2]), 0.35, C.Wood, GHOST)
			beam(c, Vector3.new(x1 + 0.35, 5.2, zz[2]), Vector3.new(x1 + 0.35, top - 0.5, zz[1]), 0.35, C.Wood, GHOST)
		end
		ladder(c, Vector3.new(x1 + 0.6, 0, zc - 3), Vector3.new(1, 0, 0), 5)
		ladder(c, Vector3.new(x1 + 0.6, 4.8, z1 - 3), Vector3.new(1, 0, 0), top - 4.8)
		Style.fence(model, pt(c, x1 + 0.2, top, z0 + 0.4), pt(c, x1 + 0.2, top, z1 - 0.4), { Height = 2.4, PostEvery = 7 })
		-- a bridge to the ledge walkway, the walkway along the first ledge, a ladder up to the second
		Style.planks(model, at(c, -WALL_X - 0.4, top, 14.5), Vector3.new(3.8, 0.4, 3), rng)
		deck(c, Vector3.new(-WALL_X - 3, top, -9.5), Vector3.new(3.4, 0.4, 47), 2.2, 0)
		Style.fence(model, pt(c, -WALL_X - 1.6, top, -32.5), pt(c, -WALL_X - 1.6, top, 13), { Height = 2.4, PostEvery = 7.5 })
		ladder(c, Vector3.new(-WALL_X - 6.4, top - 0.2, -2), Vector3.new(1, 0, 0), sideSteps[2].Top - top + 1)
		-- crates, a barrel and a lit lamp hook on the scaffold
		Style.crate(model, at(c, cx - 0.6, top, z1 - 2.4), rng, 2)
		Style.barrel(model, pt(c, cx, top, z0 + 2.4), rng)
		block(c, at(c, x1 - 0.6, top + 1.8, zc), Vector3.new(0.5, 3.6, 0.5), C.WoodDark)
		block(c, at(c, x1 + 0.1, top + 3.5, zc), Vector3.new(1.9, 0.4, 0.4), C.WoodDark, nil, TINY)
		local lamp = Style.lantern(model, at(c, x1 + 0.6, top + 3.3, zc), { Kind = "Hanging" })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 16, 1.2)
		end
		Style.crate(model, at(c, -WALL_X + 3, 0, 29.5), rng)
		Style.barrel(model, pt(c, -WALL_X + 7.5, 0, 28.6), rng)
		Style.crate(model, at(c, -WALL_X - 3, top, -26), rng, 2)
		for _, z in { -30, -8 } do
			local walkLamp = Style.lantern(model, at(c, -WALL_X - 4.3, top, z) * CFrame.Angles(0, -math.pi / 2, 0), { Height = 5 })
			if walkLamp.PrimaryPart then
				light(c, walkLamp.PrimaryPart, C.Lamp, 16, 1.2)
			end
		end
	end

	------------------------------------------------------------ the back ledge walkway
	do
		local top = backSteps[1].Top + 1.25
		deck(c, Vector3.new(31, top, BACK_Z - 3), Vector3.new(3.2, 0.4, 26), 2.2, math.pi / 2)
		Style.fence(model, pt(c, 18.5, top, BACK_Z - 1.7), pt(c, 43.5, top, BACK_Z - 1.7), { Height = 2.4, PostEvery = 6.5 })
		ladder(c, Vector3.new(24, 0, BACK_Z + 0.7), Vector3.new(0, 0, 1), top + 0.4)
		local lamp = Style.lantern(model, at(c, 37, top, BACK_Z - 3.8) * CFrame.Angles(0, math.pi, 0), { Height = 5 })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 18, 1.2)
		end
		Style.crate(model, at(c, 29, top, BACK_Z - 3.2), rng, 2.2)
		Style.crate(model, at(c, 31.4, top, BACK_Z - 3.2), rng, 1.8)
		Style.barrel(model, pt(c, 20.5, top, BACK_Z - 3.3), rng)
	end

	------------------------------------------------------------ the tool shed (front right)
	do
		local s = at(c, 28, 0, 38)
		local w, d, h = 10, 8, 6
		block(c, s * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.8, 0.6, d + 0.8), C.StoneDark, nil, SOLID)
		-- plank walls with darker corner posts
		block(c, s * CFrame.new(0, 0.6 + h / 2, d / 2 - 0.3), Vector3.new(w, h, 0.6), C.WoodLight)
		block(c, s * CFrame.new(0, 0.6 + h / 2, -d / 2 + 0.3), Vector3.new(w, h, 0.6), C.WoodLight)
		block(c, s * CFrame.new(w / 2 - 0.3, 0.6 + h / 2, 0), Vector3.new(0.6, h, d - 1.2), C.Wood)
		block(c, s * CFrame.new(-w / 2 + 0.3, 0.6 + h / 2, 0), Vector3.new(0.6, h, d - 1.2), C.Wood)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				block(c, s * CFrame.new(sx * (w / 2 - 0.2), 0.6 + h / 2, sz * (d / 2 - 0.2)), Vector3.new(0.8, h, 0.8), C.WoodDark, nil, TINY)
			end
		end
		-- gable ends filled with wedges under the roof
		for _, sz in { -1, 1 } do
			local gz = sz * (d / 2 - 0.3)
			Geo.wedge(model, s * CFrame.new(w / 4, 0.6 + h + 1.5, gz) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(0.6, 3, w / 2), C.WoodLight, nil, TINY)
			Geo.wedge(model, s * CFrame.new(-w / 4, 0.6 + h + 1.5, gz) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.6, 3, w / 2), C.WoodLight, nil, TINY)
		end
		Style.gableRoof(model, s * CFrame.new(0, 0.6 + h, 0) * CFrame.Angles(0, math.pi / 2, 0), d + 1.6, w + 2, 3.2)
		-- door toward the path, a lit window and a sign toward the front, a lantern by the door
		block(c, s * CFrame.new(-w / 2 - 0.05, 0.6 + 2.3, -1), Vector3.new(0.3, 4.6, 2.8), C.WoodDark, nil, TINY)
		block(c, s * CFrame.new(-w / 2 - 0.15, 0.6 + 2.3, -1), Vector3.new(0.2, 4.6, 0.3), C.Wood, nil, TINY)
		Style.window(model, s * CFrame.new(0, 0.6 + 3.2, d / 2 + 0.05) * CFrame.Angles(0, math.pi, 0), 2.4, 1.8)
		Style.sign(model, s * CFrame.new(0, 0.6 + 5.1, d / 2 + 0.2) * CFrame.Angles(0, math.pi, 0), "TOOLS", 4, 1.1, { Depth = 0.3 })
		block(c, s * CFrame.new(-w / 2 - 0.4, 0.6 + 5.5, 1.4), Vector3.new(0.9, 0.25, 0.25), C.Iron, nil, TINY)
		local lamp = Style.lantern(model, s * CFrame.new(-w / 2 - 0.75, 0.6 + 5.4, 1.4), { Kind = "Hanging" })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 16, 1.3)
		end
		-- tool rack on the wall: two pickaxes and a shovel
		local rack = s * CFrame.new(-w / 2 - 0.5, 0, 2.6)
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
		Style.crate(model, at(c, 20.8, 0, 33.8), rng)
		Style.crate(model, at(c, 20.4, 0, 37.2), rng, 2.4)
		Style.crate(model, at(c, 20.5, 2.4, 37.2), rng, 1.8)
		Style.barrel(model, pt(c, 21.4, 0, 42.6), rng)
		Style.barrel(model, pt(c, 34.6, 0, 43.4), rng, C.Copper)
	end

	------------------------------------------------------------ lanterns along the paths, props
	local postLamps = { -- x, z, lamp direction (x, z)
		{ -7.5, 30, 1, 0 },
		{ 7.5, 18, -1, 0 },
		{ -7.5, -23, 1, 0 },
		{ 7.5, -31, -1, 0 },
		{ -10, 38.6, 0, -1 },
	}
	for _, l in postLamps do
		local p = pt(c, l[1], 0, l[2])
		local dir = c.o:VectorToWorldSpace(Vector3.new(l[3], 0, l[4]))
		local lamp = Style.lantern(model, CFrame.lookAt(p, p + dir), { Height = 6.5 })
		if lamp.PrimaryPart then
			light(c, lamp.PrimaryPart, C.Lamp, 18, 1.3)
		end
	end
	for _, a in { 110, 250, 330 } do
		local r = math.rad(a)
		Style.lantern(model, at(c, GIANT.X + math.cos(r) * 15.5, 0, GIANT.Z + math.sin(r) * 15.5), { Kind = "Ground" })
	end
	Style.crate(model, at(c, -12.5, 0, -33.5), rng)
	Style.crate(model, at(c, -12.3, 2.5, -33.4), rng, 1.6)
	Style.barrel(model, pt(c, 13.5, 0, -33.6), rng)
	Style.barrel(model, pt(c, -17.5, 0, 40.5), rng)
	Style.crate(model, at(c, -31, 0, 41.5), rng)

	------------------------------------------------------------ trees, bushes, flowers and crystals on the rim
	local kinds = { "Green", "Orange", "Green", "Pink", "Green", "Yellow" }
	local perWall: { [string]: number } = {}
	local trees = 0
	for _, top in c.tops do
		local n = (perWall[top.wall] or 0) + 1
		perWall[top.wall] = n
		local front = top.wall == "frontL" or top.wall == "frontR"
		if top.rim and not front and top.step == 3 then
			local p = top.cf.Position
			if n % 4 == 2 then
				trees += 1
				Style.tree(model, CFrame.new(p) * CFrame.new(rng:range(-1.2, 1.2), -0.3, rng:range(-1.2, 1.2)), kinds[trees % #kinds + 1], rng, rng:range(0.95, 1.3))
			elseif n % 4 == 0 then
				Style.bush(model, (top.cf * CFrame.new(rng:range(-1.5, 1.5), 0, -top.d * 0.32)).Position, if rng:chance(0.5) then C.LeafGreen else C.LeafGreenDark, rng, rng:range(2.4, 3.4))
			elseif top.wall == "backL" and n % 4 == 1 then
				wallCrystal(c, c.o:PointToObjectSpace((top.cf * CFrame.new(0, -0.6, -top.d * 0.2)).Position), UP, 0.1, 6, 5, true, 30 + n)
			elseif rng:chance(0.6) then
				Style.flowers(model, (top.cf * CFrame.new(0, 0, -top.d * 0.3)).Position, rng:pick({ C.FlowerYellow, C.FlowerWhite, C.FlowerPink }), rng, 5, 1.6)
			end
		elseif top.rim and top.wall == "backMid" and n % 2 == 1 then
			Style.tree(model, CFrame.new(top.cf.Position) * CFrame.new(0, -0.3, 1), kinds[(trees + n) % #kinds + 1], rng, 1.1)
		elseif front and top.rim then
			-- the front bank / the front rim: boulders, bushes, flowers and small quartz crystals
			local p = (top.cf * CFrame.new(rng:range(-1.5, 1.5), 0, rng:range(-1, 1))).Position
			local kind = n % 4
			if kind == 1 then
				Style.boulder(model, p - Vector3.new(0, 0.3, 0), rng:range(2.2, 3.2), rng, { Color = SLATE2 })
			elseif kind == 2 then
				Style.bush(model, p, if rng:chance(0.5) then C.LeafGreen else C.LeafGreenLight, rng, rng:range(2.2, 3))
			elseif kind == 3 then
				Style.flowers(model, p, rng:pick({ C.FlowerYellow, C.FlowerWhite, C.FlowerPink }), rng, 6, 2)
			else
				wallCrystal(c, c.o:PointToObjectSpace(p) - Vector3.new(0, 0.5, 0), UP, 0.15, 4, 3, true, 60 + n)
			end
		elseif not top.rim and rng:chance(0.12) then
			Style.bush(model, (top.cf * CFrame.new(0, -0.1, top.d * 0.2)).Position, C.LeafGreen, rng, rng:range(1.8, 2.4))
		end
	end
	-- grass tufts at the wall feet
	for _ = 1, 12 do
		local side = rng:pick({ -1, 1 })
		local z = rng:range(-34, 42)
		local x = side * (WALL_X - rng:range(1.5, 3.5))
		for k = 1, 2 do
			block(c, at(c, x + rng:range(-0.6, 0.6), 0.35, z + rng:range(-0.6, 0.6)) * CFrame.Angles(0, rng:range(0, 3), 0.15 * k), Vector3.new(0.3, 0.8 + k * 0.2, 0.3), C.LeafGreen, nil, TINY)
		end
	end

	model.Parent = parent
	return model
end

return Floor
