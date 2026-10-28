--[[
	Plaza life (concept fixes 2026-10-18, docs/art/lobby_concept*.webp):

	  Miners     up to MaxMiners blocky mining golems from parts (owner
	             2026-10-25: golems in place of the human miners; a hard hat
	             with a lamp, a pickaxe on the shoulder, swung at an ore rock
	             or an ore chunk held up), standing on the lawns around the
	             plaza looking at it. No Humanoid, no collision (the fire
	             crystal stays the plaza's only spinner).
	  Lanterns   warm hanging lanterns on their own L-posts at the front
	             corners of the stalls (neon only, no lights)
	  Props      crates, barrels and an ore sack beside the stall fronts

	It runs after the whole lobby, the plots and the railway (WorldBuilder),
	before the meadow, and only uses free ground (Flora/Meadow's index):
	never on a road, the plaza ring, a stall's walking line (Flora.Kit
	aprons) or within PromptClear studs of a stall's counter or any tagged
	stall part (steps 6-7 put prompts there), never on the Great Forge's
	porch and stairs or the Blaster Vault and its approach. Parented to
	Emberfall.Lobby.Plaza.Life. Pure decoration: non-collide, no shadows.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)
local Meadow = require(script.Parent.Parent.Flora.Meadow)
local FloraKit = require(script.Parent.Parent.Flora.Kit)
local StreetLampPlan = require(script.Parent.StreetLampPlan)

local C = Style.C
local NEON = Enum.Material.Neon

local Life = {}

Life.MaxMiners = 9
Life.PromptClear = 3 -- studs from a counter / tagged stall part
Life.RingClear = 39 -- the plaza ring's walking area
-- Stalls that get lanterns and props (the Hall of Fame boards and the wheel stay bare)
Life.Stalls = { "Shop", "Upgrades", "CapsuleStall", "EnchantShop", "BackpackStall", "FossilDig" }
-- Kept clear: the Great Forge's porch and stairs, the vault and its approach.
Life.Clear = {
	{ Min = Vector3.new(-26, 0, -48), Max = Vector3.new(26, 0, -30) },
	{ Min = Vector3.new(-72, 0, 58), Max = Vector3.new(72, 0, 160) },
}

-- the golems' looks (Districts.Kit.GolemLooks' family: silver, gold, copper, amethyst, ember, mossy, jade)
local GOLEMS = {
	{ Body = C.IronLight, Accent = C.Iron, Eyes = C.CrystalCyan },
	{ Body = C.Gold, Accent = C.Brass, Eyes = C.Fire, Gem = C.CrystalPink },
	{ Body = C.Copper, Accent = C.LeafOrangeDark, Eyes = C.CrystalCyan },
	{ Body = C.StoneDark, Accent = C.StoneDeep, Eyes = C.CrystalPurple, Gem = C.CrystalPurple },
	{ Body = C.StoneDeep, Accent = C.Iron, Eyes = C.Ember, Gem = C.Ember },
	{ Body = C.Stone, Accent = C.StoneDark, Eyes = C.LampAmber, Moss = true },
	{ Body = C.LeafGreenDark, Accent = C.StoneDark, Eyes = C.FireCore, Gem = C.CrystalCyan },
} :: { { [string]: any } }
local HAT = Color3.fromRGB(250, 196, 40)
local ORE = { C.CrystalCyan, C.Gold, C.CrystalPurple, C.Ember }

type Box = { Min: Vector3, Max: Vector3 }

local function box(min: Vector3, max: Vector3): Box
	return { Min = min, Max = max }
end

local function inBox(p: Vector3, b: Box, margin: number): boolean
	return p.X > b.Min.X - margin and p.X < b.Max.X + margin and p.Z > b.Min.Z - margin and p.Z < b.Max.Z + margin
end

-- Counters and every tagged part of the stalls (Districts): props keep
-- PromptClear studs off them (prompts sit on them at runtime).
local function promptBoxes(lobby: Instance?): { Box }
	local out: { Box } = {}
	local districts = lobby and lobby:FindFirstChild("Districts")
	if not districts then
		return out
	end
	for _, d in districts:GetDescendants() do
		local tagged = #d:GetTags() > 0 or string.find(d.Name, "Counter", 1, true) ~= nil
		if tagged and d:IsA("BasePart") then
			local c, h = d.CFrame.Position, d.Size / 2
			local reach = math.max(h.X, h.Z)
			table.insert(out, box(c - Vector3.new(reach, 0, reach), c + Vector3.new(reach, 0, reach)))
		elseif d:IsA("Attachment") and string.find(d.Name, "Prompt", 1, true) then
			local parent = d.Parent
			if parent and parent:IsA("BasePart") then
				local w = (parent.CFrame * d.CFrame).Position
				table.insert(out, box(w, w))
			end
		end
	end
	return out
end

local function apronHit(p: Vector3, r: number): boolean
	for _, apron in FloraKit.Aprons do
		if FloraKit.apronDistance(apron, p) < r + 0.5 then
			return true
		end
	end
	return false
end

-- A spot props may use: free ground, off the roads, the ring, the clear zones,
-- the aprons and the prompts.
local function usable(index: Meadow.Index, prompts: { Box }, p: Vector3, r: number, top: number, ring: number?): boolean
	if Vector3.new(p.X, 0, p.Z).Magnitude < (ring or Life.RingClear) + r then
		return false
	end
	for _, z in Life.Clear do
		if inBox(p, z, r) then
			return false
		end
	end
	for _, b in prompts do
		if inBox(p, b, Life.PromptClear + r) then
			return false
		end
	end
	-- (the street lamps are built after the plaza life: keep their spots free)
	if StreetLampPlan.near(p, r + 2.5) then
		return false
	end
	return Common.offStrips(p, r + 0.5) and not apronHit(p, r) and Meadow.allowed(p, r) and Meadow.free(index, p, r, top)
end

local function track(index: Meadow.Index, model: Instance)
	Meadow.track(index, model)
end

local function decorate(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

---------------------------------------------------------------- miners

-- A blocky mining golem (owner 2026-10-25: golems in place of the human
-- miners) at `base` (feet), facing its LookVector, about as tall as the old
-- miners: stubby legs, a wide body, arm blocks, a big head with a face plate
-- and a glowing visor, a yellow hard hat with a lamp. Pose: "Pickaxe" (on the
-- shoulder), "Swing" (raised over the head at an ore rock in front), "Ore"
-- (holding up a glowing chunk). 13-17 parts.
function Life.miner(parent: Instance, base: CFrame, pose: string, rng: Rng.Rng): Model
	local m = Style.model("Miner", parent)
	local s = 2.2
	local look = GOLEMS[rng:int(1, #GOLEMS)]
	local body: Color3, accent: Color3 = look.Body, look.Accent
	local function part(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
		return Style.block(m, base * cf, size * s, color, material, Style.tiny())
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end
	-- legs, the body, the head with its face plate and visor
	for _, x in { -0.32, 0.32 } do
		part(at(x, 0.3, 0), Vector3.new(0.48, 0.6, 0.58), accent)
	end
	local torso = part(at(0, 0.98, 0), Vector3.new(1.2, 0.8, 0.85), body)
	torso.Name = "Torso"
	local head = part(at(0, 1.92, 0), Vector3.new(1.4, 1.1, 1.2), body)
	head.Name = "Head"
	part(at(0, 1.86, -0.61), Vector3.new(1.1, 0.62, 0.03), accent)
	part(at(0, 1.92, -0.64), Vector3.new(0.86, 0.2, 0.03), look.Eyes, NEON)
	if look.Gem then
		part(at(0, 1.0, -0.44) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.3, 0.3, 0.04), look.Gem, NEON)
	elseif look.Moss then
		part(at(-0.15, 1.42, 0.1), Vector3.new(0.9, 0.12, 0.7), C.GrassLight)
	end
	-- the hard hat with a lamp
	part(at(0, 2.6, 0), Vector3.new(1.5, 0.3, 1.3), HAT)
	part(at(0, 2.5, -0.62), Vector3.new(1.5, 0.12, 0.3), HAT)
	part(at(0, 2.62, -0.67), Vector3.new(0.34, 0.24, 0.06), Color3.fromRGB(255, 236, 170), NEON)
	-- arms and the pose
	local arm = Vector3.new(0.4, 0.85, 0.5)
	if pose == "Pickaxe" then
		part(at(-0.8, 0.9, -0.05), arm, accent)
		part(at(0.82, 1.3, 0.05) * CFrame.Angles(math.rad(160), 0, math.rad(8)), arm, accent)
		local grip = at(0.78, 1.75, 0.3) * CFrame.Angles(math.rad(-35), 0, math.rad(15))
		part(grip, Vector3.new(0.1, 1.3, 0.1), C.Wood)
		part(grip * CFrame.new(0, -0.62 * s, 0), Vector3.new(0.9, 0.14, 0.15), C.IronLight)
	elseif pose == "Swing" then
		-- both arms up, the pickaxe over the head, its blade toward the ore rock in front
		for _, x in { -0.55, 0.55 } do
			part(at(x, 1.55, -0.3) * CFrame.Angles(math.rad(150), 0, math.rad(-x * 20)), arm, accent)
		end
		local grip = at(0, 2.35, -0.55) * CFrame.Angles(math.rad(-60), 0, 0)
		part(grip, Vector3.new(0.1, 1.4, 0.1), C.Wood)
		part(grip * CFrame.new(0, 0.68 * s, 0) * CFrame.Angles(math.rad(90), 0, 0), Vector3.new(0.9, 0.14, 0.15), C.IronLight)
		local rock = at(0, 0.32, -1.25) * CFrame.Angles(0, rng:range(0, math.pi), 0)
		part(rock, Vector3.new(0.9, 0.62, 0.8), C.StoneDark)
		part(
			rock * CFrame.new(0.1 * s, 0.22 * s, -0.2 * s) * CFrame.Angles(0.4, 0.5, 0.2),
			Vector3.new(0.34, 0.34, 0.34),
			ORE[rng:int(1, #ORE)],
			NEON
		)
	else
		for _, x in { -1, 1 } do
			part(at(x * 0.62, 1.12, -0.45) * CFrame.Angles(math.rad(70), 0, math.rad(-x * 18)), arm, accent)
		end
		part(at(0, 1.2, -0.85) * CFrame.Angles(0.4, 0.6, 0.2), Vector3.new(0.5, 0.45, 0.45), ORE[rng:int(1, #ORE)], NEON)
	end
	m.PrimaryPart = torso
	Style.streaming(m, "Atomic")
	return m
end

local function miners(parent: Instance, index: Meadow.Index, prompts: { Box }, rng: Rng.Rng)
	local m = Style.model("Miners", parent)
	local placed: { Vector3 } = {}
	local poses = { "Pickaxe", "Swing", "Ore" }
	local angles: { number } = {}
	for i = 0, 35 do
		table.insert(angles, i * 10 + rng:range(-3, 3))
	end
	for i = #angles, 2, -1 do
		local j = rng:int(1, i)
		angles[i], angles[j] = angles[j], angles[i]
	end
	for _, a in angles do
		if #placed >= Life.MaxMiners then
			break
		end
		for _, r in { 41, 45, 50, 56, 63, 70 } do
			local rad = math.rad(a)
			local p = Vector3.new(math.cos(rad) * r, 0, math.sin(rad) * r)
			local near = false
			for _, q in placed do
				near = near or (p - q).Magnitude < 14
			end
			if not near and usable(index, prompts, p, 1.6, 8) then
				local look = CFrame.lookAt(p, Vector3.new(0, 0, 0)) * CFrame.Angles(0, rng:range(-0.5, 0.5), 0)
				track(index, Life.miner(m, look, poses[#placed % #poses + 1], rng))
				table.insert(placed, p)
				break
			end
		end
	end
	return m
end

---------------------------------------------------------------- lanterns and props

-- A hanging lantern on an L-post: post, arm, iron cap, amber glass.
-- 4 parts (phones), no light.
function Life.lanternPost(parent: Instance, foot: Vector3, toward: Vector3): Model
	local m = Style.model("HangingLantern", parent)
	local dir = Vector3.new(toward.X, 0, toward.Z).Unit
	local h = 7
	local post = CFrame.lookAt(foot, foot + dir)
	Style.block(m, post * CFrame.new(0, h / 2, 0), Vector3.new(0.5, h, 0.5), C.WoodDark, nil, Style.tiny())
	Style.block(m, post * CFrame.new(0, h - 0.25, -1), Vector3.new(0.4, 0.4, 2.4), C.WoodDark, nil, Style.tiny())
	Style.block(m, post * CFrame.new(0, h - 0.57, -1.9), Vector3.new(1.05, 0.25, 1.05), C.Iron, nil, Style.tiny())
	local glass =
		Style.block(m, post * CFrame.new(0, h - 1.2, -1.9), Vector3.new(0.8, 1.05, 0.8), Common.Colors.AmberGlass, NEON, Style.tiny())
	glass.Name = "LanternGlow"
	return m
end

-- 2-3 props in a little heap: crates, a barrel, an ore sack.
local function heap(parent: Instance, at: Vector3, rng: Rng.Rng)
	local m = Style.model("StallProps", parent)
	Style.crate(m, CFrame.new(at), rng, rng:range(1.8, 2.3))
	local side = Vector3.new(rng:range(-1, 1), 0, rng:range(-1, 1))
	side = if side.Magnitude > 0.1 then side.Unit else Vector3.new(1, 0, 0)
	if rng:chance(0.6) then
		Style.barrel(m, at + side * 2.3, rng)
	else
		local sack = at + side * 2.2
		Style.block(
			m,
			CFrame.new(sack + Vector3.new(0, 0.7, 0)),
			Vector3.new(1.6, 1.4, 1.3),
			Color3.fromRGB(196, 168, 120),
			nil,
			Style.tiny()
		)
		Style.block(m, CFrame.new(sack + Vector3.new(0, 1.5, 0)), Vector3.new(0.9, 0.4, 0.9), ORE[rng:int(1, #ORE)], NEON, Style.tiny())
	end
	return m
end

local function stallFronts(parent: Instance, index: Meadow.Index, prompts: { Box }, rng: Rng.Rng)
	local lanterns = Style.model("Lanterns", parent)
	local props = Style.model("Props", parent)
	for _, id in Life.Stalls do
		local piece = LobbyLayout.ById[id]
		if not piece then
			continue
		end
		local frame = LobbyLayout.frame(piece)
		local hx, hz = piece.Size.X / 2, piece.Size.Z / 2
		for _, side in { -1, 1 } do
			-- a lantern post at the front corner, its lamp hanging toward the front
			local done = false
			for _, dz in { 1, 3, -1, 5 } do
				for _, dx in { 1.5, 3, 4.5, 6 } do
					local foot = frame:PointToWorldSpace(Vector3.new(side * (hx + dx), 0, -hz + dz))
					if not done and usable(index, prompts, foot, 0.8, 8, Common.PlazaRadius + 0.5) then
						track(index, Life.lanternPost(lanterns, foot, frame.LookVector - frame.RightVector * side * 0.4))
						done = true
					end
				end
			end
			-- a heap of props beside the front, set back a little
			done = false
			for _, dz in { 3.5, 6, 1.5, 9 } do
				for _, dx in { 3, 5, 7, 9 } do
					local at = frame:PointToWorldSpace(Vector3.new(side * (hx + dx), 0, -hz + dz))
					if not done and usable(index, prompts, at, 2.4, 4, Common.PlazaRadius + 1) then
						track(index, heap(props, at, rng))
						done = true
					end
				end
			end
		end
	end
end

-- Builds the plaza life into `map`'s Emberfall.Lobby.Plaza (or the map).
function Life.build(map: Instance, rng: Rng.Rng): Model
	local emberfall = map:FindFirstChild("Emberfall")
	local lobby = emberfall and emberfall:FindFirstChild("Lobby")
	local plaza = lobby and lobby:FindFirstChild("Plaza")
	local m = Style.model("Life", plaza or map)
	local index = Meadow.index(map)
	local prompts = promptBoxes(lobby)
	stallFronts(m, index, prompts, Rng.new(`Life/Fronts/{rng:nextU32()}`))
	miners(m, index, prompts, Rng.new(`Life/Miners/{rng:nextU32()}`))
	decorate(m)
	return m
end

return Life
