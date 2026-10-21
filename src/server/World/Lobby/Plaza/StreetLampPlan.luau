--[[
	Where the street lamps stand (owner 2026-10-20: "lamps everywhere, the
	whole map lit", after the owner's TERRAFORGE street lamp picture). Pure
	placement, no parts: StreetLamps.luau builds the lamps after the lobby
	packages; Flora reads the spots to leave a gap in the town belts and
	the west street there (no crowns through a lamp), Meadow sets its road
	fences behind them.

	Every road gets lamps on one side or alternating sides at a steady
	rhythm, the arm and the glowing head over the road: Tall lamps along
	the plot roads (town side: the plot side is a 1.5-stud verge before the
	bases) and the quarry rim road (town side), Medium ones along the forge
	paths, the spurs and the lane to the next area, Small ones on the
	scanner path and the MINE lane. The walkways at the stalls, the south
	road over the creek bridge (Flora lights the bridge and the vault's
	approach), the bridge garden and the plaza itself (its entrance lantern
	pillars) get none.

	The spots follow the road ends (Common.strips: WorldLayout.Roads and
	LobbyLayout.Paths), so the plot roads, which run the length of the plot
	columns (WorldLayout.PlotGrid), get more lamps when the plots grow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Common = require(script.Parent.Common)

local StreetLampPlan = {}

-- Off: the old lanterns (Roads RoadLanterns, the belt and west street posts) come back.
StreetLampPlan.Enabled = true

export type SizeSpec = { Height: number, Arm: number, Range: number }
-- Height: top of the pole (the arm leaves it there); Arm: pole to head.
-- Range: the lit lamps' PointLight (phones, integrator 2026-10-21: <= 14,
-- short-range lights are cheap on Voxel/compatibility lighting).
StreetLampPlan.Sizes = {
	Small = { Height = 6.2, Arm = 2.3, Range = 12 },
	Medium = { Height = 8.4, Arm = 3.1, Range = 13 },
	Tall = { Height = 10.6, Arm = 3.9, Range = 14 },
} :: { [string]: SizeSpec }

-- Side: "Inner" = toward the plaza center, "Outer" = away from it, "Both" =
-- alternating. First: studs from the strip start; Every: studs between lamps.
type RoadPlan = { Size: string, Side: string, First: number, Every: number }
StreetLampPlan.Roads = {
	WestPlotRoad = { Size = "Tall", Side = "Inner", First = 6, Every = 26 },
	EastPlotRoad = { Size = "Tall", Side = "Inner", First = 6, Every = 26 },
	-- (the quarry's rim stones stand right past the rim road's north edge)
	RimRoad = { Size = "Tall", Side = "Inner", First = 12, Every = 26 },
	ForgePathEast = { Size = "Medium", Side = "Outer", First = 12, Every = 22 },
	ForgePathWest = { Size = "Medium", Side = "Outer", First = 12, Every = 22 },
	EastSpur = { Size = "Medium", Side = "Both", First = 12, Every = 12 },
	WestSpur = { Size = "Medium", Side = "Both", First = 12, Every = 12 },
	ToScanner = { Size = "Small", Side = "Both", First = 9, Every = 14 },
	MineLane = { Size = "Small", Side = "Outer", First = 4, Every = 20 },
	-- (none on ToMine, under the rails in the MINE yard, nor on the hamlet
	-- lanes: the yard's and the garden's lanterns light them)
	ToNextArea = { Size = "Medium", Side = "Both", First = 10, Every = 22 },
} :: { [string]: RoadPlan }

StreetLampPlan.Offset = 1.15 -- the pole's center past the road edge
StreetLampPlan.BaseHalf = 0.9 -- half the foot plate
StreetLampPlan.MinGap = 9 -- no two lamps closer (road corners)
-- No lamps here: the bridge garden under and behind THE GREAT FORGE's roof
-- (its own path lanterns light it; Meadow.BridgeGarden + 2).
StreetLampPlan.ClearBoxes = {
	{ Min = Vector3.new(-24, 0, -116), Max = Vector3.new(24, 0, -36) },
}

export type Place = { Position: Vector3, Facing: Vector3 }
export type Spot = {
	Road: string,
	Position: Vector3, -- ground point under the pole
	Facing: Vector3, -- toward the road (the arm's direction)
	Size: string,
	Lit: boolean, -- carries a PointLight (every other lamp of a road)
	-- the next best places (a little along the road, then across it), in
	-- order, for when something built stands in the way (StreetLamps)
	Alternates: { Place },
}

local function clear(p: Vector3, placed: { Spot }): boolean
	local r = StreetLampPlan.BaseHalf + 0.2
	if Vector3.new(p.X, 0, p.Z).Magnitude < Common.PlazaRadius + 3 then
		return false
	end
	if not Common.isClear(p, r) or not Common.offStrips(p, StreetLampPlan.BaseHalf) then
		return false
	end
	for _, box in StreetLampPlan.ClearBoxes do
		if p.X > box.Min.X - r and p.X < box.Max.X + r and p.Z > box.Min.Z - r and p.Z < box.Max.Z + r then
			return false
		end
	end
	-- the Plaza's own pieces (THE GREAT FORGE, the spawn pad, the crystal)
	for _, piece in LobbyLayout.Pieces do
		if piece.Package == "Plaza" and LobbyLayout.isGroundPiece(piece) and LobbyLayout.distanceTo(piece, p) < r + 1 then
			return false
		end
	end
	for _, other in placed do
		if (other.Position - p).Magnitude < StreetLampPlan.MinGap then
			return false
		end
	end
	return true
end

local cache: { Spot }? = nil

-- Every lamp spot, in Common.strips() order (deterministic; cached).
function StreetLampPlan.spots(): { Spot }
	if cache then
		return cache
	end
	local placed: { Spot } = {}
	if not StreetLampPlan.Enabled then
		cache = placed
		return placed
	end
	for _, s in Common.strips() do
		local plan = StreetLampPlan.Roads[s.Id]
		if not plan then
			continue
		end
		local from = Vector3.new(s.From.X, 0, s.From.Z)
		local delta = Vector3.new(s.To.X, 0, s.To.Z) - from
		local length = delta.Magnitude
		local dir = delta / length
		local right = Vector3.new(-dir.Z, 0, dir.X)
		-- +1 = right of the strip; the inner side faces the plaza center
		local mid = from + delta / 2
		local inner = if right:Dot(-mid) >= 0 then 1 else -1
		local offset = s.Width / 2 + StreetLampPlan.Offset
		local count = 0
		local k = 0
		local t = plan.First
		while t <= length - 1 do
			local side = if plan.Side == "Inner" then inner elseif plan.Side == "Outer" then -inner elseif k % 2 == 0 then inner else -inner
			local found: { Place } = {}
			for _, sd in { side, -side } do
				for _, shift in { 0, 2, -2, 4, -4, 6, -6 } do
					local tt = t + shift
					if tt >= 0 and tt <= length then
						local p = from + dir * tt + right * sd * offset
						if clear(p, placed) then
							table.insert(found, { Position = p, Facing = -right * sd })
						end
					end
				end
			end
			if #found > 0 then
				count += 1
				local first = table.remove(found, 1) :: Place
				table.insert(placed, {
					Road = s.Id,
					Position = first.Position,
					Facing = first.Facing,
					Size = plan.Size,
					Lit = count % 2 == 1,
					Alternates = found,
				})
			end
			k += 1
			t += plan.Every
		end
	end
	cache = placed
	return placed
end

-- Is a lamp within r (studs, ground plane) of p?
function StreetLampPlan.near(p: Vector3, r: number): boolean
	local flat = Vector3.new(p.X, 0, p.Z)
	for _, spot in StreetLampPlan.spots() do
		if (spot.Position - flat).Magnitude < r then
			return true
		end
	end
	return false
end

return StreetLampPlan
