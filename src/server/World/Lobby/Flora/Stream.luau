--[[
	Stream (concept fix 2026-10-18, docs/art/lobby_concept.webp: the stream
	with a humped wooden bridge and a waterfall off the island's edge, front
	right). In the south-east corner, where the MAP hamlet stood:

	  Pond       a stone-rimmed pond at the end of the hamlet lane (the lane
	             and ToMap paths lead here), lily pads
	  Channel    the stream from the pond south to the island's edge, a gentle
	             bend, stone banks, glinting streaks
	  Bridge     a humped wooden bridge over it (Style.archBridge, walkable)
	  Waterfall  the stream pours over the south rim into the sea; Land leaves
	             the rim low there (Land.RimNotch)

	Off the plot yards, the railway lines (x +-166), the vault zone and every
	road. Built from WorldBuilder before the meadow (which keeps off it).
	Parented to Emberfall.Lobby.Flora.Stream. Water is non-collide; the
	bridge deck is walkable; nothing casts shadows but the bridge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local WorldLayout = require(Shared.Config.WorldLayout)
local Style = require(script.Parent.Parent.Style)

local C = Style.C

local Stream = {}

-- the south band moves south with the plot columns (WorldLayout.PlotGrid, 0 at 12 cells)
local SOUTH = WorldLayout.PlotGrid.SouthShift

Stream.Pond = { Center = Vector3.new(101, 0, 127 + SOUTH), Size = Vector2.new(17, 12) }
-- the stream's centre line, from the pond's south edge to the island's edge
Stream.Path = {
	Vector3.new(101, 0, 132.5 + SOUTH),
	Vector3.new(98, 0, 141 + SOUTH),
	Vector3.new(99.5, 0, 149 + SOUTH),
	Vector3.new(101, 0, 156 + SOUTH),
}
Stream.Width = 4.2
Stream.WaterTop = 0.2
-- the bridge crosses the second leg (west to east)
Stream.Bridge = { From = Vector3.new(91.5, 0, 142.5 + SOUTH), To = Vector3.new(105.5, 0, 140.5 + SOUTH), Width = 4.4, Rise = 2.2 }
-- Land keeps the south rim low over this x range (Land.RimNotch)
Stream.Notch = { X0 = 96, X1 = 106 }

local function water(parent: Instance, a: Vector3, b: Vector3, width: number, y: number, rng: Rng.Rng)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	local mid = Vector3.new((a.X + b.X) / 2, y - 0.25, (a.Z + b.Z) / 2)
	local cf = CFrame.lookAt(mid, mid + d)
	-- deep bed, water (overlapping the next leg so the bends stay closed)
	Style.block(parent, cf * CFrame.new(0, -0.08, 0), Vector3.new(width - 0.6, 0.2, len + width * 0.6), C.WaterDeep, nil, Style.tiny())
	Style.water(parent, cf, Vector3.new(width, 0.5, len + width * 0.6))
	-- a glinting streak along the flow
	Style.block(
		parent,
		cf * CFrame.new(rng:range(-0.6, 0.6), 0.27, 0),
		Vector3.new(0.25, 0.05, len * 0.6),
		C.FallsGlint,
		Enum.Material.Neon,
		Style.tiny({ Transparency = 0.4 })
	)
	-- stone banks: a few blocks along both sides
	for _, side in { -1, 1 } do
		local n = math.max(1, math.floor(len / 4))
		for i = 0, n - 1 do
			if rng:chance(0.75) then
				local t = (i + 0.5) / n - 0.5
				local s = rng:range(1.2, 1.9)
				Style.block(
					parent,
					cf * CFrame.new(side * (width / 2 + s * 0.25), s * 0.18, t * len) * CFrame.Angles(0, rng:range(-0.4, 0.4), 0),
					Vector3.new(s, s * 0.6, s * 1.2),
					Style.vary(if rng:chance(0.5) then C.Stone else C.StoneLight, rng, 0.05),
					nil,
					Style.tiny()
				)
			end
		end
	end
end

-- The south rim under the stream's mouth: its outer edge and top (from the
-- built Land parts), so the fall starts at the right lip. The rim starts at
-- the island's south coast (Island.Max.Z, 150 at 12 cells).
local function rimLip(map: Instance): (number, number)
	local land = map:FindFirstChild("Land")
	local coast = WorldLayout.Island.Max.Z
	local outer, top = coast + 10, -0.2
	if land then
		for _, d in land:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Ground" and d.Transparency < 1 then
				local c, h = d.CFrame.Position, d.Size / 2
				if
					c.X + h.X > Stream.Notch.X0
					and c.X - h.X < Stream.Notch.X1
					and c.Z - h.Z >= coast
					and c.Z - h.Z < coast + 25
					and c.Y + h.Y > -3
				then
					outer = math.max(outer, c.Z + h.Z)
					top = math.max(top, c.Y + h.Y)
				end
			end
		end
	end
	return outer, top
end

function Stream.build(map: Instance, rng: Rng.Rng): Model
	local emberfall = map:FindFirstChild("Emberfall")
	local lobby = emberfall and emberfall:FindFirstChild("Lobby")
	local flora = lobby and lobby:FindFirstChild("Flora")
	local m = Style.model("Stream", flora or map)

	-- the pond and its lily pads
	local pond = Style.pond(m, Stream.Pond.Center, Stream.Pond.Size.X, Stream.Pond.Size.Y, rng)
	pond.Name = "StreamPond"
	for _ = 1, 3 do
		local q = Stream.Pond.Center
			+ Vector3.new(
				rng:range(-Stream.Pond.Size.X * 0.3, Stream.Pond.Size.X * 0.3),
				0.7,
				rng:range(-Stream.Pond.Size.Y * 0.25, Stream.Pond.Size.Y * 0.25)
			)
		Geo.cylinder(pond, q, 0.12, rng:range(1.6, 2.6), C.LeafGreen, nil, Style.tiny())
	end

	-- the channel, leg by leg; the last leg runs out over the rim to its lip
	local channel = Style.model("Channel", m)
	local outer, rimTop = rimLip(map)
	local path = table.clone(Stream.Path)
	path[#path] = Vector3.new(path[#path].X, 0, outer)
	for i = 1, #path - 1 do
		water(channel, path[i], path[i + 1], Stream.Width, Stream.WaterTop, rng)
	end
	-- the stretch over the rim sits on the rim's grass
	local overRim = math.max(Stream.WaterTop, rimTop + 0.25)
	if overRim > Stream.WaterTop + 0.05 then
		water(channel, Vector3.new(path[#path].X, 0, WorldLayout.Island.Max.Z + 7), path[#path], Stream.Width, overRim, rng)
	end

	-- the humped bridge
	local bridge = Style.archBridge(m, Stream.Bridge.From, Stream.Bridge.To, Stream.Bridge.Width, Stream.Bridge.Rise, rng)
	bridge.Name = "StreamBridge"

	-- the waterfall into the sea
	local lipPos = Vector3.new(path[#path].X, math.max(overRim, Stream.WaterTop), outer + 0.3)
	local lip = CFrame.lookAt(lipPos, lipPos + Vector3.new(0, 0, 1))
	Style.waterfall(m, lip, lipPos.Y + 21, Stream.Width + 0.6, rng, { Mist = true })

	-- water, banks and the fall are pure decoration; the bridge stays walkable
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and not d:IsDescendantOf(bridge) then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	return m
end

return Stream
