--[[
	ScaffoldWest / ScaffoldWest2 (LOBBY_PLAN 6.2 item 7): timber derricks
	on the west mountain shelf (Land cuts the mountain columns under them to
	Land.ShelfHeight): WoodDark posts, X-braces every ~8 studs, two plank
	platforms, a ladder, a pulley wheel with a rope and bucket, a lantern on
	top. The footing plinth reaches down onto the shelf's grass.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Geo = require(Shared.Builders.Geo)
local Rng = require(Shared.Util.Rng)
local Style = require(script.Parent.Parent.Style)
local Kit = require(script.Parent.Kit)
local Land = require(script.Parent.Parent.Parent.Land)

local C = Style.C

local Scaffolds = {}

Scaffolds.FootY = Land.ShelfHeight + 0.8 -- the shelf's grass top

local function tower(parent: Instance, id: string, rng: Rng.Rng)
	local m, piece = Kit.piece(parent, id)
	local foot = Scaffolds.FootY
	local x, z = piece.Center.X, piece.Center.Z
	local topY = piece.Center.Y + piece.Size.Y
	Kit.box(
		m,
		Vector3.new(x - 4, foot - 1.4, z - 4),
		Vector3.new(x + 4, foot + 0.6, z + 4),
		Style.vary(C.StoneDark, rng, 0.05),
		nil,
		Style.solid()
	)
	local base = CFrame.new(x, foot + 0.6, z)
	local height = topY - 7 - (foot + 0.6)
	local levels = math.max(2, math.floor(height / 8 + 0.5))
	local top = Kit.lattice(m, base, 7, 4.4, height, height / levels, C.WoodDark, {
		Thickness = 0.65,
		Faces = { { 3, 4 }, { 2, 3 } },
		Cross = true,
	})
	-- platforms: one halfway, one on top
	local midY = math.floor(levels / 2) * height / levels
	local midW = 7 + (4.4 - 7) * (midY / height)
	Style.block(
		m,
		base * CFrame.new(0, midY + 0.25, 0),
		Vector3.new(midW + 1.4, 0.5, midW + 1.4),
		Style.vary(C.Plank, rng, 0.04),
		nil,
		Style.solid()
	)
	Style.block(m, top * CFrame.new(0, 0.25, 0), Vector3.new(6.4, 0.5, 6.4), Style.vary(C.Plank, rng, 0.04), nil, Style.solid())
	-- ladder on the south face up to the middle platform
	local front = 7 / 2 + 0.5
	Kit.ladder(m, base * CFrame.new(1.2, 0, front - 0.2), midY + 0.5, 1.6, 3)
	-- A-frame with a pulley wheel, a rope and a bucket
	local apex = top * CFrame.new(0, 5.5, 0)
	for _, side in { -1, 1 } do
		Kit.beam(m, (top * CFrame.new(side * 2.6, 0.5, 0)).Position, apex.Position, 0.5, C.WoodDark)
	end
	Geo.make(
		"Part",
		Style.tiny({
			Shape = Enum.PartType.Cylinder,
			CFrame = apex * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Size = Vector3.new(0.5, 2.6, 2.6),
			Color = C.Wood,
			Material = Enum.Material.SmoothPlastic,
		}),
		m
	)
	local ropeTop = (apex * CFrame.new(0, -0.6, 1.3)).Position
	local ropeEnd = ropeTop - Vector3.new(0, 9, 0)
	Kit.beam(m, ropeTop, ropeEnd, 0.15, C.WoodLight)
	Style.block(m, CFrame.new(ropeEnd - Vector3.new(0, 0.6, 0)), Vector3.new(1.2, 1.2, 1.2), C.Wood, nil, Style.tiny())
	-- lantern hanging under the apex
	Style.lantern(m, apex * CFrame.new(0, -0.2, -1.2), { Kind = "Hanging" })
end

function Scaffolds.build(parent: Instance, rng: Rng.Rng)
	tower(parent, "ScaffoldWest", rng)
	tower(parent, "ScaffoldWest2", rng)
end

return Scaffolds
