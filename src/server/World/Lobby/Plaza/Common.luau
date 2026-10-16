--[[
	Shared helpers of the Plaza package (src/server/World/Lobby/Plaza):
	the list of road/path strips with their look, the plaza entrance test
	(where the curb opens), placement checks against the other packages'
	footprints and a flat path strip builder (Style.path with a lift and a
	curb range, so overlapping strips never z-fight).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LobbyLayout = require(Shared.Config.LobbyLayout)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)

local C = Style.C

local Common = {}

Common.PlazaRadius = 36
Common.CurbRadius = 35.6
Common.FloorTop = 0.4 -- top of the collidable plaza disc
Common.TileTop = 0.43 -- top of the flagstones (TownSpawn's top is 0.45, the spawn inlay 0.445)
Common.ForgeApproach = 11 -- half width of the open plaza edge in front of the forge

export type Strip = {
	Id: string,
	From: Vector3,
	To: Vector3,
	Width: number,
	Kind: string, -- "Cobble" | "Dirt"
	Lift: number, -- stacking order where strips overlap (cobble over dirt)
	Main: boolean, -- a WorldLayout road (lanterns, curbs near the plaza)
}

local function roadName(road: WorldLayout.Road): string
	local a, b = road.From, road.To
	if math.abs(a.X - b.X) < 0.01 then
		if math.abs(a.X) < 0.01 then
			return "SouthRoad"
		elseif math.abs(a.X) >= 60 then
			return if a.X > 0 then "EastPlotRoad" else "WestPlotRoad"
		end
		return if a.X > 0 then "ForgePathEast" else "ForgePathWest"
	end
	if a.Z <= -100 then
		return "RimRoad"
	end
	return if a.X + b.X > 0 then "EastSpur" else "WestSpur"
end

local stripCache: { Strip }? = nil

-- Every WorldLayout road and LobbyLayout path with the look the plan gives it:
-- plot roads, the rim road, ToMine and ToNextArea are dirt, the rest cobble.
function Common.strips(): { Strip }
	if stripCache then
		return stripCache
	end
	local list: { Strip } = {}
	for _, road in WorldLayout.Roads do
		local id = roadName(road)
		local dirt = id == "EastPlotRoad" or id == "WestPlotRoad" or id == "RimRoad"
		table.insert(list, {
			Id = id,
			From = road.From,
			To = road.To,
			Width = road.Width,
			Kind = if dirt then "Dirt" else "Cobble",
			Lift = if id == "RimRoad" then 0.012 elseif dirt then 0 else 0.03,
			Main = true,
		})
	end
	for _, path in LobbyLayout.Paths do
		local dirt = path.Kind == "Dirt" or path.Id == "ToNextArea"
		table.insert(list, {
			Id = path.Id,
			From = path.From,
			To = path.To,
			Width = path.Width,
			Kind = if dirt then "Dirt" else "Cobble",
			Lift = if dirt then 0.022 else 0.045,
			Main = false,
		})
	end
	stripCache = list
	return list
end

function Common.strip(id: string): Strip
	for _, s in Common.strips() do
		if s.Id == id then
			return s
		end
	end
	error("unknown strip " .. id)
end

-- Is the plaza edge open at this angle (radians from +X toward +Z)? Open
-- where a road or path enters and in front of the forge.
function Common.isEntrance(angle: number, margin: number?): boolean
	local p = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Common.CurbRadius
	if p.Z < 0 and math.abs(p.X) < Common.ForgeApproach then
		return true
	end
	for _, s in Common.strips() do
		if LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < (margin or 0.8) then
			return true
		end
	end
	return false
end

-- Ground point clear of every other package's ground pieces, the ore
-- outcrops, the player bases, the keep-out boxes and the quarry pit.
function Common.isClear(p: Vector3, radius: number): boolean
	for _, piece in LobbyLayout.Pieces do
		if piece.Package ~= "Plaza" and LobbyLayout.isGroundPiece(piece) and LobbyLayout.distanceTo(piece, p) < radius + 0.5 then
			return false
		end
	end
	local flat = Vector3.new(p.X, 0, p.Z)
	for _, spot in WorldLayout.OutcropSpots do
		if (flat - Vector3.new(spot.X, 0, spot.Z)).Magnitude < radius + 6 then
			return false
		end
	end
	for _, plot in WorldLayout.Plots do
		if LobbyLayout.onBase(plot, p, radius) then
			return false
		end
	end
	if WorldLayout.isKeepOut(p, radius) then
		return false
	end
	if p.Z < WorldLayout.Quarry.Max.Z + radius + 0.5 then
		return false
	end
	return true
end

-- Ground point off every road and path strip.
function Common.offStrips(p: Vector3, radius: number): boolean
	for _, s in Common.strips() do
		if LobbyLayout.distanceToStrip(s.From, s.To, s.Width, p) < radius + 0.2 then
			return false
		end
	end
	return true
end

export type PathOpts = {
	Kind: string?, -- "Cobble" (default) | "Dirt"
	TileEvery: number?, -- studs between tile rows
	CurbUntil: number?, -- curb stones from the strip start up to this distance (studs)
	CurbEvery: number?,
	Lift: number?, -- extra height so overlapping strips never z-fight
	Name: string?,
	CurbSkip: ((Vector3) -> boolean)?, -- no curb stone where this returns true
}

--[[
	Flat walk-over path strip from `from` to `to` (ground points), extended
	by Width/2 past both ends like the road strips (tests use the same rule).
	Non-collide over the solid ground. One base slab, one tile per row
	(alternating sides), optional curb stones near the start.
]]
function Common.path(parent: Instance, from: Vector3, to: Vector3, width: number, rng: Rng.Rng, opts: PathOpts?): Model
	local o: PathOpts = opts or {}
	local m = Style.model(o.Name or "Path", parent)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local lift = o.Lift or 0
	local mid = Vector3.new((from.X + to.X) / 2, lift, (from.Z + to.Z) / 2)
	local frame = CFrame.fromMatrix(mid, right, Vector3.new(0, 1, 0), -dir)
	local kind = o.Kind or "Cobble"
	local dirt = kind == "Dirt"
	local full = length + width
	local base = Style.block(
		m,
		frame * CFrame.new(0, 0.08, 0),
		Vector3.new(width, 0.3, full),
		if dirt then C.DirtLight else C.Cobble,
		nil,
		Style.tiny({ CanQuery = true })
	)
	base.Name = "PathBase"
	local every = o.TileEvery or (if dirt then 7 else 4.5)
	local rows = math.floor(full / every)
	for i = 0, rows - 1 do
		local z = -full / 2 + (i + 0.5) * (full / rows)
		local tw = if dirt then rng:range(1.6, 3) else math.min(width * 0.42, rng:range(2.2, 3.4))
		local side = if i % 2 == 0 then -1 else 1
		local x = side * rng:range(0.15, 0.5) * (width / 2 - tw / 2 - 0.3)
		local shade = if dirt then (if rng:chance(0.6) then C.Dirt else C.Sand) elseif rng:chance(0.5) then C.FlagLight else C.CobbleDark
		Style.block(
			m,
			frame * CFrame.new(x, 0.26, -z),
			Vector3.new(tw, 0.08, rng:range(1.4, 2.2)),
			Style.vary(shade, rng, 0.05),
			nil,
			Style.tiny()
		)
	end
	local curbUntil = o.CurbUntil or 0
	if curbUntil > 0 then
		local curbEvery = o.CurbEvery or 4
		local count = math.floor(math.min(curbUntil, full) / curbEvery)
		for i = 0, count - 1 do
			local side = if i % 2 == 0 then -1 else 1
			-- local -Z runs from `from` to `to`: the strip starts at +full/2
			local z = full / 2 - (i + 0.5) * curbEvery
			local cf = frame * CFrame.new(side * (width / 2 + 0.3), 0.25, z)
			if o.CurbSkip and o.CurbSkip(cf.Position) then
				continue
			end
			Style.block(m, cf, Vector3.new(1.1, 0.5, rng:range(1.6, 2.4)), Style.vary(C.StoneDark, rng, 0.06), nil, Style.tiny())
		end
	end
	return m
end

return Common
