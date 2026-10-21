--[[
	Plaza life (concept fixes 2026-10-18, docs/art/lobby_concept*.webp):

	  Miners     up to MaxMiners blocky miner NPCs from parts (hard hat with a
	             lamp, overalls, a pickaxe or an ore chunk), standing on the
	             lawns around the plaza looking at it. No Humanoid, no
	             collision (the fire crystal stays the plaza's only spinner).
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
Life.Stalls = { "Shop", "Upgrades", "CapsuleStall", "EnchantShop", "RockScanner", "FossilDig" }
-- Kept clear: the Great Forge's porch and stairs, the vault and its approach.
Life.Clear = {
	{ Min = Vector3.new(-26, 0, -48), Max = Vector3.new(26, 0, -30) },
	{ Min = Vector3.new(-72, 0, 58), Max = Vector3.new(72, 0, 160) },
}

local SKIN = { Color3.fromRGB(255, 204, 160), Color3.fromRGB(226, 168, 120), Color3.fromRGB(176, 118, 80), Color3.fromRGB(120, 78, 52) }
local SHIRT = {
	Color3.fromRGB(214, 110, 40),
	Color3.fromRGB(176, 52, 46),
	Color3.fromRGB(62, 110, 176),
	Color3.fromRGB(70, 140, 70),
	Color3.fromRGB(150, 98, 60),
}
local PANTS = { Color3.fromRGB(46, 60, 96), Color3.fromRGB(70, 56, 44), Color3.fromRGB(56, 56, 64) }
local HAT = Color3.fromRGB(250, 196, 40)
local BEARD = { Color3.fromRGB(90, 60, 40), Color3.fromRGB(200, 196, 190), Color3.fromRGB(150, 70, 30) }
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

-- A blocky miner (R6 proportions, 1.25 scale) at `base` (feet), facing its
-- LookVector. Pose: "Pickaxe" (on the shoulder), "Ore" (holding a glowing
-- chunk), "Rest" (hands on the pickaxe in front). 14-17 parts.
function Life.miner(parent: Instance, base: CFrame, pose: string, rng: Rng.Rng): Model
	local m = Style.model("Miner", parent)
	local s = 1.25
	local skin = SKIN[rng:int(1, #SKIN)]
	local shirt = SHIRT[rng:int(1, #SHIRT)]
	local pants = PANTS[rng:int(1, #PANTS)]
	local function part(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
		return Style.block(m, base * cf, size * s, color, material, Style.tiny())
	end
	-- legs, boots, torso, overall straps, belt
	for _, x in { -0.5, 0.5 } do
		part(CFrame.new(x * s, 1 * s, 0), Vector3.new(0.95, 2, 0.95), pants)
		part(CFrame.new(x * s, 0.2 * s, -0.08 * s), Vector3.new(1, 0.4, 1.12), Color3.fromRGB(52, 40, 32))
	end
	local torso = part(CFrame.new(0, 3 * s, 0), Vector3.new(2, 2, 1), shirt)
	torso.Name = "Torso"
	part(CFrame.new(0, 2.25 * s, 0), Vector3.new(2.05, 0.35, 1.05), Color3.fromRGB(86, 58, 36))
	part(CFrame.new(0, 2.7 * s, -0.5 * s), Vector3.new(1.3, 0.9, 0.08), pants)
	-- head, eyes, beard
	local head = part(CFrame.new(0, 4.6 * s, 0), Vector3.new(1.2, 1.2, 1.2), skin)
	head.Name = "Head"
	for _, x in { -0.25, 0.25 } do
		part(CFrame.new(x * s, 4.75 * s, -0.61 * s), Vector3.new(0.17, 0.2, 0.05), Color3.fromRGB(30, 26, 26))
	end
	if rng:chance(0.6) then
		part(CFrame.new(0, 4.2 * s, -0.55 * s), Vector3.new(1.1, 0.55, 0.2), BEARD[rng:int(1, #BEARD)])
	end
	-- hard hat with a lamp
	part(CFrame.new(0, 5.35 * s, 0), Vector3.new(1.35, 0.45, 1.35), HAT)
	part(CFrame.new(0, 5.15 * s, -0.1 * s), Vector3.new(1.65, 0.12, 1.75), HAT)
	part(CFrame.new(0, 5.35 * s, -0.72 * s), Vector3.new(0.38, 0.3, 0.12), Color3.fromRGB(255, 236, 170), NEON)
	-- arms and the pose
	local arm = Vector3.new(0.95, 2, 0.95)
	if pose == "Pickaxe" then
		part(CFrame.new(-1.5 * s, 3 * s, 0), arm, shirt)
		part(CFrame.new(1.45 * s, 3.55 * s, 0.2 * s) * CFrame.Angles(math.rad(160), 0, math.rad(8)), arm, shirt)
		local grip = CFrame.new(1.35 * s, 4.55 * s, 0.75 * s) * CFrame.Angles(math.rad(-35), 0, math.rad(15))
		part(grip, Vector3.new(0.22, 2.8, 0.22), C.Wood)
		part(grip * CFrame.new(0, -1.35 * s, 0), Vector3.new(2, 0.3, 0.32), C.IronLight)
	elseif pose == "Ore" then
		for _, x in { -1, 1 } do
			part(CFrame.new(x * 1.2 * s, 3.4 * s, -0.7 * s) * CFrame.Angles(math.rad(70), 0, math.rad(-x * 18)), arm, shirt)
		end
		part(CFrame.new(0, 3.2 * s, -1.55 * s) * CFrame.Angles(0.4, 0.6, 0.2), Vector3.new(1, 0.9, 0.9), ORE[rng:int(1, #ORE)], NEON)
	else
		for _, x in { -1, 1 } do
			part(CFrame.new(x * 1.3 * s, 2.9 * s, -0.35 * s) * CFrame.Angles(math.rad(25), 0, math.rad(-x * 14)), arm, shirt)
		end
		local handle = CFrame.new(0, 1.7 * s, -1.25 * s)
		part(handle, Vector3.new(0.22, 2.8, 0.22), C.Wood)
		part(handle * CFrame.new(0, 1.45 * s, 0), Vector3.new(2, 0.3, 0.32), C.IronLight)
	end
	m.PrimaryPart = torso
	Style.streaming(m, "Atomic")
	return m
end

local function miners(parent: Instance, index: Meadow.Index, prompts: { Box }, rng: Rng.Rng)
	local m = Style.model("Miners", parent)
	local placed: { Vector3 } = {}
	local poses = { "Pickaxe", "Ore", "Rest" }
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
