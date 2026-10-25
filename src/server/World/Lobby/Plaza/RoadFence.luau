--[[
	The road fences in the street lamps' style (owner 2026-10-25: "the
	fences along the roads", after the neon walkways and the TERRAFORGE
	street lamps): dark grey metal posts, two dark metal rails and a
	deep-orange neon strip along the top rail, so the fence draws a warm
	line beside every road like the walkways' edge strips; the two end
	posts of a run carry a glowing orange cap. Flora/Meadow lays the runs
	(along both sides of the roads, behind the lamps' feet, with gaps to
	walk through); the posts and the rails collide, the glow does not.

	A run of length L: ceil(L / PostEvery) + 1 posts, 2 rails, 1 strip,
	2 caps (a 24-stud run is 10 parts; the timber fence with its three
	lanterns was 14).
]]

local Style = require(script.Parent.Parent.Style)
local Common = require(script.Parent.Common)

local K = Common.Colors
local NEON = Enum.Material.Neon
local rgb = Color3.fromRGB

local RoadFence = {}

-- Off: Meadow lays the timber fences with their lanterns again.
RoadFence.Enabled = true
RoadFence.Height = 2.4
RoadFence.PostEvery = 6
RoadFence.Colors = {
	Post = rgb(66, 70, 86), -- the street lamps' pole grey
	Rail = K.MetalDark,
	Glow = K.SlotAmber, -- the lamps' deep-orange slots
}

-- One run from `from` to `to` (ground points). Returns the model "RoadFence".
function RoadFence.run(parent: Instance, from: Vector3, to: Vector3): Model
	local m = Style.model("RoadFence", parent)
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = delta.Magnitude
	if length < 0.5 then
		return m
	end
	local h = RoadFence.Height
	local dir = delta / length
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local frame = CFrame.fromMatrix(Vector3.new(from.X, 0, from.Z), right, Vector3.new(0, 1, 0), -dir)
	local posts = math.max(1, math.ceil(length / RoadFence.PostEvery))
	for i = 0, posts do
		local z = -length * i / posts
		Style.block(m, frame * CFrame.new(0, (h + 0.1) / 2, z), Vector3.new(0.55, h + 0.1, 0.55), RoadFence.Colors.Post).Name = "Post"
		if i == 0 or i == posts then
			local cap =
				Style.block(m, frame * CFrame.new(0, h + 0.17, z), Vector3.new(0.7, 0.16, 0.7), RoadFence.Colors.Glow, NEON, Style.tiny())
			cap.Name = "PostCap"
		end
	end
	local mid = frame * CFrame.new(0, 0, -length / 2)
	Style.block(
		m,
		mid * CFrame.new(0, h - 0.3, 0),
		Vector3.new(0.34, 0.3, length),
		RoadFence.Colors.Rail,
		nil,
		Style.decor({ CastShadow = false })
	).Name =
		"TopRail"
	Style.block(
		m,
		mid * CFrame.new(0, h * 0.45, 0),
		Vector3.new(0.28, 0.24, length),
		RoadFence.Colors.Rail,
		nil,
		Style.decor({ CastShadow = false })
	).Name =
		"MidRail"
	local glow =
		Style.block(m, mid * CFrame.new(0, h - 0.1, 0), Vector3.new(0.2, 0.1, length - 0.3), RoadFence.Colors.Glow, NEON, Style.tiny())
	glow.Name = "RailGlow"
	return m
end

return RoadFence
