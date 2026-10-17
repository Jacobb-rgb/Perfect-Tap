--[[
	Flora hero trees (LOBBY_PLAN 6.5 items 8-10): the light cherry grove
	behind UPGRADES, the red tree at the east town edge and the yellow /
	orange autumn corner in the south-west, all concept v1 voxel trees
	(a visible trunk under offset canopy clusters, light on top, dark
	underneath), and the town-edge belts: two staggered rows of low-part
	voxel trees along both plot roads with hedges between them, timber
	fence runs on the town side and neon lantern posts (no lights), so the
	hero view reads as a dense town from edge to edge (concept v1) instead
	of open plot lawns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)

local C = Style.C

local Trees = {}

local function falling(part: BasePart, color: Color3)
	local e = Style.emitter(part, "Sparkle", color, 2)
	e.Name = "PetalParticles"
	e.Speed = NumberRange.new(0.5, 1.5)
	e.Acceleration = Vector3.new(0.6, -1.6, 0.3)
	e.Lifetime = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
end

local function crownPart(tree: Model): BasePart?
	-- the first ghost (non-colliding, shadow-casting) block is the crown core
	for _, child in tree:GetChildren() do
		if child:IsA("BasePart") and not child.CanCollide and child.CastShadow then
			return child
		end
	end
	return nil
end

function Trees.pinkGrove(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("PinkGrove")
	local c = piece.Center
	local m = Style.model("PinkGrove", parent)
	-- the big one stands behind the INN line, its side crown toward the forge
	-- path (well clear of the forge's wing); the small one east of it keeps
	-- clear of the INN, and the way from the forge east path to the ENCHANT
	-- door stays open
	local big = Kit.bigTree(m, CFrame.new(c + Vector3.new(-3, 0, 2)), "Cherry", rng, 1.45, -1)
	Kit.bigTree(m, CFrame.new(c + Vector3.new(4, 0, 5)), "Cherry", rng, 1.05, 1)
	Kit.flowerRing(m, c + Vector3.new(-3, 0, 2), 2.4, { C.FlowerPink, C.FlowerWhite, C.LeafPinkLight }, rng, 4)
	local crown = crownPart(big)
	if crown then
		falling(crown, C.LeafPinkLight)
	end
	return m
end

-- The red tree at the east town edge, a little smaller than the other hero
-- trees, its side crown toward the town.
Trees.RedTreeOffset = Vector3.new(0, 0, 0)
Trees.RedTreeScale = 1.0

function Trees.redTree(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("RedTree")
	local c = piece.Center + Trees.RedTreeOffset
	local m = Style.model("RedTree", parent)
	Kit.bigTree(m, CFrame.new(c), "Red", rng, Trees.RedTreeScale, -1)
	Style.bush(m, c + Vector3.new(-3.2, 0, 2.6), C.LeafRedDark, rng, 1.8)
	Kit.flowerRing(m, c, 2.4, { C.FlowerYellow, C.FlowerRed, C.FlowerWhite }, rng, 5)
	return m
end

function Trees.autumnCorner(parent: Instance, rng: Rng.Rng)
	local piece = LobbyLayout.get("AutumnCorner")
	local c = piece.Center
	local m = Style.model("AutumnCorner", parent)
	-- the big yellow tree stands well south of the MINE portal frame
	Kit.bigTree(m, CFrame.new(c + Vector3.new(-3, 0, 2)), "Yellow", rng, 1.15)
	Style.tree(m, CFrame.new(c + Vector3.new(6, 0, -5)), "Orange", rng, 1.0)
	Style.tree(m, CFrame.new(c + Vector3.new(5, 0, 6)), "Yellow", rng, 1.0)
	Kit.leanTree(m, CFrame.new(c + Vector3.new(-7, 0, 8)), "Orange", rng, 0.95)
	Style.bush(m, c + Vector3.new(1.5, 0, -1.5), C.LeafOrangeDark, rng, 2.2)
	Kit.pumpkin(m, c + Vector3.new(0.5, 0, -4.5), rng, 1.6)
	Kit.pumpkin(m, c + Vector3.new(-1.6, 0, 5.6), rng, 1.2)
	Kit.pumpkin(m, c + Vector3.new(8.6, 0, 0.6), rng, 1.4)
	Style.flowers(m, c + Vector3.new(-8.5, 0, -2.5), C.FlowerYellow, rng, 4, 1.2)
	return m
end

---------------------------------------------------------------- town-edge belts

--[[
	Rows of the belt on each side (|x| of the trunks): the town-side row on
	the strip between the town sites and the plot road, a tree every
	Every studs, and the plot-side row on the narrow verge between the plot
	road and the bases (staggered half a step, crowns leaning over the
	road, never over a base). The plot entrances and the spur roads stay
	open.
]]
Trees.BeltZ = { -60, 112 }
Trees.BeltRows = {
	{ X = 62.9, Every = 7, Phase = 0, Scale = { 1.05, 1.3 }, Lean = false },
	{ X = 75.5, Every = 7, Phase = 3.5, Scale = { 1.0, 1.15 }, Lean = true },
}
Trees.BeltLanternEvery = 16
Trees.BeltLanternColor = C.LampAmber

-- Belt keep-out boxes (world XZ) for the scatter: nothing else crowds the rows.
function Trees.beltBoxes(): { Kit.Box }
	local out: { Kit.Box } = {}
	for _, side in { -1, 1 } do
		local x0, x1 = 59.5, 80
		table.insert(out, {
			Min = Vector2.new(if side > 0 then x0 else -x1, Trees.BeltZ[1] - 4),
			Max = Vector2.new(if side > 0 then x1 else -x0, Trees.BeltZ[2] + 4),
		})
	end
	return out
end

-- Is the ground at p (an object of radius r whose top part reaches `reach`
-- studs around it) clear for the belt: off the roads and paths, the
-- bases, the outcrops, the keep-outs, the town sites and the other
-- packages' pieces (the stalls by a wide margin)?
local function beltClear(p: Vector3, r: number, reach: number, sites: { Kit.Box }, roads: boolean?): boolean
	if roads ~= false then
		for _, road in WorldLayout.Roads do
			if LobbyLayout.distanceToStrip(road.From, road.To, road.Width, p) < r + 0.3 then
				return false
			end
		end
	end
	for _, path in LobbyLayout.Paths do
		if LobbyLayout.distanceToStrip(path.From, path.To, path.Width, p) < r + 1 then
			return false
		end
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, 0) then
			return false
		end
		-- the road entrance of every base stays open
		if math.abs(p.Z - plot.Center.Z) < 12 and math.abs(math.abs(p.X) - 75) < 4 then
			return false
		end
	end
	for _, spot in WorldLayout.OutcropSpots do
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < 7 + r then
			return false
		end
	end
	if WorldLayout.isKeepOut(p, r) then
		return false
	end
	for _, box in sites do
		if Kit.boxDistance(box, p) < reach * 1.42 + 1.1 then
			return false
		end
	end
	for _, piece in LobbyLayout.Pieces do
		if LobbyLayout.isGroundPiece(piece) then
			local gap = if piece.Package == "Districts" then reach * 1.42 + 1.2 else r + 1
			if LobbyLayout.distanceTo(piece, p) < gap then
				return false
			end
		end
	end
	if Kit.apronClear(p, reach + 0.5) == false then
		return false
	end
	return true
end

local BELT_KINDS = { Green = 60, Pink = 12, Yellow = 12, Orange = 8, Red = 8 }

-- A belt lantern post: a dark timber post, a small deep-amber glow under an
-- iron hat (neon only, no light). 4 parts.
local function beltLantern(parent: Instance, foot: Vector3, h: number)
	local m = Style.model("Lantern", parent)
	Style.block(m, CFrame.new(foot + Vector3.new(0, h / 2, 0)), Vector3.new(0.6, h, 0.6), C.WoodDark)
	Style.block(m, CFrame.new(foot + Vector3.new(0, h + 0.1, 0)), Vector3.new(0.9, 0.2, 0.9), C.Iron, nil, Style.tiny())
	local glow = Style.block(
		m,
		CFrame.new(foot + Vector3.new(0, h + 0.5, 0)),
		Vector3.new(0.5, 0.6, 0.5),
		Trees.BeltLanternColor,
		Enum.Material.Neon,
		Style.tiny()
	)
	glow.Name = "LanternGlow"
	Style.block(m, CFrame.new(foot + Vector3.new(0, h + 0.95, 0)), Vector3.new(0.95, 0.3, 0.95), C.Iron, nil, Style.tiny())
	m.PrimaryPart = glow
end

--[[
	The two town-edge belts. `sites`: the town building rectangles (the
	belt keeps its crowns off them). Returns the model.
]]
function Trees.belt(parent: Instance, rng: Rng.Rng, sites: { Kit.Box }): Model
	local m = Style.model("TownBelt", parent)
	for _, side in { -1, 1 } do
		local townSide: { number } = {}
		for _, row in Trees.BeltRows do
			local z = Trees.BeltZ[1] + row.Phase
			while z <= Trees.BeltZ[2] do
				local p = Vector3.new(side * row.X, 0, z + rng:range(-0.8, 0.8))
				local scale = rng:range(row.Scale[1], row.Scale[2])
				local reach = 3.6 * scale
				if beltClear(p, 0.5 * scale, if row.Lean then 0.6 else reach, sites) then
					local kind = rng:weighted(BELT_KINDS)
					if side < 0 and p.Z > 60 then
						kind = if rng:chance(0.5) then "Yellow" else "Orange"
					end
					local lean = if row.Lean then Vector3.new(-side, 0, 0) else nil
					local tree = Kit.beltTree(m, CFrame.new(p), kind, rng, scale, lean)
					if not Kit.clearOfStalls(tree) then
						tree:Destroy()
					elseif not row.Lean then
						table.insert(townSide, p.Z)
					end
				end
				z += row.Every
			end
		end
		-- hedges between neighbouring town-side trees, timber fence runs behind
		-- every other gap, a lantern post every BeltLanternEvery studs
		table.sort(townSide)
		for i = 1, #townSide - 1 do
			local z0, z1 = townSide[i] + 1.4, townSide[i + 1] - 1.4
			local len = z1 - z0
			if len >= 2 and len <= 11 then
				local mid = Vector3.new(side * 62.6, 0, (z0 + z1) / 2)
				if beltClear(mid, 0.8, 0.8, sites) then
					Style.block(
						m,
						CFrame.new(mid + Vector3.new(0, 0.8, 0)),
						Vector3.new(1.5, 1.6, len),
						Style.vary(C.LeafGreenDark, rng, 0.05),
						nil,
						Style.ghost()
					).Name =
						"Hedge"
					Style.block(
						m,
						CFrame.new(mid + Vector3.new(0, 1.75, rng:range(-0.4, 0.4))),
						Vector3.new(1.1, 0.4, len * 0.6),
						Style.vary(C.LeafGreen, rng, 0.05),
						nil,
						Style.tiny()
					)
				end
				local fenceA = Vector3.new(side * 60.3, 0, z0 + 0.4)
				local fenceB = Vector3.new(side * 60.3, 0, z1 - 0.4)
				if i % 2 == 1 and beltClear(fenceA, 0.6, 0.6, sites) and beltClear(fenceB, 0.6, 0.6, sites) then
					Style.fence(m, fenceA, fenceB, { Height = 2.2, PostEvery = 4.5, Rails = 2, Caps = true })
				end
			end
		end
		local z = Trees.BeltZ[1] + 7
		while z <= Trees.BeltZ[2] do
			local foot = Vector3.new(side * 64.3, 0, z)
			if beltClear(foot, 0.5, 0.5, sites) then
				beltLantern(m, foot, 4.6)
			end
			z += Trees.BeltLanternEvery
		end
	end
	return m
end

function Trees.build(parent: Instance, rng: Rng.Rng, sites: { Kit.Box }?)
	Trees.pinkGrove(parent, Kit.sub(rng))
	Trees.redTree(parent, Kit.sub(rng))
	Trees.autumnCorner(parent, Kit.sub(rng))
	Trees.belt(parent, Kit.sub(rng), sites or {})
end

return Trees
